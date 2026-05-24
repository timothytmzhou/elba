{-# LANGUAGE Trustworthy #-}

module Web
  ( Url
  , getWebpage
  , postWebpage
  ) where

import LIO.DCLabel (DC, DCLabel, dcPublic)
import Policy (DCLabeled, relabelTCB, write)
import WebTCB (Url)
import WebTCB qualified

-- | The web is a single public sink, regardless of the URL.
webLabel :: a -> DC DCLabel
webLabel _ = pure dcPublic

-- | Fetch the page at @url@, ignoring the unused data slot (getWebpage uses
-- the URL as both the sink pointer and the data).
fetchPage :: Url -> a -> IO String
fetchPage url _ = WebTCB.getWebpage url

-- | Fetch the content of @labeledUrl@. Result is labeled public/untrusted.
getWebpage :: DCLabeled Url -> DC (DCLabeled String)
getWebpage labeledUrl = do
  content <- write id webLabel fetchPage labeledUrl labeledUrl
  relabelTCB dcPublic content

-- | Post @labeledContent@ to @labeledUrl@.
postWebpage :: DCLabeled Url -> DCLabeled String -> DC ()
postWebpage = write id webLabel WebTCB.postWebpage
