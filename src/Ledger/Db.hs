module Ledger.Db where

import           Configuration.Dotenv       (defaultConfig, loadFile)
import           Database.PostgreSQL.Simple
import           System.Environment         (getEnv)
import           Text.Read                  (readMaybe)

-- Build a ConnectInfo by reading env vars.
-- loadFile reads .env from the current directory and pokes
-- the vars into the process environment. Call this once at
-- startup before anyone asks for a connection.
loadConnectInfo :: IO ConnectInfo
loadConnectInfo = do
  _        <- loadFile defaultConfig       -- harmless if .env missing in prod
  host     <- getEnv "LEDGER_DB_HOST"
  portStr  <- getEnv "LEDGER_DB_PORT"
  user     <- getEnv "LEDGER_DB_USER"
  password <- getEnv "LEDGER_DB_PASSWORD"
  db       <- getEnv "LEDGER_DB_NAME"
  let port = case readMaybe portStr of
               Just n  -> n
               Nothing -> error ("LEDGER_DB_PORT not a number: " ++ portStr)
  pure defaultConnectInfo
    { connectHost     = host
    , connectPort     = port
    , connectUser     = user
    , connectPassword = password
    , connectDatabase = db
    }

-- Smoke test. Loads config, connects, pings, closes.
testConnection :: IO ()
testConnection = do
  ci   <- loadConnectInfo
  conn <- connect ci
  rows <- query_ conn "SELECT 1 :: int"
  print (rows :: [Only Int])
  close conn