module Agents
  ( Env
  , gen
  ) where

import           Data.Proxy                   (Proxy (..))
import           Data.Typeable                (Typeable, typeRep)

import           Env
import           Interpret
import           LLM

agentPrompt :: String
agentPrompt = "You are a Haskell code generator. You output ONLY a single Haskell expression, nothing else. The expression will be evaluated with the environment described below, so do not use anything from modules not listed."

buildContext :: forall a. (Typeable a) => Proxy a -> Env -> String -> String
buildContext proxy env prompt = unlines
  [ "The expression must have type: " ++ show (typeRep proxy)
  , ""
  , "Available modules:"
  , unlines (map showImport env)
  , prompt
  ]

gen :: forall a. (Typeable a) => Config -> Env -> String -> IO a
gen config env prompt = do
  ask <- withSession config { systemPrompt = agentPrompt }
  code <- ask (buildContext (Proxy :: Proxy a) env prompt)
  putStrLn code
  result <- interpretCode env code
  case result of
    Nothing -> error "interpretation failed"
    Just a  -> pure a
