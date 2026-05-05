{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- Trusted-base IO interface to AgentDojo's Web tools. Tools call
-- `Bridge.callPy` directly and return plain `IO`. The LIO-secured
-- wrapper that the agent actually sees lives in `Web`.

module WebTCB
  ( Url
  , getWebpage
  , postWebpage
  ) where

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
