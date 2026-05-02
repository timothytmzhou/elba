{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure baseline for AgentDojo's Web tools. Bridge handle is
-- threaded through the `Web` value because of hint's CAF isolation
-- (see comment on Slack.hs).

module Web
  ( Url
  , Web
  , mkWeb
  , bridge
  , getWebpage
  , postWebpage
  ) where

import Bridge (Bridge, callPy)
import Data.Aeson (object, (.=))

type Url = String

newtype Web = Web {bridge :: Bridge}

mkWeb :: Bridge -> Web
mkWeb = Web

-- | Returns the content of the webpage at a given URL.
-- @url@: The URL of the webpage.
getWebpage :: Web -> Url -> IO String
getWebpage w u =
  callPy (bridge w) "get_webpage" (object ["url" .= u])

-- | Posts a webpage at a given URL with the given content.
-- @url@: The URL of the webpage.
-- @content@: The content of the webpage.
postWebpage :: Web -> Url -> String -> IO ()
postWebpage w u content =
  callPy (bridge w) "post_webpage" (object ["url" .= u, "content" .= content])
