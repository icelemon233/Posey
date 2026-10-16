import { afterEach, describe, expect, it, vi } from 'vitest';
import { generateAiPose } from './aiPose';

const request = {
  sourceImage: 'data:image/jpeg;base64,c291cmNl',
  guideUrl: '/pose-guides/example.webp',
  fallbackGuideImage: 'data:image/png;base64,ZmFsbGJhY2s=',
  targetTitle: '单手插袋',
};
const arkConfig = {
  apiKey: 'test-ark-key',
  apiUrl: 'https://ark.example.com/api/v3',
  model: 'test-seedream-model',
};

afterEach(() => vi.unstubAllGlobals());

describe('generateAiPose', () => {
  it('loads the guide and sends two images directly to Volcengine Ark', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, blob: async () => new Blob(['guide'], { type: 'image/webp' }) })
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: [{ b64_json: 'cmVzdWx0' }] }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(generateAiPose(request, undefined, arkConfig)).resolves.toBe('data:image/jpeg;base64,cmVzdWx0');
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [url, options] = fetchMock.mock.calls[1] as [string, RequestInit];
    expect(url).toBe('https://ark.example.com/api/v3/images/generations');
    expect(options.headers).toEqual({
      'Content-Type': 'application/json',
      Authorization: 'Bearer test-ark-key',
    });
    const body = JSON.parse(String(options.body));
    expect(body).toMatchObject({
      model: 'test-seedream-model',
      image: [request.sourceImage, expect.stringMatching(/^data:image\//)],
      response_format: 'b64_json',
      watermark: false,
    });
    expect(body.prompt).toContain('面部是不可编辑的身份区域');
    expect(body.prompt).toContain('严格保持图1的原始表情和情绪');
    expect(body.prompt).toContain('严格保持图1的视线方向');
  });

  it('turns the visible generation preferences into hidden face, expression and gaze instructions', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, blob: async () => new Blob(['guide'], { type: 'image/webp' }) })
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: [{ b64_json: 'cmVzdWx0' }] }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await generateAiPose({
      ...request,
      preferences: { faceFidelity: 'natural', expression: 'subtle', gaze: 'follow-pose' },
    }, undefined, arkConfig);

    const body = JSON.parse(String((fetchMock.mock.calls[1][1] as RequestInit).body));
    expect(body.prompt).toContain('极轻微且自然的光影过渡');
    expect(body.prompt).toContain('只允许为身体姿势做极轻微的面部肌肉过渡');
    expect(body.prompt).toContain('视线可以轻微顺应目标姿势');
  });

  it('uses the generated skeleton fallback when the guide asset is unavailable', async () => {
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new Error('missing'))
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: [{ b64_json: 'cmVzdWx0' }] }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await generateAiPose(request, undefined, arkConfig);
    const body = JSON.parse(String((fetchMock.mock.calls[1][1] as RequestInit).body));
    expect(body.image[1]).toBe(request.fallbackGuideImage);
  });

  it('surfaces the Ark error message', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, blob: async () => new Blob(['guide'], { type: 'image/webp' }) })
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: { message: '请求过多' } }), { status: 429 }));
    vi.stubGlobal('fetch', fetchMock);

    await expect(generateAiPose(request, undefined, arkConfig)).rejects.toThrow('AI Pose 现在有点忙');
  });

  it('forwards cancellation to both guide and generation requests', async () => {
    const controller = new AbortController();
    const fetchMock = vi.fn((_url: string, options?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      options?.signal?.addEventListener('abort', () => reject(new DOMException('cancelled', 'AbortError')), { once: true });
    }));
    vi.stubGlobal('fetch', fetchMock);

    const pending = generateAiPose(request, controller.signal, arkConfig);
    controller.abort();
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('fails before loading images when the bundled Ark key is missing', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    await expect(generateAiPose(request, undefined, { ...arkConfig, apiKey: '' })).rejects.toThrow('还没有配置火山方舟 API Key');
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
