{-# LANGUAGE DeriveGeneric              #-}
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
  ( -- types
    Money (..)
  , AccountId (..)
  , EntryInput (..)
  , Transaction        -- note: constructor NOT exported
  , entries            -- read-only accessor on Transaction
  , LedgerError (..)
  , TransferRequest (..)
    -- smart constructor
  , mkTransaction
    -- helpers
  , sumEntries
  ) where

import           Data.Aeson                           (FromJSON (..), ToJSON (..), defaultOptions, fieldLabelModifier, genericParseJSON, genericToJSON)
import           Data.Text                            (Text)
import           Database.PostgreSQL.Simple.FromField (FromField)
import           Database.PostgreSQL.Simple.ToField   (ToField)
import           GHC.Generics                         (Generic)


-- Money as integer cents. Newtype-deriving gets us FromField
-- and ToField for free, so Postgres can read/write it as if
-- it were just an Int, while in Haskell it stays its own type.
-- Same trick for JSON: Money 500 serializes as 500, parses back
-- from 500. No wrapper object, just the raw number.
newtype Money = Money { unMoney :: Int }
  deriving (Eq, Ord, Show)
  deriving newtype (FromField, ToField, FromJSON, ToJSON)

-- Same idea. Keeps account ids and amounts from mixing.
newtype AccountId = AccountId { unAccountId :: Int }
  deriving (Eq, Ord, Show)
  deriving newtype (FromField, ToField, FromJSON, ToJSON)

-- What the caller gives us: "this account, this signed amount."
-- Negative = money leaving, positive = money arriving.
-- This is a plain record, anyone can build one. The *bundle* of
-- entries is what has to balance, not any single entry.
--
-- Generic deriving teaches aeson to serialize this as
-- {"account": 1, "amount": -500} without us writing it out.
data EntryInput = EntryInput
  { account :: AccountId
  , amount  :: Money
  } deriving (Eq, Show, Generic)

instance FromJSON EntryInput
instance ToJSON   EntryInput

-- Transaction's constructor is deliberately NOT in the export
-- list above. External code cannot write `Transaction [...]`.
-- The only way to make one is through mkTransaction, which
-- enforces the sum-to-zero rule. This is the whole trick.
--
-- Deriving ToJSON only. We don't want FromJSON here because
-- parsing a Transaction from JSON would bypass the smart
-- constructor and let unbalanced transactions in through the
-- back door. Clients post TransferRequest, we build the
-- Transaction server-side.
data Transaction = Transaction { entries :: [EntryInput] }
  deriving (Eq, Show, Generic)

instance ToJSON Transaction

-- All the ways building a transaction can go wrong.
-- Having a dedicated error type beats returning Maybe or a
-- magic string, you get exhaustiveness checking at use sites.
data LedgerError
  = EmptyTransaction
  | Unbalanced Int   -- carry the actual sum for debugging
  deriving (Eq)

instance Show LedgerError where
  show EmptyTransaction = "EmptyTransaction"
  show (Unbalanced cents) =
    let dollars = abs cents `div` 100
        remaining = abs cents `mod` 100
        sign = if cents < 0 then "-" else ""
    in "Unbalanced " ++ sign ++ show dollars ++ "." ++ (if remaining < 10 then "0" else "") ++ show remaining

-- The POST /transfers body. Separate from Transaction on
-- purpose, see the comment on Transaction above.
--
-- Field is named transferEntries (not entries) to avoid
-- clashing with Transaction's own entries field. Keeps the
-- module compiling without DuplicateRecordFields and keeps
-- Transaction.entries usable with dot syntax and as a plain
-- accessor function.
data TransferRequest = TransferRequest
  { transferEntries :: [EntryInput]
  , idempotency_key :: Maybe Text
  } deriving (Eq, Show, Generic)

instance FromJSON TransferRequest where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = \f -> if f == "transferEntries" then "entries" else f }

instance ToJSON TransferRequest where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = \f -> if f == "transferEntries" then "entries" else f }

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