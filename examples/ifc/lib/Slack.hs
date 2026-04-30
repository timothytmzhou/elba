{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE Trustworthy #-}

-- Slack tool bindings for AgentDojo's slack default suite.
-- Mirrors the Python Slack class: each per-Python-field has a corresponding
-- LIORef on the Haskell side that holds the *policy label* for that data
-- (not the data itself). Each LIORef is allocated at dcPublic so its read/write
-- bypasses LIO label tracking; only the value (a DCLabel) carries policy meaning.
-- For this baseline none of the tool functions actually consult those labels.

module Slack
  ( -- Re-exports so the agent's type ascription `Slack -> Web -> DC String`
    -- can be typechecked by hint, which expands DC to LIO DCLabel.
    LIO
  , DCLabel
  , DC
  , User
  , Channel
  , Body
  , Message (..)
  , Slack
  , mkSlack
  , user
  , channel
  , getChannels
  , addUserToChannel
  , readChannelMessages
  , readInbox
  , sendDirectMessage
  , sendChannelMessage
  , inviteUserToSlack
  , removeUserFromSlack
  , getUsersInChannel
  ) where

import Bridge (Bridge, ToolError, callPy)
import Data.Aeson (FromJSON, ToJSON, Value, object, parseJSON, toJSON, withObject, withText, (.:), (.=))
import Data.Aeson qualified as A
import Data.ByteString.Char8 qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import LIO (LIO)
import LIO.DCLabel (DCLabel, Principal, dcPublic, principal, principalName)
import LIO.LIORef (LIORef, newLIORef)
import LIO.TCB (ioTCB)

type DC = LIO DCLabel

type User = Principal

type Channel = Principal

type Body = String

data Message = Message
  { sender :: User
  , recipient :: User
  , body :: Body
  }
  deriving (Show)

data Slack = Slack
  { usersListLabel :: LIORef DCLabel DCLabel
  , channelsListLabel :: LIORef DCLabel DCLabel
  , inboxLabels :: LIORef DCLabel (Map User DCLabel)
  , channelMsgLabels :: LIORef DCLabel (Map Channel DCLabel)
  , membershipLabels :: LIORef DCLabel (Map Channel DCLabel)
  , bridge :: Bridge
  }

mkSlack :: Bridge -> DC Slack
mkSlack br = do
  usersListLabel <- newLIORef dcPublic dcPublic
  channelsListLabel <- newLIORef dcPublic dcPublic
  inboxLabels <- newLIORef dcPublic Map.empty
  channelMsgLabels <- newLIORef dcPublic Map.empty
  membershipLabels <- newLIORef dcPublic Map.empty
  let bridge = br
  pure Slack {..}

user :: String -> User
user = principal

channel :: String -> Channel
channel = principal

-- Tool functions: each is a thin wrapper that lifts the bridge call into DC.
-- Label checks (taint, guardAlloc) are deliberately absent in the baseline.

getChannels :: Slack -> DC [Channel]
getChannels s = ioTCB $ callPy (bridge s) "get_channels" A.Null

addUserToChannel :: Slack -> User -> Channel -> DC ()
addUserToChannel s u c =
  ioTCB $
    callPy
      (bridge s)
      "add_user_to_channel"
      (object ["user" .= u, "channel" .= c])

readChannelMessages :: Slack -> Channel -> DC [Message]
readChannelMessages s c =
  ioTCB $
    callPy
      (bridge s)
      "read_channel_messages"
      (object ["channel" .= c])

readInbox :: Slack -> User -> DC [Message]
readInbox s u =
  ioTCB $
    callPy
      (bridge s)
      "read_inbox"
      (object ["user" .= u])

sendDirectMessage :: Slack -> User -> Body -> DC ()
sendDirectMessage s recipient body =
  ioTCB $
    callPy
      (bridge s)
      "send_direct_message"
      (object ["recipient" .= recipient, "body" .= body])

sendChannelMessage :: Slack -> Channel -> Body -> DC ()
sendChannelMessage s c body =
  ioTCB $
    callPy
      (bridge s)
      "send_channel_message"
      (object ["channel" .= c, "body" .= body])

inviteUserToSlack :: Slack -> User -> String -> DC ()
inviteUserToSlack s u email =
  ioTCB $
    callPy
      (bridge s)
      "invite_user_to_slack"
      (object ["user" .= u, "user_email" .= email])

removeUserFromSlack :: Slack -> User -> DC ()
removeUserFromSlack s u =
  ioTCB $
    callPy
      (bridge s)
      "remove_user_from_slack"
      (object ["user" .= u])

getUsersInChannel :: Slack -> Channel -> DC [User]
getUsersInChannel s c =
  ioTCB $
    callPy
      (bridge s)
      "get_users_in_channel"
      (object ["channel" .= c])

-- Orphan instances for Principal and Message — required to ship User/Message
-- through the JSON-RPC. Confined to this Trustworthy module; not visible to the
-- agent because it imports Slack but does not see Aeson.

instance ToJSON Principal where
  toJSON p = A.String (T.pack (BS.unpack (principalName p)))

instance FromJSON Principal where
  parseJSON = withText "Principal" (pure . principal . T.unpack)

instance ToJSON Message where
  toJSON Message {..} =
    object ["sender" .= sender, "recipient" .= recipient, "body" .= body]

instance FromJSON Message where
  parseJSON = withObject "Message" $ \o -> do
    sender <- o .: "sender"
    recipient <- o .: "recipient"
    body <- o .: "body"
    pure Message {..}
