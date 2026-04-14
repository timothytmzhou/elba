{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE TemplateHaskellQuotes #-}
module Main where

import Agents (mkAgent)
import LLM (defaultConfig)
import Server

main :: IO ()
main = do
  let agent = mkAgent defaultConfig ['buy, ''ServerRequest]
  let task :: Cap %1 -> ServerRequest () = agent "buy two apples"
  runRequest $ task Cap
