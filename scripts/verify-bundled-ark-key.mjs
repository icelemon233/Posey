import { readdir, readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function normalizeApiKey(value) {
  return value
    .replace(/^ARK_API_KEY\s*=\s*/, '')
    .replace(/[\s\u200B-\u200D\uFEFF]/g, '');
}

let raw = process.env.ARK_API_KEY || '';
if (!raw) raw = await readFile(resolve(projectRoot, 'doubao-api-key.txt'), 'utf8');
const apiKey = normalizeApiKey(raw);
if (!apiKey) throw new Error('火山方舟 API Key 为空');

const assetsDir = resolve(projectRoot, 'dist/assets');
const scripts = (await readdir(assetsDir)).filter((name) => name.endsWith('.js'));
const bundles = await Promise.all(scripts.map((name) => readFile(resolve(assetsDir, name), 'utf8')));
if (!bundles.some((bundle) => bundle.includes(apiKey))) {
  throw new Error('生产包未包含火山方舟 API Key，停止后续原生同步');
}
console.log('生产包火山方舟 API Key 注入校验通过');
