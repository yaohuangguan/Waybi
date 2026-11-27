import './status-page.css';
import { checkoutState } from './routes';
import { lockupSvg } from './brand';
import { t, type Language } from './i18n';
import { applyTheme, readLanguage } from './preferences';

function shell(language: Language, kicker: string, title: string, body: string, links: [string, string][]) {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.body.dataset.surface = 'status';
  const main = document.createElement('main');
  main.className = 'status-page';
  main.innerHTML = `<div class="status-box"><a href="/" aria-label="${t(language, 'home')}">${lockupSvg('Waybi', '', 180)}</a>
    <p class="status-kicker"></p><h1></h1><p class="status-body"></p><div class="status-links"></div></div>`;
  main.querySelector('.status-kicker')!.textContent = kicker;
  main.querySelector('h1')!.textContent = title;
  main.querySelector('.status-body')!.textContent = body;
  const nav = main.querySelector('.status-links')!;
  for (const [href, label] of links) {
    const link = document.createElement('a');
    link.href = href;
    link.textContent = label;
    nav.append(link);
  }
  document.body.replaceChildren(main);
}

function noindex() {
  let robots = document.querySelector<HTMLMetaElement>('meta[name="robots"]');
  if (!robots) { robots = document.createElement('meta'); robots.name = 'robots'; document.head.append(robots); }
  robots.content = 'noindex,follow';
  document.querySelector('link[rel="canonical"]')?.remove();
}

/** A real not-found state instead of the marketing home (soft 404). */
export function renderNotFound(language: Language = readLanguage()) {
  applyTheme();
  noindex();
  document.title = `${t(language, 'notFoundTitle')} · Waybi`;
  shell(language, t(language, 'notFoundKicker'), t(language, 'notFoundTitle'), t(language, 'notFoundBody'),
    [['/', t(language, 'returnHome')], ['/app', t(language, 'openApp')]]);
}

/** Landing page for the checkout success/cancel/portal return URLs. */
export function renderSubscribe(search = location.search, language: Language = readLanguage()) {
  applyTheme();
  noindex();
  const state = checkoutState(search);
  const key = state === 'success' ? 'subscribeSuccess' : state === 'cancelled' ? 'subscribeCancelled' : 'subscribeManage';
  document.title = `${t(language, `${key}Title`)} · Waybi`;
  shell(language, t(language, 'subscribeKicker'), t(language, `${key}Title`), t(language, `${key}Body`),
    [['/dashboard', t(language, 'subscribeDashboard')], ['/app', t(language, 'openApp')]]);
}
