{-# LANGUAGE Unsafe #-}

module Policy
  ( DCLabeled
  , unlabelTCB
  , relabelTCB
  , expandPrincipals
  , rewriteLabel
  , guard
  , assertWrite
  , write
  ) where

import Control.Monad (unless)
import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified LIO
import LIO (getClearance, getLabel)
import LIO.DCLabel (CNF, DC, DCLabel, Disjunction, Principal,
                    cFalse, cToSet, cTrue, dToSet, dFromList,
                    dcIntegrity, dcSecrecy, toCNF, (%%), (/\), (\/))
import LIO.Error (labelError)
import LIO.Labeled (Labeled, labelOf, labelP, unlabelP)
import LIO.TCB (Priv (PrivTCB), ioTCB)

type DCLabeled a = Labeled DCLabel a

unlabelTCB :: DCLabeled a -> DC a
unlabelTCB = unlabelP (PrivTCB (toCNF False))

relabelTCB :: DCLabel -> a -> DC (DCLabeled a)
relabelTCB = labelP (PrivTCB (toCNF False))

-- | From Hails/PolicyModule/Groups.hs, with one tweak: missing keys
-- default to identity instead of @Map.!@ crashing.
expandPrincipals :: Map Principal [Principal] -> CNF -> CNF
expandPrincipals pMap origPrincipals =
  let cFoldF :: Disjunction -> CNF -> CNF
      cFoldF disj accm =
        (Set.foldr expandOne cFalse $ dToSet disj) /\ accm
      expandOne :: Principal -> CNF -> CNF
      expandOne princ accm =
        (dFromList $ Map.findWithDefault [princ] princ pMap) \/ accm
  in Set.foldr cFoldF cTrue $ cToSet origPrincipals

-- | Rewrite both halves of a label with one expansion map.
rewriteLabel :: Map Principal [Principal] -> DCLabel -> DCLabel
rewriteLabel pMap lab =
  expandPrincipals pMap (dcSecrecy lab) %% expandPrincipals pMap (dcIntegrity lab)

-- | The single source of truth for label flow in this policy module:
-- both labels are expanded by @rewrite@ before LIO's @canFlowTo@.
flowsTo :: (DCLabel -> DCLabel) -> DCLabel -> DCLabel -> Bool
flowsTo rewrite from to = LIO.canFlowTo (rewrite from) (rewrite to)

-- | Privileged variant of @flowsTo@: same routing rule.
flowsToP :: (DCLabel -> DCLabel) -> Priv CNF -> DCLabel -> DCLabel -> Bool
flowsToP rewrite priv from to = LIO.canFlowToP priv (rewrite from) (rewrite to)

-- | guardAlloc, inlined. Pass @id@ for plain guardAlloc behavior.
guard :: (DCLabel -> DCLabel) -> DCLabel -> DC ()
guard rewrite newl = do
  l <- getLabel
  c <- getClearance
  unless (flowsTo rewrite l newl && flowsTo rewrite newl c) $
    labelError "guard" [newl]

-- | Privileged variant of @guard@.
guardP :: (DCLabel -> DCLabel) -> Priv CNF -> DCLabel -> DC ()
guardP rewrite priv newl = do
  l <- getLabel
  c <- getClearance
  unless (flowsToP rewrite priv l newl && flowsToP rewrite priv newl c) $
    labelError "guardP" [newl]

-- | Check that a write of data labeled @dataLabel@ into a sink with policy
-- label @sinkLabel@ is permitted, using the integrity of @sinkPointerLabel@
-- (the label of the labeled handle pointing at the sink) as the privilege.
assertWrite :: (DCLabel -> DCLabel) -> DCLabel -> DCLabel -> DCLabel -> DC ()
assertWrite rewrite sinkPointerLabel dataLabel sinkLabel = do
  let priv = PrivTCB (dcIntegrity (rewrite sinkPointerLabel)) :: Priv CNF
  guardP rewrite priv sinkLabel
  unless (flowsToP rewrite priv dataLabel sinkLabel) $
    labelError "assertWrite" [dataLabel, sinkPointerLabel, sinkLabel]

-- | Perform an IO side-effect against a labeled sink and labeled data,
-- gated by @assertWrite@. The destination's policy label is computed from
-- the dereferenced sink via @labelFor@. @rewrite@ is threaded into the
-- @assertWrite@ call. Args ordered so callers can write point-free.
write
  :: (DCLabel -> DCLabel)
  -> (a -> DC DCLabel)
  -> (a -> b -> IO c)
  -> DCLabeled a
  -> DCLabeled b
  -> DC c
write rewrite labelFor io labeledSink labeledData = do
  sinkValue <- unlabelTCB labeledSink
  sinkLabel <- labelFor sinkValue
  assertWrite rewrite (labelOf labeledSink) (labelOf labeledData) sinkLabel
  dataValue <- unlabelTCB labeledData
  ioTCB (io sinkValue dataValue)
