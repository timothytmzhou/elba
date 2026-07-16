{-# LANGUAGE TemplateHaskell #-}

module Main where

import AgentApp (runSecureAgent)
import Env (Env (..), Extension (OverloadedStrings), defEnv)
import LLM (Config (..), defaultSystemPrompt)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax qualified as TH
import System.FilePath (takeDirectory, (</>))

agentEnv :: Env
agentEnv =
  defEnv
    { modules = ["Slack", "Web", "IFC"]
    , extensions = [OverloadedStrings]
    }

-- Information-flow guidance appended to the default system prompt.
ifcGuidance :: String
ifcGuidance =
  $( do
      loc <- TH.location
      let path = takeDirectory (TH.loc_filename loc) </> ".." </> ".." </> "IfcGuidance.md"
      TH.addDependentFile path
      contents <- runIO (readFile path)
      TH.lift contents
   )

main :: IO ()
main = runSecureAgent agentEnv withGuidance
  where
    withGuidance cfg = cfg {systemPrompt = defaultSystemPrompt ++ "\n" ++ ifcGuidance}
