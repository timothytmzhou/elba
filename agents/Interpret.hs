module Interpret
  ( interpretCode
  ) where

import           Data.Typeable                (Typeable)
import           Language.Haskell.Interpreter

import           Env

interpretCode :: forall a. (Typeable a) => Env -> String -> IO (Maybe a)
interpretCode env code = do
  let prelude = ModuleImport "Prelude" NotQualified NoImportList
  result <- runInterpreter $ do
    setImportsF (prelude : env)
    interpret code (as :: (Typeable a) => a)
  case result of
    Left _  -> pure Nothing
    Right a -> pure (Just a)
