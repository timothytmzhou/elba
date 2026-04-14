module RIO
  ( RIO,
    runRIO,
    scoped,
    pwd,
    readFileRIO,
    writeFileRIO,
    listDirectoryRIO,
    PathEscape (..),
  )
where

import Control.Exception (Exception, throwIO)
import Control.Monad (when)
import Control.Monad.Reader (ReaderT, ask, lift, local, runReaderT)
import Data.List (isPrefixOf)
import System.Directory qualified as Dir
import System.FilePath (splitDirectories, (</>))

newtype RIO a = RIO (ReaderT FilePath IO a)
  deriving (Functor, Applicative, Monad)

newtype PathEscape = PathEscape FilePath
  deriving (Show)

instance Exception PathEscape

runRIO :: FilePath -> RIO a -> IO a
runRIO root (RIO action) = Dir.canonicalizePath root >>= runReaderT action

pwd :: RIO FilePath
pwd = RIO ask

scoped :: FilePath -> RIO a -> RIO a
scoped newDir (RIO action) = do
  r <- resolvePath newDir
  RIO (local (const r) action)

withResolved :: (FilePath -> IO a) -> FilePath -> RIO a
withResolved f p = do
  resolved <- resolvePath p
  RIO (lift (f resolved))

readFileRIO :: FilePath -> RIO String
readFileRIO = withResolved readFile

writeFileRIO :: FilePath -> String -> RIO ()
writeFileRIO p contents = withResolved (`writeFile` contents) p

listDirectoryRIO :: FilePath -> RIO [FilePath]
listDirectoryRIO = withResolved Dir.listDirectory

resolvePath :: FilePath -> RIO FilePath
resolvePath p = RIO $ do
  root <- ask
  lift $ do
    let target = root </> p
    canonicalTarget <- Dir.canonicalizePath target
    if isPathPrefix root canonicalTarget
      then pure canonicalTarget
      else throwIO (PathEscape p)
  where
    isPathPrefix :: FilePath -> FilePath -> Bool
    isPathPrefix root target =
      splitDirectories root `isPrefixOf` splitDirectories target
