{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- | Insecure tool surface for AgentDojo's @workspace@ suite (email +
-- calendar + cloud drive). Each binding forwards to the Python tool of the
-- same snake_case name over the JSON bridge. This is the no-policy surface
-- used by the @agentdojo-workspace@ executable; the IFC-secured surface is
-- left to be written by hand (see workspace/policy/Policy.hs).
module WorkspaceTCB
  ( module AgentDojoTypes
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

import AgentDojoTypes
import Bridge (callPy)
import Data.Aeson (object, (.=))

----------------------------------------------------------------
-- Email
----------------------------------------------------------------

-- | Return all unread emails in the inbox (marks them read).
getUnreadEmails :: IO [Email]
getUnreadEmails = callPy "get_unread_emails" (object [])

-- | Return all sent emails.
getSentEmails :: IO [Email]
getSentEmails = callPy "get_sent_emails" (object [])

-- | Return all received emails.
getReceivedEmails :: IO [Email]
getReceivedEmails = callPy "get_received_emails" (object [])

-- | Return all draft emails.
getDraftEmails :: IO [Email]
getDraftEmails = callPy "get_draft_emails" (object [])

-- | Search emails whose subject or body contains @query@; optionally
-- restrict to a given @sender@.
-- @query@: text to look for. @sender@: sender filter, or empty for all.
searchEmails :: String -> String -> IO [Email]
searchEmails query sender =
  callPy "search_emails" (object ["query" .= query, "sender" .= senderArg])
  where
    senderArg = if null sender then Nothing else Just sender

-- | Send an email.
-- @recipients@: recipient addresses. @subject@, @body@: the message.
sendEmail :: [String] -> String -> String -> IO Email
sendEmail recipients subject body =
  callPy
    "send_email"
    (object ["recipients" .= recipients, "subject" .= subject, "body" .= body])

-- | Delete the email with the given id.
deleteEmail :: EmailId -> IO String
deleteEmail eid = callPy "delete_email" (object ["email_id" .= eid])

-- | Find contacts by name.
searchContactsByName :: String -> IO [EmailContact]
searchContactsByName query = callPy "search_contacts_by_name" (object ["query" .= query])

-- | Find contacts by email.
searchContactsByEmail :: String -> IO [EmailContact]
searchContactsByEmail query = callPy "search_contacts_by_email" (object ["query" .= query])

----------------------------------------------------------------
-- Calendar
----------------------------------------------------------------

-- | The current day in ISO format (YYYY-MM-DD).
getCurrentDay :: IO String
getCurrentDay = callPy "get_current_day" (object [])

-- | Search calendar events matching @query@ (optionally on @date@).
searchCalendarEvents :: String -> String -> IO [CalendarEvent]
searchCalendarEvents query date =
  callPy "search_calendar_events" (object ["query" .= query, "date" .= dateArg])
  where
    dateArg = if null date then Nothing else Just date

-- | Appointments on @day@ (YYYY-MM-DD).
getDayCalendarEvents :: String -> IO [CalendarEvent]
getDayCalendarEvents day = callPy "get_day_calendar_events" (object ["day" .= day])

-- | Create a calendar event.
-- @startTime@/@endTime@: "YYYY-MM-DD HH:MM". @participants@: attendee emails.
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

-- | Cancel the event with the given id.
cancelCalendarEvent :: String -> IO String
cancelCalendarEvent eid = callPy "cancel_calendar_event" (object ["event_id" .= eid])

-- | Reschedule an event to a new start (and optional new end) time.
rescheduleCalendarEvent :: String -> String -> String -> IO CalendarEvent
rescheduleCalendarEvent eid newStart newEnd =
  callPy
    "reschedule_calendar_event"
    (object ["event_id" .= eid, "new_start_time" .= newStart, "new_end_time" .= endArg])
  where
    endArg = if null newEnd then Nothing else Just newEnd

-- | Add participants to an event.
addCalendarEventParticipants :: String -> [String] -> IO CalendarEvent
addCalendarEventParticipants eid participants =
  callPy "add_calendar_event_participants" (object ["event_id" .= eid, "participants" .= participants])

----------------------------------------------------------------
-- Cloud drive
----------------------------------------------------------------

-- | All files in the cloud drive.
listFiles :: IO [CloudDriveFile]
listFiles = callPy "list_files" (object [])

-- | Files whose name matches @filename@.
searchFilesByFilename :: String -> IO [CloudDriveFile]
searchFilesByFilename name = callPy "search_files_by_filename" (object ["filename" .= name])

-- | Files whose content matches @query@.
searchFiles :: String -> IO [CloudDriveFile]
searchFiles query = callPy "search_files" (object ["query" .= query])

-- | Fetch a file by id.
getFileById :: CloudFileId -> IO CloudDriveFile
getFileById fid = callPy "get_file_by_id" (object ["file_id" .= fid])

-- | Create a file.
createFile :: String -> String -> IO CloudDriveFile
createFile name content = callPy "create_file" (object ["filename" .= name, "content" .= content])

-- | Append content to a file.
appendToFile :: CloudFileId -> String -> IO CloudDriveFile
appendToFile fid content = callPy "append_to_file" (object ["file_id" .= fid, "content" .= content])

-- | Delete a file by id.
deleteFile :: CloudFileId -> IO CloudDriveFile
deleteFile fid = callPy "delete_file" (object ["file_id" .= fid])

-- | Share a file with a user at @email@ granting @permission@ ("r"/"rw").
shareFile :: CloudFileId -> String -> String -> IO CloudDriveFile
shareFile fid email permission =
  callPy "share_file" (object ["file_id" .= fid, "email" .= email, "permission" .= permission])
