import { expect, it, vi } from 'vitest';
import { applyTheme, LANGUAGE_EVENT, LANGUAGE_KEY, readLanguage, readTheme, writeLanguage, writeTheme } from '../src/preferences';

it('migrates the map key, then the website key, into the single shared language key', () => {
  localStorage.setItem('waybi-language', 'en');
  localStorage.setItem('kiwi-language', 'zh');
  expect(readLanguage()).toBe('zh');
  expect(localStorage.getItem(LANGUAGE_KEY)).toBe('zh');
  expect(localStorage.getItem('kiwi-language')).toBeNull();
  expect(localStorage.getItem('waybi-language')).toBeNull();
  localStorage.clear();
  localStorage.setItem('waybi-language', 'zh');
  expect(readLanguage()).toBe('zh');
  expect(localStorage.getItem(LANGUAGE_KEY)).toBe('zh');
});

it('prefers the shared key, ignores junk and falls back to English', () => {
  localStorage.setItem(LANGUAGE_KEY, 'en');
  localStorage.setItem('kiwi-language', 'zh');
  expect(readLanguage()).toBe('en');
  localStorage.clear();
  localStorage.setItem('kiwi-language', 'fr');
  expect(readLanguage()).toBe('en');
});

it('writes the shared key, removes legacy keys and announces the change', () => {
  localStorage.setItem('kiwi-language', 'en');
  const listener = vi.fn();
  window.addEventListener(LANGUAGE_EVENT, listener);
  writeLanguage('zh');
  window.removeEventListener(LANGUAGE_EVENT, listener);
  expect(localStorage.getItem(LANGUAGE_KEY)).toBe('zh');
  expect(localStorage.getItem('kiwi-language')).toBeNull();
  expect((listener.mock.calls[0]![0] as CustomEvent).detail).toBe('zh');
});

it('persists a manual theme and applies it to the document', () => {
  document.head.innerHTML = '<meta name="theme-color" media="(prefers-color-scheme: light)" content="#F8FBEF"><meta name="theme-color" media="(prefers-color-scheme: dark)" content="#10180D">';
  expect(readTheme()).toBe('system');
  writeTheme('dark');
  expect(readTheme()).toBe('dark');
  expect(document.documentElement.dataset.theme).toBe('dark');
  expect([...document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')].map(m => m.content)).toEqual(['#10180D', '#10180D']);
  writeTheme('system');
  expect(document.documentElement.dataset.theme).toBeUndefined();
  expect([...document.querySelectorAll<HTMLMetaElement>('meta[name="theme-color"]')].map(m => m.content)).toEqual(['#F8FBEF', '#10180D']);
  localStorage.setItem('waybi-theme', 'purple');
  expect(readTheme()).toBe('system');
  applyTheme('light');
  expect(document.documentElement.dataset.theme).toBe('light');
});
