{-# LANGUAGE Trustworthy #-}

-- | IFC-secured surface for the workspace suite. THE POLICY IS NOT
-- WRITTEN YET: every binding below is 'undefined', to be implemented by
-- hand following the slack suite as the worked reference (Slack.hs,
-- SlackPrincipal.hs, SlackLabelTCB.hs, policy/Policy.hs): define the
-- principals (mailbox owner, event participants, file collaborators),
-- label each read, and gate each write on the current label.
--
-- The signatures are PROVISIONAL — where the labels sit is itself part of
-- the policy design; adjust freely when implementing. The insecure
-- executable (agentdojo-workspace) only uses WorkspaceTCB and does not
-- depend on this module's implementation.
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
import LIO.DCLabel (DC, DCLabeled)

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
