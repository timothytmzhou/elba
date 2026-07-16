{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (runSecureAgent)
import Banking
import Env (Env (..), defEnv)
import IFC (toLabeled, unlabel)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''Transaction
       , 'getIban
       , 'getBalance
       , 'getUserInfo
       , 'sendMoney
       , 'scheduleTransaction
       , 'getMostRecentTransactions
       , 'getScheduledTransactions
       , 'readFile_
       , 'unlabel
       , 'toLabeled
       , 'printf
       ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = runSecureAgent agentEnv id
