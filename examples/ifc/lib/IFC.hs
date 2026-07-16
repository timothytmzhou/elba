{-# LANGUAGE Trustworthy #-}

-- Agent facing IFC surface. DC is lio's own type and opacity is lio's own
-- model. The LIOTCB constructor and the TCB primitives live in the Unsafe
-- LIO.TCB module, so safely interpreted code can name these types and
-- sequence DC computations but cannot unwrap them or perform IO. The LIO
-- and DCLabel exports let the interpreter resolve the expanded synonym in
-- the agent's required type.
module IFC
  ( DC,
    DCLabel,
    DCLabeled,
    LIO,
    LIOState (..),
    evalLIO,
    initialState,
    toLabeled,
    unlabel,
  )
where

import LIO (LIO, LIOState (..), evalLIO, getClearance, glb, setClearance, taint)
import LIO.DCLabel (DC, DCLabel, DCLabeled, cFalse, cTrue, dcIntegrity, (%%))
import LIO.TCB
  ( LIOState (lioClearance, lioLabel),
    Labeled (LabeledTCB),
    getLIOStateTCB,
    putLIOStateTCB,
  )

initialState :: LIOState DCLabel
initialState =
  LIOState
    { lioLabel = cTrue %% cFalse,
      lioClearance = cFalse %% cTrue
    }

-- | Runs a computation without tainting the current label.
toLabeled :: DC a -> DC (DCLabeled a)
toLabeled action = do
  s0 <- getLIOStateTCB
  a <- action
  s1 <- getLIOStateTCB
  putLIOStateTCB s1 {lioLabel = lioLabel s0, lioClearance = lioClearance s0}
  return (LabeledTCB (lioLabel s1) a)

-- | Unlabels a labeled value, tainting the current label and lowering clearance.
unlabel :: DCLabeled a -> DC a
unlabel (LabeledTCB l v) = do
  c <- getClearance
  setClearance (c `glb` (dcIntegrity l %% cTrue))
  taint l
  return v
