{-# LANGUAGE Trustworthy #-}

-- Agent facing IFC surface. DC and DCLabeled are exported as opaque types,
-- so interpreted code can hold and sequence them but cannot unwrap them or
-- reach the underlying LIO monad.
module IFC
  ( DC
  , DCLabeled
  , unlabel
  , toLabeled
  ) where

import IfcTCB
  ( DC
  , DCLabeled
  , Labeled (LabeledTCB)
  , LIOState (lioLabel)
  , cTrue
  , dcIntegrity
  , getClearance
  , getStateTCB
  , glb
  , putStateTCB
  , setClearance
  , taint
  , (%%)
  )

-- | Run a computation without leaking its taint to the caller. The result is
-- returned labeled with everything the computation observed.
toLabeled :: DC a -> DC (DCLabeled a)
toLabeled action = do
  s0 <- getStateTCB
  a <- action
  s1 <- getStateTCB
  putStateTCB s0
  pure (LabeledTCB (lioLabel s1) a)

-- | Unlabel a value, tainting the current computation with its label.
unlabel :: DCLabeled a -> DC a
unlabel (LabeledTCB l v) = do
  c <- getClearance
  setClearance (c `glb` (dcIntegrity l %% cTrue))
  taint l
  pure v
