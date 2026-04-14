module Env
  ( Env (..),
    defEnv,
    TypeEnv (..),
    Extension (..),
    ModuleName,
    setEnv,
  )
where

import Data.Char (isLower)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust, listToMaybe, mapMaybe)
import Language.Haskell.Interpreter hiding (Extension)
import Language.Haskell.TH
  ( Name,
    nameBase,
    nameModule,
    nameSpace,
  )
import Language.Haskell.TH.Syntax (Extension (..), NameSpace (VarName))

data Env = Env
  { names :: [Name],
    modules :: [ModuleName],
    extensions :: [Extension]
  }

defEnv :: Env
defEnv = Env {names = [], modules = [], extensions = []}

newtype TypeEnv = TypeEnv (Map String String)

instance Show TypeEnv where
  show (TypeEnv m) = unlines [name ++ " :: " ++ ty | (name, ty) <- Map.toList m]

setEnv :: Env -> [ModuleName] -> Interpreter TypeEnv
setEnv env silentModules = do
  setImportsF $ importsFromNames ++ openImports (modules env) ++ openImports silentModules
  importsSigs <- typeSigs importedBaseNames
  moduleSigs <- concat <$> mapM moduleValueSigs (modules env)
  pure $ TypeEnv (Map.fromList (importsSigs ++ moduleSigs))
  where
    importsFromNames = nameImports (names env)
    openImports ms = [ModuleImport m NotQualified NoImportList | m <- ms]
    importedBaseNames = [nameBase n | n <- names env, isValue n]
    isValue n = nameSpace n == Just VarName

typeSigs :: [String] -> Interpreter [(String, String)]
typeSigs names = do
  types <- mapM typeOf names
  pure (zip names types)

moduleValueSigs :: ModuleName -> Interpreter [(String, String)]
moduleValueSigs m = do
  exports <- getModuleExports m
  let names = [n | Fun n <- exports]
  typeSigs names

nameImports :: [Name] -> [ModuleImport]
nameImports names =
  [ mkImport m bases
  | (m, bases) <- groupByFst $ map splitName names
  ]
  where
    mkImport m bases = ModuleImport m NotQualified (ImportList bases)
    splitName n = (fromJust (nameModule n), nameBase n)
    groupByFst = Map.toList . Map.fromListWith (++) . map (\(k, v) -> (k, [v]))
