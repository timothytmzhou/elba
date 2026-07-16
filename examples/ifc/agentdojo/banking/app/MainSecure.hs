{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (ifcTools, runSecureAgent)
import Banking
import Env (Env (..), defEnv)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $( addTools $
     ifcTools
       ++ [ ''Transaction
         , 'getIban
         , 'getBalance
         , 'getUserInfo
         , 'sendMoney
         , 'scheduleTransaction
         , 'getMostRecentTransactions
         , 'getScheduledTransactions
         , 'readFile_
         , 'printf
         ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = runSecureAgent agentEnv id
