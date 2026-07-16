{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the workspace suite. The Workspace policy is
-- undefined so this builds but fails at run time on the first tool call.
module Main where

import AgentApp (runSecureAgent)
import Env (Env (..), defEnv)
import IFC (toLabeled, unlabel)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import Workspace

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''Email
       , ''EmailContact
       , ''CalendarEvent
       , ''CloudDriveFile
       , ''CloudFileId
       , 'getReceivedEmails
       , 'searchEmails
       , 'sendEmail
       , 'searchContactsByName
       , 'searchCalendarEvents
       , 'createCalendarEvent
       , 'listFiles
       , 'searchFiles
       , 'getFileById
       , 'createFile
       , 'shareFile
       , 'unlabel
       , 'toLabeled
       , 'printf
       ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = runSecureAgent agentEnv id
