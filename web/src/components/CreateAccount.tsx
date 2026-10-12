import { useState } from 'react'
import { createAccount, type Account } from '../api'

interface Props {
  accounts: Account[]
  onCreated: (account: Account) => void
}

export default function CreateAccount({ accounts, onCreated }: Props) {
  const [name, setName] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) return
    setLoading(true)
    setError(null)
    try {
      const account = await createAccount(name.trim())
      onCreated(account)
      setName('')
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="panel">
      <h2>Create Account</h2>
      <form onSubmit={handleSubmit}>
        <input
          type="text"
          placeholder="Account name"
          value={name}
          onChange={e => setName(e.target.value)}
          disabled={loading}
        />
        <button type="submit" disabled={loading || !name.trim()}>
          {loading ? 'Creating...' : 'Create'}
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      {accounts.length > 0 && (
        <div className="account-list">
          <h3>Accounts</h3>
          <table>
            <thead>
              <tr><th>ID</th><th>Name</th></tr>
            </thead>
            <tbody>
              {accounts.map(a => (
                <tr key={a.id}><td>{a.id}</td><td>{a.name}</td></tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
