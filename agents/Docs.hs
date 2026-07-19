module Docs
  ( resolveTools,
  )
where

import Env (Env (..), ResolvedTool (..))
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

-- | Reads module exports and Haddock from interface files. Needs libraries built with the haddock flag.
resolveTools :: Env -> IO [ResolvedTool]
resolveTools env =
  runGhc (Just libdir) $ do
    dflags <- getSessionDynFlags
    logger <- getLogger
    (dflags', _, _) <- parseDynamicFlags logger dflags []
    _ <- setSessionDynFlags dflags'
    concat <$> mapM exportsOf (modules env)

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
