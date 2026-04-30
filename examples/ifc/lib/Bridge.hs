{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

module Bridge
  ( Bridge
  , withBridge
  , readPrompt
  , sendDone
  , sendFailed
  , callPy
  , ToolError (..)
  ) where

import Control.Exception (Exception, throwIO)
import Data.Aeson
  ( FromJSON
  , Result (..)
  , Value (..)
  , decodeStrict
  , encode
  , fromJSON
  , object
  , (.=)
  )
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Text qualified as T
import System.IO (BufferMode (LineBuffering), Handle, hFlush, hSetBuffering, stdin, stdout)

data Bridge = Bridge {bIn :: Handle, bOut :: Handle}

newtype ToolError = ToolError String
  deriving (Show)

instance Exception ToolError

withBridge :: (Bridge -> IO a) -> IO a
withBridge action = do
  hSetBuffering stdin LineBuffering
  hSetBuffering stdout LineBuffering
  action (Bridge stdin stdout)

readPrompt :: Bridge -> IO String
readPrompt br = do
  line <- BS.hGetLine (bIn br)
  let parsed = decodeStrict line :: Maybe Value
  case parsed of
    Just (Object o) | Just (String t) <- KM.lookup "prompt" o -> pure (T.unpack t)
    _ -> error ("Bridge.readPrompt: expected {\"prompt\": ...}, got: " ++ BS.unpack line)

sendDone :: Bridge -> String -> IO ()
sendDone br answer = sendLine br (object ["done" .= answer])

sendFailed :: Bridge -> String -> IO ()
sendFailed br msg = sendLine br (object ["failed" .= msg])

callPy :: (FromJSON b) => Bridge -> String -> Value -> IO b
callPy br method args = do
  sendLine br (object ["call" .= method, "args" .= args])
  reply <- BS.hGetLine (bIn br)
  case decodeStrict reply :: Maybe Value of
    Just (Object o)
      | Just v <- KM.lookup "ok" o ->
          case fromJSON v of
            Success x -> pure x
            Error e -> error ("Bridge.callPy: decode failed: " ++ e ++ " on " ++ show v)
      | Just (String e) <- KM.lookup "err" o ->
          throwIO (ToolError (T.unpack e))
    _ -> error ("Bridge.callPy: malformed reply: " ++ BS.unpack reply)

sendLine :: Bridge -> Value -> IO ()
sendLine br v = do
  BSL.hPut (bOut br) (encode v <> "\n")
  hFlush (bOut br)
