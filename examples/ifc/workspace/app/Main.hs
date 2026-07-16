{-# LANGUAGE TemplateHaskell #-}

-- Insecure (no-policy) agent app for the workspace suite. The shared
-- driver lives in 'InsecureApp'; this module only fixes the tool set.
module Main where

import Env (Env (..), defEnv)
import InsecureApp (runInsecureAgent)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import WorkspaceTCB

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- types
         ''Email
       , ''EmailId
       , ''EmailContact
       , ''CalendarEvent
       , ''CloudDriveFile
       , ''CloudFileId
         -- email
       , 'getUnreadEmails
       , 'getSentEmails
       , 'getReceivedEmails
       , 'getDraftEmails
       , 'searchEmails
       , 'sendEmail
       , 'deleteEmail
       , 'searchContactsByName
       , 'searchContactsByEmail
         -- calendar
       , 'getCurrentDay
       , 'searchCalendarEvents
       , 'getDayCalendarEvents
       , 'createCalendarEvent
       , 'cancelCalendarEvent
       , 'rescheduleCalendarEvent
       , 'addCalendarEventParticipants
         -- cloud drive
       , 'listFiles
       , 'searchFilesByFilename
       , 'searchFiles
       , 'getFileById
       , 'createFile
       , 'appendToFile
       , 'deleteFile
       , 'shareFile
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
