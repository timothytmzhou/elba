{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- TH helpers for populating an `Env` from a list of TH names. `addTools`
-- queries Haddock docs at compile time via `getDoc` and produces an
-- `Env -> Env` updater that fills both `names` and `toolDocs` from a single
-- list, so the caller doesn't repeat the names twice.

module TH
  ( addTools
  ) where

import Data.Map.Strict qualified as Map
import Env (Env (names, toolDocs))
import Language.Haskell.TH (Exp, Name, Q)
import Language.Haskell.TH.Syntax (DocLoc (DeclDoc), getDoc, lift, nameBase)

addTools :: [Name] -> Q Exp
addTools ns = do
  docs <- mapM (\n -> getDoc (DeclDoc n)) ns
  let pairs = [(nameBase n, dropTrailingNewline d) | (n, Just d) <- zip ns docs]
  [|\e -> e {names = $(lift ns), toolDocs = Map.fromList $(lift pairs)}|]

dropTrailingNewline :: String -> String
dropTrailingNewline s = case reverse s of
  '\n' : rest -> reverse rest
  _ -> s
