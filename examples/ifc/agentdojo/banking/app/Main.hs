{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the banking suite. The driver lives in InsecureApp.
-- The tool set is the whole BankingTCB surface plus printf.
module Main where

import Env (Env (..), defEnv)
import InsecureApp (runInsecureAgent)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $(addTools ['printf])
    defEnv
      { modules = ["BankingTCB"]
      , extensions = [OverloadedStrings]
      }

main :: IO ()
main = runInsecureAgent agentEnv
