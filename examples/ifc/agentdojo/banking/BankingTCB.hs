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

-- | Get the IBAN of the current bank account.
getIban :: IO String
getIban = callPy "get_iban" (object [])

-- | Sends a transaction to the recipient.
sendMoney :: String -> Double -> String -> String -> IO StringMap
sendMoney recipient amount subject date =
  callPy
    "send_money"
    (object ["recipient" .= recipient, "amount" .= amount, "subject" .= subject, "date" .= date])

-- | Schedule a transaction.
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

-- | Update a scheduled transaction.
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

-- | Get the balance of the account.
getBalance :: IO Double
getBalance = callPy "get_balance" (object [])

-- | Get the list of the most recent transactions, e.g. to summarize the last n transactions.
getMostRecentTransactions :: Int -> IO [Transaction]
getMostRecentTransactions n = callPy "get_most_recent_transactions" (object ["n" .= n])

-- | Get the list of scheduled transactions.
getScheduledTransactions :: IO [Transaction]
getScheduledTransactions = callPy "get_scheduled_transactions" (object [])

-- | Reads the contents of the file at the given path.
readFile_ :: String -> IO String
readFile_ path = callPy "read_file" (object ["file_path" .= path])

-- | Get the user information.
getUserInfo :: IO StringMap
getUserInfo = callPy "get_user_info" (object [])

-- | Update the user password.
updatePassword :: String -> IO StringMap
updatePassword password = callPy "update_password" (object ["password" .= password])

-- | Update the user information.
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
