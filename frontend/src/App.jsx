import { useCallback, useEffect, useState } from 'react'
import Game from './Game.jsx'
import Leaderboard from './Leaderboard.jsx'
import { getStats } from './api.js'

export default function App() {
  const [refreshKey, setRefreshKey] = useState(0)
  const [stats, setStats] = useState(null)

  const onSubmitted = useCallback(() => setRefreshKey((k) => k + 1), [])

  useEffect(() => {
    let cancelled = false
    const load = () => {
      if (document.hidden) return
      getStats()
        .then((s) => !cancelled && setStats(s))
        .catch(() => {})
    }
    load()
    const interval = setInterval(load, 15000)
    return () => {
      cancelled = true
      clearInterval(interval)
    }
  }, [refreshKey])

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-bolt">⚡</span>
          <div>
            <h1>Reflex Arena</h1>
            <p>How fast are you, really?</p>
          </div>
        </div>
        {stats && (
          <div className="stats-chip" title="Live from /api/stats">
            <strong>{stats.players}</strong> players · <strong>{stats.total_submissions}</strong>{' '}
            attempts
          </div>
        )}
      </header>

      <main className="layout">
        <Game onSubmitted={onSubmitted} />
        <Leaderboard refreshKey={refreshKey} />
      </main>

      <footer className="footer">
        Click when the panel turns green · 5 rounds · your <em>average</em> goes on the board
      </footer>
    </div>
  )
}
