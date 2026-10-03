const path = window.location.pathname.replace(/\/+$/, '') || '/';
const app = document.getElementById('app');

function renderBootState(label: string) {
  document.body.innerHTML = `
    <div style="min-height:100vh;display:grid;place-items:center;background:#F8FBEF;color:#152510;font:600 14px system-ui,sans-serif">
      <div style="display:grid;justify-items:center;gap:14px">
        <span style="width:42px;height:42px;border-radius:13px;background:#152510;box-shadow:0 10px 26px rgba(11,23,23,.18)"></span>
        <span style="color:#64705B">${label}</span>
      </div>
    </div>`;
}

async function boot() {
  try {
    if (path === '/app') {
      if (app) app.hidden = false;
      await import('./main');
      return;
    }

    app?.remove();

    if (path === '/dashboard') {
      renderBootState('Loading your Waybi dashboard…');
      await import('./dashboard');
      return;
    }

    renderBootState('Loading Waybi…');
    await import('./marketing');
  } catch (error) {
    console.error('Waybi route failed to load', error);
    document.body.innerHTML = `
      <main style="min-height:100vh;display:grid;place-items:center;padding:32px;background:#F8FBEF;font-family:system-ui,sans-serif;color:#152510">
        <div style="max-width:520px;text-align:center"><h1>Waybi could not load this page.</h1><p style="color:#64705B">Refresh the page or return to the website.</p><a href="/" style="color:#486B29;font-weight:700">Return home</a></div>
      </main>`;
  }
}

void boot();
