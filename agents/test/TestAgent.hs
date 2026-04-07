module Main where

import Agents
import LLM
import Language.Haskell.Interpreter (ModuleImport(..), ImportList(..), ModuleQualification(..))

main :: IO ()
main = do
  let env = []
  result :: [Int] <- gen defaultConfig env "Give me a list of the first 5 fibonacci numbers"
  putStrLn $ "Result: " ++ show result
