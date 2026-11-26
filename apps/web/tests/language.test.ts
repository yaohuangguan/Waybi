import { expect, it } from 'vitest';
import { applyUiLanguage, formatDuration, plural, t, translateTree } from '../src/i18n';

it.each(['en','zh'] as const)('localizes document metadata, search and accessible actions (%s)', language => {
  document.head.innerHTML='<meta name="description">';
  document.body.innerHTML='<div id="map" data-i18n-aria-label="map"></div><input id="destinationInput" data-i18n-placeholder="destination" data-i18n-aria-label="destination"><button id="settingsButton" data-i18n-aria-label="settings"></button><button id="clearDestinationButton" data-i18n="cancelDestination"></button>';
  applyUiLanguage(language);
  expect(document.title).toBe(t(language,'title'));
  expect(document.documentElement.lang).toBe(language==='zh'?'zh-CN':'en-NZ');
  expect(document.querySelector('meta[name="description"]')?.getAttribute('content')).toBe(t(language,'description'));
  expect(document.querySelector('#destinationInput')?.getAttribute('aria-label')).toBe(t(language,'destination'));
  expect(document.querySelector('#destinationInput')?.getAttribute('placeholder')).toBe(t(language,'destination'));
  expect(document.querySelector('#settingsButton')?.getAttribute('aria-label')).toBe(t(language,'settings'));
  expect(document.querySelector('#clearDestinationButton')?.textContent).toBe(t(language,'cancelDestination'));
});

it('fills placeholders, plurals and localized duration units', () => {
  expect(t('en','parkingHint',{parking:'Wilson',destination:'Museum'})).toBe('Parking: Wilson · then walk to Museum');
  expect(plural('en',1,'transitStopsOne','transitStopsOther')).toBe('1 stop');
  expect(plural('en',4,'transitStopsOne','transitStopsOther')).toBe('4 stops');
  expect(plural('zh',4,'transitStopsOne','transitStopsOther')).toBe('4 站');
  expect(formatDuration(300,'en')).toBe('5 min');
  expect(formatDuration(4800,'en')).toBe('1 h 20 min');
  expect(formatDuration(3600,'zh')).toBe('1 小时');
  expect(formatDuration(4800,'zh')).toBe('1 小时 20 分钟');
  expect(formatDuration(null,'zh')).toBe('—');
});

it('ignores unknown keys instead of blanking text', () => {
  document.body.innerHTML='<span data-i18n="notARealKey">Keep me</span>';
  translateTree('zh');
  expect(document.body.textContent).toBe('Keep me');
});
