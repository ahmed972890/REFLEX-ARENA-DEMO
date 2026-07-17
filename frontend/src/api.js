async function request(path, options) {
  const response = await fetch(path, options)
  if (!response.ok) {
    let detail
    try {
      detail = (await response.json()).detail
    } catch {
      /* non-JSON error body */
    }
    throw new Error(detail ? JSON.stringify(detail) : `HTTP ${response.status}`)
  }
  return response.json()
}

export const getLeaderboard = (limit = 10) => request(`/api/leaderboard?limit=${limit}`)

export const getStats = () => request('/api/stats')

export const submitScore = (player, scoreMs) =>
  request('/api/scores', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ player, score_ms: scoreMs }),
  })
