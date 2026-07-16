module Main where

import AgentApp (runSecureAgent)
import Env (Env (..), Extension (OverloadedStrings), defEnv)

agentEnv :: Env
agentEnv =
  defEnv
    { modules = ["Workspace", "IFC"]
    , functions = [("Text.Printf", "printf")]
    , extensions = [OverloadedStrings]
    }

main :: IO ()
main = runSecureAgent agentEnv id
