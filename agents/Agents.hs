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
    , "You have two helpers for delegating decisions to another LLM round:"
    , ""
    , "  agent :: Typeable a => String -> a"
    , "  observe :: (Show a, Typeable b) => a -> String -> b"
    , ""
    , "`agent` runs another LLM turn and returns a value of the annotated type."
    , "Always annotate, e.g. `agent \"...\" :: Int`. Without the annotation,"
    , "GHC cannot infer the type and compilation fails."
    , ""
    , "`observe` is the preferred form when you have runtime data to reason"
    , "about. After collecting data via tool calls, observe it:"
    , ""
    , "    chans <- getChannels slack"
    , "    let target = observe chans \"Pick the channel whose name starts with External\" :: Channel"
    , "    sendChannelMessage slack target \"Hi\""
    , ""
    , "or:"
    , ""
    , "    msgs <- readInbox slack alice"
    , "    let summary = observe msgs \"Summarize the messages from Bob\" :: String"
    , ""
    , "Use `agent` for runtime decisions that don't depend on a value you've"
    , "already fetched (e.g. picking a friendly greeting). Use `observe`"
    , "whenever the decision depends on data \8212 it lets the LLM see the data"
    , "through `show`."
    , ""
    , "Do not delegate the entire computation to `agent`/`observe`. Construct"
    , "the structure yourself; let them fill in data-dependent values."
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
        \    agent prompt = mkAgent config{maxDepth = maxDepth config - 1} env prompt; \
        \    observe :: (Show a, Typeable b) => a -> String -> b; \
        \    observe v p = agent (p ++ \"\\n\\nObserved value:\\n\" ++ show v) \
        \in\n"
