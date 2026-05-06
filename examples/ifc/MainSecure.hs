{-# LANGUAGE TemplateHaskell #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import LIO (LIOState (..), evalLIO, getLabel, label, unlabel)
import LIO.DCLabel (DC, DCLabel, cFalse, cTrue, (%%), (/\), (\/))
import LIO.Labeled (lAp, lFmap)
import LLM (Config (..), defaultConfig, defaultSystemPrompt)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Language.Haskell.TH.Syntax qualified as TH
import Slack
import System.Environment (getArgs)
import System.FilePath (takeDirectory, (</>))
import TH (addTools)
import Text.Printf (printf)
import ToLabeled (toLabeled)
import Web

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- Slack types
         ''Body
       , ''Message
       , ''DC
       , ''DCLabel
       , ''DCLabeled
         -- Web type
       , ''Url
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
         -- LIO API
       , 'getLabel
       , 'label
       , 'unlabel
       , 'lFmap
       , 'lAp
       , 'toLabeled
       , '(%%)
       , '(/\)
       , '(\/)
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv
      { extensions = [OverloadedStrings]
      , silentModules = ["LIO"]
      }

-- Information-flow guidance appended to the default system prompt.
-- Lives in IfcGuidance.md so it can be edited as prose; reloaded on
-- every build via `addDependentFile`.
ifcGuidance :: String
ifcGuidance =
  $( do
      loc <- TH.location
      let path = takeDirectory (TH.loc_filename loc) </> "IfcGuidance.md"
      TH.addDependentFile path
      contents <- runIO (readFile path)
      TH.lift contents
   )

-- Initial label `True %% False`: secrecy at the bottom of the
-- secrecy lattice (public) and integrity at the top of the integrity
-- lattice (untainted). Clearance is the top of the DCLabel lattice.
initialState :: LIOState DCLabel
initialState =
  LIOState
    { lioLabel = cTrue %% cFalse
    , lioClearance = cFalse %% cTrue
    }

parseLogPath :: [String] -> Maybe FilePath
parseLogPath ("--log-path" : p : _) = Just p
parseLogPath (_ : rest) = parseLogPath rest
parseLogPath [] = Nothing

main :: IO ()
main = do
  agentLogPath <- parseLogPath <$> getArgs
  withBridge $ do
    prompt <- readPrompt
    let cfg = defaultConfig
          { logPath = agentLogPath
          , systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance
          }
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
