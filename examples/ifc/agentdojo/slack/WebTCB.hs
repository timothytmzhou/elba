{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- Internal API for interfacing with the web.

module WebTCB
  ( Url,
    getWebpage,
    postWebpage,
  )
where

import Bridge (callPy)
import Data.Aeson (object, (.=))

type Url = String

-- | Returns the content of the webpage at a given URL.
-- @url@: The URL of the webpage.
getWebpage :: Url -> IO String
getWebpage u = callPy "get_webpage" (object ["url" .= u])

-- | Posts a webpage at a given URL with the given content.
-- @url@: The URL of the webpage.
-- @content@: The content of the webpage.
postWebpage :: Url -> String -> IO ()
postWebpage u content = callPy "post_webpage" (object ["url" .= u, "content" .= content])
