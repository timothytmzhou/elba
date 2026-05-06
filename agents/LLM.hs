{-# LANGUAGE TemplateHaskell #-}

module LLM
  ( Config (..)
  , defaultConfig
  , defaultSystemPrompt
  , withSession
  ) where

import Data.IORef (newIORef, readIORef, writeIORef)
import Language.Haskell.TH (runIO)
import Language.Haskell.TH.Syntax qualified as TH
import System.FilePath (takeDirectory, (</>))
import System.Process (readProcess)

data Config = Config
  { modelName       :: Maybe String
  , seed            :: Integer
  , reasoningEffort :: Maybe String
  -- ^ For reasoning models (e.g. gpt-5.x): "low" | "medium" | "high".
  --   Nothing skips the flag and uses the provider default.
  , systemPrompt    :: String
  , logPath         :: Maybe FilePath
  -- ^ JSONL log destination for the agent loop. Nothing disables logging.
  , maxAttempts     :: Int
  -- ^ Compile retries per mkAgent call. >= 1; first attempt counts.
  , maxDepth        :: Int
  -- ^ Recursion budget across the recursive `subagent` binding. Decremented
  --   on each recursive call; mkAgent refuses to call the LLM at depth <= 0.
  }

-- The default system prompt body lives in SystemPrompt.md so it can be
-- edited as prose. `addDependentFile` triggers a rebuild whenever that
-- file changes. Callers (e.g. MainSecure) can extend this string with
-- environment-specific addenda when constructing their own Config.
defaultSystemPrompt :: String
defaultSystemPrompt =
  $( do
      loc <- TH.location
      let path = takeDirectory (TH.loc_filename loc) </> "SystemPrompt.md"
      TH.addDependentFile path
      contents <- runIO (readFile path)
      TH.lift contents
   )

defaultConfig :: Config
defaultConfig = Config
  { modelName       = Just "gpt-5.4"
  , seed            = 0
  , reasoningEffort = Just "high"
  , systemPrompt    = defaultSystemPrompt
  , logPath         = Nothing
  , maxAttempts     = 3
  , maxDepth        = 7
  }

toArgs :: Config -> [String]
toArgs Config {modelName, seed, reasoningEffort} = modelArgs ++ seedArgs ++ effortArgs
  where
    modelArgs = case modelName of
      Nothing   -> []
      Just name -> ["-m", name]
    seedArgs = ["-o", "seed", show seed]
    effortArgs = case reasoningEffort of
      Nothing -> []
      Just e  -> ["-o", "reasoning_effort", e]

withSession :: Config -> IO (String -> IO String)
withSession config = do
  let base = toArgs config ++ ["--no-stream"]
  first <- newIORef True
  pure $ \msg -> do
    isFirst <- readIORef first
    writeIORef first False
    let continueArgs = if isFirst then ["-s", systemPrompt config] else ["-c"]
    readProcess "llm" (base ++ continueArgs) msg
