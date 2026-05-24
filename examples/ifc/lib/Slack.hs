{-# LANGUAGE Trustworthy #-}

module Slack
  ( DC,
    DCLabeled,
    Body,
    Message (..),
    channelLabel,
    public,
    secret,
    trusted,
    untrusted,
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

import qualified Data.ByteString.Char8 as S8
import Data.Map (Map)
import qualified Data.Map as Map
import LIO (taint)
import LIO.DCLabel (CNF, DC, DCLabel, Principal, cFalse, cTrue, principalBS, (%%))
import LIO.TCB (ioTCB)
import Policy (DCLabeled, relabelTCB, rewriteLabel)
import qualified Policy
import SlackTCB (Body, Message (..))
import SlackTCB qualified

-- | Channel principal → member principals; user principal → [itself].
slackGroups :: DC (Map Principal [Principal])
slackGroups = do
  channels <- ioTCB SlackTCB.getChannels
  membership <- ioTCB (traverse fetchMembers channels)
  let p = principalBS . S8.pack
      channelEntries = [(p c, map p us) | (c, us) <- membership]
      userEntries    = [(p u, [p u])    | (_, us) <- membership, u <- us]
  pure (Map.fromList (channelEntries ++ userEntries))
  where
    fetchMembers c = do
      us <- SlackTCB.getUsersInChannel c
      pure (c, us)

-- | Rewriter that expands channel principals to member CNFs.
expandChannelLabels :: DC (DCLabel -> DCLabel)
expandChannelLabels = do
  m <- slackGroups
  pure (rewriteLabel m)

-- | The canonical label for a channel — secrecy and integrity both
-- bound to that channel's principal. Useful as a @toLabeled@ wrap
-- when the inner action only reads from this one channel.
channelLabel :: String -> DCLabel
channelLabel channel = channel %% channel

-- | Secrecy: anyone may read.
public :: CNF
public = cTrue

-- | Secrecy: nobody may read.
secret :: CNF
secret = cFalse

-- | Integrity: endorsed (data has not been tainted by external content).
trusted :: CNF
trusted = cFalse

-- | Integrity: no endorsement (data could be from anywhere).
untrusted :: CNF
untrusted = cTrue

-- | List the channels in the workspace.
getChannels :: DC (DCLabeled [String])
getChannels = do
  channels <- ioTCB SlackTCB.getChannels
  let l = True %% True
  relabelTCB l channels

-- | Read the messages from @channel@. Raises the current label to the channel's label.
readChannelMessages :: String -> DC (DCLabeled [Message])
readChannelMessages channel = do
  msgs <- ioTCB (SlackTCB.readChannelMessages channel)
  let l = channelLabel channel
  taint l
  relabelTCB l msgs

-- | Read @user@'s inbox. Does not raise current; the returned value is labeled.
readInbox :: String -> DC (DCLabeled [Message])
readInbox user = do
  msgs <- ioTCB (SlackTCB.readInbox user)
  let l = user %% user
  relabelTCB l msgs

-- | List the users in @channel@. Raises the current label to the channel's label.
getUsersInChannel :: String -> DC (DCLabeled [String])
getUsersInChannel channel = do
  users <- ioTCB (SlackTCB.getUsersInChannel channel)
  let l = channelLabel channel
  taint l
  relabelTCB l users

-- | Add @user@ to @channel@. Requires current to be trusted.
addUserToChannel :: String -> String -> DC ()
addUserToChannel user channel = do
  expand <- expandChannelLabels
  Policy.guard expand (False %% False)
  ioTCB (SlackTCB.addUserToChannel user channel)

-- | Invite @user@ at @user_email@ to the workspace. Requires current to be trusted.
inviteUserToSlack :: String -> String -> DC ()
inviteUserToSlack user user_email = do
  expand <- expandChannelLabels
  Policy.guard expand (False %% False)
  ioTCB (SlackTCB.inviteUserToSlack user user_email)

-- | Remove @user@ from the workspace. Requires current to be trusted.
removeUserFromSlack :: String -> DC ()
removeUserFromSlack user = do
  expand <- expandChannelLabels
  Policy.guard expand (False %% False)
  ioTCB (SlackTCB.removeUserFromSlack user)

-- | The DM-sink label for a recipient: secret to that user, attested by that user.
userLabel :: String -> DC DCLabel
userLabel user = pure (user %% user)

-- | Send a DM with @labeledBody@ to @labeledRecipient@.
sendDirectMessage :: DCLabeled String -> DCLabeled Body -> DC ()
sendDirectMessage labeledRecipient labeledBody = do
  expand <- expandChannelLabels
  Policy.write expand userLabel SlackTCB.sendDirectMessage labeledRecipient labeledBody

-- | Post @labeledBody@ to @labeledChannel@.
sendChannelMessage :: DCLabeled String -> DCLabeled Body -> DC ()
sendChannelMessage labeledChannel labeledBody = do
  expand <- expandChannelLabels
  Policy.write expand (pure . channelLabel) SlackTCB.sendChannelMessage labeledChannel labeledBody
