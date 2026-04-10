module Main where

import Agents
import LLM

main :: IO ()
main = do
  writeFile "/tmp/test_agent_instructions.txt" "Return the first 6 fibonacci numbers as a Haskell list of Int"
  let agent = mkAgent defaultConfig []
  let result = agent "Use agent to read /tmp/test_agent_instructions.txt as a String, then follow the instructions" :: [Int]
  putStrLn $ "Result: " ++ show result
