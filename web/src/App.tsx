import { useState } from 'react'
import { type Account } from './api'
import CreateAccount from './components/CreateAccount'
import Transfer from './components/Transfer'
import BalanceLookup from './components/BalanceLookup'
import AccountHistory from './components/AccountHistory'
import TransactionDetail from './components/TransactionDetail'
import './App.css'

function App() {
  const [accounts, setAccounts] = useState<Account[]>([])

  function handleAccountCreated(account: Account) {
    setAccounts(prev => [...prev, account])
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1 className="app-title">Ledger</h1>
        <p className="app-subtitle">Double-entry accounting API</p>
      </header>
      <div className="panels">
        <CreateAccount accounts={accounts} onCreated={handleAccountCreated} />
        <Transfer />
        <BalanceLookup />
        <AccountHistory />
        <TransactionDetail />
      </div>
    </div>
  )
}

export default App
