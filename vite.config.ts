import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = dirname(fileURLToPath(import.meta.url));

function bundledArkApiKey() {
  let raw = process.env.ARK_API_KEY || '';
  if (!raw) {
    try { raw = readFileSync(resolve(projectRoot, 'doubao-api-key.txt'), 'utf8'); } catch { /* checked below */ }
  }
  return raw
    .replace(/^ARK_API_KEY\s*=\s*/, '')
    .replace(/[\s\u200B-\u200D\uFEFF]/g, '');
}

export default defineConfig(({ command }) => {
  const isPublicWebBuild = process.env.POSEY_PUBLIC_BUILD === 'true';
  const apiKey = isPublicWebBuild ? '' : bundledArkApiKey();
  if (command === 'build' && !isPublicWebBuild && !apiKey) {
    throw new Error('缺少 doubao-api-key.txt，无法构建 AI Pose 真机包');
  }
  return {
    base: process.env.POSEY_PUBLIC_BASE || '/',
    plugins: [react()],
    define: {
      'import.meta.env.VITE_ARK_API_KEY': JSON.stringify(apiKey),
      'import.meta.env.VITE_ARK_API_URL': JSON.stringify('https://ark.cn-beijing.volces.com/api/v3'),
      'import.meta.env.VITE_ARK_IMAGE_MODEL': JSON.stringify('doubao-seedream-5-0-pro-260628'),
    },
    server: { host: '127.0.0.1', port: 4173 },
    preview: { host: '127.0.0.1', port: 4173 },
  };
});
