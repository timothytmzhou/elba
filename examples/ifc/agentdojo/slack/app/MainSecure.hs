{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (ifcTools, runSecureAgent)
import Env (Env (..), defEnv)
import LLM (Config (..), defaultSystemPrompt)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Language.Haskell.TH.Syntax qualified as TH
import Slack
import System.FilePath (takeDirectory, (</>))
import TH (addTools)
import Text.Printf (printf)
import Web

agentEnv :: Env
agentEnv =
  $( addTools $
     ifcTools
       ++ [ -- Slack types
           ''Body
         , ''LabeledMessage
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
           -- prompt formatting
         , 'printf
         ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , -- SlackPrincipal keeps the opaque id types nameable
        silentModules = ["IFC", "SlackPrincipal"]
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
main = runSecureAgent agentEnv withGuidance
  where
    withGuidance cfg = cfg {systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance}
