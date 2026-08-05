module Main where

import qualified Data.Text as T
import           Database.PostgreSQL.Simple (close)

import           Ledger.Db
import           Ledger.Types

main :: IO ()
main = do
  conn <- openConnection

  -- Create two fresh accounts. Suffix with a random-ish bit
  -- so you can re-run without unique-constraint pain.
  alice <- createAccount conn (T.pack "alice-demo")
  bob   <- createAccount conn (T.pack "bob-demo")
  putStrLn ("alice id = " ++ show alice)
  putStrLn ("bob   id = " ++ show bob)

  -- Build a balanced tx: alice sends 500 cents to bob.
  let txEither = mkTransaction
        [ EntryInput alice (Money (-500))
        , EntryInput bob   (Money 500)
        ]
  case txEither of
    Left e   -> putStrLn ("domain rejected tx: " ++ show e)
    Right tx -> do
      txId <- insertTransaction conn (Just (T.pack "demo-key-1")) tx
      putStrLn ("inserted tx id = " ++ show txId)

      -- Replay the same key, should return the SAME tx id, no
      -- second set of entries.
      txId2 <- insertTransaction conn (Just (T.pack "demo-key-1")) tx
      putStrLn ("replay    id = " ++ show txId2)

  aliceBal <- fetchBalance conn alice
  bobBal   <- fetchBalance conn bob
  putStrLn ("alice balance = " ++ show aliceBal)
  putStrLn ("bob   balance = " ++ show bobBal)

  close conn