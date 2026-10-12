module Main where

import           Ledger.Http
import           System.Environment (lookupEnv)

main :: IO ()
main = do
  portStr <- lookupEnv "PORT"
  let port = maybe 3000 read portStr
  putStrLn $ "starting ledger on port " ++ show port
  runServer port