{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the slack suite. Opaque types stay out of the
-- tool list. addTools would leak their constructors and their defining
-- modules are unsafe to import. The agent still sees them in the tool
-- signatures, with DC and DCLabeled in scope through the silent IFC import.
module Main where

import AgentApp (runSecureAgent)
import Env (Env (..), defEnv)
import IFC (toLabeled, unlabel)
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
  $( addTools
       [ -- Slack types
         ''LabeledMessage
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
main = runSecureAgent agentEnv withGuidance
  where
    withGuidance cfg = cfg {systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance}
