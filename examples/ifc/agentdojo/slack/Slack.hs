{-# LANGUAGE Trustworthy #-}

module Slack
  ( module SlackPrincipal,
    DC,
    DCLabeled,
    Body,
    LabeledMessage (..),
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

import IFCInternal (DC, DCLabeled, Labeled (LabeledTCB), cFalse, ioTCB, dcIntegrity, getLabel, speaksFor, (%%))
import Policy qualified
import SlackLabelTCB qualified as SL
import SlackPrincipal
import SlackTCB (Body)
import SlackTCB qualified

data LabeledMessage = LabeledMessage
  { sender :: UserID,
    recipient :: UserID,
    body :: DCLabeled Body
  }

-- | List the channels the current integrity is cleared to view.
-- Note: strictly speaking, the length of this list should itself be secret,
-- but currently we do not consider this.
getChannels :: DC [ChannelID]
getChannels = do
  cnf <- SL.cnfFor
  names <- ioTCB SlackTCB.getChannels
  current <- getLabel
  let authority = dcIntegrity current
  let viewable name = authority `speaksFor` cnf (SL.ForChannel (SL.ChannelID name))
  pure [SL.ChannelID name | name <- names, viewable name]

-- | Read the messages from @channel@.
readChannelMessages :: ChannelID -> DC [LabeledMessage]
readChannelMessages channel@(SL.ChannelID name) = do
  cnf <- SL.cnfFor
  let channelSecrecy = cnf (SL.ForChannel channel)
  let labelMessage m =
        let sender = SL.UserID (SlackTCB.sender m)
            recipient = SL.UserID (SlackTCB.recipient m)
            messageLabel = channelSecrecy %% cnf (SL.ForUser sender)
            body = LabeledTCB messageLabel (SlackTCB.body m)
         in LabeledMessage {sender, recipient, body}
  messages <- ioTCB (SlackTCB.readChannelMessages name)
  pure (map labelMessage messages)

-- | Read @user@'s inbox.
readInbox :: UserID -> DC (DCLabeled [Body])
readInbox user@(SL.UserID name) = do
  l <- SL.labelFor (SL.ForUser user)
  messages <- ioTCB (SlackTCB.readInbox name)
  pure (LabeledTCB l (map SlackTCB.body messages))

-- | List the users in @channel@.
getUsersInChannel :: ChannelID -> DC [UserID]
getUsersInChannel (SL.ChannelID name) = do
  users <- ioTCB (SlackTCB.getUsersInChannel name)
  pure (map SL.UserID users)

-- | Add @user@ to @channel@.
addUserToChannel :: UserID -> ChannelID -> DC ()
addUserToChannel (SL.UserID user) channel@(SL.ChannelID name) = do
  cnf <- SL.cnfFor
  Policy.assertIntegrity (cnf (SL.ForChannel channel))
  ioTCB (SlackTCB.addUserToChannel user name)

-- | Invite @user@ at @user_email@.
inviteUserToSlack :: String -> String -> DC ()
inviteUserToSlack user email = do
  cnf <- SL.cnfFor
  Policy.assertIntegrity (cnf SL.AnyUser)
  ioTCB (SlackTCB.inviteUserToSlack user email)

-- | Remove @user@.
removeUserFromSlack :: UserID -> DC ()
removeUserFromSlack (SL.UserID user) = do
  Policy.assertIntegrity cFalse
  ioTCB (SlackTCB.removeUserFromSlack user)

-- | Send a DM with @labeledBody@ to @recipient@.
sendDirectMessage :: UserID -> DCLabeled Body -> DC ()
sendDirectMessage recipient@(SL.UserID name) labeledBody = do
  l <- SL.labelFor (SL.ForUser recipient)
  Policy.write (SlackTCB.sendDirectMessage name) l labeledBody

-- | Post @labeledBody@ to @channel@.
sendChannelMessage :: ChannelID -> DCLabeled Body -> DC ()
sendChannelMessage channel@(SL.ChannelID name) labeledBody = do
  l <- SL.labelFor (SL.ForChannel channel)
  Policy.write (SlackTCB.sendChannelMessage name) l labeledBody
