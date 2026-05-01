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
    , "Each call to `agent` runs another LLM turn that must emit code of the"
    , "annotated type. Always annotate, e.g. `agent \"...\" :: Int`."
    , "Without the annotation, GHC cannot infer the type and compilation fails."
    , ""
    , "The sub-agent's code runs in a fresh scope and cannot see the values in"
    , "your local scope (function parameters, do-block bindings, etc.). If you"
    , "need the sub-agent's code to use such values, annotate with a function"
    , "type so it produces a function, then apply your runtime values to it:"
    , ""
    , "    let summarize = agent \"Summarize Bob's article\" :: Slack -> Web -> DC String"
    , "    result <- summarize slack web"
    , ""
    , "Use `agent` to defer reasoning that depends on data you don't yet have."
    , "Do not use `agent` for information already given in the prompt, and do"
    , "not delegate the entire computation to `agent`."
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
mkAgent config _ _
  | LLM.maxDepth config <= 0 = error "Agents.mkAgent: recursion depth exceeded"
mkAgent config env userPrompt = unsafePerformIO $
  withLog (logPath config) $ \lg -> do
    ask <- withSession config {LLM.systemPrompt = Agents.systemPrompt}
    result <- unsafeRunInterpreterWithArgs ["-package", "template-haskell", "-XSafe"] $ do
      setupInterp env
      typeEnv <- setEnv env baseModules
      let ctx = buildContext (Proxy :: Proxy a) typeEnv userPrompt
      code <- liftIO (ask ctx)
      liftIO (logEvent lg (Request Agents.systemPrompt ctx requiredType))
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
    -- Decrementing maxDepth on each recursive call caps total nesting.
    wrapper =
      (++)
        "\\config env -> \
        \let agent :: Typeable a => String -> a; \
        \    agent prompt = mkAgent config{maxDepth = maxDepth config - 1} env prompt \
        \in\n"
