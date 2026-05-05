{-# LANGUAGE TemplateHaskell #-}

module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import LIO (LIOState (..), evalLIO, label, unlabel)
import LIO.Concurrent (lFork, lWait)
import LIO.DCLabel (DC, DCLabel, cFalse, cTrue, dcPublic, (%%), (/\), (\/))
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Slack
import System.Environment (getArgs)
import TH (addTools)
import Web

agentEnv :: Env
agentEnv =
  $( addTools
       [ -- LIO API (curated subset; LIO itself stays silent)
         'label
       , 'unlabel
       , 'lFork
       , 'lWait
       , 'dcPublic
       , '(%%)
       , '(/\)
       , '(\/)
       ]
   )
    defEnv
      { modules = ["Slack", "Web"]
      , silentModules = ["LIO"]
      , extensions = [OverloadedStrings]
      }

-- Initial label is `dcBottom = True %% False`: secrecy at the bottom
-- of the secrecy lattice and integrity at the bottom of the integrity
-- lattice, so both components grow monotonically as the agent reads.
-- Clearance is the top of the DCLabel lattice.
initialState :: LIOState DCLabel
initialState =
  LIOState
    { lioLabel = dcBottom
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
    let cfg = defaultConfig {logPath = agentLogPath}
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
