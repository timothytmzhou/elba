{-# LANGUAGE Trustworthy #-}

module Web
  ( Url,
    getWebpage,
    postWebpage,
  )
where

import LIO.DCLabel (DC, dcPublic)
import LIO.TCB (Labeled (LabeledTCB), ioTCB)
import Policy (DCLabeled, assertWrite, write)
import WebTCB (Url)
import WebTCB qualified

-- | Fetch @url@ exposing current to the web and reading public content.
getWebpage :: Url -> DC (DCLabeled String)
getWebpage url = do
  assertWrite dcPublic
  content <- ioTCB (WebTCB.getWebpage url)
  pure (LabeledTCB dcPublic content)

-- | Post @labeledContent@ to @url@.
postWebpage :: Url -> DCLabeled String -> DC ()
postWebpage url = write (WebTCB.postWebpage url) dcPublic
