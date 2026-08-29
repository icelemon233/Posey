import type { LandmarkMap, LandmarkName, Point, PoseCategory, PoseRelation, PoseTemplate, ShotType } from '../types';

const point = (x: number, y: number, visibility = 1): Point => ({ x, y, visibility });
const pose = (values: number[]): LandmarkMap => {
  const names = [
    'nose', 'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow', 'leftWrist', 'rightWrist',
    'leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
  ] as const;
  return Object.fromEntries(names.map((name, index) => [name, point(values[index * 2], values[index * 2 + 1])])) as LandmarkMap;
};

const STAND = pose([.5,.12,.4,.25,.6,.25,.36,.42,.64,.42,.34,.58,.66,.58,.45,.52,.55,.52,.45,.74,.55,.74,.44,.93,.56,.93]);
const SEATED = pose([.5,.16,.4,.29,.6,.29,.35,.43,.65,.43,.34,.57,.66,.57,.44,.54,.56,.54,.35,.72,.65,.72,.3,.88,.7,.88]);
const CROUCH = pose([.5,.22,.4,.34,.6,.34,.35,.48,.65,.48,.34,.59,.66,.59,.44,.54,.56,.54,.35,.68,.65,.68,.33,.86,.67,.86]);
const KNEEL = pose([.5,.15,.4,.28,.6,.28,.35,.43,.65,.43,.34,.58,.66,.58,.44,.53,.56,.53,.38,.7,.62,.72,.34,.89,.67,.89]);

const variant = (base: LandmarkMap, changes: Partial<Record<LandmarkName, [number, number, number?]>>): LandmarkMap =>
  Object.fromEntries(Object.entries(base).map(([name, value]) => {
    const next = changes[name as LandmarkName];
    return [name, next ? point(next[0], next[1], next[2] ?? 1) : { ...value }];
  })) as LandmarkMap;

const relation = (
  type: PoseRelation['type'], from: PoseRelation['from'], to: PoseRelation['to'],
  tolerance: number, simpleHint: string,
): PoseRelation => ({ type, from, to, tolerance, simpleHint, critical: true });

const supportedSource = {
  usageStatus: 'owned' as const,
  label: 'Posey 原创抽象模板；研究来源已达到准入门槛',
  evidenceStatus: 'supported' as const,
};
const previewSource = {
  usageStatus: 'owned' as const,
  label: 'Posey 原创抽象模板；已有真人动作证据，来源准入继续补充中',
  evidenceStatus: 'experimental' as const,
};

type Config = {
  id: string;
  title: string;
  subtitle: string;
  category: PoseCategory;
  shotType: ShotType;
  base: LandmarkMap;
  changes: Partial<Record<LandmarkName, [number, number, number?]>>;
  relations: PoseRelation[];
  supported?: boolean;
};

const colors = ['#ff9f7f', '#89d9c2', '#ffd36e', '#9dc7ff', '#dda9ff', '#ff9fbd'];
const categoryTags: Record<PoseCategory, string> = {
  standing: '站姿',
  half: '半身',
  seated: '坐姿',
  crouching: '蹲跪',
};
const makeTemplate = (config: Config, index: number): PoseTemplate => ({
  id: config.id,
  title: config.title,
  subtitle: config.subtitle,
  category: config.category,
  shotType: config.shotType,
  tags: [categoryTags[config.category], config.supported ? '已验证' : '试用'],
  accent: colors[index % colors.length],
  illustration: `/poses/${config.id}.webp`,
  landmarks: variant(config.base, config.changes),
  relations: config.relations,
  source: config.supported ? supportedSource : previewSource,
});

const configs: Config[] = [
  { id: 'one-hand-in-pocket', title: '单手插兜', subtitle: '另一只手自然放松', category: 'standing', shotType: 'full-body', base: STAND, supported: true,
    changes: { rightElbow:[.61,.43], rightWrist:[.55,.52], leftWrist:[.33,.59] },
    relations: [relation('near','rightWrist','rightHip',.075,'右手再靠近裤兜'), relation('minimum-distance','leftWrist','leftHip',.07,'左手放在兜外面')] },
  { id: 'standing-one-arm-up', title: '单手举高', subtitle: '身体站直，一只手向上', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { leftElbow:[.38,.14], leftWrist:[.42,.02] }, relations: [relation('vertical-offset','leftWrist','leftShoulder',.08,'左手再高一点')] },
  { id: 'both-arms-raised', title: '双手举高', subtitle: '双臂一起向上伸展', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { leftElbow:[.4,.13], rightElbow:[.6,.13], leftWrist:[.44,.01], rightWrist:[.56,.01] }, relations: [relation('distance','leftWrist','rightWrist',.08,'双手再分开一点')] },
  { id: 'hand-in-hair-standing', title: '单手撩发', subtitle: '一只手轻碰头发', category: 'half', shotType: 'half-body', base: STAND,
    changes: { rightElbow:[.67,.32], rightWrist:[.58,.14] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近头发')] },
  { id: 'both-hands-near-face', title: '双手靠近脸', subtitle: '两只手放在脸旁', category: 'half', shotType: 'half-body', base: STAND,
    changes: { leftElbow:[.34,.34], rightElbow:[.66,.34], leftWrist:[.43,.19], rightWrist:[.57,.19] }, relations: [relation('distance','leftWrist','rightWrist',.1,'双手再靠近脸')] },
  { id: 'natural-stand-hands-front', title: '双手自然放前', subtitle: '简单放松的站姿', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { leftWrist:[.47,.59], rightWrist:[.53,.59] }, relations: [relation('near','leftWrist','rightWrist',.1,'双手再靠近一点')] },
  { id: 'one-hand-near-ear-other-low', title: '一手靠耳边', subtitle: '另一只手自然垂下', category: 'half', shotType: 'half-body', base: STAND,
    changes: { leftElbow:[.33,.34], leftWrist:[.43,.17], rightWrist:[.65,.61] }, relations: [relation('near','leftWrist','nose',.12,'左手再靠近耳边')] },
  { id: 'one-hand-on-shoulder-other-low', title: '一手搭肩', subtitle: '另一只手自然放低', category: 'half', shotType: 'half-body', base: STAND,
    changes: { leftElbow:[.48,.39], leftWrist:[.59,.27], rightWrist:[.65,.61] }, relations: [relation('near','leftWrist','rightShoulder',.08,'左手再靠近肩膀')] },
  { id: 'one-leg-back-lift', title: '单脚向后抬', subtitle: '轻轻抬起一只脚', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { rightKnee:[.61,.75], rightAnkle:[.68,.66] }, relations: [relation('distance','rightAnkle','leftAnkle',.12,'右脚再抬高一点')] },
  { id: 'one-leg-forward-toe-up', title: '一脚向前点', subtitle: '脚尖轻轻抬起', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { leftKnee:[.4,.74], leftAnkle:[.28,.88] }, relations: [relation('minimum-distance','leftAnkle','rightAnkle',.1,'左脚再往前一点')] },
  { id: 'standing-salute', title: '抬手敬礼', subtitle: '一只手放到额前', category: 'half', shotType: 'half-body', base: STAND,
    changes: { rightElbow:[.67,.29], rightWrist:[.57,.13] }, relations: [relation('near','rightWrist','nose',.1,'右手再靠近额头')] },
  { id: 'walking-side-profile', title: '侧身走路', subtitle: '迈步时看向前方', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { nose:[.57,.13], leftShoulder:[.45,.26], rightShoulder:[.57,.24], leftHip:[.47,.52], rightHip:[.55,.51], leftKnee:[.36,.73], rightKnee:[.62,.69], leftAnkle:[.28,.91], rightAnkle:[.7,.88] }, relations: [relation('minimum-distance','leftAnkle','rightAnkle',.12,'步子再打开一点')] },
  { id: 'standing-both-hands-near-head', title: '双手靠近头部', subtitle: '双手放在头两侧', category: 'half', shotType: 'half-body', base: STAND,
    changes: { leftElbow:[.32,.32], rightElbow:[.68,.32], leftWrist:[.42,.12], rightWrist:[.58,.12] }, relations: [relation('distance','leftWrist','rightWrist',.1,'双手再靠近头部')] },
  { id: 'standing-both-hands-waist-look-side', title: '双手叉腰侧看', subtitle: '双手放腰，看向一边', category: 'half', shotType: 'half-body', base: STAND,
    changes: { nose:[.58,.13], leftElbow:[.3,.45], rightElbow:[.7,.45], leftWrist:[.45,.52], rightWrist:[.55,.52] }, relations: [relation('near','leftWrist','leftHip',.08,'左手再靠近腰'), relation('near','rightWrist','rightHip',.08,'右手再靠近腰')] },
  { id: 'side-look-back-hand-behind-head', title: '侧身回头扶发', subtitle: '回头时一手放脑后', category: 'half', shotType: 'half-body', base: STAND,
    changes: { nose:[.59,.14], leftShoulder:[.44,.27], rightShoulder:[.6,.24], rightElbow:[.68,.3], rightWrist:[.57,.12], leftHip:[.47,.53] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近头发')] },
  { id: 'side-stand-arms-down', title: '侧身站立', subtitle: '双臂自然放下', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { nose:[.57,.13], leftShoulder:[.44,.26], rightShoulder:[.58,.24], leftWrist:[.45,.6], rightWrist:[.6,.59], leftHip:[.47,.52] }, relations: [relation('horizontal-offset','nose','leftHip',.08,'身体再侧一点')] },
  { id: 'two-hands-front-asymmetric', title: '双手前后错开', subtitle: '两只手放在不同高度', category: 'half', shotType: 'half-body', base: STAND,
    changes: { leftWrist:[.45,.48], rightWrist:[.55,.61] }, relations: [relation('vertical-offset','leftWrist','rightWrist',.08,'左手再高一点')] },
  { id: 'forward-lean-hands-low', title: '前倾双手放低', subtitle: '身体前倾，双手靠近膝盖', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { nose:[.5,.2], leftShoulder:[.4,.31], rightShoulder:[.6,.31], leftElbow:[.38,.47], rightElbow:[.62,.47], leftWrist:[.42,.66], rightWrist:[.58,.66] }, relations: [relation('vertical-offset','nose','leftShoulder',.08,'身体再往前一点')] },
  { id: 'arms-crossed-one-leg-lifted', title: '抱臂抬脚', subtitle: '抱住双臂，一脚向后抬', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { leftElbow:[.42,.38], rightElbow:[.58,.38], leftWrist:[.57,.34], rightWrist:[.43,.34], rightKnee:[.61,.75], rightAnkle:[.68,.66] }, relations: [relation('near','leftWrist','rightElbow',.12,'左手再靠近右臂'), relation('distance','rightAnkle','leftAnkle',.12,'右脚再抬高一点')] },
  { id: 'arms-open-look-side', title: '打开双臂侧看', subtitle: '双臂张开，看向一边', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { nose:[.6,.13], leftElbow:[.25,.29], rightElbow:[.75,.29], leftWrist:[.08,.31], rightWrist:[.92,.31] }, relations: [relation('distance','leftWrist','rightWrist',.18,'双臂再打开一点')] },
  { id: 'back-facing-both-hands-in-hair', title: '背身双手扶发', subtitle: '背对镜头，双手放头边', category: 'half', shotType: 'half-body', base: STAND,
    changes: { nose:[.5,.12,.2], leftElbow:[.32,.32], rightElbow:[.68,.32], leftWrist:[.43,.12], rightWrist:[.57,.12] }, relations: [relation('distance','leftWrist','rightWrist',.1,'双手再靠近头发')] },
  { id: 'crouch-knees-together-both-hands-cup-face', title: '蹲姿双手托脸', subtitle: '双膝靠近，双手放脸旁', category: 'crouching', shotType: 'full-body', base: CROUCH,
    changes: { leftElbow:[.36,.39], rightElbow:[.64,.39], leftWrist:[.44,.24], rightWrist:[.56,.24], leftKnee:[.46,.68], rightKnee:[.54,.68] }, relations: [relation('distance','leftWrist','rightWrist',.1,'双手再靠近脸')] },
  { id: 'crouch-knees-together-hands-low', title: '蹲姿双手放低', subtitle: '双膝靠近，双手自然放下', category: 'crouching', shotType: 'full-body', base: CROUCH,
    changes: { leftWrist:[.46,.66], rightWrist:[.54,.66], leftKnee:[.46,.68], rightKnee:[.54,.68] }, relations: [relation('near','leftWrist','rightWrist',.1,'双手再靠近一点')] },
  { id: 'crouch-knees-together-one-hand-cheek', title: '蹲姿单手托脸', subtitle: '双膝靠近，一手碰脸', category: 'crouching', shotType: 'full-body', base: CROUCH,
    changes: { rightElbow:[.63,.39], rightWrist:[.56,.24], leftWrist:[.43,.63], leftKnee:[.46,.68], rightKnee:[.54,.68] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近脸')] },
  { id: 'crouch-one-hand-in-hair', title: '蹲姿撩发', subtitle: '蹲下时一手碰头发', category: 'crouching', shotType: 'full-body', base: CROUCH,
    changes: { leftElbow:[.34,.39], leftWrist:[.44,.22], rightWrist:[.61,.61] }, relations: [relation('near','leftWrist','nose',.11,'左手再靠近头发')] },
  { id: 'crouch-one-knee-up-hand-near-face', title: '单膝抬高蹲姿', subtitle: '一手靠脸，一边膝盖抬高', category: 'crouching', shotType: 'full-body', base: CROUCH,
    changes: { rightWrist:[.56,.24], rightElbow:[.64,.39], leftKnee:[.35,.63], rightKnee:[.62,.55], rightAnkle:[.68,.82] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近脸'), relation('vertical-offset','rightKnee','leftKnee',.1,'右膝再高一点')] },
  { id: 'low-crouch', title: '低位蹲姿', subtitle: '身体放低，双手自然', category: 'crouching', shotType: 'full-body', base: CROUCH,
    changes: { nose:[.5,.3], leftShoulder:[.4,.4], rightShoulder:[.6,.4], leftHip:[.44,.59], rightHip:[.56,.59], leftKnee:[.34,.69], rightKnee:[.66,.69] }, relations: [relation('vertical-offset','nose','leftHip',.1,'身体再蹲低一点')] },
  { id: 'one-knee-kneel', title: '单膝跪姿', subtitle: '一边膝盖落低', category: 'crouching', shotType: 'full-body', base: KNEEL,
    changes: { leftKnee:[.4,.72], leftAnkle:[.33,.88], rightKnee:[.62,.64], rightAnkle:[.68,.88] }, relations: [relation('vertical-offset','leftKnee','rightKnee',.1,'左膝再低一点')] },
  { id: 'low-kneel-arms-extended-look-side', title: '低跪打开双臂', subtitle: '跪低后双臂向两边伸', category: 'crouching', shotType: 'full-body', base: KNEEL,
    changes: { nose:[.59,.18], leftElbow:[.25,.37], rightElbow:[.75,.37], leftWrist:[.08,.4], rightWrist:[.92,.4], leftKnee:[.4,.7], rightKnee:[.6,.7] }, relations: [relation('distance','leftWrist','rightWrist',.18,'双臂再打开一点')] },
  { id: 'seated-both-hands-cup-face', title: '坐姿双手托脸', subtitle: '坐好后双手放脸旁', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftElbow:[.36,.39], rightElbow:[.64,.39], leftWrist:[.44,.2], rightWrist:[.56,.2] }, relations: [relation('distance','leftWrist','rightWrist',.1,'双手再靠近脸')] },
  { id: 'seated-hand-near-forehead', title: '坐姿手靠额头', subtitle: '坐着把一手放额前', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { rightElbow:[.66,.36], rightWrist:[.56,.17] }, relations: [relation('near','rightWrist','nose',.1,'右手再靠近额头')] },
  { id: 'seated-knees-open-hands-low', title: '坐姿双膝打开', subtitle: '双手自然放低', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftWrist:[.44,.64], rightWrist:[.56,.64], leftKnee:[.28,.7], rightKnee:[.72,.7], leftAnkle:[.24,.89], rightAnkle:[.76,.89] }, relations: [relation('minimum-distance','leftKnee','rightKnee',.12,'双膝再打开一点')] },
  { id: 'seated-one-hand-in-hair', title: '坐姿撩发', subtitle: '坐着一手碰头发', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftElbow:[.34,.38], leftWrist:[.44,.19] }, relations: [relation('near','leftWrist','nose',.11,'左手再靠近头发')] },
  { id: 'seated-one-hand-support-cheek', title: '坐姿单手托腮', subtitle: '一只手轻轻托住脸', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { rightElbow:[.62,.44], rightWrist:[.56,.22] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近脸')] },
  { id: 'seated-one-hand-support-chin', title: '坐姿托下巴', subtitle: '一只手放在下巴下', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftElbow:[.39,.44], leftWrist:[.49,.24] }, relations: [relation('near','leftWrist','nose',.1,'左手再靠近下巴')] },
  { id: 'floor-seated-cross-legged-hold-prop', title: '盘腿双手拿书', subtitle: '盘腿坐下，双手放身前', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftWrist:[.45,.53], rightWrist:[.55,.53], leftKnee:[.3,.7], rightKnee:[.7,.7], leftAnkle:[.58,.77], rightAnkle:[.42,.77] }, relations: [relation('near','leftWrist','rightWrist',.1,'双手再靠近一点')] },
  { id: 'floor-seated-knees-raised-one-hand-near-face', title: '抱膝坐姿手靠脸', subtitle: '双膝抬起，一手靠脸', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { rightWrist:[.56,.22], rightElbow:[.63,.4], leftKnee:[.39,.58], rightKnee:[.61,.58], leftAnkle:[.35,.82], rightAnkle:[.65,.82] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近脸')] },
  { id: 'low-seated-one-leg-extended-selfie', title: '低坐伸腿自拍', subtitle: '一腿伸直，一手向前', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftElbow:[.28,.4], leftWrist:[.08,.35], leftKnee:[.35,.69], leftAnkle:[.16,.87], rightKnee:[.62,.62], rightAnkle:[.68,.82] }, relations: [relation('minimum-distance','leftWrist','leftShoulder',.12,'左手再伸远一点')] },
  { id: 'steps-seated-crossed-legs-both-hands-behind-head', title: '台阶坐姿双手脑后', subtitle: '双腿交叉，双手放脑后', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { leftElbow:[.28,.3], rightElbow:[.72,.3], leftWrist:[.45,.16], rightWrist:[.55,.16], leftAnkle:[.6,.86], rightAnkle:[.42,.82] }, relations: [relation('distance','leftElbow','rightElbow',.12,'双肘再打开一点')] },
  { id: 'steps-seated-side-one-hand-near-ear', title: '台阶侧坐手靠耳', subtitle: '侧身坐下，一手靠耳边', category: 'seated', shotType: 'seated', base: SEATED,
    changes: { nose:[.58,.17], leftShoulder:[.44,.3], rightShoulder:[.59,.28], rightElbow:[.64,.38], rightWrist:[.57,.2], leftHip:[.47,.54], leftKnee:[.38,.7], rightKnee:[.61,.66] }, relations: [relation('near','rightWrist','nose',.11,'右手再靠近耳边')] },
  { id: 'railing-standing-one-hand-shade-eyes', title: '栏杆边抬手遮光', subtitle: '一手放到额前看远处', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { nose:[.59,.13], rightElbow:[.67,.3], rightWrist:[.56,.13], leftWrist:[.36,.56] }, relations: [relation('near','rightWrist','nose',.1,'右手再靠近额头')] },
  { id: 'wall-touch-one-hand-one-foot-forward', title: '扶墙一脚向前', subtitle: '一手扶墙，一只脚迈出', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { leftElbow:[.28,.34], leftWrist:[.12,.32], leftKnee:[.4,.73], leftAnkle:[.28,.9] }, relations: [relation('minimum-distance','leftWrist','leftShoulder',.12,'左手再伸远一点'), relation('minimum-distance','leftAnkle','rightAnkle',.1,'左脚再往前一点')] },
  { id: 'wall-lean-body-side-hands-low', title: '侧靠双手放低', subtitle: '身体侧靠，双手自然下垂', category: 'standing', shotType: 'full-body', base: STAND,
    changes: { nose:[.57,.14], leftShoulder:[.43,.29], rightShoulder:[.62,.24], leftWrist:[.42,.62], rightWrist:[.62,.59], leftHip:[.46,.55], rightHip:[.57,.52], rightKnee:[.64,.71], rightAnkle:[.7,.88] }, relations: [relation('vertical-offset','leftShoulder','rightShoulder',.08,'身体再侧靠一点')] },
  { id: 'mirror-standing-one-hand-phone', title: '单手镜面自拍', subtitle: '一手举手机，另一手放松', category: 'half', shotType: 'half-body', base: STAND,
    changes: { rightElbow:[.62,.36], rightWrist:[.55,.26], leftWrist:[.35,.59] }, relations: [relation('near','rightWrist','rightShoulder',.1,'右手再靠近胸前')] },
];

export const EXPANDED_TEMPLATES = configs.map(makeTemplate);
