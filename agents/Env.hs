module Env
  ( Env (..),
    defEnv,
    TypeEnv (..),
    Extension (..),
    ModuleName,
    setEnv,
    parenIfOp,
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
    -- | Pre-rendered import items per module, populated by `addTools`
    -- via TH-time `reify` so we know whether to emit `Foo`, `Foo(..)`,
    -- etc. Empty means "fall back to deriving items from `names`".
    nameImports :: Map ModuleName [String],
    modules :: [ModuleName],
    silentModules :: [ModuleName],
    extensions :: [Extension],
    toolDocs :: Map String String
  }

defEnv :: Env
defEnv =
  Env
    { names = [],
      nameImports = Map.empty,
      modules = [],
      silentModules = [],
      extensions = [],
      toolDocs = Map.empty
    }

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
setEnv Env {names, nameImports, modules, silentModules = userSilent, toolDocs} silentModules = do
  let namedImports
        | Map.null nameImports = importNamesFromBases names
        | otherwise = importNamesFromMap nameImports
  let moduleImports = importModules (modules ++ silentModules ++ userSilent)
  setImportsF (namedImports ++ moduleImports)

  let namedValues = listNamedValues names
  moduleValues <- listModuleValues modules

  sigs <- typeSigs (namedValues ++ moduleValues)
  let entries = [(n, (s, Map.lookup n toolDocs)) | (n, s) <- sigs]
  pure (TypeEnv (Map.fromList entries))

-- | Imports built from a pre-rendered Map of module → items (populated
-- at TH time by `addTools`).
importNamesFromMap :: Map ModuleName [String] -> [ModuleImport]
importNamesFromMap m =
  [ ModuleImport mn NotQualified (ImportList items)
  | (mn, items) <- Map.toList m
  ]

-- | Legacy fallback: derive a flat import list from a [Name] without
-- TH-time namespace info. Used when `nameImports` is empty (i.e.,
-- Env was built without `addTools`).
importNamesFromBases :: [Name] -> [ModuleImport]
importNamesFromBases names =
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

-- TODO: tools listed via `modules` arrive without Haddock docstrings —
-- hint's `getModuleExports` only returns names, and `.hi` files don't
-- carry Haddock. To fix, add a TH helper (e.g. `addToolsFromModule`)
-- that uses `reifyModule` at host compile time to enumerate a module's
-- exports as `[Name]` and feeds them through `addTools`, recovering
-- the Haddock-via-`getDoc` path.
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
