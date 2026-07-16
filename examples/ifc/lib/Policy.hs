{-# LANGUAGE Unsafe #-}

module Policy
  ( DCLabeled
  , unlabelTCB
  , assertWrite
  , assertIntegrity
  , write
  , public
  , secret
  , trusted
  , untrusted
  ) where

import Control.Monad (unless)
import IfcTCB
  ( CNF
  , DC
  , DCLabel
  , DCLabeled
  , cFalse
  , cTrue
  , dcIO
  , dcIntegrity
  , getLabel
  , labelError
  , speaksFor
  , unlabelTCB
  , (%%)
  )

-- | Secrecy anyone may read.
public :: CNF
public = cTrue

-- | Secrecy nobody may read.
secret :: CNF
secret = cFalse

-- | Integrity endorsed.
trusted :: CNF
trusted = cFalse

-- | Integrity unendorsed.
untrusted :: CNF
untrusted = cTrue

-- | A write requires current integrity to speak for the destination.
assertWrite :: DCLabel -> DC ()
assertWrite destLabel = do
  cur <- getLabel
  unless (dcIntegrity cur `speaksFor` dcIntegrity destLabel) $
    labelError "assertWrite" [destLabel]

-- | Require current integrity to speak for @needed@.
assertIntegrity :: CNF -> DC ()
assertIntegrity needed = do
  cur <- getLabel
  unless (dcIntegrity cur `speaksFor` needed) $
    labelError "assertIntegrity" [cTrue %% needed]

-- | Write labeled data gated by assertWrite.
write :: (b -> IO c) -> DCLabel -> DCLabeled b -> DC c
write io destLabel labeledData = do
  assertWrite destLabel
  dataValue <- unlabelTCB labeledData
  dcIO (io dataValue)
