{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the slack suite. The tool set is the whole
-- Slack and Web secured surface plus the IFC API and printf.
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, evalLIO, initialState, toLabeled, unlabel)
import InsecureApp (loadConfig, parseFlag)
import LLM (Config (..), defaultConfig, defaultSystemPrompt)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Language.Haskell.TH.Syntax qualified as TH
import System.Environment (getArgs)
import System.FilePath (takeDirectory, (</>))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $(addTools ['unlabel, 'toLabeled, 'printf])
    defEnv
      { modules = ["Slack", "Web"]
      , silentModules = ["IFC"]
      , extensions = [OverloadedStrings]
      }

ifcGuidance :: String
ifcGuidance =
  $( do
      loc <- TH.location
      let path = takeDirectory (TH.loc_filename loc) </> ".." </> ".." </> "IfcGuidance.md"
      TH.addDependentFile path
      contents <- runIO (readFile path)
      TH.lift contents
   )

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg
          { logPath = parseFlag "--log-path" args
          , systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance
          }
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
