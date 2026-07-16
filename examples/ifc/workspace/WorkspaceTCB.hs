{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure tool surface for the workspace suite.
module WorkspaceTCB (module WorkspaceTCB, module AgentDojoTypes) where

import AgentDojoTypes
import Tool (defTool, defTools)

defTools
  [ defTool "getUnreadEmails" "get_unread_emails" [] [t|IO [Email]|]
  , defTool "getSentEmails" "get_sent_emails" [] [t|IO [Email]|]
  , defTool "getReceivedEmails" "get_received_emails" [] [t|IO [Email]|]
  , defTool "getDraftEmails" "get_draft_emails" [] [t|IO [Email]|]
  , defTool "searchEmails" "search_emails" ["query", "sender"] [t|String -> Maybe String -> IO [Email]|]
  , defTool "sendEmail" "send_email" ["recipients", "subject", "body"] [t|[String] -> String -> String -> IO Email|]
  , defTool "deleteEmail" "delete_email" ["email_id"] [t|EmailId -> IO String|]
  , defTool "searchContactsByName" "search_contacts_by_name" ["query"] [t|String -> IO [EmailContact]|]
  , defTool "searchContactsByEmail" "search_contacts_by_email" ["query"] [t|String -> IO [EmailContact]|]
  , defTool "getCurrentDay" "get_current_day" [] [t|IO String|]
  , defTool "searchCalendarEvents" "search_calendar_events" ["query", "date"] [t|String -> Maybe String -> IO [CalendarEvent]|]
  , defTool "getDayCalendarEvents" "get_day_calendar_events" ["day"] [t|String -> IO [CalendarEvent]|]
  , defTool "createCalendarEvent" "create_calendar_event" ["title", "start_time", "end_time", "description", "participants"] [t|String -> String -> String -> String -> [String] -> IO CalendarEvent|]
  , defTool "cancelCalendarEvent" "cancel_calendar_event" ["event_id"] [t|String -> IO String|]
  , defTool "rescheduleCalendarEvent" "reschedule_calendar_event" ["event_id", "new_start_time", "new_end_time"] [t|String -> String -> Maybe String -> IO CalendarEvent|]
  , defTool "addCalendarEventParticipants" "add_calendar_event_participants" ["event_id", "participants"] [t|String -> [String] -> IO CalendarEvent|]
  , defTool "listFiles" "list_files" [] [t|IO [CloudDriveFile]|]
  , defTool "searchFilesByFilename" "search_files_by_filename" ["filename"] [t|String -> IO [CloudDriveFile]|]
  , defTool "searchFiles" "search_files" ["query"] [t|String -> IO [CloudDriveFile]|]
  , defTool "getFileById" "get_file_by_id" ["file_id"] [t|CloudFileId -> IO CloudDriveFile|]
  , defTool "createFile" "create_file" ["filename", "content"] [t|String -> String -> IO CloudDriveFile|]
  , defTool "appendToFile" "append_to_file" ["file_id", "content"] [t|CloudFileId -> String -> IO CloudDriveFile|]
  , defTool "deleteFile" "delete_file" ["file_id"] [t|CloudFileId -> IO CloudDriveFile|]
  , defTool "shareFile" "share_file" ["file_id", "email", "permission"] [t|CloudFileId -> String -> String -> IO CloudDriveFile|]
  ]
