{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Crossref backed literature search sandbox. The only way to obtain a
-- @Trusted Bibtex@ is 'fetchBib', so the agent cannot forge or tamper
-- with entries.
module LitSearch
  ( Trusted, untrust, Bibtex, SearchResult(..), TIO, runTIO
  , searchWorks, fetchBib, writeBibFile, tioPutStrLn
  ) where

import Control.Applicative (optional)
import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Aeson (Value, decode, withObject, (.:), (.:?), (.!=))
import Data.Aeson.Types (Parser, parseMaybe)
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.List (intercalate, isPrefixOf)
import Data.Maybe (catMaybes, fromMaybe)
import Network.HTTP.Simple (getResponseBody, httpLBS, parseRequest)
import Network.URI (escapeURIString, isUnreserved)

-- | Attests that the value came from the registry. Constructor hidden.
newtype Trusted a = MkTrusted { untrust :: a } deriving (Show)

-- | A raw BibTeX entry.
type Bibtex = String

-- | One Crossref search hit.
data SearchResult = SearchResult
  { srDoi, srTitle, srYear, srVenue :: String
  , srAuthors :: [String]
  } deriving (Show)

-- | Restricted IO. The exported operations are the only effects available.
newtype TIO a = UnsafeTIO { runTIO :: IO a }
  deriving (Functor, Applicative, Monad)

-- | Search the Crossref scholarly database for publications matching a
-- query string. Returns at most 10 results, ranked by relevance.
searchWorks :: String -> TIO [SearchResult]
searchWorks query = UnsafeTIO $ do
  let url = "https://api.crossref.org/works?rows=10&mailto=ttzhou@ucsd.edu\
            \&select=DOI,title,author,issued,container-title&query="
            ++ escapeURIString isUnreserved query
  body <- fetch url
  pure (fromMaybe [] (decode body >>= parseMaybe hits))

-- | Fetch the BibTeX entry for a search result from Crossref.
-- Returns Nothing when the registry has no BibTeX for the record.
-- The only way to obtain a @Trusted Bibtex@.
fetchBib :: SearchResult -> TIO (Maybe (Trusted Bibtex))
fetchBib sr = UnsafeTIO $ do
  let keep c = isUnreserved c || c == '/'
      url = "https://api.crossref.org/works/" ++ escapeURIString keep (srDoi sr)
            ++ "/transform/application/x-bibtex"
  entry <- dropWhile (`elem` (" \n\t" :: String)) . LBS.unpack <$> fetch url
  pure (if "@" `isPrefixOf` entry then Just (MkTrusted entry) else Nothing)

-- | Write trusted BibTeX entries to a file.
-- The agent can reorder or filter the list but cannot forge entries.
writeBibFile :: FilePath -> [Trusted Bibtex] -> TIO ()
writeBibFile path entries = UnsafeTIO $
  LBS.writeFile path (LBS.pack (intercalate "\n\n" (map untrust entries) ++ "\n"))

-- | Print a progress message to stdout.
tioPutStrLn :: String -> TIO ()
tioPutStrLn = UnsafeTIO . putStrLn

-- Empty responses are retried, the registry sheds load under bursts.
fetch :: String -> IO LBS.ByteString
fetch url = go (4 :: Int)
  where
    go n = do
      result <- try (httpLBS =<< parseRequest url)
      let body = case result of
            Left (_ :: SomeException) -> ""
            Right response -> getResponseBody response
      if LBS.null body && n > 0
        then threadDelay (5000000 * (5 - n)) >> go (n - 1)
        else pure body

hits :: Value -> Parser [SearchResult]
hits = withObject "works" $ \o -> do
  items <- o .: "message" >>= withObject "message" (.: "items")
  catMaybes <$> mapM (optional . hit) (items :: [Value])
  where
    hit = withObject "work" $ \w -> do
      doi <- w .: "DOI"
      title : _ <- w .: "title"
      (year : _) : _ <- w .: "issued" >>= withObject "issued" (.: "date-parts")
      venue <- concat . take 1 <$> w .:? "container-title" .!= []
      authors <- w .:? "author" .!= [] >>= mapM name
      True <- pure (not (null authors))
      pure (SearchResult doi title (show (year :: Int)) venue authors)
    name = withObject "author" $ \a -> do
      family <- a .: "family"
      given <- a .:? "given"
      pure (maybe family (++ " " ++ family) given)
