import { Capacitor, registerPlugin, type PluginListenerHandle } from '@capacitor/core';
import { prepareAiPoseRequest, type AiPoseRequest } from '../aiPose';

export type NativeAiPoseJob = {
  completedAt?: number;
  createdAt: number;
  id: string;
  image?: string;
  message?: string;
  state: 'queued' | 'generating' | 'completed' | 'failed';
  targetTitle?: string;
};

type NativeAiPoseJobEvent = Pick<NativeAiPoseJob, 'id' | 'state'>;

interface PoseyBackgroundAIPlugin {
  addListener(eventName: 'aiPoseJobUpdate', listener: (event: NativeAiPoseJobEvent) => void): Promise<PluginListenerHandle>;
  cancel(options: { jobId: string }): Promise<void>;
  clear(options: { jobId: string }): Promise<void>;
  getJobs(): Promise<{ jobs: NativeAiPoseJob[] }>;
  start(options: {
    apiKey: string;
    endpoint: string;
    guideImage: string;
    model: string;
    prompt: string;
    sourceImage: string;
    targetTitle: string;
  }): Promise<{ jobId: string }>;
}

const NativeBackgroundAI = registerPlugin<PoseyBackgroundAIPlugin>('PoseyBackgroundAI');

export function supportsNativeBackgroundAiPose() {
  return Capacitor.getPlatform() === 'ios';
}

export async function startNativeBackgroundAiPose(request: AiPoseRequest, signal?: AbortSignal) {
  const prepared = await prepareAiPoseRequest(request, signal);
  return NativeBackgroundAI.start(prepared);
}

export async function getNativeBackgroundAiPoseJobs() {
  return (await NativeBackgroundAI.getJobs()).jobs;
}

export async function cancelNativeBackgroundAiPose(jobId: string) {
  await NativeBackgroundAI.cancel({ jobId });
}

export async function clearNativeBackgroundAiPose(jobId: string) {
  await NativeBackgroundAI.clear({ jobId });
}

export async function addNativeBackgroundAiPoseListener(listener: (event: NativeAiPoseJobEvent) => void) {
  return NativeBackgroundAI.addListener('aiPoseJobUpdate', listener);
}
