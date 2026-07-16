{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE Unsafe #-}

-- Implementation of the IFC monad. DC wraps LIO so the agent facing type is
-- opaque. The primitives below keep the same names as their LIO originals, so
-- policy modules only swap this import for their LIO imports. The constructor
-- and these primitives are never exported to the interpreted agent.
module IFCInternal
  ( DC (..)
  , evalDC
  , initialState
  , LIOState (..)
  , getLabel
  , getClearance
  , setClearance
  , taint
  , ioTCB
  , labelError
  , unlabelP
  , getLIOStateTCB
  , putLIOStateTCB
  , CNF
  , DCLabel
  , DCLabeled
  , Labeled (LabeledTCB)
  , Priv (PrivTCB)
  , cFalse
  , cTrue
  , dcPublic
  , dcIntegrity
  , speaksFor
  , toCNF
  , glb
  , (%%)
  , (\/)
  ) where

import LIO (LIO, LIOState (..), evalLIO, glb, speaksFor)
import LIO qualified
import LIO.DCLabel (CNF, DCLabel, DCLabeled, cFalse, cTrue, dcIntegrity, dcPublic, toCNF, (%%), (\/))
import LIO.Error qualified
import LIO.Labeled qualified
import LIO.TCB (Labeled (LabeledTCB), Priv (PrivTCB))
import LIO.TCB qualified

newtype DC a = DC (LIO DCLabel a)
  deriving (Functor, Applicative, Monad)

evalDC :: DC a -> LIOState DCLabel -> IO a
evalDC (DC m) = evalLIO m

initialState :: LIOState DCLabel
initialState = LIOState {lioLabel = cTrue %% cFalse, lioClearance = cFalse %% cTrue}

getLabel :: DC DCLabel
getLabel = DC LIO.getLabel

getClearance :: DC DCLabel
getClearance = DC LIO.getClearance

setClearance :: DCLabel -> DC ()
setClearance = DC . LIO.setClearance

taint :: DCLabel -> DC ()
taint = DC . LIO.taint

ioTCB :: IO a -> DC a
ioTCB = DC . LIO.TCB.ioTCB

labelError :: String -> [DCLabel] -> DC a
labelError msg = DC . LIO.Error.labelError msg

unlabelP :: Priv CNF -> DCLabeled a -> DC a
unlabelP p = DC . LIO.Labeled.unlabelP p

getLIOStateTCB :: DC (LIOState DCLabel)
getLIOStateTCB = DC LIO.TCB.getLIOStateTCB

putLIOStateTCB :: LIOState DCLabel -> DC ()
putLIOStateTCB = DC . LIO.TCB.putLIOStateTCB
