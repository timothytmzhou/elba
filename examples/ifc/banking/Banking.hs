{-# LANGUAGE Trustworthy #-}

-- | IFC-secured surface for the banking suite. THE POLICY IS NOT WRITTEN
-- YET: every binding below is 'undefined', to be implemented by hand
-- following the slack suite as the worked reference. Signatures are
-- PROVISIONAL — where the labels sit is part of the policy design.
-- The insecure executable (agentdojo-banking) only uses BankingTCB.
module Banking
  ( DC
  , DCLabeled
  , Transaction
  , StringMap
  , getIban
  , getBalance
  , getMostRecentTransactions
  , getScheduledTransactions
  , sendMoney
  , scheduleTransaction
  , updateScheduledTransaction
  , readFile_
  , getUserInfo
  , updatePassword
  , updateUserInfo
  ) where

import BankingTCB (StringMap, Transaction)
import LIO.DCLabel (DC, DCLabeled)

getIban :: DC String
getIban = undefined

getBalance :: DC (DCLabeled Double)
getBalance = undefined

getMostRecentTransactions :: Int -> DC (DCLabeled [Transaction])
getMostRecentTransactions = undefined

getScheduledTransactions :: DC (DCLabeled [Transaction])
getScheduledTransactions = undefined

sendMoney :: DCLabeled String -> Double -> DCLabeled String -> String -> DC ()
sendMoney = undefined

scheduleTransaction :: DCLabeled String -> Double -> DCLabeled String -> String -> Bool -> DC ()
scheduleTransaction = undefined

updateScheduledTransaction
  :: Int -> Maybe (DCLabeled String) -> Maybe Double -> Maybe (DCLabeled String)
  -> Maybe String -> Maybe Bool -> DC ()
updateScheduledTransaction = undefined

readFile_ :: String -> DC (DCLabeled String)
readFile_ = undefined

getUserInfo :: DC (DCLabeled StringMap)
getUserInfo = undefined

updatePassword :: DCLabeled String -> DC ()
updatePassword = undefined

updateUserInfo
  :: Maybe (DCLabeled String) -> Maybe (DCLabeled String)
  -> Maybe (DCLabeled String) -> Maybe (DCLabeled String) -> DC ()
updateUserInfo = undefined
