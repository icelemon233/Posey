import { readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const deepReadPath = resolve(root, 'research/xiaohongshu/deep-read.json');
const outputPath = resolve(root, 'research/xiaohongshu/pose-families.json');
const parameterizationDir = resolve(root, 'research/pose-parameterizations');
const deepRead = JSON.parse(await readFile(deepReadPath, 'utf8'));
const parameterizationFiles = await readdir(parameterizationDir).catch(() => []);
const parameterizations = new Map(await Promise.all(parameterizationFiles
  .filter((file) => file.endsWith('.json'))
  .map(async (file) => {
    const data = JSON.parse(await readFile(resolve(parameterizationDir, file), 'utf8'));
    return [data.id, { file, data }];
  })));
const sourceTimestamps = deepRead.records
  .filter((record) => (record.analysis?.candidateFamilies ?? []).length > 0)
  .map((record) => record.capturedAt)
  .filter(Boolean)
  .sort();

const byFamily = new Map();
for (const record of deepRead.records) {
  const families = Array.from(new Set(record.analysis?.candidateFamilies ?? []));
  for (const familyId of families) {
    const sources = byFamily.get(familyId) ?? [];
    sources.push({
      noteId: record.noteId,
      creatorId: record.creatorId ?? null,
      creatorDisplay: record.creatorDisplay,
      canonicalUrl: record.canonicalUrl,
      evidenceLevel: record.analysis?.evidenceLevel ?? 'unclassified',
      qualifiesForAdmission: record.analysis?.qualifiesForPoseAdmission !== false
        && ['body-and-screenshot', 'screenshot'].includes(record.analysis?.evidenceLevel),
      exclusionReason: record.analysis?.qualifiesForPoseAdmission === false
        ? record.analysis?.exclusionReason ?? 'unspecified-manual-exclusion'
        : null,
      screenshotPath: record.screenshotPath,
    });
    byFamily.set(familyId, sources);
  }
}

const families = Array.from(byFamily, ([familyId, sources]) => {
  const qualifying = sources.filter((source) => source.qualifiesForAdmission);
  const qualifyingNotes = new Set(qualifying.map((source) => source.noteId));
  const qualifyingCreators = new Set(qualifying.map((source) => source.creatorId).filter(Boolean));
  const sourceReady = qualifyingNotes.size >= 5 && qualifyingCreators.size >= 3;
  const draft = parameterizations.get(familyId);
  return {
    familyId,
    status: sourceReady ? 'ready-for-parameterization' : qualifying.length ? 'needs-evidence' : 'excluded-only',
    researchObservationCount: new Set(sources.map((source) => source.noteId)).size,
    qualifyingPostCount: qualifyingNotes.size,
    qualifyingCreatorCount: qualifyingCreators.size,
    missingQualifyingPosts: Math.max(0, 5 - qualifyingNotes.size),
    missingQualifyingCreators: Math.max(0, 3 - qualifyingCreators.size),
    sources,
    parameterization: {
      artifactPath: draft ? `research/pose-parameterizations/${draft.file}` : null,
      landmarks33: draft && Object.keys(draft.data.landmarks ?? {}).length === 33 ? 'draft-owned-abstract' : 'pending-authorized-reference',
      guideContour: draft?.data.guideContour?.length ? 'draft-owned-abstract' : 'pending-authorized-reference',
      keyRelations: draft?.data.relations?.length ? 'draft-research-derived' : 'pending-evidence-admission',
      toleranceRanges: draft?.data.tolerancePresets ? 'draft-awaiting-real-device-calibration' : 'pending-real-device-calibration',
      realDeviceAcceptance: 'pending',
    },
  };
}).sort((a, b) => b.qualifyingPostCount - a.qualifyingPostCount || a.familyId.localeCompare(b.familyId));

const result = {
  generatedAt: sourceTimestamps.at(-1) ?? deepRead.capturedAt,
  scope: 'Research-derived single-person pose-family candidates. Research screenshots never grant product usage rights.',
  deduplicationRule: {
    mirroredVariantsCountAsSameFamily: true,
    cropVariantsCountAsSameFamily: true,
    microJointChangesCountAsSameFamily: true,
    combinedActionRelationsMayFormADistinctFamily: true,
  },
  admissionRule: {
    minimumIndependentPosts: 5,
    minimumStableCreatorIdentities: 3,
    requiresIndependentContentReview: true,
    requiredEvidence: ['body-and-screenshot', 'screenshot'],
    excludedEvidence: [
      'creator-claim-ai-assisted',
      'syndicated-or-reposted-source',
      'explicit-negative-example',
      'unseen-video-action',
      'title-only',
      'search-card-only',
    ],
  },
  counts: {
    observedFamilies: families.length,
    readyForParameterization: families.filter((family) => family.status === 'ready-for-parameterization').length,
    needsEvidence: families.filter((family) => family.status === 'needs-evidence').length,
    excludedOnly: families.filter((family) => family.status === 'excluded-only').length,
    parameterizationDrafts: parameterizations.size,
    targetFamilies: 300,
  },
  families,
};

await writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`);
console.log(`Pose families built: ${result.counts.observedFamilies} observed, ${result.counts.readyForParameterization} ready, ${result.counts.excludedOnly} excluded-only.`);
