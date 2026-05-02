{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure baseline for AgentDojo's slack default suite. Each tool
-- takes a Slack handle (the bridge to Python) explicitly because hint
-- does not share top-level CAF state across its interpreter session
-- with the host process — IORef-based dependency injection inside the
-- module doesn't reach interpreted code.

module Slack
  ( Body
  , Message (..)
  , Slack
  , mkSlack
  , bridge
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

import Bridge (Bridge, callPy)
import Data.Aeson (FromJSON, ToJSON, object, parseJSON, toJSON, withObject, (.:), (.=))
import Data.Aeson qualified as A

type Body = String

data Message = Message
  { sender :: String
  , recipient :: String
  , body :: Body
  }
  deriving (Show)

newtype Slack = Slack {bridge :: Bridge}

mkSlack :: Bridge -> Slack
mkSlack = Slack

-- | Get the list of channels in the slack.
getChannels :: Slack -> IO [String]
getChannels s = callPy (bridge s) "get_channels" A.Null

-- | Add a user to a given channel.
-- @user@: The user to add to the channel.
-- @channel@: The channel to add the user to.
addUserToChannel :: Slack -> String -> String -> IO ()
addUserToChannel s u c =
  callPy (bridge s) "add_user_to_channel" (object ["user" .= u, "channel" .= c])

-- | Read the messages from the given channel.
-- @channel@: The channel to read the messages from.
readChannelMessages :: Slack -> String -> IO [Message]
readChannelMessages s c =
  callPy (bridge s) "read_channel_messages" (object ["channel" .= c])

-- | Read the messages from the given user inbox.
-- @user@: The user whose inbox to read.
readInbox :: Slack -> String -> IO [Message]
readInbox s u =
  callPy (bridge s) "read_inbox" (object ["user" .= u])

-- | Send a direct message from the bot to @recipient@ with the given @body@.
-- @recipient@: The recipient of the message.
-- @body@: The body of the message.
sendDirectMessage :: Slack -> String -> Body -> IO ()
sendDirectMessage s r b =
  callPy (bridge s) "send_direct_message" (object ["recipient" .= r, "body" .= b])

-- | Send a channel message from the bot to @channel@ with the given @body@.
-- @channel@: The channel to send the message to.
-- @body@: The body of the message.
sendChannelMessage :: Slack -> String -> Body -> IO ()
sendChannelMessage s c b =
  callPy (bridge s) "send_channel_message" (object ["channel" .= c, "body" .= b])

-- | Invites a user to the Slack workspace.
-- @user@: The user to invite.
-- @user_email@: The user email where invite should be sent.
inviteUserToSlack :: Slack -> String -> String -> IO ()
inviteUserToSlack s u email =
  callPy (bridge s) "invite_user_to_slack" (object ["user" .= u, "user_email" .= email])

-- | Remove a user from the Slack workspace.
-- @user@: The user to remove.
removeUserFromSlack :: Slack -> String -> IO ()
removeUserFromSlack s u =
  callPy (bridge s) "remove_user_from_slack" (object ["user" .= u])

-- | Get the list of users in the given channel.
-- @channel@: The channel to get the users from.
getUsersInChannel :: Slack -> String -> IO [String]
getUsersInChannel s c =
  callPy (bridge s) "get_users_in_channel" (object ["channel" .= c])

instance ToJSON Message where
  toJSON Message {..} =
    object ["sender" .= sender, "recipient" .= recipient, "body" .= body]

instance FromJSON Message where
  parseJSON = withObject "Message" $ \o -> do
    sender <- o .: "sender"
    recipient <- o .: "recipient"
    body <- o .: "body"
    pure Message {..}
