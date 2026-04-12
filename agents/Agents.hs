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
import Language.Haskell.Interpreter
import Language.Haskell.Interpreter.Unsafe (unsafeRunInterpreterWithArgs)

systemPrompt :: String
systemPrompt =
  unlines
    [ "You are a Haskell code generator. Output ONLY a single Haskell expression, nothing else.",
      "",
      "You also have a special function:",
      "  agent :: String -> a",
      "agent takes a prompt and produces a value of whatever type the call site requires.",
      "Use agent when a decision depends on a runtime value not known at generation time.",
      "",
      "You will be supplied with a target type and a list of allowed functions.",
      "You MUST produce an expression of that type, using those functions as well as anything from Prelude."
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
    go :: (String -> IO String) -> String -> IO a
    go ask p = do
      result <- unsafeRunInterpreterWithArgs ["-package", "template-haskell"] $ do
        typeEnv <- setEnv env ["Prelude", "LLM", "Agents", "Language.Haskell.TH"]
        let context = buildContext (Proxy :: Proxy a) typeEnv p
        code <- liftIO $ ask context
        liftIO $ putStrLn context >> putStrLn code
        interpret (wrapper code) (as :: Config -> Env -> a)
      case result of
        Left err -> error $ show err
        Right f -> pure (f config env)
    wrapper = (++) "\\config env -> let agent prompt = mkAgent config env prompt in "
