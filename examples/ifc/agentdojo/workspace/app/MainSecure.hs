{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the workspace suite. The Workspace policy is
-- undefined so this builds but fails at run time on the first tool call.
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, toLabeled, unlabel)
import IfcTCB (evalDC, initialState)
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
      { silentModules = ["IFC"]
      , extensions = [OverloadedStrings]
      }

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg {logPath = parseFlag "--log-path" args}
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalDC agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
