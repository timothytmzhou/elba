{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE Trustworthy #-}

-- Web tool bindings for AgentDojo's slack default suite.
-- Same shape as Slack: pageLabels mirrors the Python Web class' page state,
-- holding labels (not data). Baseline tool functions do not consult labels.

module Web
  ( Url
  , Web
  , mkWeb
  , getWebpage
  , postWebpage
  ) where

import Bridge (Bridge, callPy)
import Data.Aeson (object, (.=))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import LIO (LIO)
import LIO.DCLabel (DCLabel, dcPublic)
import LIO.LIORef (LIORef, newLIORef)
import LIO.TCB (ioTCB)
import Slack (DC)

type Url = String

data Web = Web
  { pageLabels :: LIORef DCLabel (Map Url DCLabel)
  , bridge :: Bridge
  }

mkWeb :: Bridge -> DC Web
mkWeb br = do
  pageLabels <- newLIORef dcPublic Map.empty
  let bridge = br
  pure Web {..}

getWebpage :: Web -> Url -> DC String
getWebpage w u =
  ioTCB $
    callPy
      (bridge w)
      "get_webpage"
      (object ["url" .= u])

postWebpage :: Web -> Url -> String -> DC ()
postWebpage w u content =
  ioTCB $
    callPy
      (bridge w)
      "post_webpage"
      (object ["url" .= u, "content" .= content])
