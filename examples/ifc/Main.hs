{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import qualified Data.ByteString.Lazy as BL
import Env (Env (..), defEnv)
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import SlackTCB
import System.Environment (getArgs)
import TH (addTools)
import Text.Printf (printf)
import WebTCB

$(deriveFromJSON defaultOptions ''Config)

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- types: ''Body / ''Url / ''Message bring the corresponding
         -- imports into scope without needing silentModules.
         -- ''Message also brings the Message data constructor and its
         -- field functions via reify-driven `Message(..)`.
         ''Body
       , ''Url
       , ''Message
         -- values
       , 'getChannels
       , 'addUserToChannel
       , 'readChannelMessages
       , 'readInbox
       , 'sendDirectMessage
       , 'sendChannelMessage
       , 'inviteUserToSlack
       , 'removeUserFromSlack
       , 'getUsersInChannel
       , 'getWebpage
       , 'postWebpage
         -- prompt formatting
       , 'printf
       ]
   )
    defEnv {extensions = [OverloadedStrings]}

parseLogPath :: [String] -> Maybe FilePath
parseLogPath ("--log-path" : p : _) = Just p
parseLogPath (_ : rest) = parseLogPath rest
parseLogPath [] = Nothing

parseConfigPath :: [String] -> Maybe FilePath
parseConfigPath ("--config" : p : _) = Just p
parseConfigPath (_ : rest) = parseConfigPath rest
parseConfigPath [] = Nothing

loadConfig :: FilePath -> IO Config
loadConfig path = do
  bs <- BL.readFile path
  case eitherDecode bs of
    Right cfg -> pure cfg
    Left err -> error ("config decode failed: " ++ err)

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseConfigPath args)
  let cfg = baseCfg {logPath = parseLogPath args}
  withBridge $ do
    prompt <- readPrompt
    let agentExpr = mkAgent cfg agentEnv prompt :: IO String
    result <- try agentExpr :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
