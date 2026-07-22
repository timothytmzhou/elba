{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- JSONL logging for the agent loop. One timestamped event per line.

module Log
  ( Log
  , withLog
  , logEvent
  , Event (..)
  ) where

import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.ByteString.Lazy qualified as BSL
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import System.IO (IOMode (AppendMode), withFile)

-- Nothing when logPath was unset; logEvent is then a no-op.
-- We hold the path (not a handle) and open per-event so that recursive
-- mkAgent calls don't contend on a single long-lived handle (GHC's
-- file-locking semantics would otherwise reject the second open).
newtype Log = Log {logPath :: Maybe FilePath}

data Event
  = Request {systemPrompt :: String, userPrompt :: String, requiredType :: String}
  | Response {code :: String}
  | Retry {previousError :: String}
  | Failure {finalError :: String}
  | Success
  deriving (Show)

instance ToJSON Event where
  toJSON ev = case ev of
    Request {systemPrompt, userPrompt, requiredType} ->
      object
        [ "kind" .= ("request" :: String)
        , "system_prompt" .= systemPrompt
        , "user_prompt" .= userPrompt
        , "required_type" .= requiredType
        ]
    Response {code} ->
      object ["kind" .= ("response" :: String), "code" .= code]
    Retry {previousError} ->
      object ["kind" .= ("retry" :: String), "previous_error" .= previousError]
    Failure {finalError} ->
      object ["kind" .= ("failure" :: String), "final_error" .= finalError]
    Success ->
      object ["kind" .= ("success" :: String)]

withLog :: Maybe FilePath -> (Log -> IO a) -> IO a
withLog mp action = action (Log mp)

logEvent :: Log -> Event -> IO ()
logEvent (Log Nothing) _ = pure ()
logEvent (Log (Just path)) ev = do
  ts <- getCurrentTime
  let entry = object ["ts" .= iso8601Show ts, "event" .= ev]
  withFile path AppendMode $ \h ->
    BSL.hPut h (encode entry <> "\n")
