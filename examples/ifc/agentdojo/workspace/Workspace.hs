{-# LANGUAGE Trustworthy #-}

-- IFC secured surface for the workspace suite. The policy is not written
-- yet. Every binding is undefined and the signatures are provisional.
-- Follow the slack suite as the worked reference.
module Workspace
  ( DC
  , DCLabeled
  , Email
  , EmailContact
  , CalendarEvent
  , CloudDriveFile
  , CloudFileId
    -- * Email
  , getUnreadEmails
  , getSentEmails
  , getReceivedEmails
  , getDraftEmails
  , searchEmails
  , sendEmail
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
  , searchFiles
  , searchFilesByFilename
  , getFileById
  , createFile
  , appendToFile
  , deleteFile
  , shareFile
  ) where

import AgentDojoTypes (CalendarEvent, CloudDriveFile, CloudFileId, Email, EmailContact)
import IFC (DC, DCLabeled)

getUnreadEmails :: DC (DCLabeled [Email])
getUnreadEmails = undefined

getSentEmails :: DC (DCLabeled [Email])
getSentEmails = undefined

getReceivedEmails :: DC (DCLabeled [Email])
getReceivedEmails = undefined

getDraftEmails :: DC (DCLabeled [Email])
getDraftEmails = undefined

searchEmails :: String -> String -> DC (DCLabeled [Email])
searchEmails = undefined

sendEmail :: [String] -> DCLabeled String -> DCLabeled String -> DC ()
sendEmail = undefined

searchContactsByName :: String -> DC (DCLabeled [EmailContact])
searchContactsByName = undefined

searchContactsByEmail :: String -> DC (DCLabeled [EmailContact])
searchContactsByEmail = undefined

getCurrentDay :: DC String
getCurrentDay = undefined

searchCalendarEvents :: String -> String -> DC (DCLabeled [CalendarEvent])
searchCalendarEvents = undefined

getDayCalendarEvents :: String -> DC (DCLabeled [CalendarEvent])
getDayCalendarEvents = undefined

createCalendarEvent :: DCLabeled String -> String -> String -> DCLabeled String -> [String] -> DC ()
createCalendarEvent = undefined

cancelCalendarEvent :: String -> DC ()
cancelCalendarEvent = undefined

rescheduleCalendarEvent :: String -> String -> String -> DC ()
rescheduleCalendarEvent = undefined

addCalendarEventParticipants :: String -> [String] -> DC ()
addCalendarEventParticipants = undefined

listFiles :: DC (DCLabeled [CloudDriveFile])
listFiles = undefined

searchFiles :: String -> DC (DCLabeled [CloudDriveFile])
searchFiles = undefined

searchFilesByFilename :: String -> DC (DCLabeled [CloudDriveFile])
searchFilesByFilename = undefined

getFileById :: CloudFileId -> DC (DCLabeled CloudDriveFile)
getFileById = undefined

createFile :: String -> DCLabeled String -> DC ()
createFile = undefined

appendToFile :: CloudFileId -> DCLabeled String -> DC ()
appendToFile = undefined

deleteFile :: CloudFileId -> DC ()
deleteFile = undefined

shareFile :: CloudFileId -> String -> String -> DC ()
shareFile = undefined
