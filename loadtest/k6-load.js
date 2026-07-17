// Full load profile: warm-up → steady state → 5x traffic spike → sustained peak.
// Run against the cloud:   k6 run -e BASE_URL=http://<nlb-hostname> loadtest/k6-load.js
// While it runs, watch the HPA react:   make watch-scaling
import http from 'k6/http'
import { check, sleep } from 'k6'

const BASE = __ENV.BASE_URL || 'http://localhost:3000'

export const options = {
  scenarios: {
    traffic: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 30 }, // warm up
        { duration: '2m', target: 30 }, // steady state
        { duration: '1m', target: 150 }, // rush-hour spike (5x)
        { duration: '2m', target: 150 }, // sustained peak — HPA scales out here
        { duration: '1m', target: 0 }, // cool down — watch scale-in after ~2 min
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<800'],
  },
}

const plausibleMs = () => 140 + Math.floor(Math.random() * 420)
const randomPlayer = () => `bot-${Math.floor(Math.random() * 500)}`

export default function () {
  // Realistic mix: mostly reads (viewing the board), some writes (submitting scores).
  if (Math.random() < 0.7) {
    const res = http.get(`${BASE}/api/leaderboard?limit=10`)
    check(res, { 'leaderboard 200': (r) => r.status === 200 })
  } else {
    const res = http.post(
      `${BASE}/api/scores`,
      JSON.stringify({ player: randomPlayer(), score_ms: plausibleMs() }),
      { headers: { 'Content-Type': 'application/json' } },
    )
    check(res, { 'submit 200': (r) => r.status === 200 })
  }
  sleep(0.3 + Math.random())
}
