import { useState } from 'react'
import { submitTransfer, type TransferEntry } from '../api'

interface EntryRow {
  account: string
  amount: string
}

export default function Transfer() {
  const [rows, setRows] = useState<EntryRow[]>([
    { account: '', amount: '' },
    { account: '', amount: '' },
  ])
  const [idempotencyKey, setIdempotencyKey] = useState('')
  const [result, setResult] = useState<number | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function updateRow(i: number, field: keyof EntryRow, value: string) {
    setRows(prev => prev.map((r, j) => j === i ? { ...r, [field]: value } : r))
  }

  function addRow() {
    setRows(prev => [...prev, { account: '', amount: '' }])
  }

  function removeRow(i: number) {
    if (rows.length <= 2) return
    setRows(prev => prev.filter((_, j) => j !== i))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)
    setResult(null)
    try {
      const entries: TransferEntry[] = rows.map(r => ({
        account: parseInt(r.account, 10),
        amount: parseInt(r.amount, 10),
      }))
      if (entries.some(e => isNaN(e.account) || isNaN(e.amount))) {
        throw new Error('All fields must be valid numbers')
      }
      const res = await submitTransfer(entries, idempotencyKey || undefined)
      setResult(res.transaction_id)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="panel">
      <h2>Transfer</h2>
      <form onSubmit={handleSubmit}>
        {rows.map((row, i) => (
          <div key={i} className="entry-row">
            <input
              type="number"
              placeholder="Account ID"
              value={row.account}
              onChange={e => updateRow(i, 'account', e.target.value)}
              disabled={loading}
            />
            <input
              type="number"
              placeholder="Amount (cents)"
              value={row.amount}
              onChange={e => updateRow(i, 'amount', e.target.value)}
              disabled={loading}
            />
            {rows.length > 2 && (
              <button type="button" onClick={() => removeRow(i)} className="remove-btn">×</button>
            )}
          </div>
        ))}
        <div className="form-actions">
          <button type="button" onClick={addRow} disabled={loading}>Add entry</button>
          <button type="submit" disabled={loading}>
            {loading ? 'Submitting...' : 'Submit'}
          </button>
        </div>
        <input
          type="text"
          placeholder="Idempotency key (auto if blank)"
          value={idempotencyKey}
          onChange={e => setIdempotencyKey(e.target.value)}
          disabled={loading}
          className="full-width"
        />
      </form>
      {result !== null && <p className="success">Transaction ID: {result}</p>}
      {error && <p className="error">{error}</p>}
    </div>
  )
}
