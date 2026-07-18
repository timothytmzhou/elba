{-# LANGUAGE Trustworthy #-}

module IFC
  ( DC,
    DCLabeled,
    runDC,
    toLabeled,
    unlabel,
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

-- | Runs a DC computation from a public trusted starting label.
runDC :: DC a -> IO a
runDC m =
  evalLIO m LIOState {lioLabel = cTrue %% cFalse, lioClearance = cFalse %% cTrue}

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
