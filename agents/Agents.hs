{-# LANGUAGE Trustworthy #-}

module Agents
  ( Env
  , mkAgent
  ) where

import Control.Monad.Catch (try)
import Data.Proxy (Proxy (..))
import Data.Typeable (Typeable, typeRep)
import Env
import GHC.IO (unsafePerformIO)
import LLM
import Language.Haskell.Interpreter hiding (Extension)
import Language.Haskell.Interpreter qualified as Hint
import Language.Haskell.Interpreter.Unsafe (unsafeRunInterpreterWithArgs)
import Log (Event (..), Log, logEvent, withLog)

systemPrompt :: String
systemPrompt =
  unlines
    [ "You generate Haskell code."
    , "Output exactly one valid Haskell expression and nothing else. The expression may span multiple lines (e.g. do-blocks, let-bindings)."
    , ""
    , "A special recursive function is available:"
    , ""
    , "  agent :: Typeable a => String -> a"
    , ""
    , "Whenever you use `agent`, you MUST provide an explicit type annotation"
    , "on its result, e.g.:"
    , ""
    , "    let url = agent \"Find the article URL\" :: String"
    , "    summary <- agent \"Summarize the article\" :: DC String"
    , ""
    , "Without the annotation, GHC cannot infer the return type and your code"
    , "will fail to compile."
    , ""
    , "You can use `agent` when you need to make a subsequent decision based on"
    , "a value that will only be known at runtime. You must construct the"
    , "overall Haskell expression yourself; do not delegate the entire"
    , "computation to `agent`."
    , ""
    , "If you receive a follow-up message containing a GHC error, your previous"
    , "code did not compile. Re-emit a single corrected Haskell expression of"
    , "the same target type, and nothing else."
    , ""
    , "You will be supplied with a target type and a list of allowed functions."
    , "You MUST produce an expression of that type, using those functions as"
    , "well as Prelude."
    ]

buildContext :: forall a. (Typeable a) => Proxy a -> TypeEnv -> String -> String
buildContext proxy typeEnv task =
  unlines
    [ task
    , ""
    , "Required type: " ++ show (typeRep proxy)
    , "Allowed functions: " ++ show typeEnv
    ]

retryMessage :: String -> String
retryMessage errStr =
  unlines
    [ "Your previous code did not compile:"
    , ""
    , errStr
    , ""
    , "Re-emit a corrected Haskell expression of the required type."
    ]

formatErr :: InterpreterError -> String
formatErr (WontCompile ghcErrors) = unlines (map errMsg ghcErrors)
formatErr e = show e

setupInterp :: Env -> Interpreter ()
setupInterp env = do
  set [searchPath := []]
  set [languageExtensions := map (Hint.UnknownExtension . show) (extensions env)]

mkAgent :: forall a. (Typeable a) => Config -> Env -> String -> a
mkAgent config env userPrompt = unsafePerformIO $
  withLog (logPath config) $ \lg -> do
    ask <- withSession config {LLM.systemPrompt = Agents.systemPrompt}
    result <- unsafeRunInterpreterWithArgs ["-package", "template-haskell", "-XSafe"] $ do
      setupInterp env
      typeEnv <- setEnv env baseModules
      let ctx = buildContext (Proxy :: Proxy a) typeEnv userPrompt
      code <- liftIO (ask ctx)
      liftIO (logEvent lg (Request Agents.systemPrompt userPrompt requiredType))
      liftIO (logEvent lg (Response code))
      runAttempt lg ask code 0
    case result of
      Left interpErr -> error (show interpErr)
      Right f -> pure (f config env)
  where
    baseModules = ["Prelude", "LLM", "Agents", "Data.Typeable", "Language.Haskell.TH.Syntax"]
    requiredType = show (typeRep (Proxy :: Proxy a))

    runAttempt :: Log -> (String -> IO String) -> String -> Int -> Interpreter (Config -> Env -> a)
    runAttempt lg ask code attempt = do
      result <- try (interpret (wrapper code) (as :: Config -> Env -> a))
      case result of
        Right f -> do
          liftIO (logEvent lg Success)
          pure f
        Left err -> handleFailure lg ask (formatErr err) attempt

    handleFailure :: Log -> (String -> IO String) -> String -> Int -> Interpreter (Config -> Env -> a)
    handleFailure lg ask errStr attempt
      | attempt < LLM.maxAttempts config - 1 = do
          liftIO (logEvent lg (Retry errStr))
          newCode <- liftIO (ask (retryMessage errStr))
          liftIO (logEvent lg (Response newCode))
          runAttempt lg ask newCode (attempt + 1)
      | otherwise = do
          liftIO (logEvent lg (Failure errStr))
          error errStr

    -- Trailing \n: the LLM emission is appended verbatim; without it, multi-line
    -- code starts on our prefix line and breaks Haskell's offside rule.
    wrapper =
      (++)
        "\\config env -> \
        \let agent :: Typeable a => String -> a; \
        \    agent prompt = mkAgent config env prompt \
        \in\n"
