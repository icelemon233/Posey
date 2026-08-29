import { Capacitor, registerPlugin } from '@capacitor/core';

type SavePhotoResult = { saved: boolean };

interface PoseyPhotoPlugin {
  savePhoto(options: { dataUrl: string; fileName: string }): Promise<SavePhotoResult>;
}

const NativePhotoLibrary = registerPlugin<PoseyPhotoPlugin>('PoseyPhoto');

function downloadPhoto(dataUrl: string, fileName: string) {
  const link = document.createElement('a');
  link.href = dataUrl;
  link.download = fileName;
  link.rel = 'noopener';
  document.body.appendChild(link);
  link.click();
  link.remove();
}

export async function savePhoto(dataUrl: string): Promise<'library' | 'downloaded'> {
  if (!dataUrl.startsWith('data:image/')) throw new Error('没有可保存的照片');
  const fileName = `Posey-${new Date().toISOString().replace(/[:.]/g, '-')}.jpg`;

  if (Capacitor.isNativePlatform()) {
    const result = await NativePhotoLibrary.savePhoto({ dataUrl, fileName });
    if (!result.saved) throw new Error('照片没有保存成功');
    return 'library';
  }

  downloadPhoto(dataUrl, fileName);
  return 'downloaded';
}

export function shouldStartWithCamera() {
  return Capacitor.isNativePlatform();
}
