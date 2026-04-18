module Env
  ( Env (..),
    defEnv,
    TypeEnv (..),
    Extension (..),
    ModuleName,
    setEnv,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromJust)
import Language.Haskell.Interpreter hiding (Extension)
import Language.Haskell.TH
  ( Name,
    nameBase,
    nameModule,
    nameSpace,
  )
import Language.Haskell.TH.Syntax (Extension (..), NameSpace (DataName, VarName))

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
setEnv Env {names, modules} silentModules = do
  let namedImports = importNames names
  let moduleImports = importModules (modules ++ silentModules)
  setImportsF (namedImports ++ moduleImports)

  let namedValues = listNamedValues names
  moduleValues <- listModuleValues modules

  sigs <- typeSigs (namedValues ++ moduleValues)
  pure (TypeEnv (Map.fromList sigs))

importNames :: [Name] -> [ModuleImport]
importNames names =
  [ mkImport m bases
  | (m, bases) <- groupByFst (map splitName names)
  ]
  where
    mkImport m bases = ModuleImport m NotQualified (ImportList bases)
    splitName n = (fromJust (nameModule n), nameBase n)
    groupByFst = Map.toList . Map.fromListWith (++) . map (\(k, v) -> (k, [v]))

importModules :: [ModuleName] -> [ModuleImport]
importModules ms = [ModuleImport m NotQualified NoImportList | m <- ms]

listNamedValues :: [Name] -> [String]
listNamedValues ns = [nameBase n | n <- ns, isValue n]
  where
    isValue n = nameSpace n `elem` [Just VarName, Just DataName]

listModuleValues :: [ModuleName] -> Interpreter [String]
listModuleValues ms = do
  exportLists <- mapM getModuleExports ms
  let exports = concat exportLists
  pure [n | e <- exports, n <- valueNamesOf e]
  where
    valueNamesOf (Fun n) = [n]
    valueNamesOf (Data _ ctors) = ctors
    valueNamesOf (Class _ methods) = methods

typeSigs :: [String] -> Interpreter [(String, String)]
typeSigs names = do
  types <- mapM typeOf names
  pure (zip names types)
