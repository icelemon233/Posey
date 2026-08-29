import { readFile, access, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const readJson = async (path) => JSON.parse(await readFile(resolve(root, path), 'utf8'));
const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};

const candidates = await readJson('research/xiaohongshu/candidate-pool.json');
const deepRead = await readJson('research/xiaohongshu/deep-read.json');
const evidence = await readJson('research/xiaohongshu/template-evidence.json');
const poseFamilies = await readJson('research/xiaohongshu/pose-families.json');
const researchQueue = await readJson('research/xiaohongshu/next-deep-read-queue.json');
const mediaPipe33 = [
  'nose', 'leftEyeInner', 'leftEye', 'leftEyeOuter', 'rightEyeInner', 'rightEye', 'rightEyeOuter',
  'leftEar', 'rightEar', 'leftMouth', 'rightMouth', 'leftShoulder', 'rightShoulder', 'leftElbow',
  'rightElbow', 'leftWrist', 'rightWrist', 'leftPinky', 'rightPinky', 'leftIndex', 'rightIndex',
  'leftThumb', 'rightThumb', 'leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle',
  'rightAnkle', 'leftHeel', 'rightHeel', 'leftFootIndex', 'rightFootIndex',
];

assert(candidates.items.length === candidates.uniqueNotes, 'candidate uniqueNotes does not match items');
assert(new Set(candidates.items.map((item) => item.noteId)).size === candidates.items.length, 'candidate note ids are not unique');
assert(candidates.totalAppearances === candidates.queries.reduce((sum, query) => sum + query.count, 0), 'candidate totalAppearances does not match query counts');
assert(candidates.items.every((item) => Array.isArray(item.observedQueries) && item.observedQueries.includes(item.query)), 'candidate observedQueries is incomplete');
assert(deepRead.records.length === deepRead.count, 'deep-read count does not match records');
assert(new Set(deepRead.records.map((item) => item.noteId)).size === deepRead.records.length, 'deep-read note ids are not unique');
assert(deepRead.records.every((item) => item.openedAndRead), 'deep-read contains a record that was not opened');
assert(deepRead.records.every((item) => item.analysis?.qualifiesForPoseAdmission !== false
  || (typeof item.analysis?.exclusionReason === 'string' && item.analysis.exclusionReason.length > 0)), 'excluded deep-read record is missing an exclusion reason');

const candidateById = new Map(candidates.items.map((item) => [item.noteId, item]));
const deepById = new Map(deepRead.records.map((item) => [item.noteId, item]));
for (const record of deepRead.records) {
  const candidate = candidateById.get(record.noteId);
  assert(candidate, `deep-read note ${record.noteId} is missing from candidate pool`);
  assert(candidate.openedAndRead, `candidate ${record.noteId} is not marked openedAndRead`);
}
for (const candidate of candidates.items.filter((item) => item.openedAndRead)) {
  assert(deepById.has(candidate.noteId), `opened candidate ${candidate.noteId} is missing from deep-read`);
}

assert(researchQueue.count === researchQueue.items.length, 'research queue count does not match items');
assert(new Set(researchQueue.items.map((item) => item.noteId)).size === researchQueue.items.length, 'research queue note ids are not unique');
assert(researchQueue.sourceSnapshot.uniqueCandidates === candidates.uniqueNotes, 'research queue candidate snapshot is stale');
assert(researchQueue.sourceSnapshot.deepReadCount === deepRead.count, 'research queue deep-read snapshot is stale');
assert(researchQueue.sourceSnapshot.observedFamilies === poseFamilies.counts.observedFamilies, 'research queue family snapshot is stale');
for (const [index, item] of researchQueue.items.entries()) {
  const candidate = candidateById.get(item.noteId);
  assert(candidate, `research queue references unknown candidate ${item.noteId}`);
  assert(!candidate.openedAndRead, `research queue contains already-opened candidate ${item.noteId}`);
  assert(item.priority === index + 1, `research queue priority is not contiguous at ${item.noteId}`);
  assert(item.canonicalUrl === candidate.canonicalUrl, `research queue URL is stale for ${item.noteId}`);
  assert(item.basis === 'search-query-relevance-only', `research queue overstates its basis for ${item.noteId}`);
  assert(item.reviewStatus === 'unopened-not-evidence', `research queue overstates review status for ${item.noteId}`);
  assert(item.targetFamilyIds.length > 0, `research queue item ${item.noteId} has no target family`);
  assert(item.targetFamilyIds.every((familyId) => poseFamilies.families.some((family) => family.familyId === familyId && family.status === 'needs-evidence')), `research queue item ${item.noteId} targets a non-pending family`);
  assert(item.matchedQueries.every((query) => candidate.observedQueries.includes(query)), `research queue query is not observed for ${item.noteId}`);
  assert(Array.isArray(item.requiredChecks) && item.requiredChecks.includes('confirm-visible-real-human-action'), `research queue item ${item.noteId} lacks visual review gate`);
}

for (const template of evidence.templates) {
  const noteIds = new Set(template.sources.map((source) => source.noteId));
  const creators = new Set(template.sources.map((source) => {
    const record = deepById.get(source.noteId);
    return record?.creatorId || source.creatorId || source.creatorDisplay.replace(/\s+(?:20\d{2}-)?\d{2}-\d{2}$/, '');
  }));
  assert(['supported', 'needs-evidence', 'experimental'].includes(template.status), `${template.templateId} has an unsupported status`);
  if (template.status === 'supported') {
    assert(noteIds.size >= 5, `${template.templateId} has fewer than five distinct sources`);
    assert(creators.size >= 3, `${template.templateId} has fewer than three distinct creator display names`);
    assert(template.contexts.length >= 2, `${template.templateId} has fewer than two contexts`);
  }
  if (template.status === 'needs-evidence') {
    assert(noteIds.size < 5 || creators.size < 3, `${template.templateId} meets source counts but is still needs-evidence`);
  }
  for (const source of template.sources) {
    const record = deepById.get(source.noteId);
    assert(record, `${template.templateId} references unknown note ${source.noteId}`);
    assert(record.creatorDisplay === source.creatorDisplay, `${source.noteId} creator display does not match deep-read`);
    assert(record.canonicalUrl === source.canonicalUrl, `${source.noteId} canonical URL does not match deep-read`);
    assert(['screenshot', 'body-and-screenshot'].includes(source.evidenceKind), `${source.noteId} has an unsupported evidence kind`);
    assert(source.screenshotPath === record.screenshotPath, `${source.noteId} screenshot path does not match deep-read`);
    await access(resolve(root, source.screenshotPath));
    if (source.evidenceKind === 'body-and-screenshot') {
      assert(typeof source.excerpt === 'string' && source.excerpt.length > 0, `${source.noteId} is missing its body excerpt`);
      const excerptParts = source.excerpt.split(/[；;]/).map((part) => part.trim()).filter(Boolean);
      assert(excerptParts.every((part) => record.body.includes(part)), `${source.noteId} excerpt is not present in the saved body`);
    }
  }
}

const supported = evidence.templates.filter((template) => template.status === 'supported').length;
const needsEvidence = evidence.templates.filter((template) => template.status === 'needs-evidence').length;
const experimental = evidence.templates.filter((template) => template.status === 'experimental').length;
assert(poseFamilies.counts.observedFamilies === poseFamilies.families.length, 'pose-family observed count does not match families');
assert(new Set(poseFamilies.families.map((family) => family.familyId)).size === poseFamilies.families.length, 'pose-family ids are not unique');
for (const family of poseFamilies.families) {
  const qualifyingNotes = new Set(family.sources.filter((source) => source.qualifiesForAdmission).map((source) => source.noteId));
  const qualifyingCreators = new Set(family.sources.filter((source) => source.qualifiesForAdmission).map((source) => source.creatorId).filter(Boolean));
  assert(family.qualifyingPostCount === qualifyingNotes.size, `${family.familyId} qualifying post count is stale`);
  assert(family.qualifyingCreatorCount === qualifyingCreators.size, `${family.familyId} qualifying creator count is stale`);
  assert(family.sources.every((source) => source.qualifiesForAdmission
    || (typeof source.exclusionReason === 'string' && source.exclusionReason.length > 0)), `${family.familyId} has an excluded source without a reason`);
  if (family.status === 'ready-for-parameterization') {
    assert(qualifyingNotes.size >= 5, `${family.familyId} is ready with fewer than five posts`);
    assert(qualifyingCreators.size >= 3, `${family.familyId} is ready with fewer than three creators`);
  }
}

const parameterizationFiles = (await readdir(resolve(root, 'research/pose-parameterizations')).catch(() => []))
  .filter((file) => file.endsWith('.json'));
assert(poseFamilies.counts.parameterizationDrafts === parameterizationFiles.length, 'parameterization draft count is stale');
for (const file of parameterizationFiles) {
  const path = `research/pose-parameterizations/${file}`;
  const draft = await readJson(path);
  const family = poseFamilies.families.find((item) => item.familyId === draft.id);
  assert(family, `${file} does not map to an observed family`);
  assert(family.qualifyingPostCount >= 5 && family.qualifyingCreatorCount >= 3, `${file} was parameterized before source admission`);
  assert(draft.source?.platform !== 'xiaohongshu', `${file} must not use a Xiaohongshu product source`);
  assert(['owned', 'licensed', 'user-imported'].includes(draft.source?.usageStatus), `${file} lacks product usage rights`);
  assert(draft.review?.status === 'needs-review', `${file} must remain needs-review before real-device acceptance`);
  assert(Object.keys(draft.landmarks ?? {}).length === 33, `${file} does not contain exactly 33 landmarks`);
  assert(mediaPipe33.every((name) => draft.landmarks[name]), `${file} is missing a MediaPipe landmark`);
  for (const [name, landmark] of Object.entries(draft.landmarks)) {
    assert(Number.isFinite(landmark.position?.x) && Number.isFinite(landmark.position?.y), `${file} landmark ${name} has an invalid position`);
    assert(typeof landmark.visible === 'boolean', `${file} landmark ${name} has no visibility flag`);
    assert(Number.isFinite(landmark.weight) && landmark.weight >= 0 && landmark.weight <= 1, `${file} landmark ${name} has an invalid weight`);
  }
  assert((draft.guideContour?.length ?? 0) >= 12, `${file} has no usable guide contour draft`);
  assert(draft.guideContour.every((point) => Number.isFinite(point.x) && Number.isFinite(point.y)), `${file} guide contour contains an invalid point`);
  const firstContourPoint = draft.guideContour[0];
  const lastContourPoint = draft.guideContour.at(-1);
  assert(firstContourPoint.x === lastContourPoint.x && firstContourPoint.y === lastContourPoint.y, `${file} guide contour is not closed`);
  assert((draft.relations?.length ?? 0) > 0, `${file} has no key relation`);
  assert(draft.relations.every((relation) => draft.landmarks[relation.from] && draft.landmarks[relation.to]), `${file} relation references an unknown landmark`);
  assert(['easy', 'standard', 'precise'].every((name) => draft.tolerancePresets?.[name]), `${file} lacks tolerance presets`);
  const { easy, standard, precise } = draft.tolerancePresets;
  assert(easy.matchThreshold < standard.matchThreshold && standard.matchThreshold < precise.matchThreshold, `${file} match thresholds do not tighten by preset`);
  assert(easy.landmarkDistance > standard.landmarkDistance && standard.landmarkDistance > precise.landmarkDistance, `${file} landmark tolerances do not tighten by preset`);
  assert(easy.angleDifferenceDeg > standard.angleDifferenceDeg && standard.angleDifferenceDeg > precise.angleDifferenceDeg, `${file} angle tolerances do not tighten by preset`);
  assert(easy.stableMs > 0 && easy.stableMs === standard.stableMs && standard.stableMs === precise.stableMs, `${file} stable timing is missing or inconsistent`);
  assert(family.parameterization?.artifactPath === path, `${file} is not linked from pose-families`);
  assert(family.parameterization?.realDeviceAcceptance === 'pending', `${file} overstates real-device acceptance`);
}

console.log(`Research verified: ${candidates.items.length} unique candidates, ${deepRead.records.length} deep reads, ${poseFamilies.families.length} observed pose families, ${poseFamilies.counts.readyForParameterization} source-ready families, ${parameterizationFiles.length} parameterization drafts, ${supported} legacy supported templates, ${needsEvidence} legacy needs-evidence templates, ${experimental} experimental template.`);
