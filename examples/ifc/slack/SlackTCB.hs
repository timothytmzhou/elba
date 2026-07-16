{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure tool surface for the slack suite.
module SlackTCB (module SlackTCB) where

import Data.Aeson (FromJSON, ToJSON, object, parseJSON, toJSON, withObject, (.:), (.=))
import Tool (defTool, defTools)

type Body = String

data Message = Message
  { sender :: String
  , recipient :: String
  , body :: Body
  }
  deriving (Show)

instance ToJSON Message where
  toJSON Message {..} = object ["sender" .= sender, "recipient" .= recipient, "body" .= body]

instance FromJSON Message where
  parseJSON = withObject "Message" $ \o ->
    Message <$> o .: "sender" <*> o .: "recipient" <*> o .: "body"

defTools
  [ defTool "getChannels" "get_channels" [] [t|IO [String]|]
  , defTool "addUserToChannel" "add_user_to_channel" ["user", "channel"] [t|String -> String -> IO ()|]
  , defTool "readChannelMessages" "read_channel_messages" ["channel"] [t|String -> IO [Message]|]
  , defTool "readInbox" "read_inbox" ["user"] [t|String -> IO [Message]|]
  , defTool "sendDirectMessage" "send_direct_message" ["recipient", "body"] [t|String -> Body -> IO ()|]
  , defTool "sendChannelMessage" "send_channel_message" ["channel", "body"] [t|String -> Body -> IO ()|]
  , defTool "inviteUserToSlack" "invite_user_to_slack" ["user", "user_email"] [t|String -> String -> IO ()|]
  , defTool "removeUserFromSlack" "remove_user_from_slack" ["user"] [t|String -> IO ()|]
  , defTool "getUsersInChannel" "get_users_in_channel" ["channel"] [t|String -> IO [String]|]
  ]
