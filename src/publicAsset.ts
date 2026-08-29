export function publicAssetUrl(path: string, base = import.meta.env.BASE_URL) {
  if (/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(path)) return path;

  const normalizedBase = base.endsWith('/') ? base : `${base}/`;
  return `${normalizedBase}${path.replace(/^\/+/, '')}`;
}
