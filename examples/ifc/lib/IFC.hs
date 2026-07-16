{-# LANGUAGE Trustworthy #-}

-- Agent facing IFC surface. DC and DCLabeled are exported as opaque types,
-- so interpreted code can hold and sequence them but cannot unwrap them or
-- reach the underlying LIO monad.
module IFC
  ( DC,
    DCLabeled,
    toLabeled,
    unlabel,
  )
where

import IFCInternal
  ( DC,
    DCLabeled,
    LIOState (lioClearance, lioLabel),
    Labeled (LabeledTCB),
    cTrue,
    dcIntegrity,
    getClearance,
    getLIOStateTCB,
    glb,
    putLIOStateTCB,
    setClearance,
    taint,
    (%%),
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
