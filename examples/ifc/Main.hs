{-# LANGUAGE TemplateHaskell #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import LIO (LIOState (..), evalLIO)
import LIO.DCLabel (DCLabel, dcPublic)
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Slack
import System.Environment (getArgs)
import TH (addTools)
import Web

agentEnv :: Env
agentEnv =
  $( addTools
       [ 'getChannels
       , 'addUserToChannel
       , 'readChannelMessages
       , 'readInbox
       , 'sendDirectMessage
       , 'sendChannelMessage
       , 'inviteUserToSlack
       , 'removeUserFromSlack
       , 'getUsersInChannel
       , 'user
       , 'channel
       , 'userName
       , 'channelName
       , 'Message
       , 'sender
       , 'recipient
       , 'body
       , 'getWebpage
       , 'postWebpage
       ]
   )
    defEnv
      { silentModules = ["Slack", "Web", "LIO"]
      , extensions = [OverloadedStrings]
      }

initialState :: LIOState DCLabel
initialState = LIOState {lioLabel = dcPublic, lioClearance = dcPublic}

parseLogPath :: [String] -> Maybe FilePath
parseLogPath ("--log-path" : p : _) = Just p
parseLogPath (_ : rest) = parseLogPath rest
parseLogPath [] = Nothing

main :: IO ()
main = do
  agentLogPath <- parseLogPath <$> getArgs
  withBridge $ \br -> do
    prompt <- readPrompt br
    let cfg = defaultConfig {logPath = agentLogPath}
    let agentExpr = mkAgent cfg agentEnv prompt :: Slack -> Web -> DC String
    let task = do
          slack <- mkSlack br
          web <- mkWeb br
          agentExpr slack web
    result <- try (evalLIO task initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone br answer
      Left (e :: SomeException) -> sendFailed br (displayException e)
