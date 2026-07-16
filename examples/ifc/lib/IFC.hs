{-# LANGUAGE Trustworthy #-}

-- The IFC surface. DC is lio's type synonym and opacity is lio's own model.
-- The LIOTCB constructor and the TCB primitives live in the Unsafe LIO.TCB
-- module, so safely interpreted code can sequence DC computations but cannot
-- unwrap them or perform IO. The agent env imports only unlabel and
-- toLabeled from here, by name. runDC is the host entry point and never
-- reaches the interpreter. Tool implementations use Policy and lio directly.
module IFC
  ( DC,
    DCLabeled,
    toLabeled,
    unlabel,
    runDC,
  )
where

import LIO (evalLIO, getClearance, glb, setClearance, taint)
import LIO.DCLabel (DC, DCLabeled, cFalse, cTrue, dcIntegrity, (%%))
import LIO.TCB
  ( LIOState (..),
    Labeled (LabeledTCB),
    getLIOStateTCB,
    putLIOStateTCB,
  )

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

-- | Runs a DC computation from a public trusted starting label.
runDC :: DC a -> IO a
runDC m =
  evalLIO m LIOState {lioLabel = cTrue %% cFalse, lioClearance = cFalse %% cTrue}
