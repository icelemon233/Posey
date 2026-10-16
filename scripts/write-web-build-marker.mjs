import { writeFileSync } from 'node:fs';

const sourceRevision = process.env.GITHUB_SHA?.trim();

if (!sourceRevision || !/^[0-9a-f]{40}$/i.test(sourceRevision)) {
  throw new Error('GITHUB_SHA must be a full Git commit SHA');
}

writeFileSync(new URL('../web/dist/.source-version', import.meta.url), `${sourceRevision}\n`);
