import './marketing.css';

function storeLink(value: string | undefined): string {
  try {
    const url = new URL(value || '');
    return url.protocol === 'https:' && url.hostname === 'apps.apple.com'
      && !url.username && !url.password && !url.port
      && /\/id\d+(?:\/|$)/.test(url.pathname) ? url.href : '';
  } catch { return ''; }
}
const appStoreUrl = storeLink(import.meta.env.VITE_APP_STORE_URL);

let language = localStorage.getItem('waybi-language') === 'zh' ? 'zh' : 'en';
const bird = `<svg class="waybi" viewBox="0 0 120 110" aria-hidden="true"><path fill="currentColor" d="M18 57c0-22 16-36 37-36 13 0 23 5 30 15 3-9 10-15 19-15 11 0 17 9 16 18-1 10-8 16-17 18l-16 4C85 79 70 91 48 89 28 88 18 76 18 57Z" transform="translate(-8 0)"/><path d="m98 45 21 8-24 1M44 87l-4 14m0 0-10 3m10-3 8 4m17-19 2 14m0 0-8 4m8-4 10 2" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/><circle cx="94" cy="35" r="3" fill="#F8FBEF"/><path d="M37 48c8-8 17-7 24-2" fill="none" stroke="#F8FBEF" stroke-width="3" stroke-linecap="round"/></svg>`;
const logo = `<img src="/brand/waybi-lockup.svg" alt="Waybi" width="171" height="44" />`;
const copy = {
  en: {
    skip: 'Skip to content', nav: ['The experience', 'Road awareness', 'Good to know'], open: 'Get the app', menu: 'Menu',
    eyebrow: 'A little local knowledge. A lot more Waybi.', title: 'Your map.<br>A little more<br><em>Waybi.</em>',
    lead: 'Familiar maps, thoughtful navigation, and a friend who knows what’s ahead. Meet your new travelling companion for New Zealand roads.',
    start: 'Get Waybi for iPhone', discover: 'Meet Waybi', note: 'For iPhone. Coming soon to the App Store.',
    sticker: 'Small bird.<br>Big adventure.', preview: 'Interface preview · sample route', lane: 'USE LANE', turn: 'Turn left onto Queen Street', camera: 'Safety camera ahead', destination: 'Waybi Cafe', minutes: '6 min', distance: '2.4 km', cameras: '2', labels: ['To go', 'Distance', 'Cameras'], chips: ['Voice ✓', 'Lanes ✓', 'Overview'],
    promises: ['Made for Aotearoa', 'Official NZ camera data', 'English & 中文'],
    featuresLabel: 'A NICER WAY TO GET THERE', featuresTitle: 'A clearer road.<br>A calmer journey.', featuresLead: 'The useful details, right where you need them. With a little Waybi personality along the way.',
    features: [
      ['Your next move, made clear.', 'See the next turn and recommended lanes together. Camera reminders sit just below, where they’re easy to spot.'],
      ['One voice at a time.', 'Camera announcements wait for navigation guidance to finish. Helpful reminders, with room to hear the road.'],
      ['A little “you made it”.', 'Arrive, wrap up, and see your journey at a glance: your route, distance, time and cameras along the way.'],
    ],
    safetyLabel: 'LOCAL KNOWLEDGE, LESS GUESSWORK', safetyTitle: 'A heads-up<br>for the road ahead.', safetyLead: 'Waybi puts official New Zealand safety-camera locations in the context of your drive, with reminders for what’s coming up on your route.',
    safetyItems: ['Route-aware camera reminders', 'An easy-to-spot alert above the map', 'Your map, in English or Chinese'],
    demo: 'Camera · 300 m', demoRoad: 'Queen Street · sample alert', source: 'Explore the NZTA source', sourceNote: 'Fixed camera data comes from NZ Transport Agency Waka Kotahi. Road signs and current conditions always come first.',
    faqLabel: 'BEFORE YOU SET OFF', faqTitle: 'Good to know.',
    faqs: [
      ['Can I try it without an account?', 'Yes. Open the app, choose a destination and explore routes as a guest. Sign in to your dashboard when you want saved places and trip history.'],
      ['Is this Google Maps?', 'Waybi offers Google Maps and its own independent map, with a shared navigation interface and New Zealand camera awareness. Google’s required attribution remains visible.'],
      ['What about lane guidance and camera coverage?', 'Lane guidance appears when the navigation provider supplies it. Camera data covers published fixed safety cameras; it does not describe every road hazard, camera direction or enforcement lane.'],
      ['Does the screen stay awake?', 'The keep-screen-on setting is enabled by default during navigation. Your iPhone stays awake while navigation is on screen.'],
    ],
    cta: 'Good roads.<br>Great little companion.', ctaLead: 'Your next adventure starts with a destination.', ctaButton: 'Let’s go, Waybi', footer: 'A little more awareness. A little more Waybi.', links: ['Get the app', 'Dashboard', 'Contact'], disclaimer: 'Navigation and camera information are driving aids. Follow road signs, current conditions and New Zealand law.',
  },
  zh: {
    skip: '跳转到正文', nav: ['导航体验', '沿途提醒', '出发前了解'], open: '获取 App', menu: '菜单',
    eyebrow: '懂一点本地路况，多一点 Waybi 陪伴。', title: '熟悉的地图，<br><em>多一点 Waybi。</em>',
    lead: '好用的地图，贴心的导航，还有一只知道前方路况的小伙伴。和 Waybi 一起，轻松探索新西兰的每一段路。',
    start: '获取 iPhone 版 Waybi', discover: '认识 Waybi', note: 'iPhone 版，即将登陆 App Store。',
    sticker: '小小 Waybi，<br>大大冒险。', preview: '界面示意 · 示例路线', lane: '推荐车道', turn: '左转，驶向 Queen Street', camera: '前方摄像头', destination: 'Waybi 咖啡馆', minutes: '6 分钟', distance: '2.4 公里', cameras: '2', labels: ['剩余时间', '剩余距离', '沿途摄像头'], chips: ['语音 ✓', '车道 ✓', '路线总览'],
    promises: ['为新西兰道路设计', '官方摄像头公开数据', '中文与 English'],
    featuresLabel: '让每一程，都舒服一点', featuresTitle: '看清前方，<br>从容出发。', featuresLead: '有用的信息，放在刚好看得见的位置。再加一点 Waybi 的可爱与陪伴。',
    features: [
      ['下一步，一眼就明白。', '转向信息与推荐车道一起呈现。摄像头提醒紧跟在下方，抬眼就能看见。'],
      ['一次，只听一个声音。', '摄像头播报会等待导航语音结束。需要提醒时再开口，让你听得清，也更从容。'],
      ['到啦，回顾这段小旅程。', '到达后查看路线、行驶距离、用时和沿途摄像头。这一程，和 Waybi 一起记下来。'],
    ],
    safetyLabel: '多一点路况信息，少一点猜测', safetyTitle: '前方的提醒，<br>提前看见。', safetyLead: 'Waybi 将新西兰官方公布的摄像头位置与你的行驶路线结合，在合适的时候，提醒前方需要留意的信息。',
    safetyItems: ['结合当前路线的摄像头提醒', '地图上方醒目的提示条', '中英文切换，按你的习惯来'],
    demo: '摄像头 · 300 米', demoRoad: 'Queen Street · 示例提醒', source: '查看 NZTA 数据来源', sourceNote: '固定摄像头数据来自新西兰交通局 Waka Kotahi。请始终以道路标志和实际路况为准。',
    faqLabel: '出发之前', faqTitle: '你可能想了解。',
    faqs: [
      ['不注册也能使用吗？', '可以。打开 App，选择目的地，以访客身份探索路线。需要保存地点或查看行程记录时，再登录你的个人面板。'],
      ['这是 Google Maps 吗？', 'Waybi 提供 Google Maps 和自研地图两种选择，配上自己的导航界面和新西兰摄像头提醒。Google 要求的地图署名会保持可见。'],
      ['车道信息和摄像头覆盖范围如何？', '导航服务提供车道数据时，界面会展示推荐车道。摄像头数据覆盖官方公布的固定摄像头，不代表所有道路风险，也不包含测速方向或执法车道。'],
      ['导航时屏幕会保持亮起吗？', '导航常亮设置默认开启。在 iPhone 上显示导航时，屏幕会保持亮起。'],
    ],
    cta: '好走的路，<br>可爱的小伙伴。', ctaLead: '下一段小冒险，从选个目的地开始。', ctaButton: '走吧，Waybi', footer: '多一点前方信息，多一点 Waybi 陪伴。', links: ['获取 App', '个人面板', '联系我们'], disclaimer: '导航和摄像头信息仅作为驾驶辅助。请遵守道路标志、实际路况和新西兰交通法规。',
  },
};

let menuListeners = new AbortController();
function render() {
  menuListeners.abort();
  menuListeners = new AbortController();
  const c = copy[language as keyof typeof copy];
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.title = language === 'zh' ? 'Waybi · 多一点 Waybi 的导航地图' : 'Waybi · Your map. A little more Waybi.';
  document.querySelector('meta[name="description"]')?.setAttribute('content', c.lead);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', '#F8FBEF');
  document.body.dataset.surface = 'marketing';
  document.body.innerHTML = `
    <a href="#main" class="skip-link">${c.skip}</a>
    <div class="site">
      <header class="header">
        <a class="brand" href="/" aria-label="Waybi">${logo}</a>
        <nav class="nav" id="site-nav" aria-label="${language === 'zh' ? '主导航' : 'Main navigation'}">
          ${c.nav.map((label, i) => `<a href="#${['experience', 'awareness', 'faq'][i]}">${label}</a>`).join('')}
        </nav>
        <div class="header-actions">
          <button class="language" type="button" aria-label="${language === 'zh' ? 'Switch to English' : '切换到中文'}">${language === 'zh' ? 'EN' : '中文'}</button>
          <a class="button small" href="#download">${c.open}<span aria-hidden="true">↗</span></a>
          <button class="menu" type="button" aria-controls="site-nav" aria-expanded="false" aria-label="${c.menu}">☰</button>
        </div>
      </header>
      <main id="main">
        <section class="hero">
          <div class="hero-copy">
            <span class="eyebrow"><i></i>${c.eyebrow}</span>
            <h1>${c.title}</h1>
            <p class="hero-lead">${c.lead}</p>
            <div class="hero-actions"><a class="button" href="#download">${c.start}<span aria-hidden="true">↗</span></a><a class="text-link" href="#experience">${c.discover}<span aria-hidden="true">↓</span></a></div>
            <div class="hero-note">${bird}<span>${c.note}</span></div>
          </div>
          <div class="preview" role="img" aria-label="${c.preview}: ${c.turn}; ${c.camera} 300 m">
            <div class="preview-sticker">${bird}<span>${c.sticker}</span></div>
            <div class="phone" aria-hidden="true">
              <svg class="map-art" viewBox="0 0 330 600" preserveAspectRatio="xMidYMid slice"><rect width="330" height="600" fill="#eaf0df"/><path d="M-40 277c69-63 123-55 136-136s110-101 257-85v130c-97-32-163-2-174 78s-142 80-196 141Z" fill="#d1e1c0"/><path d="M245 240c-34 21-18 74 36 87s65 31 60 117v-220Z" fill="#c4d6bb"/><g fill="none" stroke="#fffdf6" stroke-width="22"><path d="M-30 70 345 450M-10 255 370 240M-10 433 390 390M55-30 35 640M213-25 198 670M-25 575 370 565"/></g><g fill="none" stroke="#d2d9c7" stroke-width="1"><path d="M-30 70 345 450M-10 255 370 240M-10 433 390 390M55-30 35 640M213-25 198 670"/></g><path d="M163 568V402q0-15 15-15h24V252q0-10-12-10H35V87" fill="none" stroke="#486B29" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/><path d="M163 568V402q0-15 15-15h24V252q0-10-12-10H35V87" fill="none" stroke="#D0F58A" stroke-width="3" stroke-linecap="round"/></svg>
              <div class="phone-status"><span>9:41</span><span>●●● ▰</span></div>
              <div class="preview-turn"><div class="turn-line"><span class="turn-symbol">↰</span><div><strong>180 ${language === 'zh' ? '米' : 'm'}</strong><small>${c.turn}</small></div></div><div class="preview-lanes"><small>${c.lane}</small><b>↰</b><b>↑</b><b>↗</b></div></div>
              <div class="preview-camera"><span class="lens">◉</span><div><strong>${c.camera}</strong><small>Queen Street</small></div><b>300 ${language === 'zh' ? '米' : 'm'}</b></div>
              <span class="map-road-label">Queen Street</span><div class="map-kiwi">${bird}</div>
              <div class="preview-deck"><i class="deck-handle"></i><div class="deck-title">${bird}${c.destination}</div><div class="deck-stats">${[c.minutes, c.distance, c.cameras].map((value, i) => `<div><strong>${value}</strong><small>${c.labels[i]}</small></div>`).join('')}</div><div class="deck-chips">${c.chips.map(value => `<span>${value}</span>`).join('')}</div></div>
            </div><span class="preview-caption">${c.preview}</span>
          </div>
        </section>
        <div class="promise-strip">${c.promises.map((promise, i) => `<span><b aria-hidden="true">${['↗', '◉', '文'][i]}</b>${promise}</span>`).join('')}</div>
        <section class="features" id="experience">
          <div class="section-heading"><div><span class="eyebrow">${c.featuresLabel}</span><h2>${c.featuresTitle}</h2></div><p>${c.featuresLead}</p></div>
          <div class="feature-grid">${c.features.map(([title, description], i) => `<article class="feature ${['dark', '', 'lime'][i]}"><span class="feature-number">0${i + 1}</span><div class="feature-visual" aria-hidden="true">${['<span class="active">↰</span><span>↑</span><span>↗</span>', '◉ &nbsp; → &nbsp; ♫', '⌁ &nbsp; ✓' + bird][i]}</div><h3>${title}</h3><p>${description}</p></article>`).join('')}</div>
        </section>
        <section class="safety" id="awareness">
          <div class="safety-art" aria-hidden="true">${bird}<div class="camera-demo"><span>◉</span><div><strong>${c.demo}</strong><small>${c.demoRoad}</small></div></div></div>
          <div class="safety-copy"><span class="eyebrow">${c.safetyLabel}</span><h2>${c.safetyTitle}</h2><p>${c.safetyLead}</p><ul class="safety-list">${c.safetyItems.map(item => `<li><b aria-hidden="true">✓</b>${item}</li>`).join('')}</ul><a class="text-link" href="https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations" target="_blank" rel="noopener noreferrer">${c.source}<span aria-hidden="true">↗</span></a><div class="source-note">${c.sourceNote}</div></div>
        </section>
        <section class="faq" id="faq"><div><span class="eyebrow">${c.faqLabel}</span><h2>${c.faqTitle}</h2></div><div>${c.faqs.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join('')}</div></section>
        <section class="download cta" id="download" aria-labelledby="download-title">
          <div><span class="eyebrow">${language === 'zh' ? 'WAYBI · IPHONE 版' : 'WAYBI FOR IPHONE'}</span>
            <h2 id="download-title">${language === 'zh' ? '把 Waybi，<br>带上你的下一程。' : 'Your next adventure.<br>With Waybi along.'}</h2>
            <p>${language === 'zh' ? '熟悉的转向提示，贴心的道路提醒，还有你选的小伙伴。' : 'Clear turns, thoughtful road reminders, and a little companion of your own.'}</p>
            ${appStoreUrl ? `<a class="button lime store-button" href="${appStoreUrl}" target="_blank" rel="noopener noreferrer">${language === 'zh' ? '在 App Store 下载' : 'Download on the App Store'} <span aria-hidden="true">↗</span></a>` : `<button class="button lime store-button" type="button" disabled>${language === 'zh' ? 'App Store · 即将上线' : 'Coming soon on the App Store'}</button>`}
            <small class="release-note">${appStoreUrl ? (language === 'zh' ? '在 iPhone 上开启你的下一程。' : 'Start your next journey on iPhone.') : (language === 'zh' ? '目前尚未上架。发布后，这里将直接通往 App Store。' : 'Not listed yet. This will take you straight to the App Store when Waybi launches.')}</small>
          </div>${bird}
        </section>
        <section class="companions" aria-labelledby="companions-title">
          <span class="eyebrow">${language === 'zh' ? '你的旅途小伙伴' : 'A LITTLE COMPANY FOR THE ROAD'}</span>
          <h2 id="companions-title">${language === 'zh' ? '认识 Clover 和 Sett。' : 'Meet Clover and Sett.'}</h2>
          <p>${language === 'zh' ? '一只好奇的猫，一只可靠的狗。选个小伙伴，陪你一路向前。' : 'One curious cat. One loyal dog. Choose a map companion that feels like you.'}</p>
          <div class="companion-grid">
            <article class="companion clover"><img src="/brand/clover.png" alt="Clover" width="180" height="180" loading="lazy" /><div><span>${language === 'zh' ? '好奇的小猫' : 'THE CURIOUS CAT'}</span><h3>Clover</h3><p>${language === 'zh' ? '总想看看下一个转角。和你一起，发现路上的小惊喜。' : 'Always wondering what is around the next corner. For the little detours that become good stories.'}</p></div></article>
            <article class="companion sett"><img src="/brand/sett.png" alt="Sett" width="180" height="180" loading="lazy" /><div><span>${language === 'zh' ? '可靠的小狗' : 'YOUR LOYAL COPILOT'}</span><h3>Sett</h3><p>${language === 'zh' ? '每一段路，都陪在你身边。不管远近，出发就很开心。' : 'Happy to be along for the ride. From everyday errands to the long way home, Sett is right beside you.'}</p></div></article>
          </div>
        </section>
      </main>
      <footer class="footer"><a class="brand" href="/">${logo}</a><div class="footer-links">${c.links.map((label, i) => `<a href="${['#download', '/dashboard', 'https://github.com/yaohuangguan/Waybi/issues'][i]}">${label}</a>`).join('')}</div><p>${c.footer}<br>${c.disclaimer}</p><small>© ${new Date().getFullYear()} Waybi</small></footer>
    </div>`;
  document.querySelector('.language')?.addEventListener('click', () => {
    language = language === 'zh' ? 'en' : 'zh';
    localStorage.setItem('waybi-language', language);
    render();
    document.querySelector<HTMLButtonElement>('.language')?.focus({ preventScroll: true });
  });
  const menu = document.querySelector<HTMLButtonElement>('.menu')!;
  const nav = document.querySelector<HTMLElement>('.nav')!;
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('open', open);
  });
  nav.addEventListener('click', (event) => {
    if ((event.target as HTMLElement).closest('a')) {
      nav.classList.remove('open');
      menu.setAttribute('aria-expanded', 'false');
    }
  });
  document.addEventListener('keydown', closeMenu, { signal: menuListeners.signal });
}
// Replace the listener across locale renders instead of accumulating handlers.
function closeMenu(event: KeyboardEvent) {
  if (event.key !== 'Escape') return;
  const menu = document.querySelector<HTMLButtonElement>('.menu')!;
  if (menu.getAttribute('aria-expanded') !== 'true') return;
  menu.setAttribute('aria-expanded', 'false');
  document.querySelector('.nav')?.classList.remove('open');
  menu.focus();
}
render();
