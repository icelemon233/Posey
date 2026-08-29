export type AiPoseRequest = {
  sourceImage: string;
  guideUrl: string;
  fallbackGuideImage: string;
  targetTitle: string;
  preferences?: AiPosePreferences;
};

export type AiPosePreferences = {
  faceFidelity: 'strict' | 'natural';
  expression: 'preserve' | 'subtle';
  gaze: 'preserve' | 'follow-pose';
};

export const DEFAULT_AI_POSE_PREFERENCES: AiPosePreferences = {
  faceFidelity: 'strict',
  expression: 'preserve',
  gaze: 'preserve',
};

export type ArkConfigOverride = {
  apiKey?: string;
  apiUrl?: string;
  model?: string;
};

export type PreparedAiPoseRequest = {
  apiKey: string;
  endpoint: string;
  guideImage: string;
  model: string;
  prompt: string;
  sourceImage: string;
  targetTitle: string;
};

type ArkImageItem = { b64_json?: string; url?: string };

type ArkImageResponse = {
  data?: ArkImageItem[];
  error?: { code?: string; message?: string; type?: string };
};

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => typeof reader.result === 'string' ? resolve(reader.result) : reject(new Error('图片读取失败'));
    reader.onerror = () => reject(new Error('图片读取失败'));
    reader.readAsDataURL(blob);
  });
}

async function loadGuideImage(url: string, fallback: string, signal?: AbortSignal) {
  try {
    const response = await fetch(url, { signal });
    if (!response.ok) throw new Error('guide not found');
    return await blobToDataUrl(await response.blob());
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    return fallback;
  }
}

function normalizeApiKey(value: string) {
  return value
    .replace(/^ARK_API_KEY\s*=\s*/, '')
    .replace(/[\s\u200B-\u200D\uFEFF]/g, '');
}

function arkConfig(override?: ArkConfigOverride) {
  return {
    apiKey: normalizeApiKey(override?.apiKey ?? import.meta.env.VITE_ARK_API_KEY ?? ''),
    apiUrl: (override?.apiUrl ?? import.meta.env.VITE_ARK_API_URL ?? 'https://ark.cn-beijing.volces.com/api/v3').replace(/\/$/, ''),
    model: override?.model ?? import.meta.env.VITE_ARK_IMAGE_MODEL ?? 'doubao-seedream-5-0-pro-260628',
  };
}

function buildPrompt(targetTitle: string, preferences: AiPosePreferences) {
  const safeTitle = targetTitle.slice(0, 80) || '所选目标姿势';
  const faceInstruction = preferences.faceFidelity === 'strict'
    ? '面部是不可编辑的身份区域：严格锁定图1的脸型、五官形状与比例、皮肤真实纹理、妆容、年龄特征和头发边界。不要重新绘制、对称化、美颜、磨皮或替换人脸；当目标姿势与面部保持冲突时，优先保持图1面部不变。'
    : '保持图1人物身份、脸型、五官比例、年龄特征、妆容和真实皮肤纹理，只允许为新的头部角度做极轻微且自然的光影过渡；不要美颜、磨皮、对称化或替换人脸。';
  const expressionInstruction = preferences.expression === 'preserve'
    ? '严格保持图1的原始表情和情绪：眉形、眼睑开合、面部肌肉、嘴唇形状与开合、牙齿可见状态必须一致，不要新增微笑、张嘴、皱眉或其他微表情。'
    : '保持图1的原始情绪类别，只允许为身体姿势做极轻微的面部肌肉过渡；嘴唇开合、牙齿可见状态和主要表情不能改变。';
  const gazeInstruction = preferences.gaze === 'preserve'
    ? '严格保持图1的视线方向、瞳孔位置和眼睛开合，不要让人物改看镜头或看向其他方向。'
    : '视线可以轻微顺应目标姿势，但必须保持图1的眼睛形状、开合、虹膜外观和自然聚焦，不要产生空洞、斜视或不一致的双眼。';
  return [
    '这是一次局部姿势编辑，不是重新生成人像。生成一张写实且自然的人像编辑照片。',
    '图1是待修改的原始照片。必须保留同一个人物的身份、发型、服装、身材比例、背景、光线、相机角度、构图和照片风格。',
    faceInstruction,
    expressionInstruction,
    gazeInstruction,
    `图2只作为“${safeTitle}”的目标姿势参考，不要复制图2的人物身份、服装、颜色、插画风格或背景。`,
    '只改变完成目标姿势所必需的躯干和四肢位置，使其尽可能自然地贴合图2；头部和面部保持受保护。',
    '保持人物数量不变，四肢连接自然、人体结构合理，不要裁掉图1中原本可见的肢体。',
    '不要添加文字、字幕、边框、标志或水印。',
  ].join('');
}

function publicError(status: number, payload: ArkImageResponse) {
  const code = payload.error?.code || payload.error?.type || '';
  if (status === 401 || status === 403 || /api.?key|access.?denied/i.test(code)) {
    return 'AI Pose 服务鉴权失败，请检查火山方舟 API Key 和模型权限';
  }
  if (status === 429) return 'AI Pose 现在有点忙，请稍后再试';
  if (/sensitive|moderation/i.test(code)) return '当前画面无法生成，请换一个画面再试';
  return payload.error?.message || 'AI Pose 暂时生成失败，请再试一次';
}

async function resultImage(item: ArkImageItem | undefined, signal?: AbortSignal) {
  if (item?.b64_json) return `data:image/jpeg;base64,${item.b64_json}`;
  if (!item?.url) throw new Error('AI Pose 没有返回可用图片');
  const response = await fetch(item.url, { signal });
  if (!response.ok) throw new Error('AI Pose 返回图片读取失败');
  return blobToDataUrl(await response.blob());
}

export async function generateAiPose(
  request: AiPoseRequest,
  signal?: AbortSignal,
  configOverride?: ArkConfigOverride,
): Promise<string> {
  const prepared = await prepareAiPoseRequest(request, signal, configOverride);
  const response = await fetch(prepared.endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${prepared.apiKey}`,
    },
    body: JSON.stringify({
      model: prepared.model,
      prompt: prepared.prompt,
      image: [prepared.sourceImage, prepared.guideImage],
      size: '2K',
      output_format: 'jpeg',
      response_format: 'b64_json',
      watermark: false,
    }),
    signal,
  });

  let payload: ArkImageResponse = {};
  try { payload = await response.json() as ArkImageResponse; } catch { /* use the generic message below */ }
  if (!response.ok) throw new Error(publicError(response.status, payload));
  return resultImage(payload.data?.[0], signal);
}

export async function prepareAiPoseRequest(
  request: AiPoseRequest,
  signal?: AbortSignal,
  configOverride?: ArkConfigOverride,
): Promise<PreparedAiPoseRequest> {
  const config = arkConfig(configOverride);
  if (!config.apiKey) throw new Error('AI Pose 还没有配置火山方舟 API Key');
  if (!request.sourceImage.startsWith('data:image/')) throw new Error('没有可用于 AI Pose 的当前画面');

  const guideImage = await loadGuideImage(request.guideUrl, request.fallbackGuideImage, signal);
  return {
    apiKey: config.apiKey,
    endpoint: `${config.apiUrl}/images/generations`,
    guideImage,
    model: config.model,
    prompt: buildPrompt(request.targetTitle, request.preferences ?? DEFAULT_AI_POSE_PREFERENCES),
    sourceImage: request.sourceImage,
    targetTitle: request.targetTitle,
  };
}
