{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE Trustworthy #-}

module Server
  ( Cap (..),
    ServerRequest,
    runWithOneAuthorization,
    buy,
    Auth (Auth)
  )
where

data Cap = Cap

-- Opaque, so the only obtainable requests are the exported operations.
newtype ServerRequest a = ServerRequest (IO a)
  deriving (Functor, Applicative, Monad)

-- Consumes the capability token exactly once.
newtype Auth a = Auth (Cap %1 -> ServerRequest a)

runWithOneAuthorization :: Auth a -> IO a
runWithOneAuthorization (Auth f) = do
  let ServerRequest action = f Cap
  action

buy :: String -> Cap %1 -> ServerRequest ()
buy item Cap = ServerRequest $
  putStrLn ("BUY: " ++ item)
