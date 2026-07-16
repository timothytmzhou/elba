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
