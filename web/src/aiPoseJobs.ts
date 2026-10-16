export const MAX_ACTIVE_AI_POSE_JOBS = 3;
export const MAX_COMPLETED_AI_POSE_JOBS = 20;

const padDatePart = (value: number) => String(value).padStart(2, '0');

export function formatAiPoseCompletedAt(timestamp: number): string {
  const completedAt = new Date(timestamp);
  return `${completedAt.getFullYear()}-${padDatePart(completedAt.getMonth() + 1)}-${padDatePart(completedAt.getDate())} ${padDatePart(completedAt.getHours())}:${padDatePart(completedAt.getMinutes())}`;
}

type AiPoseJobHistoryItem = {
  createdAt: number;
  state: string;
};

export function retainRecentCompletedAiPoseJobs<T extends AiPoseJobHistoryItem>(jobs: T[]): T[] {
  const retainedCompletedJobs = new Set(
    jobs
      .filter((job) => job.state === 'completed')
      .sort((left, right) => right.createdAt - left.createdAt)
      .slice(0, MAX_COMPLETED_AI_POSE_JOBS),
  );
  return jobs.filter((job) => job.state !== 'completed' || retainedCompletedJobs.has(job));
}
