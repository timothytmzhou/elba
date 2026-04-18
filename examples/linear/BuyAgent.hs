{-# LANGUAGE LinearTypes #-}

module Main where

import Agents (mkAgent)
import Control.Exception (SomeException, catch)
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
  let authorized = agent "buy one apple" :: Auth ()
  let unauthorized = agent "buy two apples." :: Auth ()
  runWithOneAuthorization authorized
  runWithOneAuthorization unauthorized
    `catch` \(_ :: SomeException) -> putStrLn "unauthorized block"
