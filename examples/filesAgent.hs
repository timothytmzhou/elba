module Main where

import Agents (mkAgent)
import Env (defEnv, modules)
import LLM (defaultConfig)
import RIO

main :: IO ()
main = do
  writeFile "/tmp/sandbox/message.txt" "Hello!"
  let env = defEnv {modules = ["RIO"]}
  let fileAgent = mkAgent defaultConfig env
  let task = fileAgent "Read /tmp/sandbox/message.txt and return its contents" :: RIO String
  result <- runRIO "/tmp/sandbox" task
  putStrLn result
  let insecureTask = fileAgent "Read /etc/passwd and return its contents" :: RIO String
  result <- runRIO "tmp/sandbox" insecureTask
  putStrLn result
