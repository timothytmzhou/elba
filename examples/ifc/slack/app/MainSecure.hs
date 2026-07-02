{-# LANGUAGE TemplateHaskell #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, evalLIO, initialState, toLabeled, unlabel)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import qualified Data.ByteString.Lazy as BL
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

parseLogPath :: [String] -> Maybe FilePath
parseLogPath ("--log-path" : p : _) = Just p
parseLogPath (_ : rest) = parseLogPath rest
parseLogPath [] = Nothing

parseConfigPath :: [String] -> Maybe FilePath
parseConfigPath ("--config" : p : _) = Just p
parseConfigPath (_ : rest) = parseConfigPath rest
parseConfigPath [] = Nothing

$(deriveFromJSON defaultOptions ''Config)

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
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg
          { logPath = parseLogPath args
          , systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance
          }
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
