module LLM
  ( Config(..)
  , defaultConfig
  , withSession
  ) where

import           Data.IORef     (newIORef, readIORef, writeIORef)
import           System.Process (readProcess)

data Config = Config {
  modelName    :: Maybe String,
  seed         :: Integer,
  systemPrompt :: String
}

defaultConfig :: Config
defaultConfig = Config {
  modelName = Just "gpt-4.1",
  seed = 0,
  systemPrompt = ""
}

toArgs :: Config -> [String]
toArgs Config{modelName, seed} = modelArgs ++ seedArgs
  where
    modelArgs = case modelName of
      Nothing   -> []
      Just name -> ["-m", name]
    seedArgs = ["-o", "seed", show seed]

withSession :: Config -> IO (String -> IO String)
withSession config = do
  let base = toArgs config ++ ["--no-stream"]
  first <- newIORef True
  pure $ \msg -> do
    isFirst <- readIORef first
    writeIORef first False
    let continueArgs = if isFirst then ["-s", systemPrompt config] else ["-c"]
    readProcess "llm" (base ++ continueArgs) msg
