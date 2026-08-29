import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const readJson = async (path) => JSON.parse(await readFile(resolve(root, path), 'utf8'));

const candidates = await readJson('research/xiaohongshu/candidate-pool.json');
const deepRead = await readJson('research/xiaohongshu/deep-read.json');
const poseFamilies = await readJson('research/xiaohongshu/pose-families.json');

// These mappings only choose which already-observed search cards to open next.
// They never assert that a card contains the target action.
const targetConfigs = [
  { familyId: 'standing-look-back-one-hand-pocket', query: '回眸拍照姿势单人', boostQueries: ['靠墙插兜拍照姿势'], titleHintPattern: /回眸|回头|回身|背影|插兜|口袋/, limit: 20 },
  { familyId: 'one-hand-in-pocket', query: '靠墙插兜拍照姿势', titleHintPattern: /单手|一手|插兜|口袋|裤兜/, limit: 20 },
  { familyId: 'standing-one-arm-up', query: '手部动作拍照姿势', titleHintPattern: /举手|抬手|伸手|手臂|手势|动作/, limit: 20 },
  { familyId: 'crossed-arms-standing', query: '抱臂站姿拍照姿势', titleHintPattern: /抱臂|抱胸|交叉|站姿|站着|靠墙|男生.*(?:姿势|动作)/, limit: 20 },
  { familyId: 'side-lean-arms-open', query: '张开双臂拍照姿势', titleHintPattern: /张开|双臂|手臂|拥抱|海边|大海|草原|雪山|湖边/, limit: 20 },
  { familyId: 'back-facing-arms-open', query: '张开双臂拍照姿势', titleHintPattern: /张开|双臂|手臂|拥抱|背影|海边|大海|草原|雪山|湖边/, limit: 20 },
  { familyId: 'wall-lean-body-side-one-hand-pocket', query: '靠墙插兜拍照姿势', titleHintPattern: /靠墙|插兜|口袋|墙边|墙面/, limit: 20 },
];

const compilationTitlePattern = /合集|大全|存一些|199|九个|9个|16个|照搬|模板/;
const repostRiskPattern = /审美提升|图源|转载|搬运|存图/;
const familyById = new Map(poseFamilies.families.map((family) => [family.familyId, family]));
const queuedByNote = new Map();

const scoreCandidate = (candidate, qualifyingCreatorIds, titleHintPattern, boostQueries = []) => {
  const hasStableCreatorId = typeof candidate.creatorId === 'string' && candidate.creatorId.length > 0;
  const creatorIsNewForFamily = hasStableCreatorId && !qualifyingCreatorIds.has(candidate.creatorId);
  const titleHintMatch = titleHintPattern.test(candidate.title);
  const queryOverlapCount = boostQueries.filter((query) => candidate.observedQueries.includes(query)).length;
  const titleRiskFlags = [
    compilationTitlePattern.test(candidate.title) ? 'possible-compilation-title' : null,
    repostRiskPattern.test(candidate.title) ? 'possible-repost-title' : null,
  ].filter(Boolean);
  return { hasStableCreatorId, creatorIsNewForFamily, queryOverlapCount, titleHintMatch, titleRiskFlags };
};

const compareCandidates = (left, right) =>
  Number(right.score.creatorIsNewForFamily) - Number(left.score.creatorIsNewForFamily)
  || Number(right.score.hasStableCreatorId) - Number(left.score.hasStableCreatorId)
  || right.score.queryOverlapCount - left.score.queryOverlapCount
  || Number(right.score.titleHintMatch) - Number(left.score.titleHintMatch)
  || left.score.titleRiskFlags.length - right.score.titleRiskFlags.length
  || String(left.candidate.firstObservedAt ?? '').localeCompare(String(right.candidate.firstObservedAt ?? ''))
  || left.candidate.noteId.localeCompare(right.candidate.noteId);

const targetSnapshots = [];
for (const config of targetConfigs) {
  const family = familyById.get(config.familyId);
  if (!family || family.status !== 'needs-evidence') continue;
  const qualifyingCreatorIds = new Set(family.sources
    .filter((source) => source.qualifiesForAdmission)
    .map((source) => source.creatorId)
    .filter(Boolean));
  const ranked = candidates.items
    .filter((candidate) => !candidate.openedAndRead && candidate.observedQueries.includes(config.query))
    .map((candidate) => ({ candidate, score: scoreCandidate(candidate, qualifyingCreatorIds, config.titleHintPattern, config.boostQueries) }))
    .sort(compareCandidates)
    .slice(0, config.limit);

  targetSnapshots.push({
    familyId: family.familyId,
    query: config.query,
    qualifyingPostCount: family.qualifyingPostCount,
    qualifyingCreatorCount: family.qualifyingCreatorCount,
    missingQualifyingPosts: family.missingQualifyingPosts,
    missingQualifyingCreators: family.missingQualifyingCreators,
    queuedCandidateCount: ranked.length,
  });

  for (const { candidate, score } of ranked) {
    const existing = queuedByNote.get(candidate.noteId);
    if (existing) {
      existing.targetFamilyIds.push(family.familyId);
      if (!existing.matchedQueries.includes(config.query)) existing.matchedQueries.push(config.query);
      continue;
    }
    queuedByNote.set(candidate.noteId, {
      noteId: candidate.noteId,
      title: candidate.title,
      creatorDisplay: candidate.creatorDisplay,
      creatorId: candidate.creatorId ?? null,
      canonicalUrl: candidate.canonicalUrl,
      matchedQueries: [config.query],
      targetFamilyIds: [family.familyId],
      prioritySignals: score,
      basis: 'search-query-relevance-only',
      reviewStatus: 'unopened-not-evidence',
      requiredChecks: [
        'open-detail-page',
        'confirm-visible-real-human-action',
        'exclude-ai-or-synthetic-imagery',
        'exclude-unattributed-compilation-or-repost',
        'record-stable-creator-id',
        'record-body-visual-relations-and-visible-comments-separately',
      ],
    });
  }
}

const queue = Array.from(queuedByNote.values())
  .sort((left, right) => {
    const leftTarget = targetSnapshots.findIndex((target) => left.targetFamilyIds.includes(target.familyId));
    const rightTarget = targetSnapshots.findIndex((target) => right.targetFamilyIds.includes(target.familyId));
    return leftTarget - rightTarget
      || Number(right.prioritySignals.creatorIsNewForFamily) - Number(left.prioritySignals.creatorIsNewForFamily)
      || Number(right.prioritySignals.hasStableCreatorId) - Number(left.prioritySignals.hasStableCreatorId)
      || right.prioritySignals.queryOverlapCount - left.prioritySignals.queryOverlapCount
      || Number(right.prioritySignals.titleHintMatch) - Number(left.prioritySignals.titleHintMatch)
      || left.prioritySignals.titleRiskFlags.length - right.prioritySignals.titleRiskFlags.length
      || left.noteId.localeCompare(right.noteId);
  })
  .map((item, index) => ({ priority: index + 1, ...item }));

const result = {
  schemaVersion: 1,
  generatedAt: deepRead.capturedAt,
  purpose: 'Prioritize which unopened Xiaohongshu candidates to deep-read next. Queue membership is never pose evidence.',
  evidenceBoundary: 'Titles, search queries, engagement and queue priority cannot qualify a pose family. Only a saved detail-page review may change admission counts.',
  sourceSnapshot: {
    uniqueCandidates: candidates.uniqueNotes,
    deepReadCount: deepRead.count,
    observedFamilies: poseFamilies.counts.observedFamilies,
  },
  targetSnapshots,
  count: queue.length,
  items: queue,
};

await writeFile(
  resolve(root, 'research/xiaohongshu/next-deep-read-queue.json'),
  `${JSON.stringify(result, null, 2)}\n`,
);
console.log(`Research queue planned: ${queue.length} unopened candidates across ${targetSnapshots.length} near-admission families.`);
