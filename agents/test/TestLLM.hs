module Main where

import LLM

main :: IO ()
main = do
  ask <- withSession defaultConfig
  r1 <- ask "What is 2+2?"
  putStrLn $ "Response 1: " ++ r1
  r2 <- ask "And multiply that by 3?"
  putStrLn $ "Response 2: " ++ r2
