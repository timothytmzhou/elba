{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the slack suite. The agent sees the Slack and
-- Web secured surface plus unlabel, toLabeled, and printf, all with their
-- docstrings. DC and DCLabeled reach the interpreter through silentModules,
-- so the agent can hold them but cannot name or unwrap the internals.
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, toLabeled, unlabel)
import IfcTCB (evalDC, initialState)
import InsecureApp (loadConfig, parseFlag)
import LLM (Config (..), defaultConfig, defaultSystemPrompt)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Language.Haskell.TH.Syntax qualified as TH
import Slack
import System.Environment (getArgs)
import System.FilePath (takeDirectory, (</>))
import TH (addTools)
import Text.Printf (printf)
import Web

agentEnv :: Env
agentEnv =
  $( addTools
       [ ''LabeledMessage
       , 'getChannels
       , 'readChannelMessages
       , 'readInbox
       , 'getUsersInChannel
       , 'channelName
       , 'userName
       , 'channelID
       , 'userID
       , 'addUserToChannel
       , 'inviteUserToSlack
       , 'removeUserFromSlack
       , 'sendDirectMessage
       , 'sendChannelMessage
       , 'getWebpage
       , 'postWebpage
       , 'unlabel
       , 'toLabeled
       , 'printf
       ]
   )
    defEnv
      { silentModules = ["IFC"]
      , extensions = [OverloadedStrings]
      }

ifcGuidance :: String
ifcGuidance =
  $( do
      loc <- TH.location
      let path = takeDirectory (TH.loc_filename loc) </> ".." </> ".." </> "IfcGuidance.md"
      TH.addDependentFile path
      contents <- runIO (readFile path)
      TH.lift contents
   )

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg
          { logPath = parseFlag "--log-path" args
          , systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance
          }
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalDC agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
