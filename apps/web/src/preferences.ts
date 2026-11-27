/**
 * One place for the user preferences shared by the marketing site, the web
 * map (/app) and the account dashboard. Every surface reads and writes the
 * same keys so a language or theme chosen on one page is honoured everywhere.
 */
export type Language = 'en' | 'zh';
export type ThemePreference = 'system' | 'light' | 'dark';

export const LANGUAGE_KEY = 'waybi-ui-language';
/** Keys used by earlier releases: the map used `kiwi-language`, the website `waybi-language`. */
export const LEGACY_LANGUAGE_KEYS = ['kiwi-language', 'waybi-language'] as const;
export const THEME_KEY = 'waybi-theme';
export const LANGUAGE_EVENT = 'waybi-language-change';

const isLanguage = (value: unknown): value is Language => value === 'en' || value === 'zh';
const isTheme = (value: unknown): value is ThemePreference => value === 'system' || value === 'light' || value === 'dark';

function store(): Storage | null {
  try { return window.localStorage; } catch { return null; }
}

/**
 * Returns the stored interface language, migrating a value saved under a
 * legacy key the first time it is read. The map's own key wins over the
 * website's because it was the deliberate in-app choice that also synced to
 * the account.
 */
export function readLanguage(fallback: Language = 'en'): Language {
  const storage = store();
  if (!storage) return fallback;
  try {
    const saved = storage.getItem(LANGUAGE_KEY);
    if (isLanguage(saved)) return saved;
    for (const key of LEGACY_LANGUAGE_KEYS) {
      const legacy = storage.getItem(key);
      if (isLanguage(legacy)) {
        storage.setItem(LANGUAGE_KEY, legacy);
        for (const old of LEGACY_LANGUAGE_KEYS) storage.removeItem(old);
        return legacy;
      }
    }
  } catch { /* storage can be blocked in private modes */ }
  return fallback;
}

/** Persists the interface language for every Waybi surface and announces the change in this tab. */
export function writeLanguage(language: Language) {
  const storage = store();
  try {
    storage?.setItem(LANGUAGE_KEY, language);
    for (const old of LEGACY_LANGUAGE_KEYS) storage?.removeItem(old);
  } catch { /* keep working in memory */ }
  try { window.dispatchEvent(new CustomEvent(LANGUAGE_EVENT, { detail: language })); } catch { /* old browsers */ }
}

export function readTheme(): ThemePreference {
  try {
    const saved = store()?.getItem(THEME_KEY);
    return isTheme(saved) ? saved : 'system';
  } catch { return 'system'; }
}

const THEME_COLORS = { light: '#F8FBEF', dark: '#10180D' } as const;

/** Resolves `system` against the current media query. */
export function effectiveTheme(preference: ThemePreference = readTheme()): 'light' | 'dark' {
  if (preference !== 'system') return preference;
  try { return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'; } catch { return 'light'; }
}

/** Applies a theme preference to the document (`data-theme` on <html>, browser chrome colour). */
export function applyTheme(preference: ThemePreference = readTheme()) {
  const root = document.documentElement;
  if (preference === 'system') delete root.dataset.theme;
  else root.dataset.theme = preference;
  const color = THEME_COLORS[effectiveTheme(preference)];
  const metas = document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]');
  metas.forEach((meta) => {
    // A forced theme overrides both media-specific colours; `system` restores them.
    if (preference === 'system') {
      const media = meta.getAttribute('media') || '';
      meta.content = media.includes('dark') ? THEME_COLORS.dark : THEME_COLORS.light;
    } else meta.content = color;
  });
}

export function writeTheme(preference: ThemePreference) {
  try { store()?.setItem(THEME_KEY, preference); } catch { /* in-memory only */ }
  applyTheme(preference);
}
