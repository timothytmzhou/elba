{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- | Haskell mirrors of the pydantic record types AgentDojo's
-- workspace/travel/banking suites return over the JSON bridge. Field
-- names follow the JSON keys produced by @model_dump(mode="json")@ (see
-- eval/evalkit/bridge.py). Parsers are deliberately lenient: optional
-- fields default rather than fail, so schema drift in unused fields does
-- not break a run.
--
-- These are the /insecure/ read types shared by more than one suite
-- (email + calendar appear in both workspace and travel). Suite-specific
-- types live in each suite's TCB module.
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
  , withObject
  , object
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )

-- | Opaque email id (a stringly id in AgentDojo, e.g. "0").
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
