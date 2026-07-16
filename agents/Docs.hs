-- Resolves the exports of the Env's tool modules together with their
-- Haddock docs, which GHC stores in interface files under the -haddock
-- flag. This is the same mechanism behind GHCi's :doc command.
module Docs
  ( ResolvedTool (..),
    resolveTools,
  )
where

import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Env (Env (..))
import GHC
  ( Ghc,
    TyThing (AConLike, AnId),
    findModule,
    getDocs,
    getModuleInfo,
    getSessionDynFlags,
    lookupName,
    mkModuleName,
    modInfoExports,
    parseDynamicFlags,
    runGhc,
    setSessionDynFlags,
  )
import GHC.Hs.Doc (hsDocString)
import GHC.Hs.DocString (renderHsDocString)
import GHC.Paths (libdir)
import GHC.Types.Name (Name, getOccString)
import GHC.Utils.Logger (getLogger)
import System.IO.Unsafe (unsafePerformIO)

-- | One exported name as resolved by the docs pass.
data ResolvedTool = ResolvedTool
  { toolName :: String,
    toolIsValue :: Bool,
    toolDoc :: Maybe String
  }

-- Resolution is cached per tool spec. Subagents reuse their parent's Env,
-- so recursive mkAgent calls never open a second GHC session while the
-- interpreter session is live.
{-# NOINLINE cache #-}
cache :: IORef (Map ([String], [(String, String)]) [ResolvedTool])
cache = unsafePerformIO (newIORef Map.empty)

resolveTools :: Env -> IO [ResolvedTool]
resolveTools env = do
  let key = (modules env, functions env)
  cached <- Map.lookup key <$> readIORef cache
  case cached of
    Just tools -> pure tools
    Nothing -> do
      tools <- resolve key
      atomicModifyIORef' cache (\m -> (Map.insert key tools m, ()))
      pure tools

resolve :: ([String], [(String, String)]) -> IO [ResolvedTool]
resolve (mods, fns) =
  runGhc (Just libdir) $ do
    dflags <- getSessionDynFlags
    logger <- getLogger
    (dflags', _, _) <- parseDynamicFlags logger dflags []
    _ <- setSessionDynFlags dflags'
    fromModules <- mapM (exportsOf Nothing) mods
    picked <- mapM (\(m, n) -> exportsOf (Just n) m) fns
    pure (concat (fromModules ++ picked))

exportsOf :: Maybe String -> String -> Ghc [ResolvedTool]
exportsOf only modname = do
  m <- findModule (mkModuleName modname) Nothing
  info <-
    maybe (error ("Docs.resolveTools: no module info for " ++ modname)) pure
      =<< getModuleInfo m
  let wanted n = maybe True (== getOccString n) only
  mapM describe [n | n <- modInfoExports info, wanted n]

describe :: Name -> Ghc ResolvedTool
describe n = do
  thing <- lookupName n
  let isValue = case thing of
        Just (AnId _) -> True
        Just (AConLike _) -> True
        _ -> False
  docs <- getDocs n
  let doc = case docs of
        Right (Just ds, _) ->
          Just (dropTrailingNewline (concatMap (renderHsDocString . hsDocString) ds))
        _ -> Nothing
  pure (ResolvedTool (getOccString n) isValue doc)

dropTrailingNewline :: String -> String
dropTrailingNewline s = case reverse s of
  '\n' : rest -> reverse rest
  _ -> s
