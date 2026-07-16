module Main where

import AgentApp (runInsecureAgent)
import Env (Env (..), Extension (OverloadedStrings), defEnv)

agentEnv :: Env
agentEnv =
  defEnv
    { modules = ["BankingTCB"]
    , extensions = [OverloadedStrings]
    }

main :: IO ()
main = runInsecureAgent agentEnv
