import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.posey.camera',
  appName: 'Posey',
  webDir: 'dist',
  server: { androidScheme: 'https' },
  ios: { contentInset: 'never' },
  android: { allowMixedContent: false, adjustMarginsForEdgeToEdge: 'force' },
};

export default config;
