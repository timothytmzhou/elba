{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- The agent binary for every AgentDojo suite.
-- agentdojo --suite slack [--secure] [--config cfg.json] [--log-path log]
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Data.Aeson (eitherDecode)
import Data.Aeson.TH (defaultOptions, deriveFromJSON)
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (fromMaybe)
import Env (Env (..), Extension (OverloadedStrings), defEnv)
import IFC (DC, runDC)
import LLM (Config (..), defaultConfig, defaultSystemPrompt)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax qualified as TH
import System.Environment (getArgs)
import System.FilePath (takeDirectory, (</>))

$(deriveFromJSON defaultOptions ''Config)

-- What the interpreted agent may import, insecure and secure surfaces.
suites :: [(String, ([String], [String]))]
suites =
  [ ("slack", (["SlackTCB", "WebTCB"], ["Slack", "Web", "IFC"]))
  ]

-- Information flow guidance appended to the secure agent system prompt.
ifcGuidance :: String
ifcGuidance =
  $( do
      loc <- TH.location
      let path = takeDirectory (TH.loc_filename loc) </> ".." </> "IfcGuidance.md"
      TH.addDependentFile path
      contents <- runIO (readFile path)
      TH.lift contents
   )

parseFlag :: String -> [String] -> Maybe String
parseFlag flag (a : v : _) | a == flag = Just v
parseFlag flag (_ : rest) = parseFlag flag rest
parseFlag _ [] = Nothing

loadConfig :: FilePath -> IO Config
loadConfig path = do
  bs <- BL.readFile path
  either (\err -> error ("config decode failed: " ++ err)) pure (eitherDecode bs)

main :: IO ()
main = do
  args <- getArgs
  let secure = "--secure" `elem` args
      suite = fromMaybe (error "missing --suite") (parseFlag "--suite" args)
      (insecureMods, secureMods) =
        fromMaybe (error ("unknown suite: " ++ suite)) (lookup suite suites)
      env =
        defEnv
          { modules = if secure then secureMods else insecureMods
          , extensions = [OverloadedStrings]
          , -- The alias keeps the required type spelled DC where TypeRep would expand the synonym.
            typeAliases = [("LIO DCLabel", "DC") | secure]
          }
  loaded <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  let base = loaded {logPath = parseFlag "--log-path" args}
      cfg
        | secure = base {systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance}
        | otherwise = base
  withBridge $ do
    prompt <- readPrompt
    result <-
      try $
        if secure
          then runDC (mkAgent cfg env prompt :: DC String)
          else mkAgent cfg env prompt
    case (result :: Either SomeException String) of
      Right answer -> sendDone answer
      Left e -> sendFailed (displayException e)
