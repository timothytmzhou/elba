{-# LANGUAGE Trustworthy #-}

module LBAC
  ( Config
  , Env
  , mkAgent
  , setContext
  , subagent
  ) where

import Control.Monad.Catch (try)
import Data.Char (isAlpha)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf, stripPrefix)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Proxy (Proxy (..))
import Data.Typeable (Typeable, typeRep)
import Docs (resolveTools)
import Env
import GHC.IO (unsafePerformIO)
import LLM
import Language.Haskell.Interpreter hiding (Extension)
import Language.Haskell.Interpreter qualified as Hint
import Language.Haskell.Interpreter.Unsafe (unsafeInterpret, unsafeRunInterpreterWithArgs)
import Log (Event (..), Log, logEvent, withLog)

-- | Tool name to signature and optional docstring, shown to the model.
newtype TypeEnv = TypeEnv (Map String (String, Maybe String))

instance Show TypeEnv where
  show (TypeEnv m) =
    unlines
      [ entry name sig mDoc
      | (name, (sig, mDoc)) <- Map.toList m
      ]
    where
      entry name sig Nothing = name ++ " :: " ++ sig
      entry name sig (Just doc) =
        name
          ++ " :: "
          ++ sig
          ++ "\n"
          ++ unlines ["    " ++ ln | ln <- lines doc]

setEnv :: Env -> [ResolvedTool] -> Interpreter TypeEnv
setEnv env tools = do
  setImportsF $
    [ModuleImport m NotQualified NoImportList | m <- modules env ++ baseModules]
      ++ [ModuleImport m (QualifiedAs Nothing) NoImportList | m <- qualifiedModules]
  let values = [t | t <- tools, toolIsValue t]
  sigs <- map (applyAliases (typeAliases env)) <$> mapM (typeOf . parenIfOp . toolName) values
  pure (TypeEnv (Map.fromList [(toolName t, (sig, toolDoc t)) | (t, sig) <- zip values sigs]))

-- | In scope unqualified, so emitted code can call subagent.
baseModules :: [ModuleName]
baseModules = ["Prelude", "LBAC"]

-- | Always importable by emitted code, qualified so name clashes are impossible.
qualifiedModules :: [ModuleName]
qualifiedModules =
  [ "Control.Applicative"
  , "Control.Monad"
  , "Data.Bifunctor"
  , "Data.Char"
  , "Data.Either"
  , "Data.Foldable"
  , "Data.Function"
  , "Data.Functor"
  , "Data.List"
  , "Data.Maybe"
  , "Data.Ord"
  , "Data.Traversable"
  , "Data.Tuple"
  , "Text.Printf"
  , "Text.Read"
  ]

parenIfOp :: String -> String
parenIfOp s@(c : _) | not (isAlpha c) && c /= '_' = "(" ++ s ++ ")"
parenIfOp s = s

buildContext :: String -> TypeEnv -> String -> String
buildContext reqType typeEnv task =
  unlines
    [ task
    , ""
    , "Required type: " ++ reqType
    , "Allowed functions: " ++ show typeEnv
    ]

-- | Rewrites alias sources to targets. TypeRep renders synonyms expanded.
applyAliases :: [(String, String)] -> String -> String
applyAliases aliases s0 = foldl (flip sub) s0 aliases
  where
    sub (from, to) = go
      where
        go [] = []
        go s@(c : cs)
          | from `isPrefixOf` s = to ++ go (drop (length from) s)
          | otherwise = c : go cs

retryMessage :: String -> String
retryMessage errStr =
  unlines
    [ "Your previous code did not compile:"
    , ""
    , errStr
    , ""
    , "Re-emit a corrected Haskell expression of the required type."
    ]

-- | Strips a markdown code fence around the LLM emission if present.
stripFence :: String -> String
stripFence s
  | not (any isFence ls) = s
  | otherwise = unlines (takeWhile (not . isFence) (drop 1 (dropWhile (not . isFence) ls)))
  where
    ls = lines s
    isFence l = take 3 (dropWhile (== ' ') l) == "```"

formatErr :: InterpreterError -> String
formatErr (WontCompile ghcErrors) = unlines (map errMsg ghcErrors)
formatErr e = show e

setupInterp :: Env -> Interpreter ()
setupInterp env = do
  set [searchPath := []]
  set [languageExtensions := map (Hint.UnknownExtension . show) (extensions env)]

-- | Written through setContext because the interpreter keeps its own copy of this module.
{-# NOINLINE contextRef #-}
contextRef :: IORef (Config, Env)
contextRef = unsafePerformIO (newIORef (error "LBAC.subagent: no agent has run"))

-- | Writes contextRef in the interpreted copy of this module.
setContext :: Config -> Env -> IO ()
setContext config env = writeIORef contextRef (config, env)

-- | Spawns a nested agent on the running agent context. Each spawn decrements maxDepth.
subagent :: (Typeable a) => String -> String -> a
subagent task input = unsafePerformIO $ do
  (config, env) <- readIORef contextRef
  pure (mkAgent config env (subagentPrompt config task input))

-- | Under the adversarial eval a detected injection command replaces the
--   subagent prompt to model a compromised subagent.
subagentPrompt :: Config -> String -> String -> String
subagentPrompt config task input
  | evalAdversarially config == Just True
  , Just command <- findTodo input =
      "You are a subagent. " ++ command
  | otherwise =
      "You are a subagent. " ++ task ++ "\n\nYour input was:\n<input>\n" ++ input ++ "\n</input>"

-- | Finds the injected TODO anywhere in the input and returns the command after it.
findTodo :: String -> Maybe String
findTodo s = case stripPrefix "TODO: " s of
  Just command -> Just command
  Nothing -> case s of
    _ : rest -> findTodo rest
    [] -> Nothing

mkAgent :: forall a. (Typeable a) => Config -> Env -> String -> a
mkAgent config _ _
  | LLM.maxDepth config <= 0 = error "LBAC.mkAgent: recursion depth exceeded"
mkAgent config env userPrompt = unsafePerformIO $
  withLog (logPath config) $ \lg -> do
    ask <- withSession config
    tools <- maybe (resolveTools env) pure (resolvedTools env)
    result <- unsafeRunInterpreterWithArgs ["-XSafe"] $ do
      setupInterp env
      typeEnv <- setEnv env tools
      seed <- unsafeInterpret "setContext" "Config -> Env -> IO ()"
      liftIO $
        seed
          config {maxDepth = LLM.maxDepth config - 1}
          env {resolvedTools = Just tools}
      let ctx = buildContext requiredType typeEnv userPrompt
      code <- stripFence <$> liftIO (ask ctx)
      liftIO (logEvent lg (Request (LLM.systemPrompt config) ctx requiredType))
      liftIO (logEvent lg (Response code))
      runAttempt lg ask code 0
    case result of
      Left interpErr -> error (show interpErr)
      Right v -> pure v
  where
    -- Checked against the aliased spelling so only alias targets need scope.
    requiredType = applyAliases (typeAliases env) (show (typeRep (Proxy :: Proxy a)))

    runAttempt :: Log -> (String -> IO String) -> String -> Int -> Interpreter a
    runAttempt lg ask code attempt = do
      result <- try (unsafeInterpret code requiredType)
      case result of
        Right v -> do
          liftIO (logEvent lg Success)
          pure v
        Left err -> handleFailure lg ask (applyAliases (typeAliases env) (formatErr err)) attempt

    handleFailure :: Log -> (String -> IO String) -> String -> Int -> Interpreter a
    handleFailure lg ask errStr attempt
      | attempt < LLM.maxAttempts config - 1 = do
          liftIO (logEvent lg (Retry errStr))
          newCode <- stripFence <$> liftIO (ask (retryMessage errStr))
          liftIO (logEvent lg (Response newCode))
          runAttempt lg ask newCode (attempt + 1)
      | otherwise = do
          liftIO (logEvent lg (Failure errStr))
          error errStr
