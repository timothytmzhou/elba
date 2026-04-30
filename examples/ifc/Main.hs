module Main where

import Agents (mkAgent)
import Bridge (Bridge, readPrompt, sendDone, sendFailed, withBridge)
import Control.Exception (SomeException, displayException, try)
import Env (Env (..), defEnv)
import LIO (LIOState (..), evalLIO)
import LIO.DCLabel (DCLabel, dcPublic)
import LLM (Config (..), defaultConfig)
import Language.Haskell.TH.Syntax (Extension (OverloadedStrings))
import Slack (DC, Slack, mkSlack)
import System.Environment (getArgs)
import Web (Web, mkWeb)

agentEnv :: Env
agentEnv = defEnv {modules = ["Slack", "Web"], extensions = [OverloadedStrings]}

initialState :: LIOState DCLabel
initialState = LIOState {lioLabel = dcPublic, lioClearance = dcPublic}

-- Parse `--log-path PATH`; ignore any other args.
parseLogPath :: [String] -> Maybe FilePath
parseLogPath ("--log-path" : p : _) = Just p
parseLogPath (_ : rest) = parseLogPath rest
parseLogPath [] = Nothing

main :: IO ()
main = do
  agentLogPath <- parseLogPath <$> getArgs
  withBridge $ \br -> do
    prompt <- readPrompt br
    let cfg = defaultConfig {logPath = agentLogPath}
    let agentExpr = mkAgent cfg agentEnv prompt :: Slack -> Web -> DC String
    let task = do
          slack <- mkSlack br
          web <- mkWeb br
          agentExpr slack web
    -- Catch SomeException: covers ToolError (Python ValueErrors), WontCompile
    -- (the LLM emitted code that doesn't typecheck), and any LIO LabelError.
    -- All represent the agent failing to complete the task.
    result <- try (evalLIO task initialState) :: IO (Either SomeException String)
    case result of
      Right answer -> sendDone br answer
      Left e -> sendFailed br (displayException e)
