{-# LANGUAGE LinearTypes #-}

module Main where

import Agents (mkAgent)
import Env (Extension (LinearTypes), defEnv, extensions, modules)
import LLM (defaultConfig)
import Server

main :: IO ()
main = do
  let env =
        defEnv
          { modules = ["Server"],
            extensions = [LinearTypes]
          }
  let agent = mkAgent defaultConfig env
  let task = agent "buy two apples" :: Cap %1 -> ServerRequest ()
  runRequest (task Cap)
