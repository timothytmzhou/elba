{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure baseline for AgentDojo's slack default suite. Tools have
-- no `Slack` argument; they read/write stdin/stdout directly via
-- `Bridge.callPy`. The agent's main type is just `IO String` and
-- sub-agents typed `IO X` get tool access for free (no `Slack ->`
-- prefix to thread).

module Slack
  ( Body
  , Message (..)
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

import Bridge (callPy)
import Data.Aeson (FromJSON, ToJSON, object, parseJSON, toJSON, withObject, (.:), (.=))
import Data.Aeson qualified as A

type Body = String

data Message = Message
  { sender :: String
  , recipient :: String
  , body :: Body
  }
  deriving (Show)

-- | Get the list of channels in the slack.
getChannels :: IO [String]
getChannels = callPy "get_channels" A.Null

-- | Add a user to a given channel.
-- @user@: The user to add to the channel.
-- @channel@: The channel to add the user to.
addUserToChannel :: String -> String -> IO ()
addUserToChannel u c =
  callPy "add_user_to_channel" (object ["user" .= u, "channel" .= c])

-- | Read the messages from the given channel.
-- @channel@: The channel to read the messages from.
readChannelMessages :: String -> IO [Message]
readChannelMessages c =
  callPy "read_channel_messages" (object ["channel" .= c])

-- | Read the messages from the given user inbox.
-- @user@: The user whose inbox to read.
readInbox :: String -> IO [Message]
readInbox u =
  callPy "read_inbox" (object ["user" .= u])

-- | Send a direct message from the bot to @recipient@ with the given @body@.
-- @recipient@: The recipient of the message.
-- @body@: The body of the message.
sendDirectMessage :: String -> Body -> IO ()
sendDirectMessage r b =
  callPy "send_direct_message" (object ["recipient" .= r, "body" .= b])

-- | Send a channel message from the bot to @channel@ with the given @body@.
-- @channel@: The channel to send the message to.
-- @body@: The body of the message.
sendChannelMessage :: String -> Body -> IO ()
sendChannelMessage c b =
  callPy "send_channel_message" (object ["channel" .= c, "body" .= b])

-- | Invites a user to the Slack workspace.
-- @user@: The user to invite.
-- @user_email@: The user email where invite should be sent.
inviteUserToSlack :: String -> String -> IO ()
inviteUserToSlack u email =
  callPy "invite_user_to_slack" (object ["user" .= u, "user_email" .= email])

-- | Remove a user from the Slack workspace.
-- @user@: The user to remove.
removeUserFromSlack :: String -> IO ()
removeUserFromSlack u =
  callPy "remove_user_from_slack" (object ["user" .= u])

-- | Get the list of users in the given channel.
-- @channel@: The channel to get the users from.
getUsersInChannel :: String -> IO [String]
getUsersInChannel c =
  callPy "get_users_in_channel" (object ["channel" .= c])

instance ToJSON Message where
  toJSON Message {..} =
    object ["sender" .= sender, "recipient" .= recipient, "body" .= body]

instance FromJSON Message where
  parseJSON = withObject "Message" $ \o -> do
    sender <- o .: "sender"
    recipient <- o .: "recipient"
    body <- o .: "body"
    pure Message {..}
