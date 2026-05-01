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
    -- can be typechecked by hint, which expands `DC` to `LIO DCLabel`.
    -- User and Channel are newtypes so they don't expand to Principal.
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
  , userName
  , channelName
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

newtype User = User Principal
  deriving (Eq, Ord, Show)

newtype Channel = Channel Principal
  deriving (Eq, Ord, Show)

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
user = User . principal

channel :: String -> Channel
channel = Channel . principal

userName :: User -> String
userName (User p) = BS.unpack (principalName p)

channelName :: Channel -> String
channelName (Channel p) = BS.unpack (principalName p)

-- Tool functions: each is a thin wrapper that lifts the bridge call into DC.
-- Label checks (taint, guardAlloc) are deliberately absent in the baseline.

-- | Get the list of channels in the slack.
getChannels :: Slack -> DC [Channel]
getChannels s = ioTCB $ callPy (bridge s) "get_channels" A.Null

-- | Add a user to a given channel.
-- @user@: The user to add to the channel.
-- @channel@: The channel to add the user to.
addUserToChannel :: Slack -> User -> Channel -> DC ()
addUserToChannel s u c =
  ioTCB $
    callPy
      (bridge s)
      "add_user_to_channel"
      (object ["user" .= u, "channel" .= c])

-- | Read the messages from the given channel.
-- @channel@: The channel to read the messages from.
readChannelMessages :: Slack -> Channel -> DC [Message]
readChannelMessages s c =
  ioTCB $
    callPy
      (bridge s)
      "read_channel_messages"
      (object ["channel" .= c])

-- | Read the messages from the given user inbox.
-- @user@: The user whose inbox to read.
readInbox :: Slack -> User -> DC [Message]
readInbox s u =
  ioTCB $
    callPy
      (bridge s)
      "read_inbox"
      (object ["user" .= u])

-- | Send a direct message from the bot to @recipient@ with the given @body@.
-- @recipient@: The recipient of the message.
-- @body@: The body of the message.
sendDirectMessage :: Slack -> User -> Body -> DC ()
sendDirectMessage s recipient body =
  ioTCB $
    callPy
      (bridge s)
      "send_direct_message"
      (object ["recipient" .= recipient, "body" .= body])

-- | Send a channel message from the bot to @channel@ with the given @body@.
-- @channel@: The channel to send the message to.
-- @body@: The body of the message.
sendChannelMessage :: Slack -> Channel -> Body -> DC ()
sendChannelMessage s c body =
  ioTCB $
    callPy
      (bridge s)
      "send_channel_message"
      (object ["channel" .= c, "body" .= body])

-- | Invites a user to the Slack workspace.
-- @user@: The user to invite.
-- @user_email@: The user email where invite should be sent.
inviteUserToSlack :: Slack -> User -> String -> DC ()
inviteUserToSlack s u email =
  ioTCB $
    callPy
      (bridge s)
      "invite_user_to_slack"
      (object ["user" .= u, "user_email" .= email])

-- | Remove a user from the Slack workspace.
-- @user@: The user to remove.
removeUserFromSlack :: Slack -> User -> DC ()
removeUserFromSlack s u =
  ioTCB $
    callPy
      (bridge s)
      "remove_user_from_slack"
      (object ["user" .= u])

-- | Get the list of users in the given channel.
-- @channel@: The channel to get the users from.
getUsersInChannel :: Slack -> Channel -> DC [User]
getUsersInChannel s c =
  ioTCB $
    callPy
      (bridge s)
      "get_users_in_channel"
      (object ["channel" .= c])

-- JSON instances for shipping User/Channel/Message through the JSON-RPC.
-- Newtype wrappers serialise as plain strings so the Python side sees the
-- same shape it would for a `str`.

instance ToJSON User where
  toJSON (User p) = A.String (T.pack (BS.unpack (principalName p)))

instance FromJSON User where
  parseJSON = withText "User" (pure . User . principal . T.unpack)

instance ToJSON Channel where
  toJSON (Channel p) = A.String (T.pack (BS.unpack (principalName p)))

instance FromJSON Channel where
  parseJSON = withText "Channel" (pure . Channel . principal . T.unpack)

instance ToJSON Message where
  toJSON Message {..} =
    object ["sender" .= sender, "recipient" .= recipient, "body" .= body]

instance FromJSON Message where
  parseJSON = withObject "Message" $ \o -> do
    sender <- o .: "sender"
    recipient <- o .: "recipient"
    body <- o .: "body"
    pure Message {..}
