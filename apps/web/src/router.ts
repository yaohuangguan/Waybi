import { canonicalAppUrl, resolveSurface } from './routes';

const surface = resolveSurface(window.location.pathname);

const failureCopy = {
  en: ['Waybi could not load this page.', 'Refresh the page or return to the website.', 'Return home'],
  zh: ['Waybi 无法加载此页面。', '请刷新页面，或返回网站首页。', '返回首页'],
} as const;

function storedLanguage(): 'en' | 'zh' {
  try { return localStorage.getItem('waybi-ui-language') === 'zh' ? 'zh' : 'en'; } catch { return 'en'; }
}

function renderBootState(label: string) {
  const shell = document.createElement('div');
  shell.className = 'boot-state';
  shell.setAttribute('role', 'status');
  shell.innerHTML = '<span class="boot-mark" aria-hidden="true"></span><span class="boot-label"></span>';
  shell.querySelector('.boot-label')!.textContent = label;
  document.body.replaceChildren(shell);
}

function renderFailure() {
  const [title, body, home] = failureCopy[storedLanguage()];
  const main = document.createElement('main');
  main.className = 'boot-state';
  main.innerHTML = '<div class="boot-failure"><h1></h1><p></p><a href="/"></a></div>';
  main.querySelector('h1')!.textContent = title;
  main.querySelector('p')!.textContent = body;
  main.querySelector('a')!.textContent = home;
  document.body.replaceChildren(main);
}

async function boot() {
  try {
    if (surface === 'app') {
      const canonical = canonicalAppUrl(window.location);
      if (canonical) history.replaceState(history.state, '', canonical);
      document.getElementById('marketing-root')?.remove();
      await import('./main');
      return;
    }
    document.getElementById('app')?.remove();
    if (surface === 'marketing') {
      // The page is already rendered statically; this only adds behaviour.
      await import('./marketing');
      return;
    }
    document.getElementById('marketing-root')?.remove();
    if (surface === 'dashboard') {
      renderBootState(storedLanguage() === 'zh' ? '正在加载你的 Waybi 个人面板…' : 'Loading your Waybi dashboard…');
      await import('./dashboard');
      return;
    }
    const status = await import('./status-page');
    if (surface === 'subscribe') status.renderSubscribe();
    else status.renderNotFound();
  } catch (error) {
    console.error('Waybi route failed to load', error);
    renderFailure();
  }
}

void boot();
