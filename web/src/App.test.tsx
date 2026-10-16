import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import App from './App';
import { BUILTIN_TEMPLATES } from './data/templates';
import type { AiPoseRequest } from './aiPose';
import type { NativeAiPoseJob } from './native/backgroundAiPose';

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const nativeMocks = vi.hoisted(() => ({ savePhoto: vi.fn(async () => 'library' as const) }));
const backgroundAiPoseMocks = vi.hoisted(() => ({
  addListener: vi.fn(async () => ({ remove: vi.fn(async () => undefined) })),
  cancel: vi.fn(async () => undefined),
  clear: vi.fn(async () => undefined),
  getJobs: vi.fn<() => Promise<NativeAiPoseJob[]>>(async () => []),
  supported: false,
}));
const aiPoseMocks = vi.hoisted(() => ({
  generateAiPose: vi.fn<(_request: AiPoseRequest, _signal?: AbortSignal) => Promise<string>>(async () => 'data:image/jpeg;base64,YWktcG9zZQ=='),
}));

vi.mock('./native/photoLibrary', () => ({ savePhoto: nativeMocks.savePhoto }));
vi.mock('./native/backgroundAiPose', () => ({
  addNativeBackgroundAiPoseListener: backgroundAiPoseMocks.addListener,
  cancelNativeBackgroundAiPose: backgroundAiPoseMocks.cancel,
  clearNativeBackgroundAiPose: backgroundAiPoseMocks.clear,
  getNativeBackgroundAiPoseJobs: backgroundAiPoseMocks.getJobs,
  startNativeBackgroundAiPose: vi.fn(),
  supportsNativeBackgroundAiPose: () => backgroundAiPoseMocks.supported,
}));
vi.mock('./aiPose', () => ({
  DEFAULT_AI_POSE_PREFERENCES: { faceFidelity: 'strict', expression: 'preserve', gaze: 'preserve' },
  generateAiPose: aiPoseMocks.generateAiPose,
}));

const canvasContext = {
  fillRect: vi.fn(), beginPath: vi.fn(), moveTo: vi.fn(), lineTo: vi.fn(), stroke: vi.fn(), drawImage: vi.fn(),
  set fillStyle(_value: string | CanvasGradient) {},
  set strokeStyle(_value: string) {},
  set lineWidth(_value: number) {},
  set lineCap(_value: CanvasLineCap) {},
  set lineJoin(_value: CanvasLineJoin) {},
};

function byText(text: string) {
  const element = [...document.querySelectorAll('button')].find((item) => item.textContent?.includes(text));
  if (!element) throw new Error(`找不到按钮：${text}`);
  return element as HTMLButtonElement;
}

function byLabel(label: string) {
  const element = document.querySelector(`[aria-label="${label}"]`);
  if (!element) throw new Error(`找不到控件：${label}`);
  return element as HTMLButtonElement;
}

async function click(element: HTMLElement) {
  await act(async () => { element.click(); await Promise.resolve(); });
}

async function flush() {
  await act(async () => { await Promise.resolve(); await Promise.resolve(); });
}

function dispatchPointer(element: HTMLElement, type: string, clientX: number, clientY: number) {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperties(event, {
    clientX: { value: clientX },
    clientY: { value: clientY },
    pointerId: { value: 1 },
  });
  element.dispatchEvent(event);
}

async function swipeLeft(element: HTMLElement) {
  await act(async () => {
    dispatchPointer(element, 'pointerdown', 220, 32);
    dispatchPointer(element, 'pointermove', 130, 34);
    dispatchPointer(element, 'pointerup', 130, 34);
    await Promise.resolve();
  });
}

describe('Posey journey', () => {
  let container: HTMLDivElement;
  let root: Root;

  async function remountApp() {
    await act(async () => root.unmount());
    root = createRoot(container);
    await act(async () => root.render(<App />));
  }

  beforeEach(async () => {
    localStorage.clear();
    nativeMocks.savePhoto.mockClear();
    backgroundAiPoseMocks.supported = false;
    backgroundAiPoseMocks.addListener.mockClear();
    backgroundAiPoseMocks.cancel.mockClear();
    backgroundAiPoseMocks.clear.mockClear();
    backgroundAiPoseMocks.getJobs.mockReset();
    backgroundAiPoseMocks.getJobs.mockResolvedValue([]);
    aiPoseMocks.generateAiPose.mockReset();
    aiPoseMocks.generateAiPose.mockResolvedValue('data:image/jpeg;base64,YWktcG9zZQ==');
    Object.defineProperty(window, 'requestAnimationFrame', { configurable: true, value: vi.fn((callback: FrameRequestCallback) => { callback(0); return 1; }) });
    Object.defineProperty(window, 'cancelAnimationFrame', { configurable: true, value: vi.fn() });
    Object.defineProperty(window, 'scrollTo', { configurable: true, value: vi.fn() });
    Object.defineProperty(HTMLCanvasElement.prototype, 'getContext', { configurable: true, value: vi.fn(() => canvasContext) });
    Object.defineProperty(HTMLCanvasElement.prototype, 'toDataURL', { configurable: true, value: vi.fn(() => 'data:image/jpeg;base64,cGhvdG8=') });
    Object.defineProperty(HTMLMediaElement.prototype, 'play', { configurable: true, value: vi.fn(async () => undefined) });
    Object.defineProperty(HTMLImageElement.prototype, 'decode', { configurable: true, value: vi.fn(async () => undefined) });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: vi.fn(async () => { throw new DOMException('denied', 'NotAllowedError'); }) },
    });
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => root.render(<App />));
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
  });

  it('renders settings as an independent concise page with in-page details', async () => {
    expect(document.querySelector('.brand-mark')).toBeNull();
    expect(document.querySelector<HTMLImageElement>('.home-wordmark')?.getAttribute('src')).toBe('/brand/posey-wordmark.png');
    expect(document.querySelector<HTMLImageElement>('.home-wordmark')?.getAttribute('alt')).toBe('Posey');
    expect(document.querySelector('.home-header')?.children).toHaveLength(1);
    expect(document.querySelector('.home-header')?.textContent).not.toContain('姿势库');
    expect(document.querySelector('.home-header')?.textContent).not.toContain('我的收藏');
    await click(byLabel('前往设置页'));
    const settingsPage = document.querySelector('[data-page="settings"] .settings-page');
    expect(settingsPage?.textContent).toContain('首页主题');
    expect(settingsPage?.textContent).toContain('随心拍');
    expect(settingsPage?.textContent).not.toContain('默认拍摄模式');
    expect(settingsPage?.textContent).not.toContain('语音提示');
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(byLabel('前往设置页').getAttribute('aria-current')).toBe('page');
    expect(settingsPage?.getAttribute('data-motion-direction')).toBe('tab');

    await click(byText('产品说明'));
    const detailPage = document.querySelector('[data-page="settings"] .settings-page');
    expect(detailPage?.getAttribute('data-motion-direction')).toBe('forward');
    expect(detailPage?.textContent).toContain('照着线稿拍照');
    expect(detailPage?.textContent).toContain('拍摄安全');
    expect(detailPage?.textContent).toContain('AI Pose 风险');
    expect(byLabel('返回设置')).not.toBeNull();
    await click(byLabel('返回设置'));
    expect(document.querySelector('.settings-page')?.getAttribute('data-motion-direction')).toBe('back');
  });

  it('uses a balanced five-item bottom bar with 随心拍 in the center', () => {
    expect(document.querySelector('.library-page-content')).not.toBeNull();
    const bar = document.querySelector<HTMLElement>('.home-tab-bar');
    expect(bar?.classList.contains('home-tab-bar--liquid-glass')).toBe(true);
    expect(bar?.style.getPropertyValue('--selection-offset')).toBe('0%');
    expect(bar?.querySelector('.home-tab-bar__selection > span')).not.toBeNull();
    const buttons = [...document.querySelectorAll<HTMLButtonElement>('.home-tab-bar > button')];
    expect(buttons.map((button) => button.textContent)).toEqual(['首页', '收藏', '随心拍', 'AI Pose', '设置']);
    expect(buttons).toHaveLength(5);
    expect(buttons[2].getAttribute('aria-label')).toBe('随心拍随机选择姿势');
    expect(buttons[2].classList.contains('home-tab-bar__capture')).toBe(false);
    expect(buttons[3].querySelector('.posey-ai-pose-icon')).not.toBeNull();
    expect(buttons[3].querySelector('.lucide-sparkles')).toBeNull();
    expect(buttons[4].getAttribute('aria-label')).toBe('前往设置页');
  });

  it('slides one liquid selection surface across bottom destinations', async () => {
    const bar = document.querySelector<HTMLElement>('.home-tab-bar')!;
    const firstSurface = bar.querySelector('.home-tab-bar__selection > span');
    await click(byLabel('前往收藏页'));
    expect(bar.style.getPropertyValue('--selection-offset')).toBe('100%');
    expect(bar.dataset.activeIndex).toBe('1');
    expect(byLabel('前往收藏页').getAttribute('aria-current')).toBe('page');
    expect(bar.querySelector('.home-tab-bar__selection > span')).not.toBe(firstSurface);
    await click(byLabel('打开 AI Pose'));
    expect(bar.style.getPropertyValue('--selection-offset')).toBe('300%');
    expect(bar.dataset.activeIndex).toBe('3');
  });

  it('opens a clean photo-pose-generate workflow from the AI Pose bottom entry', async () => {
    await click(byLabel('打开 AI Pose'));
    expect(document.querySelector('[data-testid="camera-screen"]')).toBeNull();
    expect(document.querySelector('[data-page="ai-pose"]')).not.toBeNull();
    expect(document.querySelector('.ai-workflow')?.textContent).toContain('把照片换成喜欢的姿势');
    expect(byLabel('选择 AI Pose 人物照片')).not.toBeNull();
    expect(byLabel('选择 AI Pose 目标姿势').disabled).toBe(true);
    const generateButton = document.querySelector('.ai-workflow__generate');
    expect(generateButton?.hasAttribute('disabled')).toBe(true);
    expect(generateButton?.querySelector('.posey-ai-pose-icon')).not.toBeNull();
    expect(document.querySelector('.ai-workflow .lucide-sparkles')).toBeNull();
    expect(document.querySelector('.camera-tools')).toBeNull();
    expect(document.querySelector('.camera-stage')).toBeNull();
    expect(document.querySelector('.camera-bottom')).toBeNull();
    expect(document.body.textContent).not.toContain('打开相机');
    expect(navigator.mediaDevices.getUserMedia).not.toHaveBeenCalled();
  });

  it('selects a photo and pose before generating from the AI Pose workspace', async () => {
    await click(byLabel('打开 AI Pose'));
    const input = document.querySelector<HTMLInputElement>('[aria-label="上传 AI Pose 人物照片"]')!;
    Object.defineProperty(input, 'files', { configurable: true, value: [new File(['person-photo'], 'person.jpg', { type: 'image/jpeg' })] });
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    expect(document.querySelector<HTMLImageElement>('.ai-workflow-row__preview img')?.src).toMatch(/^data:image\/jpeg;base64,/);
    expect(byLabel('选择 AI Pose 目标姿势').disabled).toBe(false);
    await click(byLabel('选择 AI Pose 目标姿势'));
    expect(document.querySelector('[aria-label="AI Pose 姿势性别"]')).not.toBeNull();
    const target = BUILTIN_TEMPLATES.find((template) => template.gender === 'female')!;
    await click(byLabel(`选择姿势：${target.title}`));
    const generateButton = document.querySelector<HTMLButtonElement>('.ai-workflow__generate')!;
    expect(generateButton.disabled).toBe(false);
    await click(generateButton);
    expect(document.querySelector('[role="dialog"]')?.textContent).toContain('发送这张照片生成 AI Pose');
    expect(document.querySelector('[aria-label="AI Pose 生成参数"]')?.textContent).toContain('面部一致性');
    expect(byLabel('面部一致性：严格保持').getAttribute('aria-pressed')).toBe('true');
    expect(byLabel('表情：保持原样').getAttribute('aria-pressed')).toBe('true');
    expect(byLabel('视线：保持原样').getAttribute('aria-pressed')).toBe('true');
    await click(byLabel('表情：轻微调整'));
    await click(byText('发送并生成'));
    await flush();
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);
    expect(aiPoseMocks.generateAiPose.mock.calls[0][0].preferences).toEqual({ faceFidelity: 'strict', expression: 'subtle', gaze: 'preserve' });
    expect(JSON.parse(localStorage.getItem('posey:ai-pose-preferences') ?? '{}')).toEqual({ faceFidelity: 'strict', expression: 'subtle', gaze: 'preserve' });
    expect(document.querySelector('.ai-pose-loading')).toBeNull();
    expect(document.querySelector('.ai-task-banner')?.textContent).toContain('AI Pose 已完成');
    expect(document.querySelector('[data-testid="result-screen"]')).toBeNull();
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(1);
    expect(document.querySelector('.ai-task-list__row--completed')?.textContent).toMatch(/完成于 \d{4}-\d{2}-\d{2} \d{2}:\d{2}/);
    await click(byText('查看'));
    expect(document.body.textContent).toContain('AI Pose 已生成');
    expect(document.body.textContent).not.toContain('再改一张');
    expect(document.body.textContent).not.toContain('换个姿势');
    expect(document.querySelector('.result-actions--single')).not.toBeNull();
    expect(document.querySelectorAll('.result-actions button')).toHaveLength(1);
    expect(document.querySelector('.result-actions')?.textContent).toContain('保存照片');
    expect(byLabel('返回 AI Pose 列表')).not.toBeNull();
    await click(byLabel('返回 AI Pose 列表'));
    expect(document.querySelector('[data-page="ai-pose"]')).not.toBeNull();
    expect(document.querySelector('[data-testid="result-screen"]')).toBeNull();
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(1);
  });

  it('keeps a native completed result through a transient empty sync until explicitly deleted', async () => {
    const completedJob = {
      completedAt: new Date(2026, 7, 28, 14, 35).getTime(),
      createdAt: new Date(2026, 7, 28, 14, 34).getTime(),
      id: 'native-completed-1',
      image: 'data:image/jpeg;base64,bmF0aXZlLWFpLXBvc2U=',
      state: 'completed' as const,
      targetTitle: '单手插兜',
    };
    backgroundAiPoseMocks.supported = true;
    backgroundAiPoseMocks.getJobs.mockResolvedValueOnce([completedJob]);
    await remountApp();
    await flush();

    await click(byLabel('打开 AI Pose'));
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(1);

    backgroundAiPoseMocks.getJobs.mockResolvedValue([]);
    await act(async () => {
      document.dispatchEvent(new Event('visibilitychange'));
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(1);

    const completedSurface = document.querySelector<HTMLElement>('.ai-task-list__swipe-surface')!;
    await swipeLeft(completedSurface);
    await click(byLabel('删除已完成任务：单手插兜'));
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(0);
    expect(backgroundAiPoseMocks.clear).toHaveBeenCalledWith('native-completed-1');

    backgroundAiPoseMocks.getJobs.mockResolvedValue([completedJob]);
    await act(async () => {
      document.dispatchEvent(new Event('visibilitychange'));
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(0);
  });

  it('queues multiple AI Pose requests and keeps every task independently actionable', async () => {
    const completions: Array<(image: string) => void> = [];
    aiPoseMocks.generateAiPose.mockImplementation(() => new Promise((resolve) => { completions.push(resolve); }));
    await click(byLabel('打开 AI Pose'));
    const input = document.querySelector<HTMLInputElement>('[aria-label="上传 AI Pose 人物照片"]')!;
    Object.defineProperty(input, 'files', { configurable: true, value: [new File(['person-photo'], 'person.jpg', { type: 'image/jpeg' })] });
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    await click(byLabel('选择 AI Pose 目标姿势'));
    const target = BUILTIN_TEMPLATES.find((template) => template.gender === 'female')!;
    await click(byLabel(`选择姿势：${target.title}`));

    await click(document.querySelector<HTMLButtonElement>('.ai-workflow__generate')!);
    await click(byText('发送并生成'));
    await flush();
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);

    await click(document.querySelector<HTMLButtonElement>('.ai-workflow__generate')!);
    await click(byText('发送并生成'));
    await flush();
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);
    await click(document.querySelector<HTMLButtonElement>('.ai-workflow__generate')!);
    await click(byText('发送并生成'));
    await flush();
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);
    expect(document.querySelector('.ai-task-banner')?.textContent).toContain('共 3 条');
    expect(document.querySelector('.ai-task-panel')?.textContent).toContain('AI Pose List');
    expect(document.querySelector('.ai-task-panel')?.textContent).toContain('1 个生成中');
    expect(document.querySelector('.ai-task-panel')?.textContent).toContain('2 个等待中');
    const fullGenerateButton = document.querySelector<HTMLButtonElement>('.ai-workflow__generate')!;
    expect(fullGenerateButton.disabled).toBe(true);
    expect(fullGenerateButton.textContent).toContain('队列已满（3/3）');
    expect(fullGenerateButton.getAttribute('aria-label')).toContain('最多 3 条');
    expect(document.querySelector('.ai-workflow__queue-hint')?.textContent).toContain('请等待完成或取消一个任务');
    await click(fullGenerateButton);
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);

    expect(document.querySelectorAll('.ai-task-list__row')).toHaveLength(3);
    await click(document.querySelector<HTMLButtonElement>('.ai-task-list__row--queued button')!);
    await flush();
    const rows = [...document.querySelectorAll<HTMLElement>('.ai-task-list__row')];
    expect(rows).toHaveLength(2);
    expect(rows.some((row) => row.textContent?.includes('正在生成'))).toBe(true);
    expect(rows.some((row) => row.textContent?.includes('等待前一项完成'))).toBe(true);
    expect(document.querySelector<HTMLButtonElement>('.ai-workflow__generate')?.disabled).toBe(false);
    expect(document.querySelector('.ai-workflow__queue-hint')?.textContent).toContain('当前队列 2/3');

    await act(async () => {
      completions[0]('data:image/jpeg;base64,Zmlyc3Q=');
      await Promise.resolve();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(2);
    expect(document.querySelector('.ai-task-panel')?.textContent).toContain('1 个已完成');
    expect(document.querySelector('.ai-task-panel')?.textContent).toContain('1 个生成中');

    await act(async () => {
      completions[1]('data:image/jpeg;base64,c2Vjb25k');
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(document.querySelectorAll('.ai-task-list__row--completed')).toHaveLength(2);
    expect(document.querySelector<HTMLButtonElement>('.ai-workflow__generate')?.disabled).toBe(false);
    expect(document.querySelector('.ai-workflow__queue-hint')).toBeNull();
    await click(document.querySelector<HTMLButtonElement>('.ai-task-list__primary')!);
    expect(document.body.textContent).toContain('AI Pose 已生成');
    expect(document.body.textContent).toContain(`用了「${target.title}」`);
  });

  it('hides the submission banner after four seconds while keeping the in-page task list', async () => {
    aiPoseMocks.generateAiPose.mockImplementation(() => new Promise(() => undefined));
    await click(byLabel('打开 AI Pose'));
    const input = document.querySelector<HTMLInputElement>('[aria-label="上传 AI Pose 人物照片"]')!;
    Object.defineProperty(input, 'files', { configurable: true, value: [new File(['person-photo'], 'person.jpg', { type: 'image/jpeg' })] });
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    await click(byLabel('关闭提示'));
    await click(byLabel('选择 AI Pose 目标姿势'));
    const target = BUILTIN_TEMPLATES.find((template) => template.gender === 'female')!;
    await click(byLabel(`选择姿势：${target.title}`));

    vi.useFakeTimers();
    try {
      await click(document.querySelector<HTMLButtonElement>('.ai-workflow__generate')!);
      await click(byText('发送并生成'));
      await flush();
      expect(document.querySelector('.ai-task-banner')).not.toBeNull();
      expect(document.querySelector('.ai-task-panel')).not.toBeNull();

      await act(async () => { await vi.advanceTimersByTimeAsync(3999); });
      expect(document.querySelector('.ai-task-banner')).not.toBeNull();
      await act(async () => { await vi.advanceTimersByTimeAsync(1); });
      expect(document.querySelector('.ai-task-banner')).toBeNull();
      expect(document.querySelector('.ai-task-panel')?.textContent).toContain('正在生成');

      await click(byLabel('前往首页'));
      await click(document.querySelector<HTMLButtonElement>('.pose-card__visual')!);
      expect(document.querySelector('[data-testid="camera-screen"]')).not.toBeNull();
      expect(document.querySelector('.ai-task-banner')).toBeNull();
      await click(byLabel('返回姿势库'));
      expect(document.querySelector('[data-testid="library-screen"]')).not.toBeNull();
      expect(document.querySelector('.ai-task-banner')).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it('migrates PosePilot preferences to Posey storage keys once', async () => {
    localStorage.setItem('posepilot:favorites', JSON.stringify([BUILTIN_TEMPLATES[0].id]));
    localStorage.setItem('posepilot:home-theme', 'sea-breeze');
    localStorage.setItem('posepilot:shuffle-scope', 'favorites');
    await remountApp();

    expect(localStorage.getItem('posey:favorites')).toBe(JSON.stringify([BUILTIN_TEMPLATES[0].id]));
    expect(localStorage.getItem('posey:home-theme')).toBe('sea-breeze');
    expect(localStorage.getItem('posey:shuffle-scope')).toBe('favorites');
    expect(document.querySelector<HTMLElement>('[data-testid="library-screen"]')?.style.getPropertyValue('--theme-page-start')).toBe('#e8f8fc');
  });

  it('filters built-in poses by gender', async () => {
    const genderSwitch = document.querySelector<HTMLElement>('.gender-switch')!;
    const firstSurface = genderSwitch.querySelector('.liquid-segmented__selection > span');
    expect(genderSwitch.style.getPropertyValue('--selection-offset')).toBe('0%');
    const femaleCards = [...document.querySelectorAll<HTMLElement>('.pose-card')];
    expect(femaleCards.length).toBeGreaterThan(0);
    expect(new Set(femaleCards.map((card) => card.dataset.gender))).toEqual(new Set(['female']));
    await click(byText('男生'));
    expect(genderSwitch.style.getPropertyValue('--selection-offset')).toBe('100%');
    expect(genderSwitch.dataset.activeIndex).toBe('1');
    expect(genderSwitch.querySelector('.liquid-segmented__selection > span')).not.toBe(firstSurface);
    const maleCards = [...document.querySelectorAll<HTMLElement>('.pose-card')];
    expect(maleCards.length).toBeGreaterThan(0);
    expect(new Set(maleCards.map((card) => card.dataset.gender))).toEqual(new Set(['male']));
  });

  it('keeps each pose filter limited to its reviewed category for both genders', async () => {
    for (const gender of ['女生', '男生']) {
      await click(byText(gender));
      for (const [label, category] of [
        ['站姿', 'standing'],
        ['半身', 'half'],
        ['坐姿', 'seated'],
        ['蹲跪', 'crouching'],
      ] as const) {
        await click(byText(label));
        const cards = [...document.querySelectorAll<HTMLElement>('.pose-card')];
        expect(cards.length, `${gender} / ${label}`).toBeGreaterThan(0);
        expect(new Set(cards.map((card) => card.dataset.category)), `${gender} / ${label}`).toEqual(new Set([category]));
      }
    }
  });

  it('keeps the current gender visible until the next gender images are decoded', async () => {
    const decodeResolvers: Array<() => void> = [];
    Object.defineProperty(HTMLImageElement.prototype, 'decode', {
      configurable: true,
      value: vi.fn(() => new Promise<void>((resolve) => decodeResolvers.push(resolve))),
    });
    await remountApp();

    await click(byText('男生'));
    expect(byText('女生').getAttribute('aria-pressed')).toBe('true');
    expect([...document.querySelectorAll<HTMLElement>('.pose-card')].every((card) => card.dataset.gender === 'female')).toBe(true);

    await act(async () => {
      decodeResolvers.forEach((resolve) => resolve());
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(byText('男生').getAttribute('aria-pressed')).toBe('true');
    expect([...document.querySelectorAll<HTMLElement>('.pose-card')].every((card) => card.dataset.gender === 'male')).toBe(true);
  });

  it('switches the home theme without changing pose results', async () => {
    const initialCardCount = document.querySelectorAll('.pose-card').length;
    await click(byLabel('前往设置页'));
    await click(byText('首页主题'));
    const themeRows = [...document.querySelectorAll<HTMLButtonElement>('[aria-label="首页主题选项"] button')];
    expect(themeRows).toHaveLength(7);
    const pageStarts = new Set<string>();
    for (const row of themeRows) {
      await click(row);
      pageStarts.add(document.querySelector<HTMLElement>('[data-testid="library-screen"]')?.style.getPropertyValue('--theme-page-start') ?? '');
    }
    expect(pageStarts.size).toBe(7);
    await click(byText('海盐清风'));
    expect(localStorage.getItem('posey:home-theme')).toBe('sea-breeze');
    expect(document.querySelector<HTMLElement>('[data-testid="library-screen"]')?.style.getPropertyValue('--home-accent')).toBe('#2f6f91');
    expect(document.querySelector<HTMLElement>('[data-testid="library-screen"]')?.style.getPropertyValue('--theme-page-start')).toBe('#e8f8fc');
    expect(document.documentElement.style.getPropertyValue('--system-bar-background')).toBe('#f2fbfd');
    expect(document.documentElement.style.getPropertyValue('--system-bar-transition-duration')).toBe('.32s');
    await click(byLabel('前往首页'));
    expect(document.querySelectorAll('.pose-card')).toHaveLength(initialCardCount);
  });

  it('shows favorites on an independent all-gender page', async () => {
    await click(byLabel('收藏'));
    await click(byText('男生'));
    await click(byLabel('收藏'));
    await click(byLabel('前往收藏页'));
    const favoriteCards = [...document.querySelectorAll<HTMLElement>('.pose-card')];
    expect(favoriteCards).toHaveLength(2);
    expect(new Set(favoriteCards.map((card) => card.dataset.gender))).toEqual(new Set(['female', 'male']));
    expect(document.querySelector('.pose-grid--favorites')?.textContent).toContain('女');
    expect(document.querySelector('.pose-grid--favorites')?.textContent).toContain('男');
    expect(document.querySelectorAll('.pose-grid--favorites .gender-symbol')).toHaveLength(2);
    expect(document.querySelector('[aria-label="人物性别"]')).toBeNull();
  });

  it('renders the empty favorites state without a rounded container', async () => {
    await click(byLabel('前往收藏页'));
    const emptyState = document.querySelector<HTMLElement>('.empty-state--favorites');
    expect(emptyState).not.toBeNull();
    expect(getComputedStyle(emptyState!).backgroundColor).toBe('rgba(0, 0, 0, 0)');
  });

  it('aligns the home, favorites, and settings headings at the same first-screen height', async () => {
    const homeHeading = document.querySelector<HTMLElement>('.pose-library-heading--first');
    const homeMarginTop = getComputedStyle(homeHeading!).marginTop;
    const homeMinHeight = getComputedStyle(homeHeading!).minHeight;
    await click(byLabel('前往收藏页'));
    const favoritesHeading = document.querySelector<HTMLElement>('.favorites-heading');
    expect(getComputedStyle(favoritesHeading!).marginTop).toBe(homeMarginTop);
    expect(getComputedStyle(favoritesHeading!).minHeight).toBe(homeMinHeight);
    await click(byLabel('前往设置页'));
    const settingsPage = document.querySelector<HTMLElement>('.settings-page');
    const settingsHeading = document.querySelector<HTMLElement>('.settings-page__header');
    expect(getComputedStyle(settingsPage!).marginTop).toBe(homeMarginTop);
    expect(getComputedStyle(settingsHeading!).minHeight).toBe(homeMinHeight);
  });

  it('disables favorite-only shuffle when empty and falls back to all', async () => {
    await click(byLabel('前往设置页'));
    expect(document.querySelector('.settings-scope')).toBeNull();
    const shuffleRangeRow = byText('选择范围');
    expect(shuffleRangeRow.querySelector('.settings-row__value')?.textContent).toBe('全部');
    await click(shuffleRangeRow);
    const disabledFavoriteScope = [...document.querySelectorAll<HTMLButtonElement>('[aria-label="随心拍选择范围"] button')].find((button) => button.textContent?.includes('收藏'));
    expect(disabledFavoriteScope?.disabled).toBe(true);
    expect(disabledFavoriteScope?.getAttribute('aria-label')).toBe('收藏，暂无收藏姿势');
    expect(disabledFavoriteScope?.querySelector('.settings-choice-row__lock')).not.toBeNull();
    expect(document.querySelector('[role="radio"][aria-checked="true"]')?.textContent).toContain('全部');
    await click(byLabel('前往首页'));
    await click(byLabel('收藏'));
    await click(byLabel('前往设置页'));
    await click(byText('选择范围'));
    await click([...document.querySelectorAll<HTMLButtonElement>('[aria-label="随心拍选择范围"] button')].find((button) => button.textContent?.includes('收藏'))!);
    expect(document.querySelector('[role="radio"][aria-checked="true"]')?.textContent).toContain('收藏');
    await click(byLabel('前往首页'));
    await click(byLabel('取消收藏'));
    await flush();
    expect(localStorage.getItem('posey:shuffle-scope')).toBe('all');
  });

  it('treats stale favorite ids as an empty favorite collection', async () => {
    localStorage.setItem('posey:favorites', JSON.stringify(['removed-pose-id']));
    localStorage.setItem('posey:shuffle-scope', 'favorites');
    await remountApp();
    await flush();
    await click(byLabel('前往设置页'));
    await click(byText('选择范围'));
    const favoriteChoice = [...document.querySelectorAll<HTMLButtonElement>('[aria-label="随心拍选择范围"] button')].find((button) => button.textContent?.includes('收藏'));
    expect(favoriteChoice?.disabled).toBe(true);
    expect(localStorage.getItem('posey:shuffle-scope')).toBe('all');
  });

  it('keeps grouped settings separators flush without rounding the version row top corners', async () => {
    await click(byLabel('前往设置页'));
    const versionRow = [...document.querySelectorAll<HTMLElement>('.settings-row')].find((row) => row.textContent?.includes('版本'));
    expect(versionRow?.closest('.settings-card')?.querySelectorAll('.settings-row')).toHaveLength(3);
    expect(versionRow?.previousElementSibling?.textContent).toContain('隐私与 AI Pose');
  });

  it('removes detection, voice, auto capture, demo and reference import surfaces', async () => {
    expect(document.body.textContent).not.toContain('导入参考图');
    expect(document.body.textContent).not.toContain('体验演示');
    await click(document.querySelector<HTMLButtonElement>('button[aria-label^="选择"]')!);
    expect(document.body.textContent).not.toContain('姿势检测');
    expect(document.body.textContent).not.toContain('语音');
    expect(document.body.textContent).not.toContain('自动');
    expect(document.body.textContent).not.toContain('精准');
    expect(document.querySelector('[data-testid="pose-guide-note"]')?.textContent).toContain('照着线稿自由调整');
  });

  it('offers upload as recovery when camera permission is denied', async () => {
    await click(document.querySelector<HTMLButtonElement>('button[aria-label^="选择"]')!);
    await flush();
    expect(document.querySelector('[aria-label="切换左右方向"]')).toBeNull();
    expect(document.querySelector('.camera-header > :last-child')?.getAttribute('aria-hidden')).toBe('true');
    expect(document.querySelector('[role="alert"]')?.textContent).toContain('相机权限没打开');
    expect(document.querySelector('[role="alert"]')?.textContent).toContain('上传照片');
    expect(byLabel('相机准备中').disabled).toBe(true);
    await click(byText('再试一次'));
    expect(navigator.mediaDevices.getUserMedia).toHaveBeenCalledTimes(2);
  });

  it('takes and saves a photo manually when the camera is ready', async () => {
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: vi.fn(async () => ({ getTracks: () => [{ stop: vi.fn() }] })) },
    });
    await click(document.querySelector<HTMLButtonElement>('[data-testid="pose-card-one-hand-in-pocket"] .pose-card__visual')!);
    await flush();
    const video = document.querySelector<HTMLVideoElement>('.camera-video')!;
    Object.defineProperties(video, {
      videoWidth: { configurable: true, value: 720 },
      videoHeight: { configurable: true, value: 1280 },
    });
    await click(byLabel('拍照'));
    expect(document.querySelector('[data-testid="result-screen"]')).not.toBeNull();
    expect(document.body.textContent).toContain('照片已拍好');
    expect(document.body.textContent).toContain('再拍一张');
    expect(document.body.textContent).toContain('换个姿势');
    expect(document.querySelector('.result-actions--single')).toBeNull();
    await click(byText('保存照片'));
    expect(nativeMocks.savePhoto).toHaveBeenCalledTimes(1);
  });

  it('enables AI Pose directly after an uploaded image is decoded', async () => {
    let completeGeneration!: (image: string) => void;
    aiPoseMocks.generateAiPose.mockImplementation(() => new Promise((resolve) => { completeGeneration = resolve; }));
    await click(document.querySelector<HTMLButtonElement>('button[aria-label^="选择"]')!);
    const input = document.querySelector<HTMLInputElement>('[aria-label="上传待修改人物照片"]')!;
    Object.defineProperty(input, 'files', { configurable: true, value: [new File(['person-photo'], 'person.jpg', { type: 'image/jpeg' })] });
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await new Promise((resolve) => setTimeout(resolve, 20));
    });
    expect(document.querySelector<HTMLImageElement>('.camera-uploaded-image')?.src).toMatch(/^data:image\/jpeg;base64,/);
    expect(document.body.textContent).toContain('照片已就绪，可以使用 AI Pose');
    expect(byLabel('使用 AI Pose').disabled).toBe(false);
    await click(byLabel('使用 AI Pose'));
    expect(document.querySelector('[role="dialog"]')?.textContent).toContain('选择图片的过程不会上传');
    await click(byText('发送并生成'));
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);
    expect(aiPoseMocks.generateAiPose.mock.calls[0][0].sourceImage).toMatch(/^data:image\/jpeg;base64,/);
    expect(document.querySelector('.ai-pose-loading')).toBeNull();
    expect(document.querySelector('.ai-task-banner')?.textContent).toContain('AI Pose 正在后台生成');
    expect(byLabel('返回姿势库').disabled).toBe(false);
    completeGeneration('data:image/jpeg;base64,YWktcG9zZQ==');
    await flush();
    expect(document.querySelector('.ai-task-banner')?.textContent).toContain('AI Pose 已完成');
    expect(document.querySelector('[data-testid="result-screen"]')).toBeNull();
    await click(byText('查看'));
    expect(document.body.textContent).toContain('AI Pose 已生成');
  });

  it('enables AI Pose from a ready camera without person detection', async () => {
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: vi.fn(async () => ({ getTracks: () => [{ stop: vi.fn() }] })) },
    });
    await click(document.querySelector<HTMLButtonElement>('button[aria-label^="选择"]')!);
    await flush();
    const video = document.querySelector<HTMLVideoElement>('.camera-video')!;
    Object.defineProperties(video, {
      videoWidth: { configurable: true, value: 720 },
      videoHeight: { configurable: true, value: 1280 },
    });
    expect(byLabel('使用 AI Pose').disabled).toBe(false);
    await click(byLabel('使用 AI Pose'));
    await click(byText('发送并生成'));
    await flush();
    expect(aiPoseMocks.generateAiPose).toHaveBeenCalledTimes(1);
    expect(document.querySelector('.ai-pose-loading')).toBeNull();
    expect(document.querySelector('.ai-task-banner')?.textContent).toContain('AI Pose 已完成');
    await click(byText('查看'));
    expect(document.body.textContent).toContain('AI Pose 已生成');
  });

  it('keeps native system chrome aligned with light and dark screens', async () => {
    expect(document.documentElement.style.getPropertyValue('--system-bar-background')).toBe('#fff9e8');
    await click(document.querySelector<HTMLButtonElement>('button[aria-label^="选择"]')!);
    expect(document.documentElement.style.getPropertyValue('--system-bar-background')).toBe('#0d0d10');
    expect(document.documentElement.style.getPropertyValue('--system-bar-transition-duration')).toBe('0ms');
  });

  it('asks for gender before starting a random pose with 随心拍', async () => {
    const random = vi.spyOn(Math, 'random').mockReturnValue(0);
    await click(byLabel('随心拍随机选择姿势'));
    expect(document.querySelector('[role="dialog"]')?.textContent).toContain('选择女生或男生');
    const genderRows = [...document.querySelectorAll<HTMLButtonElement>('.random-gender-option')];
    expect(genderRows).toHaveLength(2);
    expect(genderRows.every((row) => row.querySelector('.random-gender-option__gender-icon'))).toBe(true);
    expect(genderRows.every((row) => row.querySelector('.lucide-chevron-right'))).toBe(true);
    expect(genderRows.every((row) => row.querySelector('small') === null)).toBe(true);
    expect(document.querySelector('.camera-title')).toBeNull();
    await click(byLabel('选择女生随心拍'));
    expect(document.querySelector('.camera-title span')?.textContent).toBe(BUILTIN_TEMPLATES.find((template) => template.gender === 'female')?.title);
    random.mockRestore();
  });

  it('randomizes only within the selected male gender', async () => {
    const random = vi.spyOn(Math, 'random').mockReturnValue(0);
    await click(byLabel('随心拍随机选择姿势'));
    await click(byLabel('选择男生随心拍'));
    expect(document.querySelector('.camera-title span')?.textContent).toBe(BUILTIN_TEMPLATES.find((template) => template.gender === 'male')?.title);
    random.mockRestore();
  });

  it('disables a gender with no poses in the favorite-only random scope', async () => {
    await click(byLabel('收藏'));
    await click(byLabel('前往设置页'));
    await click(byText('选择范围'));
    await click([...document.querySelectorAll<HTMLButtonElement>('[aria-label="随心拍选择范围"] button')].find((button) => button.textContent?.includes('收藏'))!);
    await click(byLabel('前往首页'));
    await click(byLabel('随心拍随机选择姿势'));
    expect(byLabel('选择女生随心拍').disabled).toBe(false);
    expect(byLabel('选择男生随心拍').disabled).toBe(true);
  });
});
