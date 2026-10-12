import { useState } from 'react'
import { getTransaction, type Transaction } from '../api'

export default function TransactionDetail() {
  const [txId, setTxId] = useState('')
  const [tx, setTx] = useState<Transaction | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    const id = parseInt(txId, 10)
    if (isNaN(id)) return
    setLoading(true)
    setError(null)
    setTx(null)
    try {
      const res = await getTransaction(id)
      setTx(res)
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
      <h2>Transaction Detail</h2>
      <form onSubmit={handleSubmit}>
        <input
          type="number"
          placeholder="Transaction ID"
          value={txId}
          onChange={e => setTxId(e.target.value)}
          disabled={loading}
        />
        <button type="submit" disabled={loading || !txId}>
          {loading ? 'Loading...' : 'Load'}
        </button>
      </form>
      {tx && (
        <div>
          <p className="result">Transaction #{tx.id}</p>
          <table>
            <thead>
              <tr><th>Account</th><th>Amount</th></tr>
            </thead>
            <tbody>
              {tx.entries.map((e, i) => (
                <tr key={i}>
                  <td>{e.account}</td>
                  <td className={e.amount < 0 ? 'amount-negative' : 'amount-positive'}>
                    {formatDollars(e.amount)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  )
}
