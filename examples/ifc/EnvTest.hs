{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- Compile-and-run check for the two agentEnvs in this package: makes
-- sure `setEnv` succeeds (modules import cleanly under -XSafe, every
-- name in `addTools` resolves to a type) and prints the resulting
-- TypeEnv. Does not call any LLM.

module Main where

import Env (Env (..), defEnv, setEnv)
import LIO.Concurrent (lFork, lWait)
import LIO.DCLabel (dcPublic, (%%), (/\), (\/))
import LIO.Labeled (label, unlabel)
import Language.Haskell.Interpreter
  ( OptionVal ((:=))
  , languageExtensions
  , searchPath
  , set
  )
import Language.Haskell.Interpreter qualified as Hint
import Language.Haskell.Interpreter.Unsafe (unsafeRunInterpreterWithArgs)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import TH (addTools)

tcbAgentEnv :: Env
tcbAgentEnv =
  defEnv
    { modules = ["SlackTCB", "WebTCB"]
    , extensions = [OverloadedStrings]
    }

secureAgentEnv :: Env
secureAgentEnv =
  $( addTools
       [ 'label
       , 'unlabel
       , 'lFork
       , 'lWait
       , 'dcPublic
       , '(%%)
       , '(/\)
       , '(\/)
       ]
   )
    defEnv
      { modules = ["Slack", "Web"]
      , silentModules = ["LIO"]
      , extensions = [OverloadedStrings]
      }

baseModules :: [String]
baseModules = ["Prelude", "Data.Typeable", "Language.Haskell.TH.Syntax"]

testEnv :: String -> Env -> IO ()
testEnv label_ env = do
  putStrLn $ "=== " ++ label_ ++ " ==="
  result <- unsafeRunInterpreterWithArgs ["-package", "template-haskell", "-XSafe"] $ do
    set [searchPath := []]
    set [languageExtensions := map (Hint.UnknownExtension . show) (extensions env)]
    setEnv env baseModules
  case result of
    Left e -> putStrLn $ "ERROR: " ++ show e
    Right typeEnv -> putStr (show typeEnv)
  putStrLn ""

main :: IO ()
main = do
  testEnv "Insecure baseline (Main.hs)" tcbAgentEnv
  testEnv "LIO-secured (MainSecure.hs)" secureAgentEnv
