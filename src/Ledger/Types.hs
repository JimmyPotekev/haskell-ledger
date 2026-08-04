{-# LANGUAGE OverloadedRecordDot #-}

-- The domain core. Pure, no IO. Everything the rest of the
-- project depends on for correctness lives here.
--
-- Design idea: make unbalanced transactions impossible to
-- construct. If you have a value of type `Transaction`, it
-- balances. Full stop. No "did someone remember to validate it"
-- question anywhere else in the codebase.
module Ledger.Types
  ( -- types
    Money (..)
  , AccountId (..)
  , EntryInput (..)
  , Transaction        -- note: constructor NOT exported
  , entries            -- read-only accessor
  , LedgerError (..)
    -- smart constructor
  , mkTransaction
    -- helpers
  , sumEntries
  ) where

-- Money as integer cents. Floats are banned from this codebase.
-- Wrapping in a newtype means you can't accidentally pass raw
-- Ints where money is expected, or add an AccountId to a Money.
-- Zero runtime cost: the wrapper is erased by GHC.
newtype Money = Money { unMoney :: Int }
  deriving (Eq, Ord, Show)

-- Same idea. Keeps account ids and amounts from mixing.
newtype AccountId = AccountId { unAccountId :: Int }
  deriving (Eq, Ord, Show)

-- What the caller gives us: "this account, this signed amount."
-- Negative = money leaving, positive = money arriving.
-- This is a plain record, anyone can build one. The *bundle* of
-- entries is what has to balance, not any single entry.
data EntryInput = EntryInput
  { account :: AccountId
  , amount  :: Money
  } deriving (Eq, Show)

-- Transaction's constructor is deliberately NOT in the export
-- list above. External code cannot write `Transaction [...]`.
-- The only way to make one is through mkTransaction, which
-- enforces the sum-to-zero rule. This is the whole trick.
data Transaction = Transaction { entries :: [EntryInput] }
  deriving (Eq, Show)

-- All the ways building a transaction can go wrong.
-- Having a dedicated error type beats returning Maybe or a
-- magic string, you get exhaustiveness checking at use sites.
data LedgerError
  = EmptyTransaction
  | Unbalanced Int   -- carry the actual sum for debugging
  deriving (Eq, Show)

-- Sum the signed amounts across every entry. If this isn't
-- zero, money would be appearing or vanishing.
sumEntries :: [EntryInput] -> Int
sumEntries es = sum [ e.amount.unMoney | e <- es ]

-- The smart constructor. Returns Either so the caller is
-- forced by the type system to handle both outcomes.
-- Rejection cases:
--   1. no entries at all (meaningless)
--   2. entries don't sum to zero (would create or destroy money)
mkTransaction :: [EntryInput] -> Either LedgerError Transaction
mkTransaction [] = Left EmptyTransaction
mkTransaction es =
  let total = sumEntries es
  in if total == 0
       then Right (Transaction es)
       else Left (Unbalanced total)
