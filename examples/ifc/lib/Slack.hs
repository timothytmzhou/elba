{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- LIO-secured wrapper around `SlackTCB`. Every tool runs in the `DC`
-- monad and documents how it taints the current label or which sink
-- it guards against.
--
-- One principal: `slack` (data originating in the slack workspace).
-- Web data is just `dcPublic = True %% True` — no separate principal
-- is needed for it.
--
-- The agent's initial state is `dcBottom = True %% False` — secrecy
-- at the bottom of the secrecy lattice (`cTrue`, the identity for
-- `cUnion`) and integrity at the bottom of the integrity lattice
-- (`cFalse`, the identity for `cOr`) — so both components grow
-- monotonically as the agent reads from sources.
--
-- Reads taint the current label. Writes pre-guard at the sink label;
-- body-bearing writes additionally `lWait` a `DCLabeled` body. The
-- intended use is for the agent to keep outer current pristine and
-- run reads inside `lFork`, passing the resulting `DCLabeled` value
-- to a write.

module Slack
  ( DC
  , DCLabeled
  , Body
  , Message (..)
  , slack
  , dcBottom
  , getChannels
  , readChannelMessages
  , readInbox
  , getUsersInChannel
  , addUserToChannel
  , inviteUserToSlack
  , removeUserFromSlack
  , sendDirectMessage
  , sendChannelMessage
  ) where

import LIO (guardAlloc, taint)
import LIO.Concurrent (LabeledResult, lWait)
import LIO.DCLabel (CNF, DC, DCLabel, toCNF, (%%))
import LIO.TCB (ioTCB)
import SlackTCB (Body, Message (..))
import SlackTCB qualified

type DCLabeled a = LabeledResult DCLabel a

slack :: CNF
slack = toCNF ("slack" :: String)

dcBottom :: DCLabel
dcBottom = True %% False

-- | Get the list of channels in the slack.
-- Taints the current label with `True %% slack`.
getChannels :: DC [String]
getChannels = do
  taint (True %% slack)
  ioTCB SlackTCB.getChannels

-- | Read the messages from the given channel.
-- @channel@: The channel to read the messages from.
-- Taints the current label with `slack %% slack`.
readChannelMessages :: String -> DC [Message]
readChannelMessages c = do
  taint (slack %% slack)
  ioTCB (SlackTCB.readChannelMessages c)

-- | Read the messages from the given user inbox.
-- @user@: The user whose inbox to read.
-- Taints the current label with `slack %% slack`.
readInbox :: String -> DC [Message]
readInbox u = do
  taint (slack %% slack)
  ioTCB (SlackTCB.readInbox u)

-- | Get the list of users in the given channel.
-- @channel@: The channel to get the users from.
-- Taints the current label with `True %% slack`.
getUsersInChannel :: String -> DC [String]
getUsersInChannel c = do
  taint (True %% slack)
  ioTCB (SlackTCB.getUsersInChannel c)

-- | Add a user to a given channel.
-- @user@: The user to add to the channel.
-- @channel@: The channel to add the user to.
-- guardAllocs at `slack %% False` (the slack-workspace sink label).
addUserToChannel :: String -> String -> DC ()
addUserToChannel u c = do
  guardAlloc (slack %% False)
  ioTCB (SlackTCB.addUserToChannel u c)

-- | Invites a user to the Slack workspace.
-- @user@: The user to invite.
-- @user_email@: The user email where invite should be sent.
-- guardAllocs at `slack %% False`.
inviteUserToSlack :: String -> String -> DC ()
inviteUserToSlack u email = do
  guardAlloc (slack %% False)
  ioTCB (SlackTCB.inviteUserToSlack u email)

-- | Remove a user from the Slack workspace.
-- @user@: The user to remove.
-- guardAllocs at `slack %% False`.
removeUserFromSlack :: String -> DC ()
removeUserFromSlack u = do
  guardAlloc (slack %% False)
  ioTCB (SlackTCB.removeUserFromSlack u)

-- | Send a direct message from the bot to @recipient@ with the given @body@.
-- @recipient@: The recipient of the message.
-- @body@: The body of the message, supplied as a `DCLabeled Body` —
-- typically the result of an `lFork`-spawned read.
-- guardAllocs at `slack %% False`, then `lWait`s the body.
sendDirectMessage :: String -> DCLabeled Body -> DC ()
sendDirectMessage r dlr = do
  guardAlloc (slack %% False)
  body <- lWait dlr
  ioTCB (SlackTCB.sendDirectMessage r body)

-- | Send a channel message from the bot to @channel@ with the given @body@.
-- @channel@: The channel to send the message to.
-- @body@: The body of the message, as a `DCLabeled Body`.
-- guardAllocs at `slack %% False`, then `lWait`s the body.
sendChannelMessage :: String -> DCLabeled Body -> DC ()
sendChannelMessage c dlr = do
  guardAlloc (slack %% False)
  body <- lWait dlr
  ioTCB (SlackTCB.sendChannelMessage c body)
