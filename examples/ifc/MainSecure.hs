{-# LANGUAGE TemplateHaskell #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import LIO (LIOState (..), evalLIO)
import LIO.DCLabel (DCLabel, cFalse, cTrue, dcPublic, (%%))
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import SlackSecure
import System.Environment (getArgs)
import TH (addTools)
import WebSecure

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- Slack tools
         'getChannels
       , 'addUserToChannel
       , 'readChannelMessages
       , 'readInbox
       , 'sendDirectMessage
       , 'sendChannelMessage
       , 'inviteUserToSlack
       , 'removeUserFromSlack
       , 'getUsersInChannel
       , 'Message
       , 'sender
       , 'recipient
       , 'body
         -- Web tools
       , 'getWebpage
       , 'postWebpage
         -- LIO API
       , 'label
       , 'unlabel
       , 'lFork
       , 'lWait
       , 'dcPublic
       ]
   )
    defEnv
      { silentModules = ["SlackSecure", "WebSecure", "LIO"]
      , extensions = [OverloadedStrings]
      }

-- Clearance is set to the top of the DCLabel lattice (`cFalse %% cTrue`)
-- so the read-tier wrappers can allocate `Labeled DCLabel x` at the
-- "external" secrecy label. The agent's policy is enforced by the
-- per-tool priv gating, not by clearance.
initialState :: LIOState DCLabel
initialState =
  LIOState
    { lioLabel = dcPublic
    , lioClearance = cFalse %% cTrue
    }

parseLogPath :: [String] -> Maybe FilePath
parseLogPath ("--log-path" : p : _) = Just p
parseLogPath (_ : rest) = parseLogPath rest
parseLogPath [] = Nothing

-- The principal whose authority the agent acts under. Matches AgentDojo's
-- default user "Emma Johnson" so the agent's user-priv covers Emma.
agentPrincipalName :: String
agentPrincipalName = "Emma Johnson"

main :: IO ()
main = do
  agentLogPath <- parseLogPath <$> getArgs
  let userPriv = mintUserPriv agentPrincipalName
  withBridge $ \br -> do
    prompt <- readPrompt br
    let cfg = defaultConfig {logPath = agentLogPath}
    let agentExpr = mkAgent cfg agentEnv prompt :: Slack -> Web -> DC String
    let task = do
          let slack = mkSlack br userPriv
          let web = mkWeb br userPriv
          agentExpr slack web
    result <- try (evalLIO task initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone br answer
      Left (e :: SomeException) -> sendFailed br (displayException e)
