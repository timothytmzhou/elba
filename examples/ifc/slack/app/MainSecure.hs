{-# LANGUAGE TemplateHaskell #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, evalLIO, initialState, toLabeled, unlabel)
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
       [ -- Slack types
         ''Body
       , ''LabeledMessage
       , ''ChannelID
       , ''UserID
       , ''DC
       , ''DCLabeled
         -- Web type
       , ''Url
         -- Slack ids
       , 'channelName
       , 'userName
       , 'channelID
       , 'userID
         -- Slack reads
       , 'getChannels
       , 'readChannelMessages
       , 'readInbox
       , 'getUsersInChannel
         -- Slack writes
       , 'addUserToChannel
       , 'inviteUserToSlack
       , 'removeUserFromSlack
       , 'sendDirectMessage
       , 'sendChannelMessage
         -- Web tools
       , 'getWebpage
       , 'postWebpage
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

-- Information-flow guidance appended to the default system prompt.
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
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
