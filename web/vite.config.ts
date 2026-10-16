import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  base: process.env.POSEY_PUBLIC_BASE || '/',
  plugins: [react()],
  define: {
    // Browser builds never bundle provider credentials; configure a key in Settings.
    'import.meta.env.VITE_ARK_API_KEY': JSON.stringify(''),
    'import.meta.env.VITE_ARK_API_URL': JSON.stringify('https://ark.cn-beijing.volces.com/api/v3'),
    'import.meta.env.VITE_ARK_IMAGE_MODEL': JSON.stringify('doubao-seedream-5-0-pro-260628'),
  },
  server: { host: '127.0.0.1', port: 4173 },
  preview: { host: '127.0.0.1', port: 4173 },
});
