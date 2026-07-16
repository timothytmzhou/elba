{-# LANGUAGE TemplateHaskell #-}

-- No policy agent app for the travel suite. The driver lives in InsecureApp.
-- The tool set is the whole TravelTCB surface plus printf.
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
      { modules = ["TravelTCB"]
      , extensions = [OverloadedStrings]
      }

main :: IO ()
main = runInsecureAgent agentEnv
