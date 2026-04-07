module Env
  ( Env
  , showImport
  ) where

import           Language.Haskell.Interpreter

type Env = [ModuleImport]

showImport :: ModuleImport -> String
showImport (ModuleImport name qual imp) = name ++ qualStr ++ impStr
  where
    qualStr = case qual of
      NotQualified  -> ""
      ImportAs a    -> " as " ++ a
      QualifiedAs m -> " qualified" ++ maybe "" (" as " ++) m
    impStr = case imp of
      NoImportList  -> ""
      ImportList fs -> " (" ++ unwords fs ++ ")"
