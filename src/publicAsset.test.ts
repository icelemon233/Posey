import { describe, expect, it } from 'vitest';
import { publicAssetUrl } from './publicAsset';

describe('publicAssetUrl', () => {
  it('places root-style assets under the configured project base', () => {
    expect(publicAssetUrl('/poses/example.webp', '/Posey-web-demo/')).toBe('/Posey-web-demo/poses/example.webp');
    expect(publicAssetUrl('brand/posey-wordmark.png', '/Posey-web-demo')).toBe('/Posey-web-demo/brand/posey-wordmark.png');
  });

  it('preserves root hosting and already resolved URLs', () => {
    expect(publicAssetUrl('/poses/example.webp', '/')).toBe('/poses/example.webp');
    expect(publicAssetUrl('data:image/png;base64,abc', '/Posey-web-demo/')).toBe('data:image/png;base64,abc');
    expect(publicAssetUrl('blob:https://example.com/id', '/Posey-web-demo/')).toBe('blob:https://example.com/id');
    expect(publicAssetUrl('https://cdn.example.com/image.webp', '/Posey-web-demo/')).toBe('https://cdn.example.com/image.webp');
  });
});
