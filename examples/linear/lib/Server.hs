{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE Trustworthy #-}

module Server
  ( Cap (..),
    ServerRequest,
    runRequest,
    buy,
  )
where

data Cap = Cap

newtype ServerRequest a = ServerRequest (IO a)
  deriving (Functor, Applicative, Monad)

runRequest :: ServerRequest a -> IO a
runRequest (ServerRequest m) = m

buy :: String -> Cap %1 -> ServerRequest ()
buy item Cap = ServerRequest $
  putStrLn ("BUY: " ++ item)
