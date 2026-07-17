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

data ResolvedTool = ResolvedTool
  { toolName :: String,
    toolIsValue :: Bool,
    toolDoc :: Maybe String
  }

-- Subagents reuse their parent's Env, so caching keeps recursive mkAgent
-- calls from opening a second GHC session inside a live interpreter.
{-# NOINLINE cache #-}
cache :: IORef (Map [String] [ResolvedTool])
cache = unsafePerformIO (newIORef Map.empty)

-- | Reads each module's exports and Haddock from its interface file, the
-- mechanism behind GHCi's :doc command. Needs libraries built with -haddock.
resolveTools :: Env -> IO [ResolvedTool]
resolveTools env = do
  let key = modules env
  cached <- Map.lookup key <$> readIORef cache
  case cached of
    Just tools -> pure tools
    Nothing -> do
      tools <- resolve key
      atomicModifyIORef' cache (\m -> (Map.insert key tools m, ()))
      pure tools

resolve :: [String] -> IO [ResolvedTool]
resolve mods =
  runGhc (Just libdir) $ do
    dflags <- getSessionDynFlags
    logger <- getLogger
    (dflags', _, _) <- parseDynamicFlags logger dflags []
    _ <- setSessionDynFlags dflags'
    concat <$> mapM exportsOf mods

exportsOf :: String -> Ghc [ResolvedTool]
exportsOf modname = do
  m <- findModule (mkModuleName modname) Nothing
  info <-
    maybe (error ("Docs.resolveTools: no module info for " ++ modname)) pure
      =<< getModuleInfo m
  mapM describe (modInfoExports info)

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
