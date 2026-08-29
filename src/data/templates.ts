import type { LandmarkMap, PoseRelation, PoseTemplate } from '../types';
import { EXPANDED_TEMPLATES } from './expandedTemplates';

const point = (x: number, y: number, visibility = 1) => ({ x, y, visibility });
const pose = (values: number[], hidden: string[] = []): LandmarkMap => {
  const names = [
    'nose', 'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow', 'leftWrist', 'rightWrist',
    'leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
  ] as const;
  return Object.fromEntries(names.map((name, index) => [name, point(
    values[index * 2], values[index * 2 + 1], hidden.includes(name) ? 0.2 : 1,
  )])) as LandmarkMap;
};

const relation = (
  type: PoseRelation['type'], from: PoseRelation['from'], to: PoseRelation['to'],
  target: number, tolerance: number, simpleHint: string, critical = true,
): PoseRelation => ({ type, from, to, target, tolerance, simpleHint, critical });

const source = {
  usageStatus: 'owned' as const,
  label: 'Posey 原创抽象模板；研究来源已达到准入门槛',
  evidenceStatus: 'supported' as const,
};

const ORIGINAL_TEMPLATES: PoseTemplate[] = [
  {
    id: 'hand-near-hair-or-forehead', title: '手靠近头发', subtitle: '轻松半身照',
    category: 'half', shotType: 'half-body', tags: ['半身', '手部'], accent: '#ffad8a', illustration: '/poses/hand-near-hair-or-forehead.webp', source,
    landmarks: pose([.5,.14,.43,.26,.57,.26,.37,.38,.63,.31,.33,.5,.54,.17,.46,.51,.54,.51,.44,.78,.56,.78,.44,1.05,.56,1.05], ['leftKnee','rightKnee','leftAnkle','rightAnkle']),
    relations: [relation('near', 'rightWrist', 'nose', .07, .13, '右手再靠近头发')],
  },
  {
    id: 'crossed-arms-standing', title: '抱臂站好', subtitle: '自然有精神',
    category: 'standing', shotType: 'full-body', tags: ['全身', '站姿'], accent: '#e7c7ff', illustration: '/poses/crossed-arms-standing.webp', source,
    landmarks: pose([.5,.12,.39,.25,.61,.25,.41,.39,.59,.39,.57,.34,.43,.34,.45,.52,.55,.52,.46,.73,.54,.73,.46,.92,.54,.92]),
    relations: [
      relation('near', 'leftWrist', 'rightElbow', .054, .13, '左手再贴近右臂'),
      relation('near', 'rightWrist', 'leftElbow', .054, .13, '右手再贴近左臂'),
    ],
  },
  {
    id: 'back-facing-arms-open', title: '背身打开双臂', subtitle: '适合旅行风景',
    category: 'standing', shotType: 'full-body', tags: ['全身', '背影'], accent: '#8ae6c1', illustration: '/poses/back-facing-arms-open-v2.webp', source,
    landmarks: pose([.5,.12,.41,.25,.59,.25,.25,.28,.75,.28,.08,.3,.92,.3,.455,.53,.545,.53,.45,.74,.55,.74,.445,.92,.555,.92], ['nose']),
    relations: [
      relation('distance', 'leftWrist', 'rightWrist', .84, .18, '双臂再打开一点'),
      relation('distance', 'leftWrist', 'leftShoulder', .33, .14, '左手再往外一点'),
      relation('distance', 'rightWrist', 'rightShoulder', .33, .14, '右手再往外一点'),
    ],
  },
  {
    id: 'side-lean-arms-open', title: '侧倾打开双臂', subtitle: '身体向旁边倾',
    category: 'standing', shotType: 'full-body', tags: ['全身', '旅行'], accent: '#ffd76f', illustration: '/poses/side-lean-arms-open.webp', source,
    landmarks: pose([.58,.12,.44,.28,.65,.23,.28,.34,.78,.28,.12,.39,.92,.33,.45,.53,.55,.53,.43,.74,.56,.73,.4,.92,.58,.92]),
    relations: [
      relation('distance', 'leftWrist', 'rightWrist', .8, .18, '双臂再打开一点'),
      relation('vertical-offset', 'leftShoulder', 'rightShoulder', .05, .06, '身体再侧一点'),
    ],
  },
  {
    id: 'wall-lean-body-side-one-hand-pocket', title: '侧靠单手插兜', subtitle: '靠墙更松弛',
    category: 'standing', shotType: 'full-body', tags: ['全身', '靠墙'], accent: '#88c9ff', illustration: '/poses/wall-lean-body-side-one-hand-pocket.webp', source,
    landmarks: pose([.54,.12,.43,.28,.61,.25,.38,.45,.64,.4,.37,.61,.56,.54,.46,.55,.55,.54,.43,.75,.66,.7,.4,.93,.71,.82]),
    relations: [
      relation('near', 'rightWrist', 'rightHip', .015, .07, '右手再靠近裤兜'),
      relation('minimum-distance', 'leftWrist', 'leftHip', .105, .07, '左手放在兜外面'),
      relation('vertical-offset', 'leftShoulder', 'rightShoulder', .03, .055, '身体再侧靠一点'),
    ],
  },
  {
    id: 'standing-look-back-one-hand-pocket', title: '回头单手插兜', subtitle: '侧身回头看镜头',
    category: 'standing', shotType: 'full-body', tags: ['全身', '回眸'], accent: '#ff9db5', illustration: '/poses/standing-look-back-one-hand-pocket.webp', source,
    landmarks: pose([.57,.14,.43,.27,.61,.24,.38,.43,.64,.39,.36,.58,.56,.53,.46,.54,.55,.53,.44,.74,.57,.72,.42,.93,.6,.91]),
    relations: [
      relation('near', 'rightWrist', 'rightHip', .02, .075, '右手再靠近裤兜'),
      relation('minimum-distance', 'leftWrist', 'leftHip', .13, .07, '左手放在兜外面'),
      relation('horizontal-offset', 'nose', 'rightHip', .02, .07, '再回头看向手机'),
      relation('vertical-offset', 'leftShoulder', 'rightShoulder', .03, .06, '身体再侧一点'),
    ],
  },
];

// The illustration set intentionally contains two complete, consistently styled
// character groups. Keep the gender assignment next to the asset ids so a future
// generated replacement can be swapped without touching the library UI.
const FEMALE_ILLUSTRATIONS = new Set([
  'arms-crossed-one-leg-lifted', 'arms-open-look-side', 'back-facing-both-hands-in-hair',
  'both-arms-raised', 'crouch-knees-together-both-hands-cup-face', 'crouch-one-hand-in-hair',
  'crouch-one-knee-up-hand-near-face', 'floor-seated-knees-raised-one-hand-near-face',
  'hand-in-hair-standing', 'low-crouch',
  'low-seated-one-leg-extended-selfie', 'one-hand-in-pocket', 'one-hand-near-ear-other-low',
  'one-hand-on-shoulder-other-low', 'one-leg-back-lift', 'seated-both-hands-cup-face',
  'seated-hand-near-forehead', 'seated-knees-open-hands-low', 'seated-one-hand-in-hair',
  'seated-one-hand-support-cheek', 'side-look-back-hand-behind-head', 'standing-both-hands-near-head',
  'standing-both-hands-waist-look-side', 'standing-one-arm-up', 'steps-seated-crossed-legs-both-hands-behind-head',
  'steps-seated-side-one-hand-near-ear', 'side-stand-arms-down',
]);

export const BUILTIN_TEMPLATES: PoseTemplate[] = [...ORIGINAL_TEMPLATES, ...EXPANDED_TEMPLATES].map((template) => ({
  ...template,
  gender: FEMALE_ILLUSTRATIONS.has(template.id) ? 'female' : 'male',
}));
