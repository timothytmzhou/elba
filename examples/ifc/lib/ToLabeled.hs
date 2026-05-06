{-# LANGUAGE Trustworthy #-}

-- A re-implementation of the classic `toLabeled` primitive that LIO
-- removed due to internal-timing-channel concerns. Hails (and this
-- codebase) accepts that channel and brings `toLabeled` back, since
-- being able to wrap a sub-computation as a `Labeled` value without
-- monotonically raising the parent's current label is too useful to
-- give up.
--
-- Adapted from the original LIO.TCB implementation.

module ToLabeled
  ( toLabeled
  , toLabeledP
  ) where

import Control.Monad (unless)
import LIO (Label, LIO, canFlowToP, guardAllocP, noPrivs)
import LIO.Error (labelErrorP)
import LIO.Label (Priv, PrivDesc)
import LIO.Labeled (Labeled)
import LIO.TCB
  ( LIOState (lioClearance, lioLabel)
  , Labeled (LabeledTCB)
  , getLIOStateTCB
  , putLIOStateTCB
  )

-- | Run @action@ and capture its result as a @Labeled l a@, without
-- raising the parent's current label or clearance. The supplied label
-- @l@ must be reachable from the current state, and the action's
-- final label must flow to @l@.
toLabeled :: Label l => l -> LIO l a -> LIO l (Labeled l a)
toLabeled = toLabeledP noPrivs

-- | Privileged variant of 'toLabeled'.
toLabeledP :: PrivDesc l p => Priv p -> l -> LIO l a -> LIO l (Labeled l a)
toLabeledP p l action = do
  guardAllocP p l
  s0 <- getLIOStateTCB
  a <- action
  s1 <- getLIOStateTCB
  putLIOStateTCB s1 {lioLabel = lioLabel s0, lioClearance = lioClearance s0}
  unless (canFlowToP p (lioLabel s1) l) $
    labelErrorP "toLabeledP" p [l]
  return (LabeledTCB l a)
