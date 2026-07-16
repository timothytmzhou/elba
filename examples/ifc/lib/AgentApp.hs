{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- Shared main for the agent executables. Each suite app builds a tool Env
-- and hands it to one of the drivers below. The orphan FromJSON Config
-- lives here so every executable shares one copy.
module AgentApp
  ( runInsecureAgent
  , runSecureAgent
  , initialState
  ) where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import qualified Data.ByteString.Lazy as BL
import Env (Env (..))
import IFC (DC)
import LIO (LIOState (..), evalLIO)
import LIO.DCLabel (DCLabel, cFalse, cTrue, (%%))
import LLM (Config (..), defaultConfig)
import System.Environment (getArgs)

$(deriveFromJSON defaultOptions ''Config)

initialState :: LIOState DCLabel
initialState = LIOState {lioLabel = cTrue %% cFalse, lioClearance = cFalse %% cTrue}

parseFlag :: String -> [String] -> Maybe FilePath
parseFlag flag (a : v : _) | a == flag = Just v
parseFlag flag (_ : rest) = parseFlag flag rest
parseFlag _ [] = Nothing

loadConfig :: FilePath -> IO Config
loadConfig path = do
  bs <- BL.readFile path
  case eitherDecode bs of
    Right cfg -> pure cfg
    Left err -> error ("config decode failed: " ++ err)

runAgentWith :: (Config -> String -> IO String) -> (Config -> Config) -> IO ()
runAgentWith run tweak = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = tweak baseCfg {logPath = parseFlag "--log-path" args}
    result <- try (run cfg prompt) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left e -> sendFailed (displayException e)

runInsecureAgent :: Env -> IO ()
runInsecureAgent env = runAgentWith (\cfg prompt -> mkAgent cfg env prompt) id

-- | Runs the agent in the DC monad. The tweak lets a suite extend the
-- config, for example appending IFC guidance to the system prompt. The
-- alias keeps the prompt's required type spelled DC even though TypeRep
-- rendering expands the synonym.
runSecureAgent :: Env -> (Config -> Config) -> IO ()
runSecureAgent env = runAgentWith run
  where
    run cfg prompt = evalLIO (mkAgent cfg aliased prompt :: DC String) initialState
    aliased = env {typeAliases = [("LIO DCLabel", "DC")]}
