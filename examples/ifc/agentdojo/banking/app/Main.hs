{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the banking suite.
module Main where

import AgentApp (runInsecureAgent)
import BankingTCB
import Env (Env (..), defEnv)
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
       , 'updatePassword
       , 'updateUserInfo
       , 'sendMoney
       , 'scheduleTransaction
       , 'updateScheduledTransaction
       , 'getMostRecentTransactions
       , 'getScheduledTransactions
       , 'readFile_
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
