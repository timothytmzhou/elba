{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- Secure (LIO + DCLabel) wrapper over the insecure Web tools.
-- See SlackSecure for the policy commentary.

module WebSecure
  ( Url
  , Web
  , mkWeb
  , getWebpage
  , postWebpage
  ) where

import Bridge (Bridge)
import LIO (canFlowTo, getLabel)
import LIO.Core (guardAllocP)
import LIO.DCLabel (DC, DCLabel, DCPriv, dcPublic, principal, (%%))
import LIO.Labeled (Labeled, label, unlabelP)
import LIO.TCB (ioTCB)
import Web (Url)
import Web qualified as Insecure

externalLabel :: DCLabel
externalLabel = principal "external" %% True

trustedBound :: DCLabel
trustedBound = dcPublic

data Web = Web
  { insecure :: Insecure.Web
  , userPriv :: DCPriv
  }

mkWeb :: Bridge -> DCPriv -> Web
mkWeb br priv = Web (Insecure.mkWeb br) priv

gatedPriv :: Web -> DC DCPriv
gatedPriv w = do
  cur <- getLabel
  pure $ if cur `canFlowTo` trustedBound then userPriv w else mempty

-- | Webpage fetch: returns content boxed at externalLabel without
-- raising the outer current label.
getWebpage :: Web -> Url -> DC (Labeled DCLabel String)
getWebpage w u = do
  xs <- ioTCB (Insecure.getWebpage (insecure w) u)
  label externalLabel xs

-- | Posting to a webpage is action-tier: priv-gated, content
-- declassified under priv, then delegated to the insecure IO.
postWebpage :: Web -> Url -> Labeled DCLabel String -> DC ()
postWebpage w u lcontent = do
  priv <- gatedPriv w
  content <- unlabelP priv lcontent
  guardAllocP priv dcPublic
  ioTCB (Insecure.postWebpage (insecure w) u content)
