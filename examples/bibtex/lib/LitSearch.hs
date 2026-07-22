{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- | DBLP-backed literature search sandbox.
--
-- The only way to obtain a @Trusted Bibtex@ is 'dblpFetchBib', which downloads
-- it from DBLP. 'writeBibFile' requires @[Trusted Bibtex]@, so the agent
-- cannot forge or tamper with entries.
module LitSearch
  ( Trusted
  , untrust
  , Bibtex
  , SearchResult(..)
  , TIO
  , runTIO
  , dblpSearch
  , dblpFetchBib
  , writeBibFile
  , tioPutStrLn
  , Response(..)
  ) where

import Data.Aeson (Value(..), eitherDecode)
import Data.Aeson.Key (fromText)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Foldable (toList)
import qualified Data.ByteString.Lazy as LBS2
import qualified Data.Text as T
import System.Process (CreateProcess(..), StdStream(..), createProcess, proc, waitForProcess)

data Response = Step String | RespondToUser String

-- | Attests that the value came from a trusted source. The constructor is
-- hidden, so only 'dblpFetchBib' can mint 'Trusted' values.
newtype Trusted a = MkTrusted { untrust :: a }
  deriving (Show)

-- | A raw BibTeX entry.
type Bibtex = String

-- | One DBLP search hit.
data SearchResult = SearchResult
  { srKey     :: String
  , srTitle   :: String
  , srAuthors :: [String]
  , srYear    :: String
  } deriving (Show)

-- | Restricted IO for literature search. The constructor is hidden, so the
-- exported operations are the only effects available.
newtype TIO a = UnsafeTIO { runTIO :: IO a }
  deriving (Functor, Applicative, Monad)

-- | Search DBLP for publications matching a query string.
-- Returns at most 10 results.
dblpSearch :: String -> TIO [SearchResult]
dblpSearch query = UnsafeTIO $ do
  let url = "https://dblp.org/search/publ/api?format=json&h=10&q=" ++ escapeURIString query
  body <- curlBytes url
  case eitherDecode body of
    Left err -> error $ "dblpSearch: failed to parse response: " ++ err
    Right val -> return (parseSearchResults val)

-- | Fetch the BibTeX entry for a search result from DBLP.
-- The only way to obtain a @Trusted Bibtex@.
dblpFetchBib :: SearchResult -> TIO (Trusted Bibtex)
dblpFetchBib sr = UnsafeTIO $ do
  let url = "https://dblp.org/rec/" ++ srKey sr ++ ".bib"
  body <- curlBytes url
  return (MkTrusted (LBS.unpack body))

-- | Write trusted BibTeX entries to a file.
-- The agent can reorder or filter the list but cannot forge entries.
writeBibFile :: FilePath -> [Trusted Bibtex] -> TIO ()
writeBibFile path entries = UnsafeTIO $
  writeFile path (concatMap untrust entries)

-- | Print a progress message to stdout.
tioPutStrLn :: String -> TIO ()
tioPutStrLn = UnsafeTIO . putStrLn

-- | Fetch a URL as raw bytes using curl, avoiding TLS FFI issues with hint.
curlBytes :: String -> IO LBS2.ByteString
curlBytes url = do
  let cp = (proc "curl" ["-s", url]) { std_out = CreatePipe }
  (_, Just hOut, _, ph) <- createProcess cp
  body <- LBS2.hGetContents hOut
  _ <- waitForProcess ph
  return body

escapeURIString :: String -> String
escapeURIString = concatMap esc
  where
    esc ' ' = "+"
    esc c | c `elem` ("-._~" :: String) = [c]
          | c >= 'a' && c <= 'z' = [c]
          | c >= 'A' && c <= 'Z' = [c]
          | c >= '0' && c <= '9' = [c]
          | otherwise = "%" ++ hex c
    hex c = let n = fromEnum c
                hi = n `div` 16
                lo = n `mod` 16
            in [hexDigit hi, hexDigit lo]
    hexDigit n
      | n < 10    = toEnum (fromEnum '0' + n)
      | otherwise = toEnum (fromEnum 'A' + n - 10)

parseSearchResults :: Value -> [SearchResult]
parseSearchResults (Object top)
  | Just (Object result) <- KM.lookup "result" top
  , Just (Object hits)   <- KM.lookup "hits" result
  , Just (Array hitArr)  <- KM.lookup "hit" hits
  = concatMap parseHit (toList hitArr)
parseSearchResults _ = []

parseHit :: Value -> [SearchResult]
parseHit (Object hit)
  | Just (Object info) <- KM.lookup "info" hit
  , Just key   <- getString "key" info
  , Just title <- getString "title" info
  , Just year  <- getString "year" info
  = [SearchResult
      { srKey     = key
      , srTitle   = title
      , srAuthors = parseAuthors info
      , srYear    = year
      }]
parseHit _ = []

getString :: T.Text -> KM.KeyMap Value -> Maybe String
getString k obj = case KM.lookup (fromText k) obj of
  Just (String t) -> Just (T.unpack t)
  _               -> Nothing

parseAuthors :: KM.KeyMap Value -> [String]
parseAuthors info
  | Just (Object authors) <- KM.lookup "authors" info
  , Just authorVal        <- KM.lookup "author" authors
  = case authorVal of
      Array arr -> concatMap authorName (toList arr)
      Object _  -> concatMap authorName [authorVal]  -- single author (not wrapped in array)
      _         -> []
parseAuthors _ = []

authorName :: Value -> [String]
authorName (Object obj)
  | Just (String t) <- KM.lookup "text" obj = [T.unpack t]
authorName _ = []
