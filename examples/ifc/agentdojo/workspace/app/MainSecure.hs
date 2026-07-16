{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (ifcTools, runSecureAgent)
import Env (Env (..), defEnv)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)
import Workspace

agentEnv :: Env
agentEnv =
  $( addTools $
     ifcTools
       ++ [ ''Email
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
         , 'printf
         ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = runSecureAgent agentEnv id
