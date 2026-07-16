{-# LANGUAGE Unsafe #-}

module SlackLabelTCB
  ( PseudoPrincipal (..),
    ChannelID (..),
    UserID (..),
    lookupCNF,
    membership,
    cnfFor,
    labelFor,
  )
where

import Data.List (nub)
import Data.Map (Map, (!))
import Data.Map qualified as Map
import LIO.DCLabel (CNF, DC, DCLabel, cFalse, cTrue, toCNF, (%%), (\/))
import LIO.TCB (ioTCB)
import SlackTCB qualified

-- These are exported as opaque in Slack Principal.
-- Possession of IDs themselves should imply current secrecy is tainted.
newtype ChannelID = ChannelID String deriving (Eq, Ord)

newtype UserID = UserID String deriving (Eq, Ord)

data PseudoPrincipal
  = ForUser UserID
  | ForChannel ChannelID
  | AnyUser
  | Public

-- | The CNF of principals a PseudoPrincipal denotes.
lookupCNF :: Map String [String] -> PseudoPrincipal -> CNF
lookupCNF groups principal = case principal of
  ForUser (UserID u) -> toCNF u
  ForChannel (ChannelID c) -> anyOf (groups ! c)
  AnyUser -> anyOf (allUsers groups)
  Public -> cTrue
  where
    anyOf = foldr (\/) cFalse
    allUsers g = nub (concat (Map.elems g))

-- | Internal helper to map channel names to their members.
membership :: DC (Map String [String])
membership = do
  channels <- ioTCB SlackTCB.getChannels
  memberships <- ioTCB (mapM withMembers channels)
  pure (Map.fromList memberships)
  where
    withMembers c = do
      us <- SlackTCB.getUsersInChannel c
      pure (c, us)

-- | Resolve principals to CNFs against the live workspace.
cnfFor :: DC (PseudoPrincipal -> CNF)
cnfFor = lookupCNF <$> membership

-- | The label for a principal in the live workspace.
labelFor :: PseudoPrincipal -> DC DCLabel
labelFor principal = do
  cnf <- cnfFor
  let c = cnf principal
  pure (c %% c)
