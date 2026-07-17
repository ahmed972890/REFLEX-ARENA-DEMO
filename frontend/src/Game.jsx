import { useEffect, useRef, useState } from 'react'
import { submitScore } from './api.js'

const ROUNDS = 5
const NAME_KEY = 'reflex-player-name'

export default function Game({ onSubmitted }) {
  const [phase, setPhase] = useState('idle') // idle | waiting | go | roundResult | falseStart | done
  const [times, setTimes] = useState([])
  const [lastTime, setLastTime] = useState(null)
  const [name, setName] = useState(() => localStorage.getItem(NAME_KEY) || '')
  const [submitting, setSubmitting] = useState(false)
  const [submitResult, setSubmitResult] = useState(null)
  const [submitError, setSubmitError] = useState(null)

  const timerRef = useRef(null)
  const goTimeRef = useRef(0)

  useEffect(() => () => clearTimeout(timerRef.current), [])

  const armRound = () => {
    setPhase('waiting')
    timerRef.current = setTimeout(
      () => {
        goTimeRef.current = performance.now()
        setPhase('go')
      },
      1200 + Math.random() * 2600,
    )
  }

  const start = () => {
    setTimes([])
    setLastTime(null)
    setSubmitResult(null)
    setSubmitError(null)
    armRound()
  }

  const handlePanel = () => {
    if (phase === 'waiting') {
      clearTimeout(timerRef.current)
      setPhase('falseStart')
      timerRef.current = setTimeout(armRound, 1100)
      return
    }
    if (phase === 'go') {
      const elapsed = Math.round(performance.now() - goTimeRef.current)
      const nextTimes = [...times, elapsed]
      setTimes(nextTimes)
      setLastTime(elapsed)
      if (nextTimes.length >= ROUNDS) {
        setPhase('done')
      } else {
        setPhase('roundResult')
        timerRef.current = setTimeout(armRound, 900)
      }
    }
  }

  const average = times.length ? Math.round(times.reduce((a, b) => a + b, 0) / times.length) : null
  const best = times.length ? Math.min(...times) : null

  const submit = async (event) => {
    event.preventDefault()
    const trimmed = name.trim()
    if (trimmed.length < 2 || submitting) return
    localStorage.setItem(NAME_KEY, trimmed)
    setSubmitting(true)
    setSubmitError(null)
    try {
      const result = await submitScore(trimmed, average)
      setSubmitResult(result)
      onSubmitted()
    } catch (error) {
      setSubmitError(String(error.message || error))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className="card game-card">
      {phase === 'idle' && (
        <div className="panel panel-idle" onPointerDown={start} role="button" tabIndex={0}>
          <span className="panel-big">Start</span>
          <span className="panel-sub">{ROUNDS} rounds · click when it turns green</span>
        </div>
      )}

      {phase === 'waiting' && (
        <div className="panel panel-wait" onPointerDown={handlePanel}>
          <span className="panel-big">Wait…</span>
          <span className="panel-sub">green means go</span>
        </div>
      )}

      {phase === 'go' && (
        <div className="panel panel-go" onPointerDown={handlePanel}>
          <span className="panel-big">CLICK!</span>
        </div>
      )}

      {phase === 'falseStart' && (
        <div className="panel panel-false">
          <span className="panel-big">Too soon!</span>
          <span className="panel-sub">that round restarts…</span>
        </div>
      )}

      {phase === 'roundResult' && (
        <div className="panel panel-result">
          <span className="panel-ms">{lastTime}</span>
          <span className="panel-sub">ms</span>
        </div>
      )}

      {phase === 'done' && (
        <div className="panel panel-done">
          <div className="score-line">
            <div>
              <span className="panel-ms">{average}</span>
              <span className="panel-sub"> ms average</span>
            </div>
            <span className="best-line">best round: {best} ms</span>
          </div>

          {submitResult ? (
            <div className={submitResult.improved ? 'banner banner-good' : 'banner'}>
              {submitResult.improved
                ? `New personal best — you're #${submitResult.rank} 🎉`
                : `Your record stays at ${submitResult.best_ms} ms (rank #${submitResult.rank})`}
              <button className="btn btn-ghost" onPointerDown={start}>
                Play again
              </button>
            </div>
          ) : (
            <form className="submit-row" onSubmit={submit}>
              <input
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="Your name"
                maxLength={20}
                minLength={2}
                pattern="[A-Za-z0-9 _\-]+"
                title="2–20 letters, digits, spaces, - or _"
                required
              />
              <button className="btn" type="submit" disabled={submitting}>
                {submitting ? 'Saving…' : 'Submit score'}
              </button>
              <button className="btn btn-ghost" type="button" onPointerDown={start}>
                Retry
              </button>
            </form>
          )}
          {submitError && <div className="banner banner-bad">Could not save: {submitError}</div>}
        </div>
      )}

      <div className="rounds-dots" aria-label="round progress">
        {Array.from({ length: ROUNDS }, (_, index) => (
          <span key={index} className={index < times.length ? 'dot dot-on' : 'dot'}>
            {index < times.length ? `${times[index]}` : '·'}
          </span>
        ))}
      </div>
    </section>
  )
}
