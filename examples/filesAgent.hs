{-# LANGUAGE TemplateHaskellQuotes #-}

module Main where

import Agents (mkAgent)
import LLM (defaultConfig)
import RIO

main :: IO ()
main = do
  writeFile "/tmp/sandbox/message.txt" "Hello!"
  let env = [''RIO, 'readFileRIO, 'writeFileRIO, 'listDirectoryRIO, 'pwd, 'scoped]
  let fileAgent = mkAgent defaultConfig env
  let task = fileAgent "Read /tmp/sandbox/message.txt and return its contents"
  result <- runRIO "/tmp/sandbox" task
  putStrLn result
  let insecureTask = fileAgent "Read /etc/passwd and return its contents" 
  result <- runRIO "tmp/sandbox" insecureTask
  putStrLn result
