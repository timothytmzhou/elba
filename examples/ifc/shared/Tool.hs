{-# LANGUAGE TemplateHaskell #-}

-- Generates insecure tool bindings that forward to Python over the bridge.
-- Each tool is fully determined by its Haskell name, its Python name, its
-- argument keys, and its type. See WorkspaceTCB for usage.
module Tool
  ( defTools
  , defTool
  ) where

import Bridge (callPy)
import Data.Aeson (object, (.=))
import Language.Haskell.TH

defTools :: [Q [Dec]] -> Q [Dec]
defTools = fmap concat . sequence

defTool :: String -> String -> [String] -> Q Type -> Q [Dec]
defTool hsName pyName keys ty = do
  let name = mkName hsName
  vars <- mapM (const (newName "a")) keys
  let pairs = [[|$(litE (stringL k)) .= $(varE v)|] | (k, v) <- zip keys vars]
      body = [|callPy $(litE (stringL pyName)) (object $(listE pairs))|]
  sequence [sigD name ty, funD name [clause (map varP vars) (normalB body) []]]
