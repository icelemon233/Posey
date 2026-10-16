import type { LandmarkMap, LandmarkName } from '../types';

const connections: Array<[LandmarkName, LandmarkName]> = [
  ['nose', 'leftShoulder'], ['nose', 'rightShoulder'], ['leftShoulder', 'rightShoulder'],
  ['leftShoulder', 'leftElbow'], ['leftElbow', 'leftWrist'],
  ['rightShoulder', 'rightElbow'], ['rightElbow', 'rightWrist'],
  ['leftShoulder', 'leftHip'], ['rightShoulder', 'rightHip'], ['leftHip', 'rightHip'],
  ['leftHip', 'leftKnee'], ['leftKnee', 'leftAnkle'],
  ['rightHip', 'rightKnee'], ['rightKnee', 'rightAnkle'],
];

type Props = {
  target: LandmarkMap;
  compact?: boolean;
};

export function Skeleton({ target, compact = false }: Props) {
  return (
    <svg
      className={`skeleton ${compact ? 'skeleton--compact' : 'skeleton--guide'}`}
      viewBox="0 0 100 100"
      preserveAspectRatio="none"
      aria-label="静态姿势参考线稿"
    >
      <g>
        {connections.map(([from, to]) => (
          <line
            key={`${from}-${to}`}
            x1={target[from].x * 100}
            y1={target[from].y * 100}
            x2={target[to].x * 100}
            y2={target[to].y * 100}
            className="skeleton__target"
          />
        ))}
        <ellipse
          cx={target.nose.x * 100}
          cy={target.nose.y * 100}
          rx={compact ? 4.1 : 4.5}
          ry={compact ? 4.1 : 5.5}
          className="skeleton__head"
        />
      </g>
    </svg>
  );
}
