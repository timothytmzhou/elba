{-# LANGUAGE TemplateHaskell #-}

-- IFC secured agent app for the banking suite. The Banking policy is undefined so
-- this builds but fails at run time on the first tool call.
module Main where

import Agents (mkAgent)
import Bridge (readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import IFC (DC, evalLIO, initialState, toLabeled, unlabel)
import InsecureApp (loadConfig, parseFlag)
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import System.Environment (getArgs)
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $(addTools ['unlabel, 'toLabeled, 'printf])
    defEnv
      { modules = ["Banking"]
      , silentModules = ["IFC"]
      , extensions = [OverloadedStrings]
      }

main :: IO ()
main = do
  args <- getArgs
  baseCfg <- maybe (pure defaultConfig) loadConfig (parseFlag "--config" args)
  withBridge $ do
    prompt <- readPrompt
    let cfg = baseCfg {logPath = parseFlag "--log-path" args}
    let agentExpr = mkAgent cfg agentEnv prompt :: DC String
    result <- try (evalLIO agentExpr initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone answer
      Left (e :: SomeException) -> sendFailed (displayException e)
