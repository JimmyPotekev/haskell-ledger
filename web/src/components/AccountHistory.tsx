import { useState } from 'react'
import { getHistory, type HistoryEntry } from '../api'

export default function AccountHistory() {
  const [accountId, setAccountId] = useState('')
  const [entries, setEntries] = useState<HistoryEntry[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const id = parseInt(accountId, 10)
    if (isNaN(id)) return
    setLoading(true)
    setError(null)
    setEntries(null)
    try {
      const res = await getHistory(id)
      setEntries(res)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  function formatCents(cents: number): string {
    return (cents / 100).toFixed(2)
  }

  return (
    <div className="panel">
      <h2>Account History</h2>
      <form onSubmit={handleSubmit}>
        <input
          type="number"
          placeholder="Account ID"
          value={accountId}
          onChange={e => setAccountId(e.target.value)}
          disabled={loading}
        />
        <button type="submit" disabled={loading || !accountId}>
          {loading ? 'Loading...' : 'Load'}
        </button>
      </form>
      {entries !== null && (
        entries.length === 0
          ? <p className="result">No transactions yet.</p>
          : <table>
              <thead>
                <tr><th>Tx ID</th><th>Amount</th></tr>
              </thead>
              <tbody>
                {entries.map((e, i) => (
                  <tr key={i}>
                    <td>{e.transaction_id}</td>
                    <td>${formatCents(e.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  )
}
