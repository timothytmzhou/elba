module Main where

import Agents
import LLM

main :: IO ()
main = do
  writeFile "/tmp/test_agent_instructions.txt" "Return the first 6 fibonacci numbers as a Haskell list of Int"
  let agent = mkAgent defaultConfig
  print "Running agent..."
  result :: [Int] <- agent [] "Read /tmp/test_agent_instructions.txt, then follow the instructions"
  putStrLn $ "Result: " ++ show result
