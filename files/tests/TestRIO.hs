module Main where

import Control.Exception (Exception, SomeException, catch, displayException, try)
import Control.Monad (unless)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import RIO
import System.Directory qualified as Dir
import System.Exit (exitFailure, exitSuccess)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = do
  failures <- newIORef (0 :: Int)
  runTests failures
  n <- readIORef failures
  if n == 0
    then do
      putStrLn "all tests passed"
      exitSuccess
    else do
      hPutStrLn stderr (show n ++ " test(s) failed")
      exitFailure

runTests :: IORef Int -> IO ()
runTests failures = do
  test failures "readFile/writeFile round-trip" testRoundTrip
  test failures "listDirectory returns entries" testListDirectory
  test failures "rejects .. traversal" testRejectDotDot
  test failures "rejects absolute path outside root" testRejectAbsoluteOutside
  test failures "rejects symlink pointing outside root" testRejectSymlinkOut
  test failures "scoped narrows access" testScopedNarrows
  test failures "scoped rejects sibling outside narrowed dir" testScopedRejectSibling
  test failures "pwd reflects runRIO root" testPwdRoot
  test failures "pwd reflects scoped narrowing" testPwdScoped
  test failures "no substring confusion (/foo vs /foo-evil)" testNoSubstringConfusion

test :: IORef Int -> String -> IO () -> IO ()
test failures name action = do
  result <- try action :: IO (Either SomeException ())
  case result of
    Right () -> putStrLn ("ok   " ++ name)
    Left e -> do
      modifyIORef' failures (+ 1)
      putStrLn ("FAIL " ++ name ++ ": " ++ displayException e)

assert :: String -> Bool -> IO ()
assert msg cond = unless cond (fail ("assertion failed: " ++ msg))

expectEscape :: IO a -> IO ()
expectEscape action = do
  result <- try action
  case result of
    Left (_ :: PathEscape) -> pure ()
    Right _ -> fail "expected PathEscape, got success"

withSandbox :: (FilePath -> IO ()) -> IO ()
withSandbox = withSystemTempDirectory "rio-test"

testRoundTrip :: IO ()
testRoundTrip = withSandbox $ \root -> do
  runRIO root $ do
    writeFileRIO "hello.txt" "world"
  contents <- runRIO root (readFileRIO "hello.txt")
  assert "round-trip contents" (contents == "world")

testListDirectory :: IO ()
testListDirectory = withSandbox $ \root -> do
  writeFile (root </> "a") ""
  writeFile (root </> "b") ""
  entries <- runRIO root (listDirectoryRIO ".")
  assert "two entries" (length entries == 2)

testRejectDotDot :: IO ()
testRejectDotDot = withSandbox $ \root -> do
  Dir.createDirectory (root </> "inner")
  writeFile (root </> "secret") "shh"
  expectEscape $ runRIO (root </> "inner") (readFileRIO "../secret")

testRejectAbsoluteOutside :: IO ()
testRejectAbsoluteOutside = withSandbox $ \root -> do
  expectEscape $ runRIO root (readFileRIO "/etc/passwd")

testRejectSymlinkOut :: IO ()
testRejectSymlinkOut = withSandbox $ \root -> do
  writeFile (root </> "outside-target") "secret"
  Dir.createDirectory (root </> "sandbox")
  Dir.createFileLink (root </> "outside-target") (root </> "sandbox" </> "link")
  expectEscape $ runRIO (root </> "sandbox") (readFileRIO "link")

testScopedNarrows :: IO ()
testScopedNarrows = withSandbox $ \root -> do
  Dir.createDirectory (root </> "sub")
  writeFile (root </> "sub" </> "f") "ok"
  contents <- runRIO root $ do
    scoped "sub" (readFileRIO "f")
  assert "scoped read" (contents == "ok")

testScopedRejectSibling :: IO ()
testScopedRejectSibling = withSandbox $ \root -> do
  Dir.createDirectory (root </> "sub")
  writeFile (root </> "sibling") "shh"
  expectEscape $ runRIO root $ do
    scoped "sub" (readFileRIO "../sibling")

testPwdRoot :: IO ()
testPwdRoot = withSandbox $ \root -> do
  result <- runRIO root pwd
  canonical <- Dir.canonicalizePath root
  assert "pwd matches canonical root" (result == canonical)

testPwdScoped :: IO ()
testPwdScoped = withSandbox $ \root -> do
  Dir.createDirectory (root </> "sub")
  result <- runRIO root (scoped "sub" pwd)
  canonical <- Dir.canonicalizePath (root </> "sub")
  assert "pwd matches scoped dir" (result == canonical)

testNoSubstringConfusion :: IO ()
testNoSubstringConfusion = withSandbox $ \root -> do
  Dir.createDirectory (root </> "foo")
  Dir.createDirectory (root </> "foo-evil")
  writeFile (root </> "foo-evil" </> "secret") "shh"
  expectEscape $ runRIO (root </> "foo") (readFileRIO "../foo-evil/secret")
