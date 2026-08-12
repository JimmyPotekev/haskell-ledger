module Main where

import           Ledger.Http

main :: IO ()
main = do
  putStrLn "starting ledger on http://localhost:3000"
  runServer 3000