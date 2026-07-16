module Main where

import AgentApp (runInsecureAgent)
import Env (Env (..), Extension (OverloadedStrings), defEnv)

agentEnv :: Env
agentEnv =
  defEnv
    { modules = ["BankingTCB"]
    , functions = [("Text.Printf", "printf")]
    , extensions = [OverloadedStrings]
    }

main :: IO ()
main = runInsecureAgent agentEnv
