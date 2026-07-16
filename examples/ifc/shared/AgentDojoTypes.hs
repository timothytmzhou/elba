{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- Haskell mirrors of the pydantic records the workspace, travel, and
-- banking suites return over the bridge. Parsers default missing fields
-- rather than fail so unused fields never break a run.
module AgentDojoTypes
  ( EmailId (..)
  , Email (..)
  , CalendarEvent (..)
  , EmailContact (..)
  , CloudFileId (..)
  , CloudDriveFile (..)
  ) where

import Data.Aeson
  ( FromJSON (parseJSON)
  , ToJSON (toJSON)
  , object
  , withObject
  , (.!=)
  , (.:)
  , (.:?)
  , (.=)
  )

newtype EmailId = EmailId String
  deriving (Eq, Ord, Show)

instance FromJSON EmailId where
  parseJSON v = EmailId <$> parseJSON v

instance ToJSON EmailId where
  toJSON (EmailId s) = toJSON s

data Email = Email
  { emailId :: EmailId
  , sender :: String
  , recipients :: [String]
  , cc :: [String]
  , bcc :: [String]
  , subject :: String
  , body :: String
  , status :: String
  , read_ :: Bool
  }
  deriving (Show)

instance FromJSON Email where
  parseJSON = withObject "Email" $ \o ->
    Email
      <$> o .: "id_"
      <*> o .: "sender"
      <*> o .:? "recipients" .!= []
      <*> o .:? "cc" .!= []
      <*> o .:? "bcc" .!= []
      <*> o .:? "subject" .!= ""
      <*> o .:? "body" .!= ""
      <*> o .:? "status" .!= ""
      <*> o .:? "read" .!= False

data CalendarEvent = CalendarEvent
  { eventId :: String
  , title :: String
  , description :: String
  , startTime :: String
  , endTime :: String
  , location :: Maybe String
  , participants :: [String]
  }
  deriving (Show)

instance FromJSON CalendarEvent where
  parseJSON = withObject "CalendarEvent" $ \o ->
    CalendarEvent
      <$> o .: "id_"
      <*> o .:? "title" .!= ""
      <*> o .:? "description" .!= ""
      <*> o .:? "start_time" .!= ""
      <*> o .:? "end_time" .!= ""
      <*> o .:? "location"
      <*> o .:? "participants" .!= []

data EmailContact = EmailContact
  { contactEmail :: String
  , contactName :: String
  }
  deriving (Show)

instance FromJSON EmailContact where
  parseJSON = withObject "EmailContact" $ \o ->
    EmailContact <$> o .: "email" <*> o .: "name"

instance ToJSON EmailContact where
  toJSON (EmailContact e n) = object ["email" .= e, "name" .= n]

newtype CloudFileId = CloudFileId String
  deriving (Eq, Ord, Show)

instance FromJSON CloudFileId where
  parseJSON v = CloudFileId <$> parseJSON v

instance ToJSON CloudFileId where
  toJSON (CloudFileId s) = toJSON s

data CloudDriveFile = CloudDriveFile
  { fileId :: CloudFileId
  , filename :: String
  , fileContent :: String
  , owner :: String
  , fileSize :: Int
  }
  deriving (Show)

instance FromJSON CloudDriveFile where
  parseJSON = withObject "CloudDriveFile" $ \o ->
    CloudDriveFile
      <$> o .: "id_"
      <*> o .:? "filename" .!= ""
      <*> o .:? "content" .!= ""
      <*> o .:? "owner" .!= ""
      <*> o .:? "size" .!= 0
