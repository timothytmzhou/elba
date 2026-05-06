{-# LANGUAGE Trustworthy #-}

module Web
  ( Url
  , getWebpage
  , postWebpage
  ) where

import LIO (getLabel)
import LIO.DCLabel (CNF, dcPublic, toCNF)
import LIO.Labeled (labelOf, labelP, unlabelP)
import LIO.TCB (Priv (PrivTCB), ioTCB)
import Slack (DC, DCLabeled, assertWrite)
import WebTCB (Url)
import WebTCB qualified

omniPriv :: Priv CNF
omniPriv = PrivTCB (toCNF False)

-- | Returns the content of the webpage at a given URL.
-- @url@: The URL of the webpage.
-- If your current label has not been tainted by data, the call is
-- unconditional. Otherwise permitted only when your current secrecy
-- is public. Returns the content labeled at `True %% True`. Does
-- not raise your current label.
getWebpage :: Url -> DC (DCLabeled String)
getWebpage url = do
  current <- getLabel
  assertWrite current dcPublic
  content <- ioTCB (WebTCB.getWebpage url)
  labelP omniPriv dcPublic content

-- | Posts a webpage at a given URL with the given content.
-- @url@: The URL of the webpage.
-- @content@: The content of the webpage.
-- If your current label has not been tainted by data, the post is
-- unconditional. Otherwise permitted only when the content's label
-- can flow to `True %% True`.
postWebpage :: Url -> DCLabeled String -> DC ()
postWebpage url content = do
  assertWrite (labelOf content) dcPublic
  content' <- unlabelP omniPriv content
  ioTCB (WebTCB.postWebpage url content')
