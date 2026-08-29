import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import {
  AlertCircle, ArrowLeft, Camera, Check, ChevronRight, Download, Heart, House, ImagePlus,
  Info, ListChecks, LoaderCircle, Lock, Palette, RefreshCcw, Settings, ShieldCheck, Shuffle, SlidersHorizontal,
  Trash2, X,
} from 'lucide-react';
import { Skeleton } from './components/Skeleton';
import { PoseyAiPoseIcon } from './components/PoseyAiPoseIcon';
import { DEFAULT_AI_POSE_PREFERENCES, generateAiPose, type AiPosePreferences, type AiPoseRequest } from './aiPose';
import { formatAiPoseCompletedAt, MAX_ACTIVE_AI_POSE_JOBS, MAX_COMPLETED_AI_POSE_JOBS, retainRecentCompletedAiPoseJobs } from './aiPoseJobs';
import { BUILTIN_TEMPLATES } from './data/templates';
import { publicAssetUrl } from './publicAsset';
import {
  addNativeBackgroundAiPoseListener,
  cancelNativeBackgroundAiPose,
  clearNativeBackgroundAiPose,
  getNativeBackgroundAiPoseJobs,
  startNativeBackgroundAiPose,
  supportsNativeBackgroundAiPose,
} from './native/backgroundAiPose';
import { savePhoto } from './native/photoLibrary';
import { syncSystemBars } from './native/systemBars';
import type { LandmarkMap, PoseCategory, PoseGender, PoseTemplate } from './types';

type Screen = 'library' | 'camera' | 'result';
type LibraryPage = 'home' | 'favorites' | 'ai-pose' | 'settings';
type SourceMode = 'camera' | 'upload';
type Filter = 'all' | PoseCategory;
type CameraStatus = 'idle' | 'requesting' | 'ready' | 'denied' | 'unavailable' | 'error';
type SaveStatus = 'idle' | 'saving' | 'saved' | 'error';
type ResultKind = 'photo' | 'ai-pose';
type AiPoseJob = {
  completedAt?: number;
  createdAt: number;
  id: string;
  image?: string;
  message?: string;
  native: boolean;
  state: 'queued' | 'generating' | 'completed' | 'failed';
  targetTitle: string;
};
type HomeTheme = 'sunny-cream' | 'sea-breeze' | 'peach-sunset' | 'lavender-evening' | 'mint-garden' | 'sakura-mist' | 'lemon-soda';
type ShuffleScope = 'all' | 'favorites';

type AiPosePreferenceKey = keyof AiPosePreferences;

function useLiquidMotion(value: string) {
  const previous = useRef(value);
  const [motionKey, setMotionKey] = useState(0);
  useEffect(() => {
    if (previous.current === value) return;
    previous.current = value;
    setMotionKey((key) => key + 1);
  }, [value]);
  return motionKey;
}
type SettingsView = 'main' | 'theme' | 'shuffle' | 'product' | 'privacy';
type SettingsMotionDirection = 'tab' | 'forward' | 'back';

const AI_POSE_BANNER_DURATION_MS = 4000;
const AI_POSE_SWIPE_ACTION_WIDTH = 76;
const AI_POSE_SWIPE_OPEN_THRESHOLD = 34;

const nativeDebugMode = (window as Window & { __POSEY_DEBUG__?: string }).__POSEY_DEBUG__
  ?? (import.meta.env.DEV ? new URLSearchParams(window.location.search).get('poseyDebug') ?? undefined : undefined);

const filterOptions: Array<{ id: Filter; label: string }> = [
  { id: 'all', label: '全部' },
  { id: 'standing', label: '站姿' },
  { id: 'half', label: '半身' },
  { id: 'seated', label: '坐姿' },
  { id: 'crouching', label: '蹲跪' },
];
const genderOptions: Array<{ id: PoseGender; label: string }> = [
  { id: 'female', label: '女生' },
  { id: 'male', label: '男生' },
];

function GenderSymbol({ gender, className = '' }: { gender: PoseGender; className?: string }) {
  const iconClassName = `gender-symbol${className ? ` ${className}` : ''}`;
  return gender === 'female' ? (
    <svg className={iconClassName} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="8" r="4.5" />
      <path d="M12 12.5V21M8.5 17.5h7" />
    </svg>
  ) : (
    <svg className={iconClassName} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="9" cy="14" r="4.5" />
      <path d="m12.2 10.8 6.3-6.3M14 4.5h4.5V9" />
    </svg>
  );
}

const aiPosePreferenceGroups: Array<{
  key: AiPosePreferenceKey;
  label: string;
  options: Array<{ label: string; value: string }>;
}> = [
  { key: 'faceFidelity', label: '面部一致性', options: [{ label: '严格保持', value: 'strict' }, { label: '自然过渡', value: 'natural' }] },
  { key: 'expression', label: '表情', options: [{ label: '保持原样', value: 'preserve' }, { label: '轻微调整', value: 'subtle' }] },
  { key: 'gaze', label: '视线', options: [{ label: '保持原样', value: 'preserve' }, { label: '跟随姿势', value: 'follow-pose' }] },
];

function AiPosePreferenceControls({ preferences, onChange }: {
  preferences: AiPosePreferences;
  onChange: (key: AiPosePreferenceKey, value: string) => void;
}) {
  return (
    <section className="ai-pose-preferences" aria-label="AI Pose 生成参数">
      <header><strong>生成参数</strong><small>优先保护人物原貌，参数会自动用于本次生成</small></header>
      <div className="ai-pose-preferences__groups">
        {aiPosePreferenceGroups.map((group) => (
          <div className="ai-pose-preference" key={group.key}>
            <span>{group.label}</span>
            <div role="group" aria-label={group.label}>
              {group.options.map((option) => {
                const selected = preferences[group.key] === option.value;
                return <button type="button" key={option.value} className={selected ? 'active' : ''} aria-pressed={selected} aria-label={`${group.label}：${option.label}`} onClick={() => onChange(group.key, option.value)}>{option.label}</button>;
              })}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function AiPoseTaskBanner({ jobs, onCancel, onDismiss, onView, signature, visible, visibleUntil }: {
  jobs: AiPoseJob[];
  onCancel: (job: AiPoseJob) => void;
  onDismiss: (job: AiPoseJob) => void;
  onView: (job: AiPoseJob) => void;
  signature: string;
  visible: boolean;
  visibleUntil: number;
}) {
  const job = jobs[0];
  const [, setExpiredAt] = useState(0);
  useEffect(() => {
    if (!job || !visible) return;
    const remaining = visibleUntil - Date.now();
    if (remaining <= 0) return;
    const timer = window.setTimeout(() => setExpiredAt(Date.now()), remaining);
    return () => window.clearTimeout(timer);
  }, [job, signature, visible, visibleUntil]);
  if (!job || !visible || Date.now() >= visibleUntil) return null;
  const isQueued = job.state === 'queued';
  const isGenerating = job.state === 'generating';
  const isCompleted = job.state === 'completed';
  return (
    <aside className={`ai-task-banner ai-task-banner--${job.state}`} role="status" aria-live="polite">
      <span className="ai-task-banner__icon">
        {isGenerating ? <LoaderCircle className="spin" /> : isQueued ? <ListChecks /> : isCompleted ? <Check /> : <AlertCircle />}
      </span>
      <span className="ai-task-banner__copy">
        <strong>{isGenerating ? 'AI Pose 正在后台生成' : isQueued ? 'AI Pose 已加入队列' : isCompleted ? 'AI Pose 已完成' : 'AI Pose 生成失败'}</strong>
        <small>{isGenerating ? `正在生成「${job.targetTitle}」` : isQueued ? `「${job.targetTitle}」正在等待` : isCompleted ? `「${job.targetTitle}」已准备好` : job.message ?? '请稍后重新生成'}{jobs.length > 1 ? ` · 共 ${jobs.length} 条` : ''}</small>
      </span>
      {isGenerating || isQueued ? (
        <button onClick={() => onCancel(job)} aria-label="取消后台生成">取消</button>
      ) : isCompleted ? (
        <button className="ai-task-banner__primary" onClick={() => onView(job)}>查看</button>
      ) : (
        <button className="ai-task-banner__close" onClick={() => onDismiss(job)} aria-label="关闭生成结果提示"><X /></button>
      )}
    </aside>
  );
}

function AiPoseTaskList({ jobs, onCancel, onDismiss, onView }: {
  jobs: AiPoseJob[];
  onCancel: (job: AiPoseJob) => void;
  onDismiss: (job: AiPoseJob) => void;
  onView: (job: AiPoseJob) => void;
}) {
  const counts = jobs.reduce((result, item) => ({ ...result, [item.state]: result[item.state] + 1 }), {
    queued: 0,
    generating: 0,
    completed: 0,
    failed: 0,
  });
  const activeCount = counts.generating + counts.queued;
  const summary = [
    counts.generating && `${counts.generating} 个生成中`,
    counts.queued && `${counts.queued} 个等待中`,
    counts.completed && `${counts.completed} 个已完成`,
    counts.failed && `${counts.failed} 个失败`,
  ].filter(Boolean).join(' · ');

  return (
    <section className="ai-task-panel" aria-labelledby="ai-task-panel-title">
      <header className="ai-task-panel__header">
        <span>
          <strong id="ai-task-panel-title">AI Pose List</strong>
          <small>{summary}{counts.completed ? ` · 最多保留 ${MAX_COMPLETED_AI_POSE_JOBS} 个` : ''}</small>
        </span>
        <span className={activeCount >= MAX_ACTIVE_AI_POSE_JOBS ? 'ai-task-panel__count is-full' : 'ai-task-panel__count'}>{activeCount}/{MAX_ACTIVE_AI_POSE_JOBS}</span>
      </header>
      <div className="ai-task-list">
        {jobs.map((item) => <AiPoseTaskRow item={item} key={item.id} onCancel={onCancel} onDismiss={onDismiss} onView={onView} />)}
      </div>
    </section>
  );
}

function AiPoseTaskRow({ item, onCancel, onDismiss, onView }: {
  item: AiPoseJob;
  onCancel: (job: AiPoseJob) => void;
  onDismiss: (job: AiPoseJob) => void;
  onView: (job: AiPoseJob) => void;
}) {
  const isCompleted = item.state === 'completed';
  const completedAt = item.completedAt ?? item.createdAt;
  const [swipeOffset, setSwipeOffset] = useState(0);
  const gesture = useRef<{
    axis: 'horizontal' | 'vertical' | null;
    latestOffset: number;
    startOffset: number;
    startX: number;
    startY: number;
  } | null>(null);
  const suppressClick = useRef(false);

  const finishSwipe = (event: React.PointerEvent<HTMLDivElement>, cancelled = false) => {
    const current = gesture.current;
    if (!current) return;
    const shouldOpen = !cancelled && current.axis === 'horizontal'
      && current.latestOffset <= -AI_POSE_SWIPE_OPEN_THRESHOLD;
    setSwipeOffset(shouldOpen ? -AI_POSE_SWIPE_ACTION_WIDTH : 0);
    gesture.current = null;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
  };

  const row = (
    <div
      className={`ai-task-list__row ai-task-list__row--${item.state}${isCompleted ? ' ai-task-list__swipe-surface' : ''}`}
      onClickCapture={isCompleted ? (event) => {
        if (!suppressClick.current) return;
        event.preventDefault();
        event.stopPropagation();
        suppressClick.current = false;
      } : undefined}
      onPointerCancel={isCompleted ? (event) => finishSwipe(event, true) : undefined}
      onPointerDown={isCompleted ? (event) => {
        gesture.current = {
          axis: null,
          latestOffset: swipeOffset,
          startOffset: swipeOffset,
          startX: event.clientX,
          startY: event.clientY,
        };
        suppressClick.current = false;
        event.currentTarget.setPointerCapture?.(event.pointerId);
      } : undefined}
      onPointerMove={isCompleted ? (event) => {
        const current = gesture.current;
        if (!current) return;
        const deltaX = event.clientX - current.startX;
        const deltaY = event.clientY - current.startY;
        if (!current.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 6) {
          current.axis = Math.abs(deltaX) > Math.abs(deltaY) ? 'horizontal' : 'vertical';
        }
        if (current.axis !== 'horizontal') return;
        event.preventDefault();
        const nextOffset = Math.max(-AI_POSE_SWIPE_ACTION_WIDTH, Math.min(0, current.startOffset + deltaX));
        current.latestOffset = nextOffset;
        suppressClick.current = Math.abs(deltaX) >= 8;
        setSwipeOffset(nextOffset);
      } : undefined}
      onPointerUp={isCompleted ? (event) => finishSwipe(event) : undefined}
      style={isCompleted ? { transform: `translate3d(${swipeOffset}px, 0, 0)` } : undefined}
    >
      <span className="ai-task-list__state">{item.state === 'generating' ? <LoaderCircle className="spin" /> : item.state === 'queued' ? <ListChecks /> : item.state === 'completed' ? <Check /> : <AlertCircle />}</span>
      <span className="ai-task-list__copy">
        <strong>{item.targetTitle}</strong>
        <small>{item.state === 'generating' ? '正在生成' : item.state === 'queued' ? '等待前一项完成' : item.state === 'completed' ? <time dateTime={new Date(completedAt).toISOString()}>完成于 {formatAiPoseCompletedAt(completedAt)}</time> : item.message ?? '生成失败'}</small>
      </span>
      {item.state === 'completed'
        ? <button className="ai-task-list__primary" onClick={() => onView(item)}>查看</button>
        : item.state === 'failed'
          ? <button onClick={() => onDismiss(item)}>移除</button>
          : <button onClick={() => onCancel(item)}>取消</button>}
    </div>
  );

  if (!isCompleted) return row;
  return (
    <div className={`ai-task-list__swipe-shell${swipeOffset < 0 ? ' is-open' : ''}`}>
      {row}
      <button
        className="ai-task-list__delete"
        aria-label={`删除已完成任务：${item.targetTitle}`}
        onClick={() => onDismiss(item)}
        onFocus={() => setSwipeOffset(-AI_POSE_SWIPE_ACTION_WIDTH)}
      >
        <Trash2 aria-hidden="true" /><span>删除</span>
      </button>
    </div>
  );
}
const homeThemeOptions: Array<{
  id: HomeTheme;
  label: string;
  accent: string;
  soft: string;
  pageStart: string;
  pageEnd: string;
  chrome: string;
  control: string;
  surface: string;
  card: string;
  cardAlt: string;
}> = [
  { id: 'sunny-cream', label: '晴日奶油', accent: '#a9512f', soft: '#ffdda0', pageStart: '#fff6db', pageEnd: '#f2ddbb', chrome: '#fff9e8', control: '#ecd9b8', surface: '#fffaf0', card: '#fffdf7', cardAlt: '#f7e7ce' },
  { id: 'sea-breeze', label: '海盐清风', accent: '#2f6f91', soft: '#b9e0ef', pageStart: '#e8f8fc', pageEnd: '#c8e3eb', chrome: '#f2fbfd', control: '#d5e8ed', surface: '#f5fbfc', card: '#f8fdfe', cardAlt: '#dceef2' },
  { id: 'peach-sunset', label: '蜜桃日落', accent: '#a94f43', soft: '#f8c3b3', pageStart: '#fff0e8', pageEnd: '#edc9c0', chrome: '#fff7f3', control: '#efd9d3', surface: '#fff9f6', card: '#fffaf8', cardAlt: '#f3dcd6' },
  { id: 'lavender-evening', label: '薰衣暮色', accent: '#67528e', soft: '#d8cdf0', pageStart: '#f3effc', pageEnd: '#d7cce9', chrome: '#faf8ff', control: '#e4def0', surface: '#faf8ff', card: '#fdfbff', cardAlt: '#e8e1f3' },
  { id: 'mint-garden', label: '薄荷花园', accent: '#33735a', soft: '#bfe4d0', pageStart: '#eaf8f0', pageEnd: '#c5ddce', chrome: '#f5fbf7', control: '#d8e9de', surface: '#f7fcf8', card: '#fbfefc', cardAlt: '#daeade' },
  { id: 'sakura-mist', label: '樱花晨雾', accent: '#9b4e68', soft: '#efc5d4', pageStart: '#fff0f5', pageEnd: '#edced9', chrome: '#fff8fa', control: '#eedce2', surface: '#fff9fb', card: '#fffafd', cardAlt: '#f1dce4' },
  { id: 'lemon-soda', label: '柠檬苏打', accent: '#6e751e', soft: '#e5e79d', pageStart: '#fbfce7', pageEnd: '#dfe3ad', chrome: '#fdfdeb', control: '#e7e8c5', surface: '#fcfcec', card: '#fffff7', cardAlt: '#e9eac4' },
];

const APP_VERSION = '1.0';
const STORAGE_KEYS = {
  aiPosePreferences: 'posey:ai-pose-preferences',
  favorites: 'posey:favorites',
  homeTheme: 'posey:home-theme',
  shuffleScope: 'posey:shuffle-scope',
} as const;
const LEGACY_STORAGE_KEYS = {
  aiPosePreferences: 'posepilot:ai-pose-preferences',
  favorites: 'posepilot:favorites',
  homeTheme: 'posepilot:home-theme',
  shuffleScope: 'posepilot:shuffle-scope',
} as const;

function readMigratedStorage(key: keyof typeof STORAGE_KEYS) {
  const current = localStorage.getItem(STORAGE_KEYS[key]);
  if (current !== null) return current;
  const legacy = localStorage.getItem(LEGACY_STORAGE_KEYS[key]);
  if (legacy !== null) localStorage.setItem(STORAGE_KEYS[key], legacy);
  return legacy;
}

function readStoredShuffleScope(): ShuffleScope {
  return readMigratedStorage('shuffleScope') === 'favorites' ? 'favorites' : 'all';
}

function readStoredAiPosePreferences(): AiPosePreferences {
  try {
    const stored = JSON.parse(readMigratedStorage('aiPosePreferences') ?? '{}') as Partial<AiPosePreferences>;
    return {
      faceFidelity: stored.faceFidelity === 'natural' ? 'natural' : DEFAULT_AI_POSE_PREFERENCES.faceFidelity,
      expression: stored.expression === 'subtle' ? 'subtle' : DEFAULT_AI_POSE_PREFERENCES.expression,
      gaze: stored.gaze === 'follow-pose' ? 'follow-pose' : DEFAULT_AI_POSE_PREFERENCES.gaze,
    };
  } catch {
    return DEFAULT_AI_POSE_PREFERENCES;
  }
}

function useStoredFavorites() {
  const [favorites, setFavorites] = useState<string[]>(() => {
    try { return JSON.parse(readMigratedStorage('favorites') ?? '[]'); } catch { return []; }
  });
  const toggle = (id: string) => setFavorites((current) => {
    const next = current.includes(id) ? current.filter((item) => item !== id) : [...current, id];
    localStorage.setItem(STORAGE_KEYS.favorites, JSON.stringify(next));
    return next;
  });
  return { favorites, toggle };
}

function makePoseGuideReference(template: PoseTemplate) {
  const canvas = document.createElement('canvas');
  canvas.width = 768;
  canvas.height = 1152;
  const ctx = canvas.getContext('2d');
  if (!ctx) return '';
  ctx.fillStyle = '#17171b';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.strokeStyle = '#f8f5ee';
  ctx.lineWidth = 14;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  ([['nose', 'leftShoulder'], ['nose', 'rightShoulder'], ['leftShoulder', 'rightShoulder'], ['leftShoulder', 'leftElbow'], ['leftElbow', 'leftWrist'], ['rightShoulder', 'rightElbow'], ['rightElbow', 'rightWrist'], ['leftShoulder', 'leftHip'], ['rightShoulder', 'rightHip'], ['leftHip', 'rightHip'], ['leftHip', 'leftKnee'], ['leftKnee', 'leftAnkle'], ['rightHip', 'rightKnee'], ['rightKnee', 'rightAnkle']] as Array<[keyof LandmarkMap, keyof LandmarkMap]>).forEach(([from, to]) => {
    ctx.moveTo(template.landmarks[from].x * canvas.width, template.landmarks[from].y * canvas.height);
    ctx.lineTo(template.landmarks[to].x * canvas.width, template.landmarks[to].y * canvas.height);
  });
  ctx.stroke();
  return canvas.toDataURL('image/png');
}

function currentFrameDataUrl(sourceMode: SourceMode, video: HTMLVideoElement | null, uploadedImage = '') {
  if (sourceMode === 'upload') return uploadedImage;
  if (!video?.videoWidth || !video.videoHeight) return '';
  const canvas = document.createElement('canvas');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  canvas.getContext('2d')?.drawImage(video, 0, 0);
  return canvas.toDataURL('image/jpeg', 0.92);
}

function readImageFile(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    if (!file.type.startsWith('image/')) {
      reject(new Error('请选择一张图片'));
      return;
    }
    if (file.size > 12 * 1024 * 1024) {
      reject(new Error('图片请不要超过 12 MB'));
      return;
    }
    const reader = new FileReader();
    reader.onload = () => typeof reader.result === 'string' ? resolve(reader.result) : reject(new Error('图片读取失败，请再试一次'));
    reader.onerror = () => reject(new Error('图片读取失败，请再试一次'));
    reader.readAsDataURL(file);
  });
}

function cameraFailure(error: unknown): { status: CameraStatus; message: string } {
  if (error instanceof DOMException && (error.name === 'NotAllowedError' || error.name === 'SecurityError')) {
    return { status: 'denied', message: '相机权限没打开。请到系统设置允许相机，然后再试一次。' };
  }
  if (error instanceof DOMException && (error.name === 'NotFoundError' || error.name === 'OverconstrainedError')) {
    return { status: 'unavailable', message: '没有找到可用的相机。请检查设备后再试一次。' };
  }
  return { status: 'error', message: '相机暂时打不开。请再试一次。' };
}

export default function App() {
  const [screen, setScreen] = useState<Screen>(() => nativeDebugMode === 'camera' || nativeDebugMode === 'upload-camera'
    ? 'camera'
    : nativeDebugMode === 'result' ? 'result' : 'library');
  const [libraryPage, setLibraryPage] = useState<LibraryPage>(nativeDebugMode === 'favorites'
    ? 'favorites'
    : nativeDebugMode === 'ai-queue'
      ? 'ai-pose'
      : nativeDebugMode === 'settings' || nativeDebugMode === 'settings-product'
        ? 'settings'
        : 'home');
  const [filter, setFilter] = useState<Filter>('all');
  const [gender, setGender] = useState<PoseGender>('female');
  const templates = BUILTIN_TEMPLATES;
  const [selected, setSelected] = useState<PoseTemplate>(BUILTIN_TEMPLATES[0]);
  const [sourceMode, setSourceMode] = useState<SourceMode>(nativeDebugMode === 'upload-camera' ? 'upload' : 'camera');
  const [shuffleScope, setShuffleScope] = useState<ShuffleScope>(readStoredShuffleScope);
  const [capturedUrl, setCapturedUrl] = useState(() => nativeDebugMode === 'result' ? publicAssetUrl('/poses/one-hand-in-pocket.webp') : '');
  const [notice, setNotice] = useState('');
  const [cameraStatus, setCameraStatus] = useState<CameraStatus>('idle');
  const [cameraMessage, setCameraMessage] = useState('');
  const [cameraAttempt, setCameraAttempt] = useState(0);
  const [settingsView, setSettingsView] = useState<SettingsView>(nativeDebugMode === 'settings-product' ? 'product' : 'main');
  const [settingsMotionDirection, setSettingsMotionDirection] = useState<SettingsMotionDirection>(nativeDebugMode === 'settings-product' ? 'forward' : 'tab');
  const [showRandomGenderPicker, setShowRandomGenderPicker] = useState(false);
  const [showAiPosePicker, setShowAiPosePicker] = useState(false);
  const [aiPosePickerGender, setAiPosePickerGender] = useState<PoseGender>('female');
  const [aiPoseTarget, setAiPoseTarget] = useState<PoseTemplate | null>(nativeDebugMode === 'ai-queue' ? BUILTIN_TEMPLATES[0] : null);
  const [aiPosePreferences, setAiPosePreferences] = useState<AiPosePreferences>(readStoredAiPosePreferences);
  const [resultKind, setResultKind] = useState<ResultKind>('photo');
  const [aiPoseJobs, setAiPoseJobs] = useState<AiPoseJob[]>(() => nativeDebugMode === 'ai-queue'
    ? [
      { createdAt: Date.now(), id: 'debug-queued', native: false, state: 'queued', targetTitle: '回眸扶帽' },
      { createdAt: Date.now() - 1, id: 'debug-generating', native: false, state: 'generating', targetTitle: '单手插兜' },
      { createdAt: Date.now() - 2, id: 'debug-queued-two', native: false, state: 'queued', targetTitle: '侧身回望' },
    ]
    : nativeDebugMode === 'ai-background'
    ? [{ createdAt: Date.now(), id: 'debug-generating', native: false, state: 'generating', targetTitle: '单手插兜' }]
    : nativeDebugMode === 'ai-completed'
      ? [{ createdAt: Date.now(), id: 'debug-completed', image: publicAssetUrl('/poses/one-hand-in-pocket.webp'), native: false, state: 'completed', targetTitle: '单手插兜' }]
      : []);
  const [showAiPoseConsent, setShowAiPoseConsent] = useState(false);
  const [uploadedSourceImage, setUploadedSourceImage] = useState(() => nativeDebugMode === 'upload-camera' || nativeDebugMode === 'ai-queue' ? publicAssetUrl('/poses/one-hand-in-pocket.webp') : '');
  const [uploadingSource, setUploadingSource] = useState(false);
  const [saveStatus, setSaveStatus] = useState<SaveStatus>('idle');
  const [homeTheme, setHomeTheme] = useState<HomeTheme>(() => {
    const stored = readMigratedStorage('homeTheme');
    return homeThemeOptions.some((option) => option.id === stored) ? stored as HomeTheme : 'sunny-cream';
  });
  const videoRef = useRef<HTMLVideoElement>(null);
  const sourceFileRef = useRef<HTMLInputElement>(null);
  const randomTriggerRef = useRef<HTMLButtonElement>(null);
  const aiPosePickerTriggerRef = useRef<HTMLButtonElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const captureLock = useRef(false);
  const aiPoseAbortControllers = useRef(new Map<string, AbortController>());
  const dismissedNativeAiPoseJobIDs = useRef(new Set<string>());
  const nativeAiPoseSubmissionChain = useRef(Promise.resolve());
  const webAiPoseQueue = useRef<Array<{ controller: AbortController; id: string; request: AiPoseRequest }>>([]);
  const runningWebAiPoseJob = useRef<string | null>(null);
  const lastRandomPoseId = useRef<string | null>(null);
  const libraryScrollTop = useRef(0);
  const genderSwitchRequest = useRef(0);
  const systemBarStateRef = useRef<{ screen: Screen; chrome: string } | null>(null);
  const illustrationCache = useRef(new Map<string, { image: HTMLImageElement; decoded: Promise<void> }>());
  const aiPoseBannerPresentationRef = useRef({ hidden: false, signature: '', surface: '', visibleUntil: 0 });
  const { favorites, toggle: toggleFavorite } = useStoredFavorites();
  const currentHomeTheme = homeThemeOptions.find((option) => option.id === homeTheme) ?? homeThemeOptions[0];
  const activeAiPoseJobCount = aiPoseJobs.filter((job) => job.state === 'queued' || job.state === 'generating').length;
  const isAiPoseQueueFull = activeAiPoseJobCount >= MAX_ACTIVE_AI_POSE_JOBS;
  const bottomTabIndex = libraryPage === 'home' ? 0 : libraryPage === 'favorites' ? 1 : libraryPage === 'ai-pose' ? 3 : 4;
  const bottomLiquidMotionKey = useLiquidMotion(libraryPage);
  const genderLiquidMotionKey = useLiquidMotion(gender);
  const aiPoseGenderLiquidMotionKey = useLiquidMotion(aiPosePickerGender);
  const aiPoseBannerSignature = aiPoseJobs.map((job) => `${job.id}:${job.state}`).join('|');
  const aiPoseBannerSurface = screen === 'library' ? `${screen}:${libraryPage}` : screen;
  if (aiPoseBannerSignature !== aiPoseBannerPresentationRef.current.signature) {
    aiPoseBannerPresentationRef.current = {
      hidden: false,
      signature: aiPoseBannerSignature,
      surface: aiPoseBannerSurface,
      visibleUntil: Date.now() + AI_POSE_BANNER_DURATION_MS,
    };
  } else if (aiPoseBannerSignature && aiPoseBannerSurface !== aiPoseBannerPresentationRef.current.surface) {
    aiPoseBannerPresentationRef.current.hidden = true;
  }
  const aiPoseBannerPresentation = aiPoseBannerPresentationRef.current;

  const updateAiPosePreference = (key: AiPosePreferenceKey, value: string) => {
    setAiPosePreferences((current) => {
      const next = { ...current, [key]: value } as AiPosePreferences;
      localStorage.setItem(STORAGE_KEYS.aiPosePreferences, JSON.stringify(next));
      return next;
    });
  };

  const preloadIllustrations = useCallback((urls: string[]) => Promise.all(urls.map((url) => {
    const cached = illustrationCache.current.get(url);
    if (cached) return cached.decoded;
    const image = new Image();
    image.decoding = 'async';
    image.src = url;
    const decoded = typeof image.decode === 'function' ? image.decode().catch(() => undefined) : Promise.resolve();
    illustrationCache.current.set(url, { image, decoded });
    return decoded;
  })).then(() => undefined), []);

  useLayoutEffect(() => {
    const previous = systemBarStateRef.current;
    const animateThemeChange = previous?.screen === 'library'
      && screen === 'library'
      && previous.chrome !== currentHomeTheme.chrome;
    void syncSystemBars(screen === 'library' ? 'light' : 'dark', currentHomeTheme.chrome, animateThemeChange);
    systemBarStateRef.current = { screen, chrome: currentHomeTheme.chrome };
  }, [currentHomeTheme.chrome, screen]);

  useEffect(() => {
    if (nativeDebugMode !== 'library-bottom' || screen !== 'library') return;
    const timer = window.setTimeout(() => {
      window.scrollTo({ top: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight) });
    }, 500);
    return () => window.clearTimeout(timer);
  }, [screen]);

  useEffect(() => {
    if (screen !== 'library' || nativeDebugMode === 'library-bottom') return;
    const top = libraryScrollTop.current;
    const restore = () => {
      try { window.scrollTo({ top, left: 0, behavior: 'auto' }); } catch { /* native WebView may not expose scrollTo during mount */ }
    };
    const frame = window.requestAnimationFrame(restore);
    const timer = window.setTimeout(restore, 40);
    return () => { window.cancelAnimationFrame(frame); window.clearTimeout(timer); };
  }, [screen]);

  const activeTemplate = selected;
  const visibleTemplates = templates.filter((template) => {
    const genderMatches = template.source.usageStatus === 'user-imported' || template.gender === gender;
    const categoryMatches = filter === 'all' || template.category === filter;
    return genderMatches && categoryMatches;
  });
  const favoriteTemplates = templates.filter((template) => favorites.includes(template.id));
  const randomScopeTemplates = shuffleScope === 'favorites' ? favoriteTemplates : templates;
  const randomFemaleTemplates = randomScopeTemplates.filter((template) => template.gender === 'female');
  const randomMaleTemplates = randomScopeTemplates.filter((template) => template.gender === 'male');
  const aiPosePickerTemplates = templates.filter((template) => template.gender === aiPosePickerGender);
  useEffect(() => {
    void preloadIllustrations(templates.flatMap((template) => template.illustration ? [template.illustration] : []));
  }, [preloadIllustrations, templates]);

  const chooseGender = async (nextGender: PoseGender) => {
    const request = ++genderSwitchRequest.current;
    if (nextGender === gender) return;
    const targetIllustrations = templates.flatMap((template) => template.gender === nextGender && template.illustration ? [template.illustration] : []);
    await preloadIllustrations(targetIllustrations);
    if (request === genderSwitchRequest.current) setGender(nextGender);
  };

  const chooseHomeTheme = (theme: HomeTheme) => {
    setHomeTheme(theme);
    localStorage.setItem(STORAGE_KEYS.homeTheme, theme);
  };

  const chooseShuffleScope = (scope: ShuffleScope) => {
    if (scope === 'favorites' && favoriteTemplates.length === 0) return;
    setShuffleScope(scope);
    localStorage.setItem(STORAGE_KEYS.shuffleScope, scope);
  };

  useEffect(() => {
    if (favoriteTemplates.length > 0 || shuffleScope !== 'favorites') return;
    setShuffleScope('all');
    localStorage.setItem(STORAGE_KEYS.shuffleScope, 'all');
  }, [favoriteTemplates.length, shuffleScope]);

  useEffect(() => {
    if (!showRandomGenderPicker) return;
    const previousOverflow = document.body.style.overflow;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setShowRandomGenderPicker(false);
    };
    document.body.style.overflow = 'hidden';
    document.addEventListener('keydown', closeOnEscape);
    const frame = window.requestAnimationFrame(() => document.querySelector<HTMLButtonElement>('.random-gender-option:not(:disabled)')?.focus());
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener('keydown', closeOnEscape);
      window.cancelAnimationFrame(frame);
      randomTriggerRef.current?.focus();
    };
  }, [showRandomGenderPicker]);

  useEffect(() => {
    if (!showAiPosePicker) return;
    const previousOverflow = document.body.style.overflow;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setShowAiPosePicker(false);
    };
    document.body.style.overflow = 'hidden';
    document.addEventListener('keydown', closeOnEscape);
    const frame = window.requestAnimationFrame(() => document.querySelector<HTMLButtonElement>('.ai-pose-picker__close')?.focus());
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener('keydown', closeOnEscape);
      window.cancelAnimationFrame(frame);
      aiPosePickerTriggerRef.current?.focus();
    };
  }, [showAiPosePicker]);

  const prefersReducedMotion = () => window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;

  const showHome = () => {
    setLibraryPage('home');
    window.scrollTo({ top: 0, left: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  };

  const showFavorites = () => {
    setLibraryPage('favorites');
    window.scrollTo({ top: 0, left: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  };

  const openCamera = (template: PoseTemplate) => {
    libraryScrollTop.current = window.scrollY || document.documentElement.scrollTop || 0;
    setSelected(template);
    setSourceMode('camera');
    setCameraStatus('idle');
    setCameraMessage('');
    setCameraAttempt((attempt) => attempt + 1);
    setCapturedUrl('');
    setResultKind('photo');
    setShowAiPoseConsent(false);
    setUploadedSourceImage('');
    setUploadingSource(false);
    setSaveStatus('idle');
    captureLock.current = false;
    setScreen('camera');
  };

  const openAiPose = () => {
    setLibraryPage('ai-pose');
    setSourceMode('upload');
    setCameraStatus('idle');
    setCameraMessage('');
    setCapturedUrl('');
    setResultKind('photo');
    setShowAiPoseConsent(false);
    setUploadedSourceImage('');
    setUploadingSource(false);
    setAiPoseTarget(null);
    setShowAiPosePicker(false);
    setSaveStatus('idle');
    captureLock.current = false;
    window.scrollTo({ top: 0, left: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  };

  const chooseAiPoseTarget = (template: PoseTemplate) => {
    setSelected(template);
    setAiPoseTarget(template);
    setShowAiPosePicker(false);
  };

  const openRandomPose = (targetGender: PoseGender) => {
    const genderTemplates = randomScopeTemplates.filter((template) => template.gender === targetGender);
    const candidates = genderTemplates.length > 1
      ? genderTemplates.filter((template) => template.id !== lastRandomPoseId.current)
      : genderTemplates;
    if (candidates.length === 0) return;
    const chosen = candidates[Math.floor(Math.random() * candidates.length)];
    if (!chosen) return;
    lastRandomPoseId.current = chosen.id;
    setGender(targetGender);
    setShowRandomGenderPicker(false);
    openCamera(chosen);
  };

  const openRandomGenderPicker = () => setShowRandomGenderPicker(true);
  const closeRandomGenderPicker = () => setShowRandomGenderPicker(false);

  const openSettings = () => {
    setSettingsMotionDirection('tab');
    setSettingsView('main');
    setLibraryPage('settings');
    window.scrollTo({ top: 0, left: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  };

  const openSettingsView = (view: SettingsView) => {
    setSettingsMotionDirection(view === 'main' ? 'back' : 'forward');
    setSettingsView(view);
    window.scrollTo({ top: 0, left: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
  };

  const returnToLibrary = () => setScreen('library');

  const capture = useCallback(() => {
    if (captureLock.current) return;
    const video = videoRef.current;
    if (sourceMode === 'camera') {
      if (cameraStatus !== 'ready' || !video?.videoWidth || !video.videoHeight) {
        setNotice('相机准备好后才能拍照');
        return;
      }
    }
    const url = currentFrameDataUrl(sourceMode, video, uploadedSourceImage);
    if (!url) {
      setNotice('这次没有拍到，请再试一次');
      return;
    }
    captureLock.current = true;
    setResultKind('photo');
    setSaveStatus('idle');
    setCapturedUrl(url);
    setScreen('result');
  }, [cameraStatus, sourceMode, uploadedSourceImage]);

  const uploadAiPoseSource = async (file?: File) => {
    if (!file || uploadingSource) return;
    setUploadingSource(true);
    setUploadedSourceImage('');
    try {
      const dataUrl = await readImageFile(file);
      const image = new Image();
      image.src = dataUrl;
      await image.decode();
      setUploadedSourceImage(dataUrl);
      setSourceMode('upload');
      setCameraStatus('idle');
      setCameraMessage('');
      captureLock.current = false;
      setNotice('照片已就绪，可以使用 AI Pose');
    } catch (error) {
      setNotice(error instanceof Error ? error.message : '这张图片暂时无法读取');
    } finally {
      setUploadingSource(false);
      if (sourceFileRef.current) sourceFileRef.current.value = '';
    }
  };

  const aiPoseSourceReady = sourceMode === 'upload'
    ? Boolean(uploadedSourceImage)
    : cameraStatus === 'ready';

  const closeAiPoseConsent = () => {
    setShowAiPoseConsent(false);
    captureLock.current = false;
  };

  const openAiPoseConsent = () => {
    if (isAiPoseQueueFull) {
      setNotice(`AI Pose 队列已满，最多同时处理 ${MAX_ACTIVE_AI_POSE_JOBS} 条`);
      return;
    }
    if (libraryPage === 'ai-pose' && !aiPoseTarget) {
      setNotice('请先选择目标姿势');
      return;
    }
    if (!aiPoseSourceReady) {
      setNotice(sourceMode === 'upload' ? '请先上传照片' : '相机准备好后才能使用 AI Pose');
      return;
    }
    captureLock.current = true;
    setShowAiPoseConsent(true);
  };

  const syncNativeAiPoseJobs = useCallback(async (dropPendingID?: string) => {
    if (!supportsNativeBackgroundAiPose()) return;
    try {
      const nativeJobs = (await getNativeBackgroundAiPoseJobs())
        .filter((job) => !dismissedNativeAiPoseJobIDs.current.has(job.id))
        .map((job) => ({
          completedAt: job.completedAt,
          createdAt: job.createdAt,
          id: job.id,
          image: job.image,
          message: job.message,
          native: true,
          state: job.state,
          targetTitle: job.targetTitle ?? '所选姿势',
        } satisfies AiPoseJob));
      setAiPoseJobs((current) => {
        const receivedNativeJobIDs = new Set(nativeJobs.map((job) => job.id));
        const pendingNativeJobs = current.filter((job) => job.native && job.id.startsWith('pending-') && job.id !== dropPendingID);
        const retainedNativeCompletedJobs = current.filter((job) => job.native
          && !job.id.startsWith('pending-')
          && job.state === 'completed'
          && !receivedNativeJobIDs.has(job.id)
          && !dismissedNativeAiPoseJobIDs.current.has(job.id));
        const webJobs = current.filter((job) => !job.native);
        return retainRecentCompletedAiPoseJobs([...pendingNativeJobs, ...nativeJobs, ...retainedNativeCompletedJobs, ...webJobs]
          .sort((left, right) => right.createdAt - left.createdAt));
      });
    } catch {
      // The web fallback remains available if the native bridge is temporarily unavailable.
    }
  }, []);

  useEffect(() => {
    if (!supportsNativeBackgroundAiPose()) return;
    let disposed = false;
    let listener: { remove: () => Promise<void> } | undefined;
    void addNativeBackgroundAiPoseListener(() => {
      if (!disposed) void syncNativeAiPoseJobs();
    }).then((handle) => { listener = handle; });
    void syncNativeAiPoseJobs();
    const syncWhenVisible = () => {
      if (document.visibilityState === 'visible') void syncNativeAiPoseJobs();
    };
    document.addEventListener('visibilitychange', syncWhenVisible);
    return () => {
      disposed = true;
      document.removeEventListener('visibilitychange', syncWhenVisible);
      void listener?.remove();
    };
  }, [syncNativeAiPoseJobs]);

  const cancelAiPose = async (job: AiPoseJob) => {
    aiPoseAbortControllers.current.get(job.id)?.abort();
    aiPoseAbortControllers.current.delete(job.id);
    webAiPoseQueue.current = webAiPoseQueue.current.filter((item) => item.id !== job.id);
    if (job.native && !job.id.startsWith('pending-')) {
      try { await cancelNativeBackgroundAiPose(job.id); } catch { /* task may already be completing */ }
    }
    setAiPoseJobs((jobs) => jobs.filter((item) => item.id !== job.id));
    setNotice(`已取消「${job.targetTitle}」`);
  };

  const dismissAiPoseJob = (job: AiPoseJob) => {
    if (job.native && !job.id.startsWith('pending-')) {
      dismissedNativeAiPoseJobIDs.current.add(job.id);
      void clearNativeBackgroundAiPose(job.id);
    }
    setAiPoseJobs((jobs) => jobs.filter((item) => item.id !== job.id));
  };

  const viewAiPoseResult = (job: AiPoseJob) => {
    if (!job.image) return;
    const target = templates.find((template) => template.title === job.targetTitle);
    if (target) setSelected(target);
    setCapturedUrl(job.image);
    setResultKind('ai-pose');
    setSaveStatus('idle');
    setScreen('result');
  };

  function runNextWebAiPoseJob() {
    if (runningWebAiPoseJob.current) return;
    const next = webAiPoseQueue.current.shift();
    if (!next) return;
    if (next.controller.signal.aborted) {
      runNextWebAiPoseJob();
      return;
    }
    runningWebAiPoseJob.current = next.id;
    setAiPoseJobs((jobs) => jobs.map((job) => job.id === next.id ? { ...job, state: 'generating' } : job));
    void generateAiPose(next.request, next.controller.signal).then((image) => {
      if (!next.controller.signal.aborted) {
        setAiPoseJobs((jobs) => retainRecentCompletedAiPoseJobs(jobs.map((job) => job.id === next.id ? { ...job, completedAt: Date.now(), image, state: 'completed' } : job)));
      }
    }).catch((error) => {
      if (next.controller.signal.aborted || (error instanceof DOMException && error.name === 'AbortError')) return;
      setAiPoseJobs((jobs) => jobs.map((job) => job.id === next.id ? {
        ...job,
        message: error instanceof Error ? error.message : 'AI Pose 暂时生成失败，请再试一次',
        state: 'failed',
      } : job));
    }).finally(() => {
      aiPoseAbortControllers.current.delete(next.id);
      if (runningWebAiPoseJob.current === next.id) runningWebAiPoseJob.current = null;
      runNextWebAiPoseJob();
    });
  }

  const confirmAiPose = async () => {
    if (isAiPoseQueueFull) {
      closeAiPoseConsent();
      setNotice(`AI Pose 队列已满，最多同时处理 ${MAX_ACTIVE_AI_POSE_JOBS} 条`);
      return;
    }
    if (!aiPoseSourceReady) {
      closeAiPoseConsent();
      setNotice(sourceMode === 'upload' ? '请重新上传照片' : '相机还没有准备好');
      return;
    }
    const sourceImage = currentFrameDataUrl(sourceMode, videoRef.current, uploadedSourceImage);
    if (!sourceImage) {
      closeAiPoseConsent();
      setNotice('没有取到当前画面，请再试一次');
      return;
    }

    const controller = new AbortController();
    setShowAiPoseConsent(false);
    setSaveStatus('idle');
    captureLock.current = false;

    const request = {
      sourceImage,
      guideUrl: `/pose-guides/${activeTemplate.id}.webp`,
      fallbackGuideImage: makePoseGuideReference(activeTemplate),
      targetTitle: selected.title,
      preferences: aiPosePreferences,
    };

    if (supportsNativeBackgroundAiPose()) {
      const pendingID = `pending-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      aiPoseAbortControllers.current.set(pendingID, controller);
      setAiPoseJobs((jobs) => [{ createdAt: Date.now(), id: pendingID, native: true, state: 'queued', targetTitle: request.targetTitle }, ...jobs]);
      setNotice('AI Pose 已加入后台队列，可以继续使用 Posey');
      const submit = async () => {
        try {
          const { jobId } = await startNativeBackgroundAiPose(request, controller.signal);
          if (controller.signal.aborted) {
            await cancelNativeBackgroundAiPose(jobId);
            return;
          }
          setAiPoseJobs((jobs) => jobs.map((job) => job.id === pendingID ? { ...job, id: jobId } : job));
          await syncNativeAiPoseJobs(pendingID);
        } catch (error) {
          if (controller.signal.aborted) return;
          const message = error instanceof Error ? error.message : 'AI Pose 暂时生成失败，请再试一次';
          if (message.includes('最多同时')) {
            setAiPoseJobs((jobs) => jobs.filter((job) => job.id !== pendingID));
            setNotice(message);
          } else {
            setAiPoseJobs((jobs) => jobs.map((job) => job.id === pendingID ? { ...job, message, state: 'failed' } : job));
          }
        } finally {
          aiPoseAbortControllers.current.delete(pendingID);
        }
      };
      const submission = nativeAiPoseSubmissionChain.current.then(submit, submit);
      nativeAiPoseSubmissionChain.current = submission.then(() => undefined, () => undefined);
      await submission;
      return;
    }

    const jobID = `web-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    aiPoseAbortControllers.current.set(jobID, controller);
    webAiPoseQueue.current.push({ controller, id: jobID, request });
    setAiPoseJobs((jobs) => [{ createdAt: Date.now(), id: jobID, native: false, state: 'queued', targetTitle: request.targetTitle }, ...jobs]);
    setNotice('AI Pose 已加入后台队列，可以继续浏览');
    runNextWebAiPoseJob();
  };

  useEffect(() => {
    if (screen !== 'camera' || sourceMode !== 'camera') return;
    let cancelled = false;
    setCameraStatus('requesting');
    setCameraMessage('');
    if (!navigator.mediaDevices?.getUserMedia) {
      setCameraStatus('unavailable');
      setCameraMessage('这台设备现在不能打开相机。你可以重试，或上传照片使用 AI Pose。');
      return;
    }
    navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 1920 } },
    }).then(async (stream) => {
      if (cancelled) { stream.getTracks().forEach((track) => track.stop()); return; }
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
        if (!cancelled) setCameraStatus('ready');
      }
    }).catch((error: unknown) => {
      if (cancelled) return;
      const failure = cameraFailure(error);
      setCameraStatus(failure.status);
      setCameraMessage(failure.message);
    });
    return () => {
      cancelled = true;
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    };
  }, [cameraAttempt, screen, sourceMode]);

  useEffect(() => () => {
    aiPoseAbortControllers.current.forEach((controller) => controller.abort());
    aiPoseAbortControllers.current.clear();
    webAiPoseQueue.current = [];
  }, []);

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(''), 2600);
    return () => clearTimeout(timer);
  }, [notice]);

  const retryCamera = () => {
    captureLock.current = false;
    setCameraAttempt((attempt) => attempt + 1);
  };

  const saveCapturedPhoto = async () => {
    if (saveStatus === 'saving' || !capturedUrl) return;
    setSaveStatus('saving');
    try {
      const result = await savePhoto(capturedUrl);
      setSaveStatus('saved');
      setNotice(result === 'library' ? '已保存到系统相册' : '照片已下载');
    } catch (error) {
      setSaveStatus('error');
      const message = error instanceof Error && error.message ? error.message : '保存失败，请再试一次';
      setNotice(message.includes('cancel') || message.includes('取消') ? '已取消保存' : message);
    }
  };

  const closeAiPoseResult = () => {
    setSaveStatus('idle');
    setLibraryPage('ai-pose');
    setScreen('library');
  };

  if (screen === 'result') {
    const isAiPoseResult = resultKind === 'ai-pose';
    return (
      <main className="app-shell app-shell--result" data-testid="result-screen">
        <div className="result-top">
          {isAiPoseResult && <button className="result-back" onClick={closeAiPoseResult} aria-label="返回 AI Pose 列表"><ArrowLeft /></button>}
          <span>{isAiPoseResult ? 'AI Pose' : '拍好了'}</span><span className="result-check">{isAiPoseResult ? <PoseyAiPoseIcon width={17} height={17} /> : <Check size={18} />}</span>
        </div>
        <div className="result-photo"><img src={capturedUrl} alt={isAiPoseResult ? 'AI Pose 生成结果' : '刚刚拍下的照片'} /></div>
        <div className="result-copy">
          <span className="eyebrow">用了「{selected.title}」</span>
          <h1>{isAiPoseResult ? 'AI Pose 已生成' : '照片已拍好'}</h1>
          <p>{isAiPoseResult ? '这是 AI 生成结果，可能改变人物或画面细节。' : '你可以保存，也可以再拍一张。'}</p>
        </div>
        <div className={isAiPoseResult ? 'result-actions result-actions--single' : 'result-actions'}>
          {!isAiPoseResult && <button className="secondary-button" onClick={() => { captureLock.current = false; setResultKind('photo'); setScreen('camera'); }}><RefreshCcw size={19} />再拍一张</button>}
          <button className="primary-button" onClick={saveCapturedPhoto} disabled={saveStatus === 'saving'}>
            {saveStatus === 'saving' ? <LoaderCircle className="spin" size={19} /> : saveStatus === 'saved' ? <Check size={19} /> : <Download size={19} />}
            {saveStatus === 'saving' ? '正在保存' : saveStatus === 'saved' ? '已保存' : '保存照片'}
          </button>
        </div>
        {!isAiPoseResult && <button className="text-button" onClick={() => { setSaveStatus('idle'); returnToLibrary(); }}>换个姿势</button>}
        {aiPoseJobs.length > 0 && <AiPoseTaskBanner jobs={aiPoseJobs} onCancel={(job) => void cancelAiPose(job)} onDismiss={dismissAiPoseJob} onView={viewAiPoseResult} signature={aiPoseBannerPresentation.signature} visible={!aiPoseBannerPresentation.hidden} visibleUntil={aiPoseBannerPresentation.visibleUntil} />}
        {notice && <div className="toast" role="status"><span>{notice}</span><button onClick={() => setNotice('')} aria-label="关闭提示"><X /></button></div>}
      </main>
    );
  }

  if (screen === 'camera') {
    const aiPoseAvailable = aiPoseSourceReady;
    const cameraControlsDisabled = showAiPoseConsent;
    return (
      <main className="camera-screen" data-testid="camera-screen">
        <div className="camera-stage">
          {sourceMode === 'camera' ? (
            <video ref={videoRef} className="camera-video" muted playsInline aria-label="相机预览" />
          ) : uploadedSourceImage ? (
            <img className="camera-uploaded-image" src={uploadedSourceImage} alt="上传的待修改人物照片" />
          ) : (
            <div className="camera-upload-placeholder">
              <span><PoseyAiPoseIcon /></span>
              <strong>上传一张照片</strong>
              <p>选好照片后，用「{selected.title}」生成 AI Pose</p>
              <button onClick={() => sourceFileRef.current?.click()}><ImagePlus />选择照片</button>
            </div>
          )}
          <div className="camera-shade" />
          <img
            className={activeTemplate.category === 'half' ? 'pose-guide-image pose-guide-image--half' : 'pose-guide-image'}
            src={publicAssetUrl(`/pose-guides/${activeTemplate.id}.webp`)}
            alt=""
            aria-label="动漫姿势线稿引导"
          />
          <header className="camera-header">
            <button className="icon-button" aria-label="返回姿势库" onClick={returnToLibrary} disabled={cameraControlsDisabled}><ArrowLeft /></button>
            <div className="camera-title"><span>{selected.title}</span><small>{sourceMode === 'upload' ? uploadedSourceImage ? '上传照片已就绪' : '等待上传照片' : cameraStatus === 'ready' ? '相机已就绪' : cameraStatus === 'requesting' ? '正在打开相机' : '相机未就绪'}</small></div>
            <span aria-hidden="true" />
          </header>
          <div className="camera-tools">
            <button className={sourceMode === 'camera' ? 'tool-chip active' : 'tool-chip'} onClick={() => { setSourceMode('camera'); if (sourceMode === 'camera') retryCamera(); }}><Camera size={14} />打开相机</button>
            <button className={sourceMode === 'upload' ? 'tool-chip active' : 'tool-chip'} onClick={() => sourceFileRef.current?.click()} disabled={uploadingSource || cameraControlsDisabled}><ImagePlus size={14} />{uploadingSource ? '读取中' : '上传照片'}</button>
            <input ref={sourceFileRef} className="visually-hidden" type="file" accept="image/*" aria-label="上传待修改人物照片" onChange={(event) => uploadAiPoseSource(event.target.files?.[0])} />
          </div>
          {sourceMode === 'camera' && cameraStatus !== 'ready' && (
            <div className={`camera-state camera-state--${cameraStatus}`} role={cameraStatus === 'requesting' ? 'status' : 'alert'}>
              {cameraStatus === 'requesting' ? <LoaderCircle className="spin" /> : <AlertCircle />}
              <strong>{cameraStatus === 'requesting' ? '正在打开相机…' : '相机还没打开'}</strong>
              {cameraStatus !== 'requesting' && <p>{cameraMessage}</p>}
              {cameraStatus !== 'requesting' && <div><button onClick={retryCamera}>再试一次</button><button onClick={() => sourceFileRef.current?.click()}>上传照片</button></div>}
            </div>
          )}
          {uploadingSource && (
            <div className="camera-state camera-state--upload" role="status">
              <LoaderCircle className="spin" />
              <strong>正在读取照片…</strong>
              <p>确认生成前，照片不会发送给火山方舟。</p>
            </div>
          )}
          <section className="camera-bottom">
            <div className="camera-guide-note" data-testid="pose-guide-note">
              <small>{sourceMode === 'upload' ? uploadedSourceImage ? '照片已就绪' : 'AI Pose' : '参考姿势'}</small>
              <strong>{sourceMode === 'upload' ? uploadedSourceImage ? '可以直接使用 AI Pose' : '先选择一张人物照片' : '照着线稿自由调整'}</strong>
            </div>
            <div className="shutter-row">
              <button className="thumbnail-button" onClick={returnToLibrary} aria-label="选择其他姿势" disabled={cameraControlsDisabled}>
                {selected.illustration ? <img className={`pose-illustration${selected.category === 'half' ? ' pose-illustration--half' : ''}`} src={selected.illustration} alt="" /> : <Skeleton target={activeTemplate.landmarks} compact />}
              </button>
              {sourceMode === 'upload' ? (
                <button className="upload-replace-button" onClick={() => sourceFileRef.current?.click()} aria-label="重新上传照片" disabled={cameraControlsDisabled || uploadingSource}><ImagePlus /></button>
              ) : (
                <button className="shutter" onClick={capture} aria-label={cameraStatus !== 'ready' ? '相机准备中' : '拍照'} disabled={cameraControlsDisabled || cameraStatus !== 'ready'}><span /></button>
              )}
              <button className={isAiPoseQueueFull ? 'ai-pose-button is-full' : 'ai-pose-button'} onClick={openAiPoseConsent} disabled={!aiPoseAvailable || cameraControlsDisabled || isAiPoseQueueFull} aria-label={isAiPoseQueueFull ? `AI Pose 队列已满，最多 ${MAX_ACTIVE_AI_POSE_JOBS} 条` : aiPoseAvailable ? '使用 AI Pose' : 'AI Pose 准备中'}><PoseyAiPoseIcon width={19} height={19} /><small>{isAiPoseQueueFull ? `已满 ${activeAiPoseJobCount}/${MAX_ACTIVE_AI_POSE_JOBS}` : aiPoseAvailable ? 'AI Pose' : '准备中'}</small></button>
            </div>
          </section>
        </div>
        {showAiPoseConsent && (
          <div className="modal-backdrop modal-backdrop--camera" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) closeAiPoseConsent(); }}>
            <section className="ai-pose-consent" role="dialog" aria-modal="true" aria-labelledby="ai-pose-consent-title">
              <span className="ai-pose-consent__icon"><PoseyAiPoseIcon /></span>
              <h2 id="ai-pose-consent-title">发送{sourceMode === 'upload' ? '这张照片' : '当前画面'}生成 AI Pose？</h2>
              <p>{sourceMode === 'upload' ? '这张上传照片' : '当前画面'}和目标姿势图会发送给火山方舟的豆包图片模型，仅用于本次生成。{sourceMode === 'camera' ? '实时预览不会持续上传。' : '选择图片的过程不会上传。'}</p>
              <AiPosePreferenceControls preferences={aiPosePreferences} onChange={updateAiPosePreference} />
              <p className="ai-pose-consent__note">已优先保护面部与表情，AI 结果仍请生成后确认。</p>
              <div className="ai-pose-consent__actions">
                <button className="secondary-button" onClick={closeAiPoseConsent}>取消</button>
                <button className="primary-button" onClick={confirmAiPose}>发送并生成</button>
              </div>
            </section>
          </div>
        )}
        {aiPoseJobs.length > 0 && <AiPoseTaskBanner jobs={aiPoseJobs} onCancel={(job) => void cancelAiPose(job)} onDismiss={dismissAiPoseJob} onView={viewAiPoseResult} signature={aiPoseBannerPresentation.signature} visible={!aiPoseBannerPresentation.hidden} visibleUntil={aiPoseBannerPresentation.visibleUntil} />}
        {notice && <div className="toast" role="status"><span>{notice}</span><button onClick={() => setNotice('')} aria-label="关闭提示"><X /></button></div>}
      </main>
    );
  }

  const displayedTemplates = libraryPage === 'home' ? visibleTemplates : libraryPage === 'favorites' ? favoriteTemplates : [];
  const settingsTitle = settingsView === 'main' ? '设置' : settingsView === 'theme' ? '首页主题' : settingsView === 'shuffle' ? '随心拍范围' : settingsView === 'product' ? '产品说明' : '隐私与 AI Pose';

  return (
    <main
      className={`app-shell app-shell--home app-shell--theme-${homeTheme}`}
      data-testid="library-screen"
      data-page={libraryPage}
      style={{
        '--home-accent': currentHomeTheme.accent,
        '--home-soft': currentHomeTheme.soft,
        '--theme-page-start': currentHomeTheme.pageStart,
        '--theme-page-end': currentHomeTheme.pageEnd,
        '--theme-chrome': currentHomeTheme.chrome,
        '--theme-control': currentHomeTheme.control,
        '--theme-surface': currentHomeTheme.surface,
        '--theme-card': currentHomeTheme.card,
        '--theme-card-alt': currentHomeTheme.cardAlt,
      } as React.CSSProperties}
    >
      <header className="home-header">
        <img className="home-wordmark" src={publicAssetUrl('/brand/posey-wordmark.png')} alt="Posey" />
      </header>

      <div key={libraryPage} className="library-page-content">
        {libraryPage === 'home' ? (
        <>
          <section className="pose-library-heading pose-library-heading--first" aria-labelledby="pose-library-title">
            <div><span>POSES</span><h1 id="pose-library-title">从一个姿势开始</h1><p>选好参考后，可以直接拍照或上传照片。</p></div>
          </section>
          <div className="gender-switch liquid-segmented" role="group" aria-label="人物性别" data-active-index={gender === 'female' ? 0 : 1} style={{ '--selection-offset': gender === 'female' ? '0%' : '100%' } as React.CSSProperties}>
            <span className="liquid-segmented__selection" aria-hidden="true"><span key={genderLiquidMotionKey} /></span>
            {genderOptions.map((option) => <button key={option.id} className={gender === option.id ? 'active' : ''} onClick={() => void chooseGender(option.id)} aria-pressed={gender === option.id}>{option.label}</button>)}
          </div>
          <nav className="filters" aria-label="姿势分类">
            {filterOptions.map((option) => <button key={option.id} className={filter === option.id ? 'active' : ''} onClick={() => setFilter(option.id)}>{option.label}</button>)}
          </nav>
        </>
      ) : libraryPage === 'favorites' ? (
        <section className="favorites-heading" aria-labelledby="favorites-title">
          <span>SAVED POSES</span><h1 id="favorites-title">我的收藏</h1>
          <p>{favoriteTemplates.length > 0 ? `已收藏 ${favoriteTemplates.length} 个姿势` : '喜欢的姿势会集中放在这里。'}</p>
        </section>
      ) : libraryPage === 'settings' ? null : (
        <section className="ai-workflow" aria-labelledby="ai-workflow-title">
          <header className="ai-workflow__heading">
            <span>AI POSE</span>
            <h1 id="ai-workflow-title">把照片换成喜欢的姿势</h1>
            <p>选择人物照片和目标姿势后生成。</p>
          </header>
          <div className="ai-workflow__steps">
            <button className={uploadedSourceImage ? 'ai-workflow-row ready' : 'ai-workflow-row'} onClick={() => sourceFileRef.current?.click()} disabled={uploadingSource} aria-label={uploadedSourceImage ? '更换 AI Pose 人物照片' : '选择 AI Pose 人物照片'}>
              <span className="ai-workflow-row__preview">
                {uploadedSourceImage ? <img src={uploadedSourceImage} alt="已选择的人物照片" /> : <ImagePlus />}
              </span>
              <span className="ai-workflow-row__copy"><small>人物照片</small><strong>{uploadingSource ? '正在读取照片…' : uploadedSourceImage ? '照片已选择' : '选择一张照片'}</strong></span>
              {uploadingSource ? <LoaderCircle className="spin" /> : uploadedSourceImage ? <Check /> : <ChevronRight />}
            </button>
            <input ref={sourceFileRef} className="visually-hidden" type="file" accept="image/*" aria-label="上传 AI Pose 人物照片" onChange={(event) => uploadAiPoseSource(event.target.files?.[0])} />
            <button ref={aiPosePickerTriggerRef} className={aiPoseTarget ? 'ai-workflow-row ready' : 'ai-workflow-row'} onClick={() => setShowAiPosePicker(true)} disabled={!uploadedSourceImage || uploadingSource} aria-label="选择 AI Pose 目标姿势">
              <span className="ai-workflow-row__preview ai-workflow-row__preview--pose">
                {aiPoseTarget?.illustration ? <img src={aiPoseTarget.illustration} alt="" /> : <PoseyAiPoseIcon />}
              </span>
              <span className="ai-workflow-row__copy"><small>目标姿势</small><strong>{aiPoseTarget ? aiPoseTarget.title : uploadedSourceImage ? '选择一个姿势' : '选择照片后可用'}</strong></span>
              {aiPoseTarget ? <Check /> : <ChevronRight />}
            </button>
          </div>
          <button className={isAiPoseQueueFull ? 'ai-workflow__generate is-full' : 'ai-workflow__generate'} onClick={openAiPoseConsent} disabled={!uploadedSourceImage || !aiPoseTarget || uploadingSource || isAiPoseQueueFull} aria-describedby={activeAiPoseJobCount > 0 ? 'ai-workflow-queue-hint' : undefined} aria-label={isAiPoseQueueFull ? `AI Pose 队列已满，最多 ${MAX_ACTIVE_AI_POSE_JOBS} 条` : '生成 AI Pose'}>
            {isAiPoseQueueFull ? <ListChecks /> : <PoseyAiPoseIcon />}<span>{isAiPoseQueueFull ? `队列已满（${activeAiPoseJobCount}/${MAX_ACTIVE_AI_POSE_JOBS}）` : '生成 AI Pose'}</span>
          </button>
          {activeAiPoseJobCount > 0 && <p id="ai-workflow-queue-hint" className={isAiPoseQueueFull ? 'ai-workflow__queue-hint is-full' : 'ai-workflow__queue-hint'} role="status">{isAiPoseQueueFull ? `已达到 ${MAX_ACTIVE_AI_POSE_JOBS} 条上限，请等待完成或取消一个任务` : `当前队列 ${activeAiPoseJobCount}/${MAX_ACTIVE_AI_POSE_JOBS}，还可以添加 ${MAX_ACTIVE_AI_POSE_JOBS - activeAiPoseJobCount} 条`}</p>}
          {aiPoseJobs.length > 0 && <AiPoseTaskList jobs={aiPoseJobs} onCancel={(job) => void cancelAiPose(job)} onDismiss={dismissAiPoseJob} onView={viewAiPoseResult} />}
        </section>
      )}

      {(libraryPage === 'home' || libraryPage === 'favorites') && <section className={`pose-grid${libraryPage === 'favorites' ? ' pose-grid--favorites' : ''}`} aria-label={libraryPage === 'home' ? '姿势模板' : '收藏姿势'}>
        {displayedTemplates.map((template, index) => (
          <article key={template.id} className="pose-card" style={{ '--accent': template.accent } as React.CSSProperties} data-gender={template.gender ?? 'imported'} data-category={template.category} data-testid={`pose-card-${template.id}`}>
            <button className="pose-card__visual" onClick={() => openCamera(template)} aria-label={`选择${template.title}`}>
              <span className="pose-number">{String(index + 1).padStart(2, '0')}</span>
              {template.source.usageStatus === 'user-imported' && <span className="mine-badge">我的</span>}
              {template.illustration
                ? <img className="pose-illustration" src={template.illustration} alt={`${template.title}动漫姿势示范`} loading={index < 6 ? 'eager' : 'lazy'} decoding="async" />
                : <Skeleton target={template.landmarks} compact />}
            </button>
            <div className="pose-card__meta">
              <button className="pose-card__name" onClick={() => openCamera(template)}>
                <strong>{template.title}</strong>
                <small>{libraryPage === 'favorites' ? <>{template.gender === 'female' || template.gender === 'male' ? <span className={`gender-mark gender-mark--${template.gender}`}><GenderSymbol gender={template.gender} /><span>{template.gender === 'female' ? '女' : '男'}</span></span> : <span className="gender-mark">自定义</span>}{template.subtitle}</> : template.subtitle}</small>
              </button>
              <button className={favorites.includes(template.id) ? 'heart-button active' : 'heart-button'} aria-label={favorites.includes(template.id) ? '取消收藏' : '收藏'} onClick={() => toggleFavorite(template.id)}><Heart /></button>
            </div>
          </article>
        ))}
        {libraryPage === 'favorites' && displayedTemplates.length === 0 && (
          <div className="empty-state empty-state--favorites">
            <span className="empty-state__icon"><Heart /></span><strong>还没有收藏姿势</strong>
            <span>在首页点亮姿势旁的爱心，就会出现在这里。</span>
            <button onClick={showHome}>去首页挑姿势</button>
          </div>
        )}
      </section>}

        {libraryPage === 'home' && <footer className="privacy-note"><span className="privacy-dot" />AI Pose 只在你确认后发送当前画面或上传照片</footer>}
      </div>
      <nav className="home-tab-bar home-tab-bar--liquid-glass" aria-label="首页快捷导航" data-active-index={bottomTabIndex} style={{ '--selection-offset': `${bottomTabIndex * 100}%` } as React.CSSProperties}>
        <span className="home-tab-bar__selection" aria-hidden="true"><span key={bottomLiquidMotionKey} /></span>
        <button className={libraryPage === 'home' ? 'active' : ''} aria-label="前往首页" aria-current={libraryPage === 'home' ? 'page' : undefined} onClick={showHome}>
          <House /><span>首页</span>
        </button>
        <button className={libraryPage === 'favorites' ? 'active' : ''} aria-label="前往收藏页" aria-current={libraryPage === 'favorites' ? 'page' : undefined} onClick={showFavorites}>
          <Heart /><span>收藏</span>
        </button>
        <button ref={randomTriggerRef} aria-label="随心拍随机选择姿势" onClick={openRandomGenderPicker}>
          <Shuffle /><span>随心拍</span>
        </button>
        <button className={libraryPage === 'ai-pose' ? 'active' : ''} aria-label="打开 AI Pose" aria-current={libraryPage === 'ai-pose' ? 'page' : undefined} onClick={openAiPose}>
          <PoseyAiPoseIcon /><span>AI Pose</span>
        </button>
        <button className={libraryPage === 'settings' ? 'active' : ''} aria-label="前往设置页" aria-current={libraryPage === 'settings' ? 'page' : undefined} onClick={openSettings}>
          <Settings /><span>设置</span>
        </button>
      </nav>
      {showAiPosePicker && (
        <div className="modal-backdrop modal-backdrop--pose-picker" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setShowAiPosePicker(false); }}>
          <section className="ai-pose-picker" role="dialog" aria-modal="true" aria-labelledby="ai-pose-picker-title">
            <header className="ai-pose-picker__header">
              <div><h2 id="ai-pose-picker-title">选择目标姿势</h2><p>选择后返回生成页面</p></div>
              <button className="ai-pose-picker__close" onClick={() => setShowAiPosePicker(false)} aria-label="关闭姿势选择"><X /></button>
            </header>
            <div className="ai-pose-picker__gender liquid-segmented" role="group" aria-label="AI Pose 姿势性别" data-active-index={aiPosePickerGender === 'female' ? 0 : 1} style={{ '--selection-offset': aiPosePickerGender === 'female' ? '0%' : '100%' } as React.CSSProperties}>
              <span className="liquid-segmented__selection" aria-hidden="true"><span key={aiPoseGenderLiquidMotionKey} /></span>
              {genderOptions.map((option) => <button key={option.id} className={aiPosePickerGender === option.id ? 'active' : ''} aria-pressed={aiPosePickerGender === option.id} onClick={() => setAiPosePickerGender(option.id)}>{option.label}</button>)}
            </div>
            <div className="ai-pose-picker__grid">
              {aiPosePickerTemplates.map((template) => (
                <button key={template.id} className={aiPoseTarget?.id === template.id ? 'ai-pose-picker__item active' : 'ai-pose-picker__item'} onClick={() => chooseAiPoseTarget(template)} aria-label={`选择姿势：${template.title}`}>
                  <span className="ai-pose-picker__visual">
                    {template.illustration ? <img src={template.illustration} alt="" /> : <PoseyAiPoseIcon />}
                    {aiPoseTarget?.id === template.id && <span className="ai-pose-picker__selected"><Check /></span>}
                  </span>
                  <strong>{template.title}</strong>
                </button>
              ))}
            </div>
          </section>
        </div>
      )}
      {libraryPage === 'ai-pose' && showAiPoseConsent && (
        <div className="modal-backdrop modal-backdrop--ai-workflow" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) closeAiPoseConsent(); }}>
          <section className="ai-pose-consent" role="dialog" aria-modal="true" aria-labelledby="ai-workflow-consent-title">
            <span className="ai-pose-consent__icon"><PoseyAiPoseIcon /></span>
            <h2 id="ai-workflow-consent-title">发送这张照片生成 AI Pose？</h2>
            <p>人物照片和目标姿势图会发送给火山方舟的豆包图片模型，仅用于本次生成。选择图片的过程不会上传。</p>
            <AiPosePreferenceControls preferences={aiPosePreferences} onChange={updateAiPosePreference} />
            <p className="ai-pose-consent__note">已优先保护面部与表情，AI 结果仍请生成后确认。</p>
            <div className="ai-pose-consent__actions">
              <button className="secondary-button" onClick={closeAiPoseConsent}>取消</button>
              <button className="primary-button" onClick={confirmAiPose}>发送并生成</button>
            </div>
          </section>
        </div>
      )}
      {showRandomGenderPicker && (
        <div className="modal-backdrop modal-backdrop--random" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) closeRandomGenderPicker(); }}>
          <section className="random-gender-sheet" role="dialog" aria-modal="true" aria-labelledby="random-gender-title">
            <header className="random-gender-sheet__header">
              <span className="random-gender-sheet__icon"><Shuffle /></span>
              <div><h2 id="random-gender-title">选择女生或男生</h2><p>从{shuffleScope === 'favorites' ? '收藏' : '全部'}姿势中随机挑选</p></div>
              <button className="random-gender-sheet__close" onClick={closeRandomGenderPicker} aria-label="关闭随心拍选择"><X /></button>
            </header>
            <div className="random-gender-options">
              <button className="random-gender-option" onClick={() => openRandomPose('female')} aria-label="选择女生随心拍" disabled={randomFemaleTemplates.length === 0}>
                <span className="random-gender-option__symbol random-gender-option__symbol--female"><GenderSymbol gender="female" className="random-gender-option__gender-icon" /></span>
                <span className="random-gender-option__copy"><strong>女生</strong></span>
                <ChevronRight aria-hidden="true" />
              </button>
              <button className="random-gender-option" onClick={() => openRandomPose('male')} aria-label="选择男生随心拍" disabled={randomMaleTemplates.length === 0}>
                <span className="random-gender-option__symbol random-gender-option__symbol--male"><GenderSymbol gender="male" className="random-gender-option__gender-icon" /></span>
                <span className="random-gender-option__copy"><strong>男生</strong></span>
                <ChevronRight aria-hidden="true" />
              </button>
            </div>
          </section>
        </div>
      )}
      {libraryPage === 'settings' && (
        <section key={settingsView} className="settings-page" data-motion-direction={settingsMotionDirection} aria-labelledby="settings-title">
          <header className="settings-page__header">
            {settingsView !== 'main' && <button className="settings-page__back" onClick={() => openSettingsView('main')} aria-label="返回设置"><ArrowLeft /></button>}
            <div><span>SETTINGS</span><h1 id="settings-title">{settingsTitle}</h1></div>
          </header>
          <div className="settings-page__body">
              {settingsView === 'main' && (
                <>
                  <section className="settings-group" aria-labelledby="appearance-settings">
                    <h3 id="appearance-settings">外观</h3>
                    <div className="settings-card">
                      <button className="settings-row" onClick={() => openSettingsView('theme')}>
                        <span className="settings-row__icon"><Palette /></span><span className="settings-row__label">首页主题</span><span className="settings-row__value">{currentHomeTheme.label}</span><ChevronRight />
                      </button>
                    </div>
                  </section>
                  <section className="settings-group" aria-labelledby="shuffle-settings">
                    <h3 id="shuffle-settings">随心拍</h3>
                    <div className="settings-card">
                      <button className="settings-row" onClick={() => openSettingsView('shuffle')}>
                        <span className="settings-row__icon"><Shuffle /></span><span className="settings-row__label">选择范围</span><span className="settings-row__value">{shuffleScope === 'all' ? '全部' : '收藏'}</span><ChevronRight />
                      </button>
                    </div>
                  </section>
                  <section className="settings-group" aria-labelledby="about-settings">
                    <h3 id="about-settings">关于</h3>
                    <div className="settings-card">
                      <button className="settings-row" onClick={() => openSettingsView('product')}>
                        <span className="settings-row__icon"><Info /></span><span className="settings-row__label">产品说明</span><ChevronRight />
                      </button>
                      <button className="settings-row" onClick={() => openSettingsView('privacy')}>
                        <span className="settings-row__icon"><ShieldCheck /></span><span className="settings-row__label">隐私与 AI Pose</span><ChevronRight />
                      </button>
                      <div className="settings-row">
                        <span className="settings-row__icon"><SlidersHorizontal /></span><span className="settings-row__label">版本</span><span className="settings-row__value">{APP_VERSION}</span>
                      </div>
                    </div>
                  </section>
                </>
              )}
              {settingsView === 'theme' && (
                <div className="theme-detail" role="group" aria-label="首页主题选项">
                  {homeThemeOptions.map((option) => (
                    <button key={option.id} className={homeTheme === option.id ? 'theme-detail__row active' : 'theme-detail__row'} onClick={() => chooseHomeTheme(option.id)} aria-pressed={homeTheme === option.id}>
                      <span className="theme-swatch" style={{ '--swatch-accent': option.accent, '--swatch-soft': option.soft, '--swatch-start': option.pageStart, '--swatch-end': option.pageEnd } as React.CSSProperties} /><strong>{option.label}</strong>
                      {homeTheme === option.id && <Check />}
                    </button>
                  ))}
                </div>
              )}
              {settingsView === 'shuffle' && (
                <div className="settings-choice-list" role="radiogroup" aria-label="随心拍选择范围">
                  <button className={shuffleScope === 'all' ? 'settings-choice-row active' : 'settings-choice-row'} role="radio" aria-checked={shuffleScope === 'all'} onClick={() => chooseShuffleScope('all')}>
                    <span>全部</span>{shuffleScope === 'all' && <Check aria-hidden="true" />}
                  </button>
                  <button className={shuffleScope === 'favorites' ? 'settings-choice-row active' : 'settings-choice-row'} role="radio" aria-checked={shuffleScope === 'favorites'} onClick={() => chooseShuffleScope('favorites')} aria-label={favoriteTemplates.length === 0 ? '收藏，暂无收藏姿势' : '收藏'} disabled={favoriteTemplates.length === 0}>
                    <span>收藏</span>{favoriteTemplates.length === 0 ? <Lock className="settings-choice-row__lock" aria-hidden="true" /> : shuffleScope === 'favorites' && <Check aria-hidden="true" />}
                  </button>
                </div>
              )}
              {settingsView === 'product' && (
                <article className="settings-detail">
                  <span className="settings-detail__icon"><PoseyAiPoseIcon /></span>
                  <h3>Posey 能做什么</h3>
                  <p>选择一个参考姿势后，可以照着线稿拍照；也可以上传人物照片，用 AI Pose 生成目标姿势。</p>
                  <h3>拍摄安全</h3>
                  <p>拍摄时留意脚下、车辆和周围障碍物。不要在道路、临边、水域等危险位置只看屏幕摆姿势。</p>
                  <h3>AI Pose 风险</h3>
                  <p>AI 生成结果可能改变人物、服装或画面细节。确认结果后再保存或分享。</p>
                </article>
              )}
              {settingsView === 'privacy' && (
                <article className="settings-detail">
                  <span className="settings-detail__icon"><ShieldCheck /></span>
                  <h3>相机与照片</h3>
                  <p>普通拍照不会上传相机预览或照片。选择图片时，照片保留在设备上。</p>
                  <h3>使用 AI Pose 时</h3>
                  <p>只有在你确认生成后，当前画面或上传照片以及目标姿势图才会发送给火山方舟的豆包图片模型，用于本次生成。</p>
                  <h3>分享前检查</h3>
                  <p>AI 生成结果可能改变人物或画面细节，也可能出现不准确内容。请检查结果，并避免分享敏感信息。</p>
                </article>
              )}
          </div>
        </section>
      )}
      {aiPoseJobs.length > 0 && <AiPoseTaskBanner jobs={aiPoseJobs} onCancel={(job) => void cancelAiPose(job)} onDismiss={dismissAiPoseJob} onView={viewAiPoseResult} signature={aiPoseBannerPresentation.signature} visible={!aiPoseBannerPresentation.hidden} visibleUntil={aiPoseBannerPresentation.visibleUntil} />}
      {notice && <div className="toast" role="status"><span>{notice}</span><button onClick={() => setNotice('')} aria-label="关闭提示"><X /></button></div>}
    </main>
  );
}
