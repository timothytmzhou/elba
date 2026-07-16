{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the banking suite. The driver lives in InsecureApp.
module Main where

import BankingTCB
import Env (Env (..), defEnv)
import InsecureApp (runInsecureAgent)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- types
         ''Transaction
         -- account
       , 'getIban
       , 'getBalance
       , 'getUserInfo
       , 'updatePassword
       , 'updateUserInfo
         -- transactions
       , 'sendMoney
       , 'scheduleTransaction
       , 'updateScheduledTransaction
       , 'getMostRecentTransactions
       , 'getScheduledTransactions
         -- files
       , 'readFile_
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
