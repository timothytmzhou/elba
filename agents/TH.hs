{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE Trustworthy #-}

-- TH helpers for populating an `Env` from a list of TH names. `addTools`
-- looks at each name's namespace at compile time and produces an
-- `Env -> Env` updater that fills `names`, `nameImports` (pre-rendered
-- per-module import items, namespace-aware), and `toolDocs`.
--
-- Rendering rules:
--   * VarName / DataName  → bare name (operator-wrapped if needed)
--   * TcClsName + alias   → bare name (`Foo`)
--   * TcClsName + data    → wildcard form (`Foo(..)`) so the
--                          constructor and field functions come along
--   * TcClsName + class   → wildcard form so methods come along
--   * Anything else       → bare name (best effort)

module TH
  ( addTools
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Env (Env (names, nameImports, toolDocs), parenIfOp)
import Language.Haskell.TH (Exp, Info (..), Name, Q, reify)
import Language.Haskell.TH.Syntax
  ( Dec (DataD, NewtypeD, TySynD)
  , DocLoc (DeclDoc)
  , NameSpace (TcClsName)
  , getDoc
  , lift
  , nameBase
  , nameModule
  , nameSpace
  )

addTools :: [Name] -> Q Exp
addTools ns = do
  docs <- mapM (\n -> getDoc (DeclDoc n)) ns
  let pairs = [(nameBase n, dropTrailingNewline d) | (n, Just d) <- zip ns docs]
  importPairs <- buildImports ns
  [|\e -> e
       { names = $(lift ns)
       , nameImports = Map.fromList $(lift importPairs)
       , toolDocs = Map.fromList $(lift pairs)
       }|]

-- | Group names by their defining module and render each as an import
-- list item, using TH-time `reify` to choose between `Foo` and
-- `Foo(..)` for type-namespace names.
buildImports :: [Name] -> Q [(String, [String])]
buildImports ns = do
  pairs <- mapM nameToItem ns
  -- Group by module, dedupe items per module, drop names without a
  -- defining module (e.g. local TH helpers — shouldn't happen via
  -- addTools, but safe).
  let grouped = Map.toList $
        fmap dedup $
        Map.fromListWith (++) [(m, [item]) | (Just m, item) <- pairs]
  pure grouped
  where
    dedup = reverse . foldr (\x acc -> if x `elem` acc then acc else x : acc) []

nameToItem :: Name -> Q (Maybe String, String)
nameToItem n = do
  item <- renderItem n
  pure (nameModule n, item)

renderItem :: Name -> Q String
renderItem n
  | nameSpace n == Just TcClsName = do
      info <- reify n
      pure $ case info of
        TyConI (TySynD {}) -> nameBase n
        TyConI (DataD {}) -> nameBase n ++ "(..)"
        TyConI (NewtypeD {}) -> nameBase n ++ "(..)"
        ClassI {} -> nameBase n ++ "(..)"
        _ -> nameBase n
  | otherwise = pure (parenIfOp (nameBase n))

dropTrailingNewline :: String -> String
dropTrailingNewline s = case reverse s of
  '\n' : rest -> reverse rest
  _ -> s
