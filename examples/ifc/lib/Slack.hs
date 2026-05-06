{-# LANGUAGE Trustworthy #-}

module Slack
  ( DC,
    DCLabeled,
    Body,
    Message (..),
    assertWrite,
    getChannels,
    readChannelMessages,
    readInbox,
    getUsersInChannel,
    addUserToChannel,
    inviteUserToSlack,
    removeUserFromSlack,
    sendDirectMessage,
    sendChannelMessage,
  )
where

import Control.Monad (unless)
import LIO (canFlowTo, getLabel, guardAlloc, taint)
import LIO.DCLabel (CNF, DC, DCLabel, cFalse, dcIntegrity, toCNF, (%%), (\/))
import LIO.Error (labelError)
import LIO.Labeled (Labeled, labelOf, labelP, unlabelP)
import LIO.TCB (Priv (PrivTCB), ioTCB)
import SlackTCB (Body, Message (..))
import SlackTCB qualified

type DCLabeled a = Labeled DCLabel a

-- Internal helpers backed by an omnipotent priv. Not exported.
--   `relabelTCB` packages a value at an arbitrary label without
--   requiring `current ⊑ label`.
--   `unlabelTCB` extracts a `DCLabeled` value without raising current.
relabelTCB :: DCLabel -> a -> DC (DCLabeled a)
relabelTCB = labelP (PrivTCB (toCNF False))

unlabelTCB :: DCLabeled a -> DC a
unlabelTCB = unlabelP (PrivTCB (toCNF False))

-- | Write-side policy check. If current integrity is `cFalse`
-- (untainted, i.e. the agent has not absorbed any external data),
-- writes are unconditional. Otherwise require @dataLabel ⊑ sinkLabel@.
-- Raises a LabelError if neither holds.
assertWrite :: DCLabel -> DCLabel -> DC ()
assertWrite dataLabel sinkLabel = do
  current <- getLabel
  let bypass = dcIntegrity current == cFalse
  unless (bypass || canFlowTo dataLabel sinkLabel) $
    labelError "assertWrite" [dataLabel, sinkLabel]

channelLabelTCB :: String -> DC DCLabel
channelLabelTCB channel = do
  users <- ioTCB (SlackTCB.getUsersInChannel channel)
  let channelCnf = foldr (\/) cFalse users
  return (channelCnf %% channelCnf)

-- | Get the list of channels in the slack.
-- Returns the list labeled at `True %% True`. Does not raise your
-- current label.
getChannels :: DC (DCLabeled [String])
getChannels = do
  channels <- ioTCB SlackTCB.getChannels
  let l = True %% True
  relabelTCB l channels

-- | Read the messages from the given channel.
-- @channel@: The channel to read the messages from.
-- Let `c` be the disjunction of users currently in the channel.
-- Returns the messages labeled at `c %% c`, and raises your current
-- label to `c %% c`.
readChannelMessages :: String -> DC (DCLabeled [Message])
readChannelMessages channel = do
  msgs <- ioTCB (SlackTCB.readChannelMessages channel)
  l <- channelLabelTCB channel
  taint l -- the messages label itself says who is in the channel
  relabelTCB l msgs

-- | Read the messages from the given user inbox.
-- @user@: The user whose inbox to read.
-- Returns the messages labeled at `user %% user`.
readInbox :: String -> DC (DCLabeled [Message])
readInbox user = do
  msgs <- ioTCB (SlackTCB.readInbox user)
  let l = user %% user
  relabelTCB l msgs

-- | Get the list of users in the given channel.
-- @channel@: The channel to get the users from.
-- Let `c` be the disjunction of users currently in the channel.
-- Returns the user list labeled at `c %% c` and raises your current label to `c %% c`.
getUsersInChannel :: String -> DC (DCLabeled [String])
getUsersInChannel channel = do
  users <- ioTCB (SlackTCB.getUsersInChannel channel)
  l <- channelLabelTCB channel
  taint l -- the label of users itself says who is in the channel
  relabelTCB l users

-- | Add a user to a given channel.
-- @user@: The user to add to the channel.
-- @channel@: The channel to add the user to.
-- Rejected at runtime if your integrity has been tainted by
-- external data.
addUserToChannel :: String -> String -> DC ()
addUserToChannel user channel = do
  guardAlloc (False %% False)
  ioTCB (SlackTCB.addUserToChannel user channel)

-- | Invites a user to the Slack workspace.
-- @user@: The user to invite.
-- @user_email@: The user email where invite should be sent.
-- Rejected at runtime if your integrity has been tainted by
-- external data.
inviteUserToSlack :: String -> String -> DC ()
inviteUserToSlack user user_email = do
  guardAlloc (False %% False)
  ioTCB (SlackTCB.inviteUserToSlack user user_email)

-- | Remove a user from the Slack workspace.
-- @user@: The user to remove.
-- Rejected at runtime if your integrity has been tainted by
-- external data.
removeUserFromSlack :: String -> DC ()
removeUserFromSlack user = do
  guardAlloc (False %% False)
  ioTCB (SlackTCB.removeUserFromSlack user)

-- | Send a direct message from the bot to @recipient@ with the given @body@.
-- @recipient@: The recipient of the message.
-- @body@: The body of the message.
-- If your current label has not been tainted by data, the send is
-- unconditional. Otherwise permitted only when the body's label can
-- flow to the recipient's label.
sendDirectMessage :: String -> DCLabeled Body -> DC ()
sendDirectMessage recipient body = do
  assertWrite (labelOf body) (recipient %% recipient)
  body' <- unlabelTCB body
  ioTCB (SlackTCB.sendDirectMessage recipient body')

-- | Send a channel message from the bot to @channel@ with the given @body@.
-- @channel@: The channel to send the message to.
-- @body@: The body of the message.
-- If your current label has not been tainted by data, the send is
-- unconditional. Otherwise permitted only when the body's label can
-- flow to the channel's label.
sendChannelMessage :: String -> DCLabeled Body -> DC ()
sendChannelMessage channel body = do
  sinkLabel <- channelLabelTCB channel
  assertWrite (labelOf body) sinkLabel
  body' <- unlabelTCB body
  ioTCB (SlackTCB.sendChannelMessage channel body')
