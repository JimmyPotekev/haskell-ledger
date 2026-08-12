{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

-- Property tests for the ledger domain core.
--
-- Three properties, run with 100 random inputs each by default.
-- If any input breaks a rule, Hedgehog shrinks it to a minimal
-- failing case before reporting.
--
-- Chunk 2 add-on: also runs integration tests against a real
-- Postgres database. Those live in Integration.hs. We share one
-- Connection across the integration suite and run it sequentially
-- because every case truncates the DB.
module Main where

import           Control.Monad   (unless)
import           Database.PostgreSQL.Simple (close)
import           System.Exit     (exitFailure)

import           Hedgehog
import qualified Hedgehog.Gen    as Gen
import qualified Hedgehog.Range  as Range

import           Ledger.Db
import           Ledger.Types

import qualified Integration

-- ------------------------------------------------------------
-- Generators
-- ------------------------------------------------------------

-- Pick an account from a small fixed pool. Keeping the pool
-- small on purpose, we WANT collisions (two entries hitting the
-- same account) so weird cases get exercised.
genAccount :: Gen AccountId
genAccount = Gen.element [AccountId 1, AccountId 2, AccountId 3, AccountId 4]

-- Any signed amount in a reasonable range. Negative = outflow,
-- positive = inflow. Int bounds would be fine but keeping it
-- small makes shrinking failures faster to read.
genAmount :: Gen Money
genAmount = Money <$> Gen.int (Range.linearFrom 0 (-10000) 10000)

-- A single entry: pick an account, pick an amount.
genEntry :: Gen EntryInput
genEntry = EntryInput <$> genAccount <*> genAmount

-- A list of entries that sums to zero.
-- Trick: generate n-1 random entries, then append one final
-- entry whose amount is the negation of the running sum. Final
-- list is guaranteed balanced by construction.
genBalancedEntries :: Gen [EntryInput]
genBalancedEntries = do
  prefix <- Gen.list (Range.linear 1 10) genEntry
  acct   <- genAccount
  let correction = negate (sumEntries prefix)
  pure (prefix ++ [EntryInput acct (Money correction)])

-- A list of entries that does NOT sum to zero.
-- Easiest reliable way: generate arbitrary entries, then if
-- they happen to balance (unlikely but possible), nudge one.
genUnbalancedEntries :: Gen [EntryInput]
genUnbalancedEntries = do
  es <- Gen.list (Range.linear 1 10) genEntry
  if sumEntries es /= 0
    then pure es
    -- fallback: tack on a nonzero entry to force imbalance
    else do
      acct <- genAccount
      pure (es ++ [EntryInput acct (Money 1)])

-- ------------------------------------------------------------
-- Properties
-- ------------------------------------------------------------

-- Any balanced list must be accepted.
prop_balanced_succeeds :: Property
prop_balanced_succeeds = property $ do
  es <- forAll genBalancedEntries
  case mkTransaction es of
    Right _ -> success
    Left  e -> annotateShow e >> failure

-- Any unbalanced list must be rejected with Unbalanced.
prop_unbalanced_fails :: Property
prop_unbalanced_fails = property $ do
  es <- forAll genUnbalancedEntries
  case mkTransaction es of
    Left (Unbalanced _) -> success
    other               -> annotateShow other >> failure

-- Round-trip: if mkTransaction said Right, the entries inside
-- must sum to zero. Catches regressions where someone weakens
-- the smart constructor.
prop_roundtrip_sums_zero :: Property
prop_roundtrip_sums_zero = property $ do
  es <- forAll genBalancedEntries
  case mkTransaction es of
    Right tx -> sumEntries tx.entries === 0
    Left  e  -> annotateShow e >> failure

-- Group the pure properties so they can be reported together,
-- separately from the integration group.
pureGroup :: Group
pureGroup = Group "Ledger.Types"
  [ ("prop_balanced_succeeds",   prop_balanced_succeeds)
  , ("prop_unbalanced_fails",    prop_unbalanced_fails)
  , ("prop_roundtrip_sums_zero", prop_roundtrip_sums_zero)
  ]

-- ------------------------------------------------------------
-- Entry point
-- ------------------------------------------------------------

main :: IO ()
main = do
  -- One connection shared across the integration suite. The
  -- tests truncate between cases so cross-case pollution isn't
  -- an issue, and reusing the connection keeps things fast.
  conn <- openConnection

  -- Pure group can run in parallel, no shared state.
  ok1 <- checkParallel pureGroup
  -- Integration group runs sequentially because every case
  -- truncates the DB on the shared connection. Parallel would
  -- race.
  ok2 <- checkSequential (Integration.integrationGroup conn)

  close conn
  unless (ok1 && ok2) exitFailure