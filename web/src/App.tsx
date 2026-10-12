import { useState } from 'react'
import { createAccount, type Account } from './api'

function App() {
  const [result, setResult] = useState<Account | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleClick() {
    setLoading(true)
    setError(null)
    try {
      const account = await createAccount(`test-${Date.now()}`)
      setResult(account)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ padding: "2rem", fontFamily: "monospace" }}>
      <h1>Ledger — CORS test</h1>
      <button onClick={handleClick} disabled={loading}>
        {loading ? "Creating..." : "Create test account"}
      </button>
      {result && (
        <pre style={{ marginTop: "1rem" }}>
          {JSON.stringify(result, null, 2)}
        </pre>
      )}
      {error && (
        <p style={{ color: "red", marginTop: "1rem" }}>{error}</p>
      )}
    </div>
  )
}

export default App
