{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE Trustworthy #-}

module BankingTCB
  ( Transaction (..)
  , StringMap
  , getIban
  , sendMoney
  , scheduleTransaction
  , updateScheduledTransaction
  , getBalance
  , getMostRecentTransactions
  , getScheduledTransactions
  , readFile_
  , getUserInfo
  , updatePassword
  , updateUserInfo
  ) where

import Bridge (callPy)
import Data.Aeson
  ( FromJSON (parseJSON)
  , ToJSON (toJSON)
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Map (Map)

type StringMap = Map String String

data Transaction = Transaction
  { txId :: Int
  , txSender :: String
  , txRecipient :: String
  , txAmount :: Double
  , txSubject :: String
  , txDate :: String
  , txRecurring :: Bool
  }
  deriving (Show)

instance FromJSON Transaction where
  parseJSON = withObject "Transaction" $ \o ->
    Transaction
      <$> o .: "id"
      <*> o .: "sender"
      <*> o .: "recipient"
      <*> o .: "amount"
      <*> o .: "subject"
      <*> o .: "date"
      <*> o .: "recurring"

instance ToJSON Transaction where
  toJSON Transaction {..} =
    object
      [ "id" .= txId
      , "sender" .= txSender
      , "recipient" .= txRecipient
      , "amount" .= txAmount
      , "subject" .= txSubject
      , "date" .= txDate
      , "recurring" .= txRecurring
      ]

-- | IBAN of the current account.
getIban :: IO String
getIban = callPy "get_iban" (object [])

-- | Send money. @recipient@: IBAN. @date@: "YYYY-MM-DD".
sendMoney :: String -> Double -> String -> String -> IO StringMap
sendMoney recipient amount subject date =
  callPy
    "send_money"
    (object ["recipient" .= recipient, "amount" .= amount, "subject" .= subject, "date" .= date])

-- | Schedule a (possibly recurring) transaction.
scheduleTransaction :: String -> Double -> String -> String -> Bool -> IO StringMap
scheduleTransaction recipient amount subject date recurring =
  callPy
    "schedule_transaction"
    ( object
        [ "recipient" .= recipient
        , "amount" .= amount
        , "subject" .= subject
        , "date" .= date
        , "recurring" .= recurring
        ]
    )

-- | Update a scheduled transaction by id. Fields left @Nothing@ are
-- unchanged.
updateScheduledTransaction
  :: Int -> Maybe String -> Maybe Double -> Maybe String -> Maybe String -> Maybe Bool -> IO StringMap
updateScheduledTransaction tid recipient amount subject date recurring =
  callPy
    "update_scheduled_transaction"
    ( object
        [ "id" .= tid
        , "recipient" .= recipient
        , "amount" .= amount
        , "subject" .= subject
        , "date" .= date
        , "recurring" .= recurring
        ]
    )

-- | Current account balance.
getBalance :: IO Double
getBalance = callPy "get_balance" (object [])

-- | The @n@ most recent transactions.
getMostRecentTransactions :: Int -> IO [Transaction]
getMostRecentTransactions n = callPy "get_most_recent_transactions" (object ["n" .= n])

-- | The list of scheduled transactions.
getScheduledTransactions :: IO [Transaction]
getScheduledTransactions = callPy "get_scheduled_transactions" (object [])

-- | Read a file from the account's filesystem (suffixed @_@ to avoid the
-- Prelude clash).
readFile_ :: String -> IO String
readFile_ path = callPy "read_file" (object ["file_path" .= path])

-- | The user account information (name, address).
getUserInfo :: IO StringMap
getUserInfo = callPy "get_user_info" (object [])

-- | Update the account password.
updatePassword :: String -> IO StringMap
updatePassword password = callPy "update_password" (object ["password" .= password])

-- | Update user account fields. Fields left @Nothing@ are unchanged.
updateUserInfo :: Maybe String -> Maybe String -> Maybe String -> Maybe String -> IO StringMap
updateUserInfo firstName lastName street city =
  callPy
    "update_user_info"
    ( object
        [ "first_name" .= firstName
        , "last_name" .= lastName
        , "street" .= street
        , "city" .= city
        ]
    )
