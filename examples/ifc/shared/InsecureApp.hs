{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- Shared driver for the no policy agent executables. Each one runs the
-- same loop over a different tool Env. The secure executables have their
-- own driver because they run in the DC monad. The orphan FromJSON Config
-- lives here so every executable shares one copy.
module InsecureApp
  ( runInsecureAgent
  , loadConfig
  , parseFlag
  ) where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import qualified Data.ByteString.Lazy as BL
import Env (Env)
import LLM (Config (..), defaultConfig)
import System.Environment (getArgs)

$(deriveFromJSON defaultOptions ''Config)

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

runInsecureAgent :: Env -> IO ()
runInsecureAgent agentEnv = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  let cfg = baseCfg {logPath = parseFlag "--log-path" args}
  withBridge $ do
    prompt <- readPrompt
    let agentExpr = mkAgent cfg agentEnv prompt :: IO String
    result <- try agentExpr :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
