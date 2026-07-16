{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the slack suite. The driver lives in InsecureApp.
-- The tool set is the whole SlackTCB and WebTCB surface plus printf.
module Main where

import Env (Env (..), defEnv)
import InsecureApp (runInsecureAgent)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)
import Text.Printf (printf)

agentEnv :: Env
agentEnv =
  $(addTools ['printf])
    defEnv
      { modules = ["SlackTCB", "WebTCB"]
      , extensions = [OverloadedStrings]
      }

main :: IO ()
main = runInsecureAgent agentEnv
