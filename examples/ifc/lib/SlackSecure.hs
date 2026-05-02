{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE Trustworthy #-}

-- Secure (LIO + DCLabel) wrapper over the insecure Slack tools.
--
-- Policy idea (per the project plan): the agent acts on behalf of a User
-- principal and is given that principal's privilege only when the current
-- floating label has not been raised by reading untrusted data.
--
-- Read-tier tools return `Labeled DCLabel x` so the read does not raise
-- the outer current label. The agent can `unlabel` (which raises the
-- current label and revokes the privilege) or use `lFork`/`lWait` to
-- scope the taint inside a sub-computation.
--
-- Action-tier tools take `Labeled DCLabel Body` for parts that may carry
-- untrusted source taint (e.g. message body) and raw `String` for parts
-- that must remain clean. A raw arg implicitly signals "the agent
-- already raised the current label to derive me", which we use to gate
-- the privilege at tool entry: if the current label is no longer ⊑
-- trustedBound, we substitute the empty privilege (`mempty`).
--
-- We define `Body` and `Message` here (rather than re-exporting from
-- Slack) so that record-field selectors `sender`, `recipient`, `body`
-- belong to this module — otherwise hint imports both Slack and
-- SlackSecure for the agent and chokes on ambiguous occurrences.

module SlackSecure
  ( -- * Message types (defined here, not re-exported from Slack)
    Body
  , Message (..)
    -- * LIO API the agent needs.
    -- `LIO` and `DCLabel` are re-exported so the agent's type ascription
    -- (`Slack -> Web -> DC String`) typechecks: hint expands `DC` to
    -- `LIO DCLabel`, which means both names must be in scope.
  , LIO
  , DC
  , DCLabel
  , Labeled
  , LabeledResult
  , label
  , unlabel
  , dcPublic
  , lFork
  , lWait
    -- * Slack handle
  , Slack
  , mkSlack
    -- * TCB-only: minting the user privilege (called once in main)
  , mintUserPriv
    -- * Read tier
  , getChannels
  , getUsersInChannel
  , readChannelMessages
  , readInbox
    -- * Action tier
  , sendDirectMessage
  , sendChannelMessage
  , addUserToChannel
  , inviteUserToSlack
  , removeUserFromSlack
  ) where

import Bridge (Bridge)
import LIO (LIO, canFlowTo, getLabel)
import LIO.Concurrent (LabeledResult, lFork, lWait)
import LIO.Core (guardAllocP)
import LIO.DCLabel (DC, DCLabel, DCPriv, dcPublic, principal, toCNF, (%%))
import LIO.Labeled (Labeled, label, unlabel, unlabelP)
import LIO.TCB (Priv (PrivTCB), ioTCB)
import Slack qualified as Insecure

type Body = String

data Message = Message
  { sender :: String
  , recipient :: String
  , body :: Body
  }
  deriving (Show)

fromInsecureMsg :: Insecure.Message -> Message
fromInsecureMsg m =
  Message
    { sender = Insecure.sender m
    , recipient = Insecure.recipient m
    , body = Insecure.body m
    }

-- | Mint a privilege for the named principal. TCB-only — called once
-- at program startup before the agent runs.
mintUserPriv :: String -> DCPriv
mintUserPriv name = PrivTCB (toCNF (principal name))

-- | Per-source label for data the agent reads from external systems.
externalLabel :: DCLabel
externalLabel = principal "external" %% True

-- | Upper bound on the current label for which we grant the user-priv
-- at tool entry. Strict reading: only a fully clean current label
-- yields the priv.
trustedBound :: DCLabel
trustedBound = dcPublic

data Slack = Slack
  { insecure :: Insecure.Slack
  , userPriv :: DCPriv
  }

mkSlack :: Bridge -> DCPriv -> Slack
mkSlack br priv = Slack (Insecure.mkSlack br) priv

gatedPriv :: Slack -> DC DCPriv
gatedPriv s = do
  cur <- getLabel
  pure $ if cur `canFlowTo` trustedBound then userPriv s else mempty

-- ---- Read tier ----------------------------------------------------------

getChannels :: Slack -> DC (Labeled DCLabel [String])
getChannels s = do
  xs <- ioTCB (Insecure.getChannels (insecure s))
  label externalLabel xs

getUsersInChannel :: Slack -> String -> DC (Labeled DCLabel [String])
getUsersInChannel s c = do
  xs <- ioTCB (Insecure.getUsersInChannel (insecure s) c)
  label externalLabel xs

readChannelMessages :: Slack -> String -> DC (Labeled DCLabel [Message])
readChannelMessages s c = do
  xs <- ioTCB (Insecure.readChannelMessages (insecure s) c)
  label externalLabel (map fromInsecureMsg xs)

readInbox :: Slack -> String -> DC (Labeled DCLabel [Message])
readInbox s u = do
  xs <- ioTCB (Insecure.readInbox (insecure s) u)
  label externalLabel (map fromInsecureMsg xs)

-- ---- Action tier --------------------------------------------------------

sendDirectMessage :: Slack -> String -> Labeled DCLabel Body -> DC ()
sendDirectMessage s recipient lbody = do
  priv <- gatedPriv s
  body <- unlabelP priv lbody
  guardAllocP priv dcPublic
  ioTCB (Insecure.sendDirectMessage (insecure s) recipient body)

sendChannelMessage :: Slack -> String -> Labeled DCLabel Body -> DC ()
sendChannelMessage s c lbody = do
  priv <- gatedPriv s
  body <- unlabelP priv lbody
  guardAllocP priv dcPublic
  ioTCB (Insecure.sendChannelMessage (insecure s) c body)

addUserToChannel :: Slack -> String -> String -> DC ()
addUserToChannel s u c = do
  priv <- gatedPriv s
  guardAllocP priv dcPublic
  ioTCB (Insecure.addUserToChannel (insecure s) u c)

inviteUserToSlack :: Slack -> String -> String -> DC ()
inviteUserToSlack s u email = do
  priv <- gatedPriv s
  guardAllocP priv dcPublic
  ioTCB (Insecure.inviteUserToSlack (insecure s) u email)

removeUserFromSlack :: Slack -> String -> DC ()
removeUserFromSlack s u = do
  priv <- gatedPriv s
  guardAllocP priv dcPublic
  ioTCB (Insecure.removeUserFromSlack (insecure s) u)
