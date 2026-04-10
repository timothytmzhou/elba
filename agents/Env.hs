module Env
  ( Env,
    TypeEnv (..),
    setEnv,
  )
where

import Data.Char (isLower)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, listToMaybe, mapMaybe)
import Language.Haskell.Interpreter
import Language.Haskell.TH
  ( Name,
    nameBase,
    nameModule,
    nameSpace,
  )
import Language.Haskell.TH.Syntax

type Env = [Name]

newtype TypeEnv = TypeEnv (Map String String)
  deriving (Show)

setEnv :: Env -> [String] -> Interpreter TypeEnv
setEnv env modules = do
  setImportsF $ envImports ++ moduleImports
  let values = filter isValue env
  let baseNames = map nameBase values
  types <- mapM typeOf baseNames
  let sigs = zip baseNames types
  pure $ TypeEnv (Map.fromList sigs)
  where
    envImports = toImports env
    moduleImports = [ModuleImport m NotQualified NoImportList | m <- modules]
    isValue n = nameSpace n == Just VarName

toImports :: Env -> [ModuleImport]
toImports env =
  [ mkImport m bases
  | (m, bases) <- groupByFst $ map splitName env
  ]
  where
    mkImport m bases = ModuleImport m NotQualified (ImportList bases)
    splitName n = (fromJust (nameModule n), nameBase n)
    groupByFst = Map.toList . Map.fromListWith (++) . map (\(k, v) -> (k, [v]))
  