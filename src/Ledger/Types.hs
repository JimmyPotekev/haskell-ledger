{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedRecordDot        #-}

-- The domain core. Pure, no IO. Everything the rest of the
-- project depends on for correctness lives here.
--
-- Design idea: make unbalanced transactions impossible to
-- construct. If you have a value of type `Transaction`, it
-- balances. Full stop. No "did someone remember to validate
-- it" question anywhere else in the codebase.
module Ledger.Types
  ( Money (..)
  , AccountId (..)
  , EntryInput (..)
  , Transaction
  , entries
  , LedgerError (..)
  , mkTransaction
  , sumEntries
  ) where

import Database.PostgreSQL.Simple.FromField (FromField)
import Database.PostgreSQL.Simple.ToField   (ToField)

-- Money as integer cents. Newtype-deriving gets us FromField
-- and ToField for free, so Postgres can read/write it as if
-- it were just an Int, while in Haskell it stays its own type.
newtype Money = Money { unMoney :: Int }
  deriving (Eq, Ord, Show)
  deriving newtype (FromField, ToField)

newtype AccountId = AccountId { unAccountId :: Int }
  deriving (Eq, Ord, Show)
  deriving newtype (FromField, ToField)

data EntryInput = EntryInput
  { account :: AccountId
  , amount  :: Money
  } deriving (Eq, Show)

data Transaction = Transaction { entries :: [EntryInput] }
  deriving (Eq, Show)

data LedgerError
  = EmptyTransaction
  | Unbalanced Int
  deriving (Eq, Show)

sumEntries :: [EntryInput] -> Int
sumEntries es = sum [ e.amount.unMoney | e <- es ]

mkTransaction :: [EntryInput] -> Either LedgerError Transaction
mkTransaction [] = Left EmptyTransaction
mkTransaction es =
  let total = sumEntries es
  in if total == 0
       then Right (Transaction es)
       else Left (Unbalanced total)