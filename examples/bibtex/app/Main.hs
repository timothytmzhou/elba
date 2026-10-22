{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- The literature search agent binary.
-- litsearch --task-file task.txt [--config cfg.json] [--log-path log]
module Main where

import Control.Exception (SomeException, displayException, try)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (fromMaybe)
import Env (Env (..), defEnv)
import LBAC (mkAgent)
import LLM (Config (..), defaultConfig, defaultSystemPrompt)
import LitSearch (TIO, runTIO)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

$(deriveFromJSON defaultOptions ''Config)

parseFlag :: String -> [String] -> Maybe String
parseFlag flag args = case dropWhile (/= flag) args of
  (_ : value : _) -> Just value
  _ -> Nothing

-- The systemPrompt in a config file is an addendum to the built in prompt.
loadConfig :: FilePath -> IO Config
loadConfig path = do
  bs <- BL.readFile path
  cfg <- either (\err -> error ("config decode failed: " ++ err)) pure (eitherDecode bs)
  pure cfg {systemPrompt = defaultSystemPrompt ++ systemPrompt cfg}

main :: IO ()
main = do
  args <- getArgs
  let taskFile = fromMaybe (error "missing --task-file") (parseFlag "--task-file" args)
  prompt <- readFile taskFile
  loaded <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  let cfg = loaded {logPath = parseFlag "--log-path" args}
      env = defEnv {modules = ["LitSearch"]}
  result <- try (runTIO (mkAgent cfg env prompt :: TIO ()))
  case (result :: Either SomeException ()) of
    Right () -> putStrLn "AGENT_DONE"
    Left e -> do
      hPutStrLn stderr (displayException e)
      exitFailure
