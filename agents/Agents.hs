{-# LANGUAGE Trustworthy #-}

module Agents
  ( Config
  , Env
  , mkAgent
  , setContext
  , subagent
  ) where

import Control.Monad.Catch (try)
import Data.Char (isAlpha)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf)
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

-- Tool name to signature and optional docstring, shown to the model.
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
  sigs <- mapM (typeOf . parenIfOp . toolName) values
  pure (TypeEnv (Map.fromList [(toolName t, (sig, toolDoc t)) | (t, sig) <- zip values sigs]))

-- In scope unqualified like Prelude, so emitted code can spawn subagents.
baseModules :: [ModuleName]
baseModules = ["Prelude", "Agents"]

-- Ambient base vocabulary, qualified so name clashes are impossible.
-- The system prompt lists these.
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

-- Wraps operator names in parens for import lists and typeOf queries.
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

-- | Strips a markdown code fence around the LLM's emission if present.
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

-- The interpreter keeps its own copy of this module, so this slot is seeded through setContext.
{-# NOINLINE contextRef #-}
contextRef :: IORef (Config, Env)
contextRef = unsafePerformIO (newIORef (error "Agents.subagent: no agent has run"))

-- | Writes contextRef in the interpreted copy of this module.
setContext :: Config -> Env -> IO ()
setContext config env = writeIORef contextRef (config, env)

-- | Spawns a nested agent on the running agent's context. Meant for
-- interpreted code. Every spawn decrements maxDepth, which caps total
-- nesting.
subagent :: (Typeable a) => String -> String -> a
subagent task input = unsafePerformIO $ do
  (config, env) <- readIORef contextRef
  pure (mkAgent config env (task ++ "\n<input>\n" ++ input ++ "\n</input>"))

mkAgent :: forall a. (Typeable a) => Config -> Env -> String -> a
mkAgent config _ _
  | LLM.maxDepth config <= 0 = error "Agents.mkAgent: recursion depth exceeded"
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
