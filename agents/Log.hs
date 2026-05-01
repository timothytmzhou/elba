{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- Structured JSONL logging for the agent loop. One event per line; each
-- carries an ISO-8601 timestamp and a tagged payload. Used by Agents.hs to
-- record per-turn requests, responses, retries, and final outcomes without
-- printing to stderr.

module Log
  ( Log
  , withLog
  , logEvent
  , Event (..)
  ) where

import Data.Aeson (ToJSON (..), encode, object, (.=))
import Data.ByteString.Lazy qualified as BSL
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import System.IO
  ( BufferMode (LineBuffering)
  , Handle
  , IOMode (AppendMode)
  , hClose
  , hSetBuffering
  , openFile
  )

-- Nothing when logPath was unset; logEvent is then a no-op.
newtype Log = Log {logHandle :: Maybe Handle}

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
withLog Nothing action = action (Log Nothing)
withLog (Just path) action = do
  h <- openFile path AppendMode
  hSetBuffering h LineBuffering
  result <- action (Log (Just h))
  hClose h
  pure result

logEvent :: Log -> Event -> IO ()
logEvent (Log Nothing) _ = pure ()
logEvent (Log (Just h)) ev = do
  ts <- getCurrentTime
  let entry = object ["ts" .= iso8601Time ts, "event" .= ev]
  BSL.hPutStr h (encode entry <> "\n")

iso8601Time :: UTCTime -> String
iso8601Time = iso8601Show
