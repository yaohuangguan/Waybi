/**
 * Progressive enhancement for the prerendered marketing page. The English page
 * is already in the HTML; this only binds the menu and language toggle, and
 * re-renders when the visitor's saved language is Chinese.
 */
import { marketingMeta, renderMarketing } from './marketing-content';
import { applyTheme, readLanguage, writeLanguage } from './preferences';

const appStoreUrl = import.meta.env.VITE_APP_STORE_URL as string | undefined;
let language = readLanguage();
let menuListeners = new AbortController();

function root() {
  let node = document.getElementById('marketing-root');
  if (!node) {
    // Fallback when the static markup is missing (tests, or an old cached shell).
    node = document.createElement('div');
    node.id = 'marketing-root';
    node.className = 'marketing';
    document.body.replaceChildren(node);
  }
  return node;
}

function applyMeta() {
  const meta = marketingMeta(language);
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.title = meta.title;
  document.querySelector('meta[name="description"]')?.setAttribute('content', meta.description);
}

function render() {
  const node = root();
  node.innerHTML = renderMarketing(language, { appStoreUrl });
  node.dataset.language = language;
  bind();
}

function bind() {
  menuListeners.abort();
  menuListeners = new AbortController();
  const signal = menuListeners.signal;
  document.body.dataset.surface = 'marketing';
  applyMeta();
  document.querySelector('.language')?.addEventListener('click', () => {
    language = language === 'zh' ? 'en' : 'zh';
    writeLanguage(language);
    render();
    document.querySelector<HTMLButtonElement>('.language')?.focus({ preventScroll: true });
  }, { signal });
  const menu = document.querySelector<HTMLButtonElement>('.menu')!;
  const nav = document.querySelector<HTMLElement>('.nav')!;
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('open', open);
  }, { signal });
  nav.addEventListener('click', (event) => {
    if ((event.target as HTMLElement).closest('a')) {
      nav.classList.remove('open');
      menu.setAttribute('aria-expanded', 'false');
    }
  }, { signal });
  document.addEventListener('keydown', closeMenu, { signal });
}

function closeMenu(event: KeyboardEvent) {
  if (event.key !== 'Escape') return;
  const menu = document.querySelector<HTMLButtonElement>('.menu');
  if (!menu || menu.getAttribute('aria-expanded') !== 'true') return;
  menu.setAttribute('aria-expanded', 'false');
  document.querySelector('.nav')?.classList.remove('open');
  menu.focus();
}

applyTheme();
const existing = document.getElementById('marketing-root');
// First paint already shows the final English page: only bind, never repaint it.
if (existing?.dataset.language === language && existing.querySelector('h1')) bind();
else render();
