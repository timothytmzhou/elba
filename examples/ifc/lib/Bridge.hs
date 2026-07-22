{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- The "bridge" is just the process's standard handles. This works across the hint
-- interpreter session because `stdin` and `stdout` ultimately
-- reference fd 0/1, which are shared at the OS level (unlike
-- user-defined module-level CAFs, which hint allocates separately).

module Bridge
  ( withBridge
  , readPrompt
  , sendDone
  , sendFailed
  , callPy
  , parseFlag
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
import System.IO (BufferMode (LineBuffering), hFlush, hSetBuffering, stdin, stdout)

newtype ToolError = ToolError String
  deriving (Show)

instance Exception ToolError

-- | Configure stdin/stdout for line-delimited JSON, then run the action.
withBridge :: IO a -> IO a
withBridge action = do
  hSetBuffering stdin LineBuffering
  hSetBuffering stdout LineBuffering
  action

readPrompt :: IO String
readPrompt = do
  line <- BS.hGetLine stdin
  case decodeStrict line :: Maybe Value of
    Just (Object o)
      | Just (String t) <- KM.lookup "prompt" o -> pure (T.unpack t)
    _ -> error ("Bridge.readPrompt: expected {\"prompt\": ...}, got: " ++ BS.unpack line)

sendDone :: String -> IO ()
sendDone answer = sendLine (object ["done" .= answer])

sendFailed :: String -> IO ()
sendFailed msg = sendLine (object ["failed" .= msg])

callPy :: (FromJSON b) => String -> Value -> IO b
callPy method args = do
  sendLine (object ["call" .= method, "args" .= args])
  reply <- BS.hGetLine stdin
  case decodeStrict reply :: Maybe Value of
    Just (Object o)
      | Just v <- KM.lookup "ok" o ->
          case fromJSON v of
            Success x -> pure x
            Error e -> error ("Bridge.callPy: decode failed: " ++ e ++ " on " ++ show v)
      | Just (String e) <- KM.lookup "err" o ->
          throwIO (ToolError (T.unpack e))
    _ -> error ("Bridge.callPy: malformed reply: " ++ BS.unpack reply)

sendLine :: Value -> IO ()
sendLine v = do
  BSL.hPut stdout (encode v <> "\n")
  hFlush stdout

-- | The value following @flag@ in the argument list.
parseFlag :: String -> [String] -> Maybe String
parseFlag flag (a : v : _) | a == flag = Just v
parseFlag flag (_ : rest) = parseFlag flag rest
parseFlag _ [] = Nothing
