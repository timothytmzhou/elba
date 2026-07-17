{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

module WorkspaceTCB
  ( EmailId (..)
  , Email (..)
  , CalendarEvent (..)
  , EmailContact (..)
  , CloudFileId (..)
  , CloudDriveFile (..)
    -- * Email
  , getUnreadEmails
  , getSentEmails
  , getReceivedEmails
  , getDraftEmails
  , searchEmails
  , sendEmail
  , deleteEmail
  , searchContactsByName
  , searchContactsByEmail
    -- * Calendar
  , getCurrentDay
  , searchCalendarEvents
  , getDayCalendarEvents
  , createCalendarEvent
  , cancelCalendarEvent
  , rescheduleCalendarEvent
  , addCalendarEventParticipants
    -- * Cloud drive
  , listFiles
  , searchFilesByFilename
  , searchFiles
  , getFileById
  , createFile
  , appendToFile
  , deleteFile
  , shareFile
  ) where

import Bridge (callPy)
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

----------------------------------------------------------------
-- Read types, shared with the travel suite (email + calendar).
----------------------------------------------------------------

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
  , eventLocation :: Maybe String
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

----------------------------------------------------------------
-- Email
----------------------------------------------------------------

-- | Returns all the unread emails in the inbox. Each email has a sender, a subject, and a body.
-- The emails are marked as read after this function is called.
getUnreadEmails :: IO [Email]
getUnreadEmails = callPy "get_unread_emails" (object [])

-- | Returns all the sent emails in the inbox. Each email has a recipient, a subject, and a body.
getSentEmails :: IO [Email]
getSentEmails = callPy "get_sent_emails" (object [])

-- | Returns all the received emails in the inbox. Each email has a sender, a subject, and a body.
getReceivedEmails :: IO [Email]
getReceivedEmails = callPy "get_received_emails" (object [])

-- | Returns all the draft emails in the inbox. Each email has a recipient, a subject, and a body.
getDraftEmails :: IO [Email]
getDraftEmails = callPy "get_draft_emails" (object [])

-- | Searches for emails in the inbox that contain the given query in the subject or body. If @address@ is provided,
-- only emails from that address are searched.
searchEmails :: String -> String -> IO [Email]
searchEmails query sender =
  callPy "search_emails" (object ["query" .= query, "sender" .= senderArg])
  where
    senderArg = if null sender then Nothing else Just sender

-- | Sends an email with the given @body@ to the given @address@. Returns a dictionary with the email details.
sendEmail :: [String] -> String -> String -> IO Email
sendEmail recipients subject body =
  callPy
    "send_email"
    (object ["recipients" .= recipients, "subject" .= subject, "body" .= body])

-- | Deletes the email with the given @email_id@ from the inbox.
deleteEmail :: EmailId -> IO String
deleteEmail eid = callPy "delete_email" (object ["email_id" .= eid])

-- | Finds contacts in the inbox's contact list by name.
-- It returns a list of contacts that match the given name.
searchContactsByName :: String -> IO [EmailContact]
searchContactsByName query = callPy "search_contacts_by_name" (object ["query" .= query])

-- | Finds contacts in the inbox's contact list by email.
-- It returns a list of contacts that match the given email.
searchContactsByEmail :: String -> IO [EmailContact]
searchContactsByEmail query = callPy "search_contacts_by_email" (object ["query" .= query])

----------------------------------------------------------------
-- Calendar
----------------------------------------------------------------

-- | Returns the current day in ISO format, e.g. '2022-01-01'.
-- It is useful to know what the current day, year, or month is, as the assistant
-- should not assume what the current date is.
getCurrentDay :: IO String
getCurrentDay = callPy "get_current_day" (object [])

-- | Searches calendar events that match the given query in the tile or the description. If provided, filters events by date.
searchCalendarEvents :: String -> String -> IO [CalendarEvent]
searchCalendarEvents query date =
  callPy "search_calendar_events" (object ["query" .= query, "date" .= dateArg])
  where
    dateArg = if null date then Nothing else Just date

-- | Returns the appointments for the given @day@. Returns a list of dictionaries with informations about each meeting.
getDayCalendarEvents :: String -> IO [CalendarEvent]
getDayCalendarEvents day = callPy "get_day_calendar_events" (object ["day" .= day])

-- | Creates a new calendar event with the given details and adds it to the calendar.
-- It also sends an email to the participants with the event details.
createCalendarEvent :: String -> String -> String -> String -> [String] -> IO CalendarEvent
createCalendarEvent title startTime endTime description participants =
  callPy
    "create_calendar_event"
    ( object
        [ "title" .= title
        , "start_time" .= startTime
        , "end_time" .= endTime
        , "description" .= description
        , "participants" .= participants
        ]
    )

-- | Cancels the event with the given @event_id@. The event will be marked as canceled and no longer appear in the calendar.
-- It will also send an email to the participants notifying them of the cancellation.
cancelCalendarEvent :: String -> IO String
cancelCalendarEvent eid = callPy "cancel_calendar_event" (object ["event_id" .= eid])

-- | Reschedules the event with the given @event_id@ to the new start and end times.
-- It will also send an email to the participants notifying them of the rescheduling.
rescheduleCalendarEvent :: String -> String -> String -> IO CalendarEvent
rescheduleCalendarEvent eid newStart newEnd =
  callPy
    "reschedule_calendar_event"
    (object ["event_id" .= eid, "new_start_time" .= newStart, "new_end_time" .= endArg])
  where
    endArg = if null newEnd then Nothing else Just newEnd

-- | Adds the given @participants@ to the event with the given @event_id@.
-- It will also email the new participants notifying them of the event.
addCalendarEventParticipants :: String -> [String] -> IO CalendarEvent
addCalendarEventParticipants eid participants =
  callPy "add_calendar_event_participants" (object ["event_id" .= eid, "participants" .= participants])

----------------------------------------------------------------
-- Cloud drive
----------------------------------------------------------------

-- | Retrieve all files in the cloud drive.
listFiles :: IO [CloudDriveFile]
listFiles = callPy "list_files" (object [])

-- | Get a file from a cloud drive by its filename. It returns a list of files.
-- Each file contains the file id, the content, the file type, and the filename.
searchFilesByFilename :: String -> IO [CloudDriveFile]
searchFilesByFilename name = callPy "search_files_by_filename" (object ["filename" .= name])

-- | Search for files in the cloud drive by content.
searchFiles :: String -> IO [CloudDriveFile]
searchFiles query = callPy "search_files" (object ["query" .= query])

-- | Get a file from a cloud drive by its ID.
getFileById :: CloudFileId -> IO CloudDriveFile
getFileById fid = callPy "get_file_by_id" (object ["file_id" .= fid])

-- | Create a new file in the cloud drive.
createFile :: String -> String -> IO CloudDriveFile
createFile name content = callPy "create_file" (object ["filename" .= name, "content" .= content])

-- | Append content to a file in the cloud drive.
appendToFile :: CloudFileId -> String -> IO CloudDriveFile
appendToFile fid content = callPy "append_to_file" (object ["file_id" .= fid, "content" .= content])

-- | Delete a file from the cloud drive by its filename.
-- It returns the file that was deleted.
deleteFile :: CloudFileId -> IO CloudDriveFile
deleteFile fid = callPy "delete_file" (object ["file_id" .= fid])

-- | Share a file with a user.
shareFile :: CloudFileId -> String -> String -> IO CloudDriveFile
shareFile fid email permission =
  callPy "share_file" (object ["file_id" .= fid, "email" .= email, "permission" .= permission])
