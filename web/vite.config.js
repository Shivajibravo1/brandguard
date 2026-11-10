import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// envDir points at the project root so the app reads the single shared .env
// (only variables prefixed with VITE_ are exposed to the browser).
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '..', 'VITE_')
  const api = new URL(env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321')
  const wsApi = `${api.protocol === 'https:' ? 'wss:' : 'ws:'}//${api.host}`

  // Content Security Policy (CSP): the browser only loads code, styles,
  // fonts and data from the places listed here, which blocks most cross-site
  // scripting (XSS) and data theft. OWASP Top 10 A03 and A05.
  const csp = (scriptSrc) => [
    "default-src 'self'",
    `script-src ${scriptSrc}`,
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' https://fonts.gstatic.com",
    "img-src 'self' data:",
    `connect-src 'self' ${api.origin} ${wsApi}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join('; ')

  const common = {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
    'Cross-Origin-Opener-Policy': 'same-origin',
  }

  return {
    plugins: [react(), tailwindcss()],
    envDir: '..',
    build: { sourcemap: false },
    // Development server: the React fast-refresh tool needs one inline script
    // and a live-reload connection, so the policy is slightly relaxed here.
    server: {
      port: 5173,
      strictPort: true,
      host: '127.0.0.1',
      headers: { ...common, 'Content-Security-Policy': csp("'self' 'unsafe-inline'").replace("connect-src 'self'", "connect-src 'self' ws://127.0.0.1:5173 ws://localhost:5173") },
    },
    // Production-like preview of the built app: strict policy, scripts from this site only
    preview: {
      port: 4173,
      strictPort: true,
      host: '127.0.0.1',
      headers: { ...common, 'Content-Security-Policy': csp("'self'") },
    },
  }
})
