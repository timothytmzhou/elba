{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the banking suite. The Banking policy is
-- undefined so this builds but fails at run time on the first tool call.
module Main where

import AgentApp (runSecureAgent)
import Banking
import Env (Env (..), defEnv)
import IFC (DC, DCLabeled, toLabeled, unlabel)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''DC
       , ''DCLabeled
       , ''Transaction
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
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runSecureAgent agentEnv id
