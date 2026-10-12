import { useState } from 'react'
import { getBalance } from '../api'

export default function BalanceLookup() {
  const [accountId, setAccountId] = useState('')
  const [balance, setBalance] = useState<number | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const id = parseInt(accountId, 10)
    if (isNaN(id)) return
    setLoading(true)
    setError(null)
    setBalance(null)
    try {
      const res = await getBalance(id)
      setBalance(res.balance)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  function formatDollars(cents: number): string {
    const abs = Math.abs(cents / 100).toFixed(2)
    return cents < 0 ? `-$${abs}` : `$${abs}`
  }

  return (
    <div className="panel">
      <h2>Balance Lookup</h2>
      <form onSubmit={handleSubmit}>
        <input
          type="number"
          placeholder="Account ID"
          value={accountId}
          onChange={e => setAccountId(e.target.value)}
          disabled={loading}
        />
        <button type="submit" disabled={loading || !accountId}>
          {loading ? 'Checking...' : 'Check'}
        </button>
      </form>
      {balance !== null && (
        <p className={`result ${balance < 0 ? 'amount-negative' : 'amount-positive'}`}>
          {formatDollars(balance)}
        </p>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  )
}
