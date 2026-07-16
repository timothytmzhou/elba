{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE Unsafe #-}

-- Trusted core of the IFC monad. DC wraps LIO so that the agent facing type
-- is opaque. The constructor and the privileged primitives below are visible
-- only to policy code, never to the interpreted agent.
module IfcTCB
  ( DC (..)
  , runDC
  , evalDC
  , initialState
  , LIOState (..)
    -- privileged actions lifted into DC
  , getLabel
  , getClearance
  , setClearance
  , taint
  , dcIO
  , labelError
  , unlabelTCB
  , getStateTCB
  , putStateTCB
    -- pure label algebra re-exported for policy code
  , CNF
  , DCLabel
  , DCLabeled
  , Labeled (LabeledTCB)
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

runDC :: DC a -> LIO DCLabel a
runDC (DC m) = m

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

dcIO :: IO a -> DC a
dcIO = DC . LIO.TCB.ioTCB

labelError :: String -> [DCLabel] -> DC a
labelError msg = DC . LIO.Error.labelError msg

unlabelTCB :: DCLabeled a -> DC a
unlabelTCB = DC . LIO.Labeled.unlabelP (PrivTCB (toCNF False))

getStateTCB :: DC (LIOState DCLabel)
getStateTCB = DC LIO.TCB.getLIOStateTCB

putStateTCB :: LIOState DCLabel -> DC ()
putStateTCB = DC . LIO.TCB.putLIOStateTCB
