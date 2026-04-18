{-# LANGUAGE Trustworthy #-}

module Agents
  ( Env,
    mkAgent,
  )
where

import Data.Proxy (Proxy (..))
import Data.Typeable (Typeable, typeRep)
import Env
import GHC.IO (unsafePerformIO)
import LLM
import Language.Haskell.Interpreter hiding (Extension)
import Language.Haskell.Interpreter qualified as Hint
import Language.Haskell.Interpreter.Unsafe (unsafeRunInterpreterWithArgs)

systemPrompt :: String
systemPrompt =
  unlines
    [ "You generate Haskell code.",
      "Output exactly one valid Haskell expression and nothing else. The expression may span multiple lines (e.g. do-blocks, let-bindings).",
      "",
      "A special function is available:",
      "",
      "  agent :: String -> a",
      "",
      "At runtime, agent will query you to return a Haskell expression of the required type.",
      "",
      "You can use agent when you need to make a subsequent decision based on a value that will only be known at runtime.",
      "You must construct the overall Haskell expression yourself.",
      "Do not delegate the entire computation to agent.",
      "",
      "You will be supplied with a target type and a list of allowed functions.",
      "You MUST produce an expression of that type, using those functions as well as Prelude."
    ]

buildContext :: forall a. (Typeable a) => Proxy a -> TypeEnv -> String -> String
buildContext proxy typeEnv task =
  unlines
    [ task,
      "",
      "Required type: " ++ show (typeRep proxy),
      "Allowed functions: " ++ show typeEnv
    ]

mkAgent :: forall a. (Typeable a) => Config -> Env -> String -> a
mkAgent config env prompt = unsafePerformIO $ do
  ask <- withSession config {LLM.systemPrompt = Agents.systemPrompt}
  go ask prompt
  where
    baseModules = ["Prelude", "LLM", "Agents", "Data.Typeable", "Language.Haskell.TH.Syntax"]
    go :: (String -> IO String) -> String -> IO a
    go ask p = do
      result <- unsafeRunInterpreterWithArgs ["-package", "template-haskell", "-XSafe"] $ do
        set [searchPath := []]
        set [languageExtensions := map (Hint.UnknownExtension . show) (extensions env)]
        typeEnv <- setEnv env baseModules
        let context = buildContext (Proxy :: Proxy a) typeEnv p
        code <- liftIO $ ask context
        liftIO $ putStrLn context >> putStrLn code
        interpret (wrapper code) (as :: Config -> Env -> a)
      case result of
        Left err -> error $ show err
        Right f -> pure (f config env)
    wrapper =
      (++)
        "\\config env -> \
        \let agent :: Typeable a => String -> a; \
        \    agent prompt = mkAgent config env prompt \
        \in "
