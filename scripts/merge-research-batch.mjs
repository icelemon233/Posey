import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const candidatePath = resolve(root, 'research/xiaohongshu/candidate-pool.json');
const deepReadPath = resolve(root, 'research/xiaohongshu/deep-read.json');

export async function mergeCandidateBatch({ query, capturedAt, items }) {
  if (!query || !Array.isArray(items)) throw new Error('query and items are required');

  const pool = JSON.parse(await readFile(candidatePath, 'utf8'));
  const validItems = items.filter((item) => item.noteId && item.title && item.capturedUrl);
  const seenInQuery = new Map(validItems.map((item) => [item.noteId, item]));
  const existingById = new Map(pool.items.map((item) => [item.noteId, item]));
  const existingBefore = new Set(existingById.keys());

  for (const item of pool.items) {
    item.observedQueries = Array.from(new Set([...(item.observedQueries ?? []), item.query].filter(Boolean)));
  }

  for (const incoming of seenInQuery.values()) {
    const existing = existingById.get(incoming.noteId);
    if (existing) {
      existing.observedQueries = Array.from(new Set([...(existing.observedQueries ?? []), query]));
      existing.latestCapturedUrl = incoming.capturedUrl;
      existing.lastObservedAt = capturedAt;
      if (!existing.creatorDisplay && incoming.creatorDisplay) existing.creatorDisplay = incoming.creatorDisplay;
      if (!existing.creatorId && incoming.creatorId) existing.creatorId = incoming.creatorId;
      if (!existing.engagementVisible && incoming.engagementVisible) existing.engagementVisible = incoming.engagementVisible;
      continue;
    }

    const next = {
      query,
      observedQueries: [query],
      title: incoming.title,
      creatorDisplay: incoming.creatorDisplay ?? '',
      creatorId: incoming.creatorId ?? null,
      noteId: incoming.noteId,
      canonicalUrl: `https://www.xiaohongshu.com/explore/${incoming.noteId}`,
      capturedUrl: incoming.capturedUrl,
      engagementVisible: incoming.engagementVisible ?? '',
      openedAndRead: false,
      firstObservedAt: capturedAt,
      lastObservedAt: capturedAt,
    };
    pool.items.push(next);
    existingById.set(next.noteId, next);
  }

  const existingQuery = pool.queries.find((entry) => entry.query === query);
  const querySummary = {
    query,
    count: seenInQuery.size,
    examples: Array.from(seenInQuery.values()).slice(0, 4).map((item) => item.title),
    capturedAt,
  };
  if (existingQuery) Object.assign(existingQuery, querySummary);
  else pool.queries.push(querySummary);

  pool.capturedAt = capturedAt.slice(0, 10);
  pool.uniqueNotes = pool.items.length;
  pool.totalAppearances = pool.queries.reduce((sum, entry) => sum + entry.count, 0);
  pool.method = 'Chrome signed-in UI search results; search cards observed, not necessarily opened; observedQueries retains repeated query exposure';

  await writeFile(candidatePath, `${JSON.stringify(pool, null, 2)}\n`);
  return {
    query,
    observed: seenInQuery.size,
    added: Array.from(seenInQuery.keys()).filter((id) => !existingBefore.has(id)).length,
    uniqueNotes: pool.uniqueNotes,
    totalAppearances: pool.totalAppearances,
  };
}

export async function mergeDeepReadRecord(record) {
  if (!record?.noteId || !record?.openedAndRead) throw new Error('a read noteId is required');

  const [pool, deepRead] = await Promise.all([
    readFile(candidatePath, 'utf8').then(JSON.parse),
    readFile(deepReadPath, 'utf8').then(JSON.parse),
  ]);
  const candidate = pool.items.find((item) => item.noteId === record.noteId);
  if (!candidate) throw new Error(`deep-read note ${record.noteId} is missing from candidate pool`);

  const normalized = {
    ...record,
    query: record.query || candidate.query,
    title: record.title || candidate.title,
    creatorDisplay: record.creatorDisplay || candidate.creatorDisplay,
    canonicalUrl: candidate.canonicalUrl,
    capturedUrl: record.capturedUrl || candidate.latestCapturedUrl || candidate.capturedUrl,
    usageStatus: 'research-only',
  };
  const index = deepRead.records.findIndex((item) => item.noteId === record.noteId);
  if (index >= 0) deepRead.records[index] = { ...deepRead.records[index], ...normalized };
  else deepRead.records.push(normalized);

  candidate.openedAndRead = true;
  candidate.lastOpenedAt = record.capturedAt;
  deepRead.count = deepRead.records.length;
  deepRead.capturedAt = record.capturedAt.slice(0, 10);
  deepRead.method = 'Each record was opened in a real browser detail page. New records use accessContext to distinguish signed-in, anonymous, or other access; legacy records without that field remain explicitly unspecified. Rendered body, visible comments, and visual pose relations were recorded separately. Screenshots are research-only.';

  await Promise.all([
    writeFile(candidatePath, `${JSON.stringify(pool, null, 2)}\n`),
    writeFile(deepReadPath, `${JSON.stringify(deepRead, null, 2)}\n`),
  ]);
  return { noteId: record.noteId, deepReads: deepRead.count };
}
