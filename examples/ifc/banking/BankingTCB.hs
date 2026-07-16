{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure tool surface for the banking suite.
module BankingTCB (module BankingTCB) where

import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), object, withObject, (.:), (.=))
import Data.Map (Map)
import Tool (defTool, defTools)

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

defTools
  [ defTool "getIban" "get_iban" [] [t|IO String|]
  , defTool "sendMoney" "send_money" ["recipient", "amount", "subject", "date"] [t|String -> Double -> String -> String -> IO StringMap|]
  , defTool "scheduleTransaction" "schedule_transaction" ["recipient", "amount", "subject", "date", "recurring"] [t|String -> Double -> String -> String -> Bool -> IO StringMap|]
  , defTool "updateScheduledTransaction" "update_scheduled_transaction" ["id", "recipient", "amount", "subject", "date", "recurring"] [t|Int -> Maybe String -> Maybe Double -> Maybe String -> Maybe String -> Maybe Bool -> IO StringMap|]
  , defTool "getBalance" "get_balance" [] [t|IO Double|]
  , defTool "getMostRecentTransactions" "get_most_recent_transactions" ["n"] [t|Int -> IO [Transaction]|]
  , defTool "getScheduledTransactions" "get_scheduled_transactions" [] [t|IO [Transaction]|]
  , defTool "readFile_" "read_file" ["file_path"] [t|String -> IO String|]
  , defTool "getUserInfo" "get_user_info" [] [t|IO StringMap|]
  , defTool "updatePassword" "update_password" ["password"] [t|String -> IO StringMap|]
  , defTool "updateUserInfo" "update_user_info" ["first_name", "last_name", "street", "city"] [t|Maybe String -> Maybe String -> Maybe String -> Maybe String -> IO StringMap|]
  ]
