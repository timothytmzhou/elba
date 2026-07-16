{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the workspace suite. The driver lives in InsecureApp.
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
       [ ''Email
       , ''EmailId
       , ''EmailContact
       , ''CalendarEvent
       , ''CloudDriveFile
       , ''CloudFileId
       , 'getUnreadEmails
       , 'getSentEmails
       , 'getReceivedEmails
       , 'getDraftEmails
       , 'searchEmails
       , 'sendEmail
       , 'deleteEmail
       , 'searchContactsByName
       , 'searchContactsByEmail
       , 'getCurrentDay
       , 'searchCalendarEvents
       , 'getDayCalendarEvents
       , 'createCalendarEvent
       , 'cancelCalendarEvent
       , 'rescheduleCalendarEvent
       , 'addCalendarEventParticipants
       , 'listFiles
       , 'searchFilesByFilename
       , 'searchFiles
       , 'getFileById
       , 'createFile
       , 'appendToFile
       , 'deleteFile
       , 'shareFile
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

main :: IO ()
main = runInsecureAgent agentEnv
