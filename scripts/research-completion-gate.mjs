import { readFile } from 'node:fs/promises';

const familyId = 'standing-look-back-one-hand-pocket';
const [families, queue] = await Promise.all([
  readFile(new URL('../research/xiaohongshu/pose-families.json', import.meta.url), 'utf8').then(JSON.parse),
  readFile(new URL('../research/xiaohongshu/next-deep-read-queue.json', import.meta.url), 'utf8').then(JSON.parse),
]);
const family = families.families.find((item) => item.familyId === familyId);
const queueCount = queue.count ?? queue.items.length;
const targetMet = family?.qualifyingPostCount >= 5 && family?.qualifyingCreatorCount >= 3;

if (!family) {
  console.error(`Completion gate blocked: missing family ${familyId}`);
  process.exit(2);
}

if (!targetMet && queueCount > 0) {
  console.error(`Completion gate blocked: ${family.qualifyingPostCount}/5 qualifying posts, ${family.qualifyingCreatorCount}/3 creators, ${queueCount} candidates remain`);
  process.exit(1);
}

if (!targetMet) {
  console.error(`Completion gate blocked: target is ${family.qualifyingPostCount}/5 posts and ${family.qualifyingCreatorCount}/3 creators; no admission evidence`);
  process.exit(1);
}

console.log(`Completion gate passed: ${family.qualifyingPostCount} posts, ${family.qualifyingCreatorCount} creators`);
