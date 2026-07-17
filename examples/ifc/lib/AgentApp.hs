{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module AgentApp
  ( runInsecureAgent
  , runSecureAgent
  , runDC
  ) where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import qualified Data.ByteString.Lazy as BL
import Env (Env (..))
import IFC (DC)
import LIO (evalLIO)
import LIO.DCLabel (cFalse, cTrue, (%%))
import LIO.TCB (LIOState (..))
import LLM (Config (..), defaultConfig)
import System.Environment (getArgs)

$(deriveFromJSON defaultOptions ''Config)

-- | Runs a DC computation from a public trusted starting label.
runDC :: DC a -> IO a
runDC m =
  evalLIO m LIOState {lioLabel = cTrue %% cFalse, lioClearance = cFalse %% cTrue}

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

-- | The tweak extends the config, the alias keeps the required type
-- spelled DC where TypeRep rendering would expand the synonym.
runSecureAgent :: Env -> (Config -> Config) -> IO ()
runSecureAgent env = runAgentWith run
  where
    run cfg prompt = runDC (mkAgent cfg aliased prompt :: DC String)
    aliased = env {typeAliases = [("LIO DCLabel", "DC")]}
