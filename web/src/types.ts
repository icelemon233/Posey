export const LANDMARK_NAMES = [
  'nose',
  'leftShoulder',
  'rightShoulder',
  'leftElbow',
  'rightElbow',
  'leftWrist',
  'rightWrist',
  'leftHip',
  'rightHip',
  'leftKnee',
  'rightKnee',
  'leftAnkle',
  'rightAnkle',
] as const;

export type LandmarkName = (typeof LANDMARK_NAMES)[number];

export type Point = {
  x: number;
  y: number;
  z?: number;
  visibility?: number;
};

export type LandmarkMap = Record<LandmarkName, Point>;
export type PoseCategory = 'standing' | 'half' | 'seated' | 'crouching';
export type ShotType = 'full-body' | 'half-body' | 'seated';
export type PoseGender = 'female' | 'male';

export type PoseRelation = {
  type: 'near' | 'distance' | 'minimum-distance' | 'vertical-offset' | 'horizontal-offset' | 'hand-at-waist';
  from: LandmarkName;
  to: LandmarkName;
  target?: number;
  tolerance: number;
  critical: boolean;
  simpleHint?: string;
};

export type PoseTemplate = {
  id: string;
  title: string;
  subtitle: string;
  category: PoseCategory;
  shotType: ShotType;
  /** Display subject used by the library gender switch. Imported references may omit it. */
  gender?: PoseGender;
  tags: string[];
  accent: string;
  illustration?: string;
  landmarks: LandmarkMap;
  relations: PoseRelation[];
  source: {
    usageStatus: 'owned' | 'user-imported';
    label: string;
    evidenceStatus?: 'supported' | 'experimental';
  };
};
