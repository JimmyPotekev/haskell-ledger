module Main where

import Ledger.Db (testConnection)

main :: IO ()
main = testConnection