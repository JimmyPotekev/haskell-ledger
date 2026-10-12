{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings   #-}

-- The HTTP layer. Thin: parses JSON in, calls domain + Db,
-- returns JSON out. No business logic should live here.
--
-- Five endpoints:
--   POST /accounts                   create an account
--   POST /transfers                  post a balanced transfer
--   GET  /accounts/:id/balance       derived balance for an account
--   GET  /accounts/:id/history       every entry touching an account
--   GET  /transactions/:id           the entries of a transaction
--
-- Error strategy:
--   domain errors from mkTransaction -> 400 with JSON body
--   missing accounts or transactions  -> 404 with JSON body
--   other DB exceptions               -> Scotty default 500
module Ledger.Http where

import           Control.Exception          (throwIO, try)
import           Data.Aeson                (FromJSON (..), object, withObject, (.:), (.=))
import qualified Data.ByteString           as BS
import qualified Data.CaseInsensitive      as CI
import           Data.Int                  (Int64)
import           Data.Text                 (Text)
import           Database.PostgreSQL.Simple (Connection, SqlError)
import           Database.PostgreSQL.Simple.Errors (ConstraintViolation (..), constraintViolation)
import           Network.HTTP.Types.Status (status200, status201, status400, status404, status409)
import           Network.Wai               (Middleware, mapResponseHeaders,
                                            requestMethod, responseLBS)
import           Web.Scotty

import           Ledger.Db
import           Ledger.Types

-- Boot the HTTP server on the given port. One Connection is
-- opened at startup and shared across all handlers. Simple and
-- fine for a learning project; a real service would use a pool
-- (resource-pool or similar) to avoid serializing requests.
runServer :: Int -> IO ()
runServer port = do
  conn <- openConnection
  scotty port (routes conn)

-- All route definitions in one place for easy scanning.
routes :: Connection -> ScottyM ()
routes conn = do
  middleware corsMiddleware
  get  "/health"                 (handleHealth conn)
  post "/accounts"               (handleCreateAccount conn)
  post "/transfers"              (handleTransfer      conn)
  get  "/accounts/:id/balance"   (handleBalance       conn)
  get  "/accounts/:id/history"   (handleHistory       conn)
  get  "/transactions/:id"       (handleGetTx         conn)

-- ------------------------------------------------------------
-- Handlers
-- ------------------------------------------------------------

-- Smoke-test route. Confirms the server is up AND can reach
-- Postgres. Returns 200 "ok" either way, prints the DB
-- round-trip in the server log so you can see it worked.
handleHealth :: Connection -> ActionM ()
handleHealth _conn = do
  liftIO testConnection
  text "ok"

-- POST /accounts  body: {"name": "alice"}
-- Response: {"id": 1, "name": "alice"}  201
handleCreateAccount :: Connection -> ActionM ()
handleCreateAccount conn = do
  -- Minimal body: just a name field. Inline record type via
  -- Value and parsing manually would also work; a tiny named
  -- type is clearer. Keeping this one inline for now.
  req <- jsonData :: ActionM CreateAccountReq
  result <- liftIO (try (createAccount conn req.name) :: IO (Either SqlError AccountId))
  case result of
    Left e | isDuplicateName e -> do
      status status409
      json (object ["error" .= ("Account name already exists" :: Text)])
    Left e  -> liftIO (throwIO e)
    Right aid -> do
      status status201
      json (object ["id" .= aid, "name" .= req.name])

-- POST /transfers  body: TransferRequest
-- On success: {"transaction_id": 7}  201
-- On domain error (unbalanced, empty): 400 with error message.
--
-- The flow: parse body, run entries through mkTransaction to
-- enforce the balance invariant, then persist. Domain validation
-- happens BEFORE we touch the DB.
handleTransfer :: Connection -> ActionM ()
handleTransfer conn = do
  req <- jsonData :: ActionM TransferRequest
  case mkTransaction req.transferEntries of
    Left e -> do
      status status400
      json (object ["error" .= show e])
    Right tx -> do
      txId <- liftIO (insertTransaction conn req.idempotency_key tx)
      status status201
      json (object ["transaction_id" .= txId])

-- GET /accounts/:id/balance
-- Response: {"account_id": 1, "balance": -500}  200
-- 404 if the account doesn't exist.
handleBalance :: Connection -> ActionM ()
handleBalance conn = do
  rawId <- pathParam "id" :: ActionM Int
  let aid = AccountId rawId
  mName <- liftIO (fetchAccountName conn aid)
  case mName of
    Nothing -> notFound404 "account not found"
    Just _  -> do
      bal <- liftIO (fetchBalance conn aid)
      json (object ["account_id" .= aid, "balance" .= bal])

-- GET /accounts/:id/history
-- Response: [{"transaction_id": 7, "amount": -500}, ...]  200
-- 404 if the account doesn't exist.
handleHistory :: Connection -> ActionM ()
handleHistory conn = do
  rawId <- pathParam "id" :: ActionM Int
  let aid = AccountId rawId
  mName <- liftIO (fetchAccountName conn aid)
  case mName of
    Nothing -> notFound404 "account not found"
    Just _  -> do
      rows <- liftIO (fetchHistory conn aid)
      -- Reshape tuples into named-field JSON for the client.
      json [ object [ "transaction_id" .= txId
                    , "amount"         .= amt
                    ]
           | (txId, amt) <- rows
           ]

-- GET /transactions/:id
-- Response: {"id": 7, "entries": [{"account": 1, "amount": -500}, ...]}  200
-- 404 if the tx doesn't exist.
handleGetTx :: Connection -> ActionM ()
handleGetTx conn = do
  txId <- pathParam "id" :: ActionM Int64
  mEntries <- liftIO (fetchTransaction conn txId)
  case mEntries of
    Nothing -> notFound404 "transaction not found"
    Just es -> json $ object
      [ "id"      .= txId
      , "entries" .= [ object [ "account" .= aid, "amount" .= amt ]
                     | (aid, amt) <- es
                     ]
      ]

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

-- CORS: let the frontend (different port during dev) talk to us.
corsMiddleware :: Middleware
corsMiddleware app req respond
  | requestMethod req == "OPTIONS" =
      respond $ responseLBS status200 corsHeaders ""
  | otherwise =
      app req (\response -> respond $ mapResponseHeaders (corsHeaders ++) response)

corsHeaders :: [(CI.CI BS.ByteString, BS.ByteString)]
corsHeaders =
  [ ("Access-Control-Allow-Origin",  "*")
  , ("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  , ("Access-Control-Allow-Headers", "Content-Type")
  ]

-- Check if a SqlError is the UNIQUE violation on accounts.name.
isDuplicateName :: SqlError -> Bool
isDuplicateName e =
  case constraintViolation e of
    Just (UniqueViolation "accounts_name_key") -> True
    _                                          -> False

-- Shared 404 shape. Takes the message, sets status, writes JSON.
notFound404 :: Text -> ActionM ()
notFound404 msg = do
  status status404
  json (object ["error" .= msg])

-- Tiny input type for POST /accounts. Lives here because
-- nothing outside the HTTP layer needs it.
data CreateAccountReq = CreateAccountReq { name :: Text }
  deriving (Eq, Show)

instance FromJSON CreateAccountReq where
  parseJSON = withObject "CreateAccountReq" $ \o ->
    CreateAccountReq <$> o .: "name"