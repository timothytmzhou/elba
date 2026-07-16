{-# LANGUAGE TemplateHaskell #-}

-- IFC-secured agent app for the workspace suite. NOTE: the Workspace
-- policy module is not implemented yet (every tool is `undefined`), so
-- this executable builds but fails at run time on the first tool call.
-- It exists so that, once the policy is written, only Workspace.hs (and
-- a WorkspaceGuidance.md, mirroring the slack IfcGuidance.md) changes.
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, evalLIO, initialState, toLabeled, unlabel)
import InsecureApp (loadConfig, parseFlag)
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import System.Environment (getArgs)
import TH (addTools)
import Text.Printf (printf)
import Workspace

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- types
         ''Email
       , ''EmailContact
       , ''CalendarEvent
       , ''CloudDriveFile
       , ''CloudFileId
       , ''DC
       , ''DCLabeled
         -- email
       , 'getUnreadEmails
       , 'getSentEmails
       , 'getReceivedEmails
       , 'getDraftEmails
       , 'searchEmails
       , 'sendEmail
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
       , 'searchFiles
       , 'searchFilesByFilename
       , 'getFileById
       , 'createFile
       , 'appendToFile
       , 'deleteFile
       , 'shareFile
         -- IFC API
       , 'unlabel
       , 'toLabeled
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["IFC"]
      }

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg {logPath = parseFlag "--log-path" args}
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
