{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- LIO-secured wrapper around `WebTCB`. `getWebpage` is a read-and-write
-- (the URL goes out to a public sink, the response comes back tainted
-- with `dcPublic`). `postWebpage` is a write of arbitrary content to
-- the public sink.

module Web
  ( Url
  , getWebpage
  , postWebpage
  ) where

import LIO (guardAlloc, guardWrite)
import LIO.Concurrent (lWait)
import LIO.DCLabel (DC, dcPublic)
import LIO.TCB (ioTCB)
import Slack (DCLabeled)
import WebTCB (Url)
import WebTCB qualified

-- | Returns the content of the webpage at a given URL.
-- @url@: The URL of the webpage.
-- guardWrites at `dcPublic`: the URL is written to a public sink, and
-- the response taints the current label with `dcPublic`.
getWebpage :: Url -> DC String
getWebpage u = do
  guardWrite dcPublic
  ioTCB (WebTCB.getWebpage u)

-- | Posts a webpage at a given URL with the given content.
-- @url@: The URL of the webpage.
-- @content@: The content of the webpage as a `DCLabeled String`.
-- guardAllocs at `dcPublic` (the public-web sink label), then `lWait`s
-- the content.
postWebpage :: Url -> DCLabeled String -> DC ()
postWebpage url dlc = do
  guardAlloc dcPublic
  content <- lWait dlc
  ioTCB (WebTCB.postWebpage url content)
