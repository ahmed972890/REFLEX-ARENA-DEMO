// 30-second smoke test: is the stack up and fast under light traffic?
//   k6 run -e BASE_URL=http://localhost:3000 loadtest/k6-smoke.js
import http from 'k6/http'
import { check, sleep } from 'k6'

const BASE = __ENV.BASE_URL || 'http://localhost:3000'

export const options = {
  vus: 5,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
}

export default function () {
  const board = http.get(`${BASE}/api/leaderboard?limit=10`)
  check(board, { 'leaderboard 200': (r) => r.status === 200 })

  const submit = http.post(
    `${BASE}/api/scores`,
    JSON.stringify({ player: `smoke-${__VU}`, score_ms: 150 + Math.floor(Math.random() * 300) }),
    { headers: { 'Content-Type': 'application/json' } },
  )
  check(submit, { 'submit 200': (r) => r.status === 200 })

  sleep(1)
}
