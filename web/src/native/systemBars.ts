import { Capacitor, registerPlugin } from '@capacitor/core';

type SystemBarMode = 'light' | 'dark';

interface PoseySystemBarsPlugin {
  setStyle(options: { darkContent: boolean; backgroundColor: string; animated: boolean }): Promise<void>;
}

const PoseySystemBars = registerPlugin<PoseySystemBarsPlugin>('PoseySystemBars');

export async function syncSystemBars(mode: SystemBarMode, lightBackgroundColor = '#fffaf2', animated = false) {
  const lightScreen = mode === 'light';
  const backgroundColor = lightScreen ? lightBackgroundColor : '#0d0d10';
  let themeColor = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');

  if (!themeColor) {
    themeColor = document.createElement('meta');
    themeColor.name = 'theme-color';
    document.head.appendChild(themeColor);
  }
  themeColor.content = backgroundColor;
  document.documentElement.style.setProperty('--system-bar-transition-duration', animated ? '.32s' : '0ms');
  document.documentElement.style.setProperty('--system-bar-background', backgroundColor);

  if (!Capacitor.isNativePlatform()) return;
  await PoseySystemBars.setStyle({ darkContent: lightScreen, backgroundColor, animated });
}
