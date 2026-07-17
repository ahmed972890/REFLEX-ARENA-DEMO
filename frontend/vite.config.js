import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// `npm run dev` proxies /api to a locally running backend (uvicorn or compose).
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': process.env.VITE_API_PROXY || 'http://localhost:8000',
    },
  },
})
