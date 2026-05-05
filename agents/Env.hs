module Env
  ( Env (..),
    defEnv,
    TypeEnv (..),
    Extension (..),
    ModuleName,
    setEnv,
  )
where

import Data.Char (isAlpha)
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
    silentModules :: [ModuleName],
    extensions :: [Extension],
    toolDocs :: Map String String
  }

defEnv :: Env
defEnv = Env {names = [], modules = [], silentModules = [], extensions = [], toolDocs = Map.empty}

-- TypeEnv: name -> (signature, optional docstring). Show formats each entry
-- as `name :: signature`, optionally followed by an indented doc.
newtype TypeEnv = TypeEnv (Map String (String, Maybe String))

instance Show TypeEnv where
  show (TypeEnv m) =
    unlines
      [ entry name sig mDoc
      | (name, (sig, mDoc)) <- Map.toList m
      ]
    where
      entry name sig Nothing = name ++ " :: " ++ sig
      entry name sig (Just doc) =
        name
          ++ " :: "
          ++ sig
          ++ "\n"
          ++ unlines ["    " ++ ln | ln <- lines doc]

setEnv :: Env -> [ModuleName] -> Interpreter TypeEnv
setEnv Env {names, modules, silentModules = userSilent, toolDocs} silentModules = do
  let namedImports = importNames names
  let moduleImports = importModules (modules ++ silentModules ++ userSilent)
  setImportsF (namedImports ++ moduleImports)

  let namedValues = listNamedValues names
  moduleValues <- listModuleValues modules

  sigs <- typeSigs (namedValues ++ moduleValues)
  let entries = [(n, (s, Map.lookup n toolDocs)) | (n, s) <- sigs]
  pure (TypeEnv (Map.fromList entries))

importNames :: [Name] -> [ModuleImport]
importNames names =
  [ mkImport m bases
  | (m, bases) <- groupByFst (map splitName names)
  ]
  where
    mkImport m bases = ModuleImport m NotQualified (ImportList (map parenIfOp bases))
    splitName n = (fromJust (nameModule n), nameBase n)
    groupByFst = Map.toList . Map.fromListWith (++) . map (\(k, v) -> (k, [v]))

importModules :: [ModuleName] -> [ModuleImport]
importModules ms = [ModuleImport m NotQualified NoImportList | m <- ms]

listNamedValues :: [Name] -> [String]
listNamedValues ns = [parenIfOp (nameBase n) | n <- ns, isValue n]
  where
    isValue n = nameSpace n `elem` [Just VarName, Just DataName]

-- Wrap operator names in parens so they're valid in import lists and
-- in `typeOf` queries (e.g. `(%%)`, not `%%`).
parenIfOp :: String -> String
parenIfOp s@(c : _) | not (isAlpha c) && c /= '_' = "(" ++ s ++ ")"
parenIfOp s = s

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
