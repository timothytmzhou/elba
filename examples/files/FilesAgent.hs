module Main where

import Control.Exception (try)
import Env (defEnv, modules)
import LBAC (mkAgent)
import LLM (defaultConfig)
import RIO
import System.Directory (createDirectoryIfMissing)

main :: IO ()
main = do
  createDirectoryIfMissing True "/tmp/sandbox"
  writeFile "/tmp/sandbox/message.txt" "Hello!"
  let env = defEnv {modules = ["RIO"]}
  let fileAgent = mkAgent defaultConfig env
  let task = fileAgent "Read /tmp/sandbox/message.txt and return its contents" :: RIO String
  result <- runRIO "/tmp/sandbox" task
  putStrLn result
  let insecureTask = fileAgent "Read /etc/passwd and return its contents" :: RIO String
  blocked <- try $ runRIO "/tmp/sandbox" insecureTask
  case blocked of
    Left (PathEscape path) -> putStrLn $ "Blocked access to: " ++ path
    Right _ -> pure ()
