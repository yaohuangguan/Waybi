import { expect, it } from 'vitest';
import { applyUiLanguage, t } from '../src/i18n';
it.each(['en','zh'] as const)('localizes document metadata, search and accessible actions (%s)', language => {
  document.head.innerHTML='<meta name="description">';
  document.body.innerHTML='<div id="map"></div><input id="destinationInput"><button id="settingsButton"></button><button id="clearDestinationButton"></button><div id="dataOverlay"><a class="source-link"></a></div>';
  applyUiLanguage(language);
  expect(document.title).toBe(t(language,'title'));
  expect(document.documentElement.lang).toBe(language==='zh'?'zh-CN':'en-NZ');
  expect(document.querySelector('#destinationInput')?.getAttribute('aria-label')).toBe(t(language,'destination'));
  expect(document.querySelector('#settingsButton')?.getAttribute('aria-label')).toBe(t(language,'settings'));
  expect(document.querySelector('#clearDestinationButton')?.textContent).toBe(t(language,'cancelDestination'));
});
