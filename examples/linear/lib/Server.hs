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

-- Defines allowable server options via an opaque type.
newtype ServerRequest a = ServerRequest (IO a)
  deriving (Functor, Applicative, Monad)

-- Requires and consumes capabability token.
newtype Auth a = Auth (Cap %1 -> ServerRequest a)

runWithOneAuthorization :: Auth a -> IO a
runWithOneAuthorization (Auth f) = do
  let ServerRequest action = f Cap
  action

buy :: String -> Cap %1 -> ServerRequest ()
buy item Cap = ServerRequest $
  putStrLn ("BUY: " ++ item)
