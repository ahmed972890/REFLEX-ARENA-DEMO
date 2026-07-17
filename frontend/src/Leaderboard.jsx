import { useEffect, useState } from 'react'
import { getLeaderboard } from './api.js'

const MEDALS = ['🥇', '🥈', '🥉']

export default function Leaderboard({ refreshKey }) {
  const [entries, setEntries] = useState([])
  const [error, setError] = useState(false)
  const myName = (localStorage.getItem('reflex-player-name') || '').toLowerCase()

  useEffect(() => {
    let cancelled = false
    const load = () => {
      if (document.hidden) return
      getLeaderboard(10)
        .then((body) => {
          if (!cancelled) {
            setEntries(body.entries)
            setError(false)
          }
        })
        .catch(() => !cancelled && setError(true))
    }
    load()
    const interval = setInterval(load, 5000)
    return () => {
      cancelled = true
      clearInterval(interval)
    }
  }, [refreshKey])

  return (
    <aside className="card board-card">
      <div className="board-head">
        <h2>Leaderboard</h2>
        <span className={error ? 'live live-down' : 'live'}>
          <span className="live-dot" /> {error ? 'reconnecting' : 'live'}
        </span>
      </div>

      {error && entries.length === 0 && (
        <p className="board-empty">Leaderboard unavailable — retrying…</p>
      )}
      {!error && entries.length === 0 && (
        <p className="board-empty">No scores yet. Be the first!</p>
      )}

      <ol className="board-list">
        {entries.map((entry) => (
          <li
            key={entry.player}
            className={entry.player.toLowerCase() === myName ? 'row row-me' : 'row'}
          >
            <span className="row-rank">{MEDALS[entry.rank - 1] || `${entry.rank}.`}</span>
            <span className="row-name">{entry.player}</span>
            <span className="row-games">{entry.games} games</span>
            <span className="row-ms">{entry.best_ms} ms</span>
          </li>
        ))}
      </ol>
    </aside>
  )
}
