{-# LANGUAGE Trustworthy #-}

module IFC
  ( DC,
    LIOState (..),
    evalLIO,
    initialState,
    toLabeled,
    unlabel,
  )
where

import LIO (LIO, LIOState (..), Label, evalLIO, getClearance, glb, setClearance, taint)
import LIO.DCLabel (DC, DCLabel, cFalse, cTrue, dcIntegrity, (%%))
import LIO.Labeled (Labeled)
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

-- | Runs a LIO computation without tainting the current label.
toLabeled :: (Label l) => LIO l a -> LIO l (Labeled l a)
toLabeled action = do
  s0 <- getLIOStateTCB
  a <- action
  s1 <- getLIOStateTCB
  putLIOStateTCB s1 {lioLabel = lioLabel s0, lioClearance = lioClearance s0}
  return (LabeledTCB (lioLabel s1) a)

-- | Unlabels a labeled value, tainting the current label and lowering clearance.
unlabel :: Labeled DCLabel a -> DC a
unlabel (LabeledTCB l v) = do
  c <- getClearance
  setClearance (c `glb` (dcIntegrity l %% cTrue))
  taint l
  return v
