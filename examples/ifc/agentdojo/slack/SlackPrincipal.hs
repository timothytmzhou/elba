{-# LANGUAGE Trustworthy #-}

module SlackPrincipal
  ( ChannelID,
    UserID,
    channelName,
    userName,
    channelID,
    userID,
  )
where

import Data.List (nub)
import Data.Map qualified as Map
import LIO (taint)
import LIO.DCLabel (DC, DCLabeled, cFalse, (%%))
import LIO.TCB (Labeled (LabeledTCB))
import SlackLabelTCB
  ( ChannelID (..),
    PseudoPrincipal (..),
    UserID (..),
    cnfFor,
    labelFor,
    lookupCNF,
    membership,
  )

-- | Get a channel name labeled with secrecy channel and with integrity channel.
channelName :: ChannelID -> DC (DCLabeled String)
channelName cid@(ChannelID c) = do
  l <- labelFor (ForChannel cid)
  pure (LabeledTCB l c)

-- | Get a user name labeled with secrecy AnyUser and with integrity user.
userName :: UserID -> DC (DCLabeled String)
userName uid@(UserID u) = do
  cnf <- cnfFor
  pure (LabeledTCB (cnf AnyUser %% cnf (ForUser uid)) u)

-- | Get a channelID from a name.
-- Taints current secrecy with the channel label if the name exists.
-- WARNING: if the channel does not exist, taints with maximum secrecy,
-- as only the user should know what channels they cannot see.
channelID :: String -> DC (Maybe ChannelID)
channelID name = do
  groups <- membership
  if Map.member name groups
    then do
      -- Safe only because labelOf is banned; labelOf on the result would leak
      -- whether the channel exists.
      taint (lookupCNF groups (ForChannel (ChannelID name)) %% cFalse)
      pure (Just (ChannelID name))
    else do
      taint (cFalse %% cFalse)
      pure Nothing

-- | Get a userID from a name.
-- Secrecy we taint with allows any Slack user to read.
userID :: String -> DC (Maybe UserID)
userID name = do
  groups <- membership
  let known = name `elem` nub (concat (Map.elems groups))
  taint (lookupCNF groups AnyUser %% cFalse)
  pure (if known then Just (UserID name) else Nothing)
