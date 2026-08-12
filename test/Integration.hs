{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

-- Integration tests. These hit a real Postgres database.
--
-- The big property: for any random sequence of balanced transfers
-- between a fixed set of accounts, the sum of all account
-- balances after replay is zero. This is "conservation of money"
-- stated as a thing the system cannot violate without us noticing.
--
-- Also tested here: idempotency. Replaying the same sequence
-- with the same keys does not double-post.
module Integration where

import           Control.Monad                 (forM, forM_)
import qualified Data.Text                     as T
import           Data.Text                     (Text)
import           Database.PostgreSQL.Simple    (Connection)

import           Hedgehog
import qualified Hedgehog.Gen                  as Gen
import qualified Hedgehog.Range                as Range

import           Ledger.Db
import           Ledger.Types

-- ------------------------------------------------------------
-- Model of a transfer
-- ------------------------------------------------------------

-- A planned transfer at the generator level. We don't commit
-- to actual AccountIds yet because those come from the DB
-- after we create the accounts. We use indices into a fixed
-- pool of accounts instead.
data PlannedTransfer = PlannedTransfer
  { fromIdx :: Int    -- source account index
  , toIdx   :: Int    -- destination account index
  , cents   :: Int    -- positive magnitude, direction is from/to
  , key     :: Text   -- idempotency key for this transfer
  } deriving (Eq, Show)

numAccounts :: Int
numAccounts = 4

-- Generate one transfer. from and to are indices into our
-- small account pool; we don't bother forbidding self transfers,
-- the invariant still holds (money moves from A to A, net zero).
genTransfer :: Int -> Gen PlannedTransfer
genTransfer i = do
  f <- Gen.int (Range.linear 0 (numAccounts - 1))
  t <- Gen.int (Range.linear 0 (numAccounts - 1))
  c <- Gen.int (Range.linear 1 10000)
  pure PlannedTransfer
    { fromIdx = f
    , toIdx   = t
    , cents   = c
    , key     = T.pack ("tx-" ++ show i)
    }

-- Generate a list of transfers. Indexing them so idempotency
-- keys are unique per position in the sequence.
genTransferList :: Gen [PlannedTransfer]
genTransferList = do
  n  <- Gen.int (Range.linear 1 20)
  mapM genTransfer [0 .. n - 1]

-- ------------------------------------------------------------
-- Replaying a planned sequence against the DB
-- ------------------------------------------------------------

-- Create the N test accounts and return their AccountIds in order.
setupAccounts :: Connection -> IO [AccountId]
setupAccounts conn = forM [0 .. numAccounts - 1] $ \i ->
  createAccount conn (T.pack ("acct-" ++ show i))

-- Turn a PlannedTransfer into a real Transaction given the
-- resolved account ids, then insert it.
replayTransfer :: Connection -> [AccountId] -> PlannedTransfer -> IO ()
replayTransfer conn accts pt = do
  let src = accts !! pt.fromIdx
      dst = accts !! pt.toIdx
      es  = [ EntryInput src (Money (negate pt.cents))
            , EntryInput dst (Money pt.cents)
            ]
  case mkTransaction es of
    Left e -> error ("domain rejected test transfer: " ++ show e)
    Right tx -> do
      _ <- insertTransaction conn (Just pt.key) tx
      pure ()

-- Fetch the balance of every test account.
fetchAllBalances :: Connection -> [AccountId] -> IO [Money]
fetchAllBalances conn accts = forM accts (fetchBalance conn)

-- ------------------------------------------------------------
-- Properties
-- ------------------------------------------------------------

-- Conservation of money. After replaying any random sequence
-- of transfers, the sum of all balances across all accounts
-- must be zero. If this ever fails, something committed only
-- half of a transaction, which is exactly the failure mode
-- withTransaction is supposed to prevent.
prop_conservation :: Connection -> Property
prop_conservation conn = property $ do
  transfers <- forAll genTransferList
  balances  <- evalIO $ do
    truncateAll conn
    accts <- setupAccounts conn
    forM_ transfers (replayTransfer conn accts)
    fetchAllBalances conn accts
  let total = sum [ b.unMoney | b <- balances ]
  total === 0

-- Idempotency. Replaying the same transfer sequence with the
-- same keys should not change any balance. The second pass
-- hits the UNIQUE constraint on idempotency_key for every
-- transfer and returns the original tx id without posting
-- new entries.
prop_idempotent :: Connection -> Property
prop_idempotent conn = property $ do
  transfers <- forAll genTransferList
  (before, after) <- evalIO $ do
    truncateAll conn
    accts <- setupAccounts conn
    forM_ transfers (replayTransfer conn accts)
    b1 <- fetchAllBalances conn accts
    -- Second pass. Same keys, same transfers.
    forM_ transfers (replayTransfer conn accts)
    b2 <- fetchAllBalances conn accts
    pure (b1, b2)
  before === after

-- ------------------------------------------------------------
-- Group runner
-- ------------------------------------------------------------

integrationGroup :: Connection -> Group
integrationGroup conn = Group "Ledger.Db integration"
  [ ("prop_conservation", prop_conservation conn)
  , ("prop_idempotent",   prop_idempotent   conn)
  ]