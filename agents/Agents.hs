{-# LANGUAGE Trustworthy #-}

module Agents
  ( Env
  , mkAgent
  ) where

import Control.Monad.Catch (try)
import Data.List (isPrefixOf)
import Data.Proxy (Proxy (..))
import Data.Typeable (Typeable, typeRep)
import Env
import GHC.IO (unsafePerformIO)
import LLM
import Language.Haskell.Interpreter hiding (Extension)
import Language.Haskell.Interpreter qualified as Hint
import Language.Haskell.Interpreter.Unsafe (unsafeInterpret, unsafeRunInterpreterWithArgs)
import Log (Event (..), Log, logEvent, withLog)

buildContext :: forall a. (Typeable a) => Proxy a -> [(String, String)] -> TypeEnv -> String -> String
buildContext proxy aliases typeEnv task =
  unlines
    [ task
    , ""
    , "Required type: " ++ applyAliases aliases (show (typeRep proxy))
    , "Allowed functions: " ++ show typeEnv
    ]

-- | Rewrites each alias source string to its target. Types rendered from
-- TypeRep arrive with synonyms expanded, this restores the alias the
-- model is meant to see.
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

-- | Strip a markdown code fence around the LLM's emission. If the response
-- contains lines whose first non-space chars are "```", return the content
-- between the first and second such lines. Otherwise return the input
-- unchanged. Handles ```haskell ... ```, bare ``` ... ```, and prose
-- surrounding the fenced block.
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

mkAgent :: forall a. (Typeable a) => Config -> Env -> String -> a
mkAgent config _ _
  | LLM.maxDepth config <= 0 = error "Agents.mkAgent: recursion depth exceeded"
mkAgent config env userPrompt = unsafePerformIO $
  withLog (logPath config) $ \lg -> do
    ask <- withSession config
    result <- unsafeRunInterpreterWithArgs ["-package", "template-haskell", "-XSafe"] $ do
      setupInterp env
      typeEnv <- setEnv env baseModules
      let ctx = buildContext (Proxy :: Proxy a) (typeAliases env) typeEnv userPrompt
      code <- stripFence <$> liftIO (ask ctx)
      liftIO (logEvent lg (Request (LLM.systemPrompt config) ctx requiredType))
      liftIO (logEvent lg (Response code))
      runAttempt lg ask code 0
    case result of
      Left interpErr -> error (show interpErr)
      Right f -> pure (f config env)
  where
    baseModules = ["Prelude", "LLM", "Agents", "Data.Typeable", "Language.Haskell.TH.Syntax"]
    requiredType = applyAliases (typeAliases env) (show (typeRep (Proxy :: Proxy a)))
    -- The interpreter checks against the aliased spelling, so only the
    -- alias targets need to be in scope, not their expansions.
    wrapperType = applyAliases (typeAliases env) (show (typeRep (Proxy :: Proxy (Config -> Env -> a))))

    runAttempt :: Log -> (String -> IO String) -> String -> Int -> Interpreter (Config -> Env -> a)
    runAttempt lg ask code attempt = do
      result <- try (unsafeInterpret (wrapper code) wrapperType)
      case result of
        Right f -> do
          liftIO (logEvent lg Success)
          pure f
        Left err -> handleFailure lg ask (applyAliases (typeAliases env) (formatErr err)) attempt

    handleFailure :: Log -> (String -> IO String) -> String -> Int -> Interpreter (Config -> Env -> a)
    handleFailure lg ask errStr attempt
      | attempt < LLM.maxAttempts config - 1 = do
          liftIO (logEvent lg (Retry errStr))
          newCode <- stripFence <$> liftIO (ask (retryMessage errStr))
          liftIO (logEvent lg (Response newCode))
          runAttempt lg ask newCode (attempt + 1)
      | otherwise = do
          liftIO (logEvent lg (Failure errStr))
          error errStr

    -- Trailing \n: the LLM emission is appended verbatim; without it, multi-line
    -- code starts on our prefix line and breaks Haskell's offside rule.
    -- Decrementing maxDepth on each recursive call caps total nesting.
    wrapper =
      (++)
        "\\config env -> \
        \let subagent :: Typeable a => String -> String -> a; \
        \    subagent task input = mkAgent config{maxDepth = maxDepth config - 1} env \
        \      (task ++ \"\\n<input>\\n\" ++ input ++ \"\\n</input>\") \
        \in\n"
