import { describe, expect, it } from 'vitest';
import { formatAiPoseCompletedAt, MAX_COMPLETED_AI_POSE_JOBS, retainRecentCompletedAiPoseJobs } from './aiPoseJobs';

describe('retainRecentCompletedAiPoseJobs', () => {
  it('keeps active and failed jobs while retaining only the newest completed results', () => {
    const completed = Array.from({ length: MAX_COMPLETED_AI_POSE_JOBS + 2 }, (_, index) => ({
      createdAt: index,
      id: `completed-${index}`,
      state: 'completed' as const,
    }));
    const active = { createdAt: -1, id: 'generating', state: 'generating' as const };
    const failed = { createdAt: -2, id: 'failed', state: 'failed' as const };

    const retained = retainRecentCompletedAiPoseJobs([...completed, active, failed]);

    expect(retained.filter((job) => job.state === 'completed')).toHaveLength(MAX_COMPLETED_AI_POSE_JOBS);
    expect(retained.some((job) => job.id === 'completed-0')).toBe(false);
    expect(retained.some((job) => job.id === 'completed-1')).toBe(false);
    expect(retained).toContain(active);
    expect(retained).toContain(failed);
  });

  it('formats a completed timestamp with an explicit local date and time', () => {
    const completedAt = new Date(2026, 7, 28, 15, 6).getTime();
    expect(formatAiPoseCompletedAt(completedAt)).toBe('2026-08-28 15:06');
  });
});
