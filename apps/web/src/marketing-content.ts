/**
 * Renders the marketing home page as an HTML string. The build prerenders the
 * English page into index.html (so crawlers and the first paint see the final
 * content and H1); the browser only re-renders when the visitor chose Chinese.
 * Must stay free of DOM and browser APIs: vite.config.ts imports it in Node.
 */
import { copy, extraCopy, type MarketingLanguage } from './marketing-copy';
import { lockupSvg } from './brand';

export function storeLink(value: string | undefined): string {
  try {
    const url = new URL(value || '');
    return url.protocol === 'https:' && url.hostname === 'apps.apple.com'
      && !url.username && !url.password && !url.port
      && /\/id\d+(?:\/|$)/.test(url.pathname) ? url.href : '';
  } catch { return ''; }
}

export function marketingMeta(language: MarketingLanguage) {
  return { title: extraCopy[language].documentTitle, description: extraCopy[language].documentDescription };
}

const bird = `<svg class="waybi" viewBox="0 0 120 110" aria-hidden="true" focusable="false"><path fill="currentColor" d="M18 57c0-22 16-36 37-36 13 0 23 5 30 15 3-9 10-15 19-15 11 0 17 9 16 18-1 10-8 16-17 18l-16 4C85 79 70 91 48 89 28 88 18 76 18 57Z" transform="translate(-8 0)"/><path d="m98 45 21 8-24 1M44 87l-4 14m0 0-10 3m10-3 8 4m17-19 2 14m0 0-8 4m8-4 10 2" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/><circle cx="94" cy="35" r="3" fill="#F8FBEF"/><path d="M37 48c8-8 17-7 24-2" fill="none" stroke="#F8FBEF" stroke-width="3" stroke-linecap="round"/></svg>`;

/** Brand artwork is served as WebP at about twice its display size. */
function art(name: 'waybi' | 'clover' | 'sett', size: number, alt: string, className = '') {
  const file = name === 'waybi' ? (size <= 128 ? 'waybi-256.webp' : 'waybi-640.webp') : `${name}-512.webp`;
  return `<img${className ? ` class="${className}"` : ''} src="/brand/${file}" alt="${alt}" width="${size}" height="${size}" loading="lazy" decoding="async" />`;
}

export function renderMarketing(language: MarketingLanguage, options: { appStoreUrl?: string; year?: number } = {}) {
  const c = copy[language];
  const x = extraCopy[language];
  const zh = language === 'zh';
  const appStoreUrl = storeLink(options.appStoreUrl);
  const year = options.year ?? new Date().getFullYear();
  const about = zh ? '/zh/about/' : '/about/';
  const local = (path: string) => (zh ? `/zh${path}` : path);
  const logo = lockupSvg('Waybi', 'marketing-lockup', 171);
  const meters = x.previewMeters;
  return `
    <a href="#main" class="skip-link">${c.skip}</a>
    <div class="site">
      <header class="header">
        <a class="brand" href="/" aria-label="Waybi">${logo}</a>
        <nav class="nav" id="site-nav" aria-label="${x.mainNav}">
          ${c.nav.map((label, i) => `<a href="${['#experience', '#awareness', '#friends', '#faq', about][i]}">${label}</a>`).join('')}
        </nav>
        <div class="header-actions">
          <button class="language" type="button" lang="${zh ? 'en' : 'zh-CN'}" aria-label="${x.switchLanguage}">${x.languageButton}</button>
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
            <div class="hero-actions"><a class="button" href="#download">${c.start}<span aria-hidden="true">↗</span></a><a class="text-link" href="#friends">${c.discover}<span aria-hidden="true">↓</span></a></div>
            <div class="hero-note">${bird}<span>${c.note}</span></div>
          </div>
          <div class="preview" role="img" aria-label="${c.preview}: ${c.turn}; ${c.camera} 300 ${meters}">
            <div class="preview-sticker">${bird}<span>${c.sticker}</span></div>
            <div class="phone" aria-hidden="true">
              <svg class="map-art" viewBox="0 0 330 600" preserveAspectRatio="xMidYMid slice"><rect width="330" height="600" fill="#eaf0df"/><path d="M-40 277c69-63 123-55 136-136s110-101 257-85v130c-97-32-163-2-174 78s-142 80-196 141Z" fill="#d1e1c0"/><path d="M245 240c-34 21-18 74 36 87s65 31 60 117v-220Z" fill="#c4d6bb"/><g fill="none" stroke="#fffdf6" stroke-width="22"><path d="M-30 70 345 450M-10 255 370 240M-10 433 390 390M55-30 35 640M213-25 198 670M-25 575 370 565"/></g><g fill="none" stroke="#d2d9c7" stroke-width="1"><path d="M-30 70 345 450M-10 255 370 240M-10 433 390 390M55-30 35 640M213-25 198 670"/></g><path d="M163 568V402q0-15 15-15h24V252q0-10-12-10H35V87" fill="none" stroke="#486B29" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/><path d="M163 568V402q0-15 15-15h24V252q0-10-12-10H35V87" fill="none" stroke="#D0F58A" stroke-width="3" stroke-linecap="round"/></svg>
              <div class="phone-status"><span>9:41</span><span>●●● ▰</span></div>
              <div class="preview-turn"><div class="turn-line"><span class="turn-symbol">↰</span><div><strong>180 ${meters}</strong><small>${c.turn}</small></div></div><div class="preview-lanes"><small>${c.lane}</small><b>↰</b><b>↑</b><b>↗</b></div></div>
              <div class="preview-camera"><span class="lens">◉</span><div><strong>${c.camera}</strong><small>Queen Street</small></div><b>300 ${meters}</b></div>
              <span class="map-road-label">Queen Street</span><div class="map-kiwi">${bird}</div>
              <div class="preview-deck"><i class="deck-handle"></i><div class="deck-title">${bird}${c.destination}</div><div class="deck-stats">${[c.minutes, c.distance, c.cameras].map((value, i) => `<div><strong>${value}</strong><small>${c.labels[i]}</small></div>`).join('')}</div><div class="deck-chips">${c.chips.map(value => `<span>${value}</span>`).join('')}</div></div>
            </div><span class="preview-caption">${c.preview}</span>
          </div>
        </section>
        <div class="promise-strip">${c.promises.map((promise, i) => `<span><b aria-hidden="true">${['↗', '◉', '♡'][i]}</b>${promise}</span>`).join('')}</div>
        <section class="features" id="experience">
          <div class="section-heading"><div><span class="eyebrow">${c.featuresLabel}</span><h2>${c.featuresTitle}</h2></div><p>${c.featuresLead}</p></div>
          <div class="feature-grid">${c.features.map(([title, description], i) => `<article class="feature ${['dark', '', 'lime'][i]}"><span class="feature-number">0${i + 1}</span><div class="feature-visual" aria-hidden="true">${['<span class="active">↰</span><span>↑</span><span>↗</span>', '↗ &nbsp; → &nbsp; ⌖', '⌁ &nbsp; ✓' + bird][i]}</div><h3>${title}</h3><p>${description}</p></article>`).join('')}</div>
        </section>
        <section class="safety" id="awareness">
          <div class="safety-art" aria-hidden="true">${bird}<div class="camera-demo"><span>◉</span><div><strong>${c.demo}</strong><small>${c.demoRoad}</small></div></div></div>
          <div class="safety-copy"><span class="eyebrow">${c.safetyLabel}</span><h2>${c.safetyTitle}</h2><p>${c.safetyLead}</p><ul class="safety-list">${c.safetyItems.map(item => `<li><b aria-hidden="true">✓</b>${item}</li>`).join('')}</ul><a class="text-link" href="https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations" target="_blank" rel="noopener noreferrer">${c.source}<span aria-hidden="true">↗</span></a><div class="source-note">${c.sourceNote}</div></div>
        </section>
        <section class="friends-world" id="friends" aria-labelledby="friends-title">
          <div class="friends-copy">
            <span class="eyebrow">${c.friendsLabel}</span><h2 id="friends-title">${c.friendsTitle}</h2>
            <p class="friends-lead">${c.friendsLead}</p>
            <div class="friends-steps">${c.friendsSteps.map(([title, description], i) => `<article><span aria-hidden="true">0${i + 1}</span><div><h3>${title}</h3><p>${description}</p></div></article>`).join('')}</div>
            <p class="friends-entry">${c.friendsEntry}</p><a class="text-link" href="#download">${c.friendsButton}<span aria-hidden="true">↗</span></a>
          </div>
          <figure class="friends-preview"><span class="friends-preview-tag">WAYBI & FRIENDS</span><img src="/previews/waybi-friends.webp" alt="${x.friendsAlt}" width="446" height="960" loading="lazy" decoding="async" /><figcaption>${c.friendsCaption}</figcaption></figure>
          <div class="friend-introductions">${(['Waybi', 'Clover', 'Sett'] as const).map((name, i) => `<article class="friend-introduction friend-${name.toLowerCase()}"><div class="friend-portrait">${art(name.toLowerCase() as 'waybi' | 'clover' | 'sett', 130, name)}</div><span>${c.characterLabels[i]}</span><h3>${name}</h3><p>${c.characterNotes[i]}</p></article>`).join('')}</div>
        </section>
        <section class="origin-teaser" aria-labelledby="origin-title">
          <div class="origin-teaser-copy">
            <span class="eyebrow">${c.storyLabel}</span>
            <h2 id="origin-title">${c.storyTitle}</h2>
            <p>${c.storyBody}</p>
            <a class="text-link" href="${about}">${c.storyAction}<span aria-hidden="true">↗</span></a>
          </div>
          <div class="origin-teaser-visual" aria-hidden="true"><span>${x.teaserVisual}</span>${art('waybi', 205, '')}<i>↗</i></div>
        </section>
        <section class="seo-guides" aria-labelledby="seo-guides-title">
          <div class="section-heading"><div><span class="eyebrow">${x.guidesLabel}</span><h2 id="seo-guides-title">${x.guidesTitle}</h2></div><p>${x.guidesLead}</p></div>
          <div class="seo-guide-grid">
            ${x.guides.map(([kicker, title, body], i) => `<a class="seo-guide-card guide-${i}" href="${local(['/new-zealand-navigation/', '/safety-camera-navigation/', '/route-watch/', '/waybi-friends/'][i]!)}"><span class="guide-icon" aria-hidden="true">${i === 3 ? art('waybi', 70, '') : ['↰', '!', '↝'][i]}</span><span>${kicker}</span><h3>${title}</h3><p>${body}</p><b>${x.guideMore}</b></a>`).join('')}
          </div>
          <div class="planning-guides">
            <span class="eyebrow">${x.planningLabel}</span><h3>${x.planningTitle}</h3>
            <ul>${x.planning.map(([href, title, body]) => `<li><a href="${href}"${zh ? ' hreflang="en"' : ''}>${title}</a><p>${body}</p></li>`).join('')}</ul>
          </div>
        </section>
        <section class="faq" id="faq"><div><span class="eyebrow">${c.faqLabel}</span><h2>${c.faqTitle}</h2></div><div>${c.faqs.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join('')}</div></section>
        <section class="download cta" id="download" aria-labelledby="download-title">
          <div><span class="eyebrow">${x.downloadLabel}</span>
            <h2 id="download-title">${x.downloadTitle}</h2>
            <p>${x.downloadLead}</p>
            ${appStoreUrl ? `<a class="button lime store-button" href="${appStoreUrl}" target="_blank" rel="noopener noreferrer">${x.storeLive} <span aria-hidden="true">↗</span></a>` : `<button class="button lime store-button" type="button" disabled>${x.storeSoon}</button>`}
            <small class="release-note">${appStoreUrl ? x.releaseLive : x.releaseSoon}</small>
            <p class="web-map-entry">${c.webMapNote} <a href="/app">${c.webMap}<span aria-hidden="true"> ↗</span></a></p>
          </div>${bird}
        </section>
      </main>
      <footer class="footer"><a class="brand" href="/" aria-label="Waybi">${logo}</a><div class="footer-links"><a href="/app">${c.webMap}</a>${c.links.map((label, i) => `<a href="${['#download', '/dashboard', 'https://github.com/yaohuangguan/Waybi/issues'][i]}">${label}</a>`).join('')}<a href="${local('/new-zealand-navigation/')}">${x.footerGuide}</a><a href="${local('/safety-camera-navigation/')}">${x.footerCameras}</a><a href="${local('/route-watch/')}">Route Watch</a><a href="${about}">${x.footerAbout}</a>${(['privacy', 'terms', 'support'] as const).map((page, i) => `<a href="${local(`/${page}/`)}">${x.footerLegal[i]}</a>`).join('')}<a href="/zh/" lang="zh-CN">中文</a></div><p>${c.footer}<br>${c.disclaimer}</p><small>© ${year} Waybi</small></footer>
    </div>`;
}
