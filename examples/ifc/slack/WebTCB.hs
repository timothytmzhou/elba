{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- Insecure tool surface for the web.
module WebTCB (module WebTCB) where

import Tool (defTool, defTools)

type Url = String

defTools
  [ defTool "getWebpage" "get_webpage" ["url"] [t|Url -> IO String|]
  , defTool "postWebpage" "post_webpage" ["url", "content"] [t|Url -> String -> IO ()|]
  ]
