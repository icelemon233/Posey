import type { SVGProps } from 'react';

const iconStrokeWidth = 1.85;
const poseyPPath = 'M8.9 11.05C9.85 9.675 11.775 8.675 13.325 8.6C14.575 8.54 15.275 9.075 15.1 10.1C14.9 11.275 13.425 12.325 11.025 12.875M11.875 9.525C11.225 11.075 10.175 13.8 10.075 15.375M9.275 12.725C9.825 13.075 10.525 13.075 11.025 12.875';

export function PoseyAiPoseIcon({ className = '', ...props }: SVGProps<SVGSVGElement>) {
  return (
    <svg
      {...props}
      className={`posey-ai-pose-icon${className ? ` ${className}` : ''}`}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
    >
      <path d="M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M8 21H5a2 2 0 0 1-2-2v-3" stroke="currentColor" strokeWidth={iconStrokeWidth} strokeLinecap="round" strokeLinejoin="round" />
      <path d={poseyPPath} stroke="currentColor" strokeWidth={iconStrokeWidth} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
