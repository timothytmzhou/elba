module Agents
  ( Env
  , mkAgent
  ) where

import           Data.Proxy                   (Proxy (..))
import           Data.Typeable                (Typeable, typeRep)
import           GHC.IO                       (unsafePerformIO)
import           Language.Haskell.Interpreter

import           Env
import           LLM

agentPrompt :: String
agentPrompt = unlines
  [ "You are a Haskell code generator. You output ONLY a single Haskell expression, nothing else."
  , "The expression will be evaluated with the environment described below, so do not use anything from modules not listed."
  , ""
  , "You have access to a special function:"
  , "  agent :: String -> a"
  , "Calling `agent prompt` runs a sub-generation with the same context and returns any type."
  , "Use agent when you need to defer your decision to runtime."
  ]

buildContext :: forall a. (Typeable a) => Proxy a -> TypeEnv -> String -> String
buildContext proxy typeEnv prompt = unlines
  [ "The expression must have type: " ++ show (typeRep proxy)
  , ""
  , "Available functions:"
  , show typeEnv
  , prompt
  ]

mkAgent :: forall a. (Typeable a) => Config -> Env -> String -> a
mkAgent config env prompt = unsafePerformIO $ do
  ask <- withSession config { systemPrompt = agentPrompt }
  go ask prompt
  where
    go :: (String -> IO String) -> String -> IO a
    go ask p = do
      result <- runInterpreter $ do
        typeEnv <- setEnv env ["Prelude", "Agents", "LLM"]
        code    <- liftIO $ ask (buildContext (Proxy :: Proxy a) typeEnv p)
        interpret (wrapper code) (as :: Config -> Env -> a)
      case result of
        Left _  -> go ask "That expression failed to interpret. Try again."
        Right f -> pure (f config env)
    wrapper = (++) "\\config env -> let agent prompt = mkAgent config env prompt in "
