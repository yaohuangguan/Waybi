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
  "en": {
    "skip": "Skip to content",
    "nav": [
      "The experience",
      "Road awareness",
      "Waybi & Friends",
      "Good to know"
    ],
    "open": "Get the app",
    "menu": "Menu",
    "eyebrow": "FOR THE JOURNEY. AND THE WAY HOME.",
    "title": "Find your way.<br>A little more<br><em>Waybi.</em>",
    "lead": "Turn-by-turn guidance, useful road reminders, and a cosy room with Waybi, Clover and Sett. A little company, wherever your next journey takes you.",
    "start": "Get Waybi for iPhone",
    "discover": "Meet the friends",
    "note": "For iPhone. Coming soon to the App Store.",
    "sticker": "Small bird.<br>Big adventure.",
    "preview": "Interface preview · sample route",
    "lane": "USE LANE",
    "turn": "Turn left onto Queen Street",
    "camera": "Safety camera ahead",
    "destination": "Waybi Cafe",
    "minutes": "6 min",
    "distance": "2.4 km",
    "cameras": "2",
    "labels": [
      "To go",
      "Distance",
      "Cameras"
    ],
    "chips": [
      "Voice ✓",
      "Lanes ✓",
      "Overview"
    ],
    "promises": [
      "Routes beyond New Zealand",
      "NZ safety-camera data",
      "Waybi & Friends"
    ],
    "featuresLabel": "A NICER WAY TO GET THERE",
    "featuresTitle": "Follow the road.<br>Enjoy the journey.",
    "featuresLead": "Clear turns, a map that keeps up, and easier ways to start your next trip.",
    "features": [
      [
        "A map that moves with you.",
        "Waybi Map follows your direction, opens up at speed and moves closer for turns. See recommended lanes when your navigation provider supplies them."
      ],
      [
        "Found a place? Bring it along.",
        "Open a Waybi navigation link or pass an address through iPhone Shortcuts. Review the route, then choose when to start."
      ],
      [
        "Keep the journeys that matter.",
        "See your route, distance and time after arrival. Saved places and trip history make the familiar journeys easier to find again."
      ]
    ],
    "safetyLabel": "A LITTLE MORE AWARE OF WHAT’S AHEAD",
    "safetyTitle": "Useful reminders.<br>In plain sight.",
    "safetyLead": "See reported incidents, roadworks and closures along your route where data is available. In New Zealand, official fixed-camera reminders sit directly below your next turn.",
    "safetyItems": [
      "A clear camera reminder beneath the turn card",
      "Distinct symbols for community road reports",
      "English or Chinese, with Google Maps or Waybi Map"
    ],
    "demo": "Camera · 300 m",
    "demoRoad": "Queen Street · sample alert",
    "source": "Explore the NZTA camera source",
    "sourceNote": "Official fixed-camera coverage is currently New Zealand. Reports, traffic and road information vary by provider and location.",
    "friendsLabel": "A LITTLE WORLD TO COME HOME TO",
    "friendsTitle": "Waybi & Friends.<br>Make yourself at home.",
    "friendsLead": "Clover finds the sunny window. Sett trots across the rug. Waybi gets ready for a little adventure. They have their own quiet rhythm, even while you are away.",
    "friendsSteps": [
      [
        "A room with a life of its own",
        "Little footsteps, sleepy afternoons and familiar faces. Come back and see what they are up to."
      ],
      [
        "Pack a tiny adventure",
        "Bring a camera, lunch, an umbrella or Sett’s ball. One thing, two things, or an empty bag — it is your choice."
      ],
      [
        "A story to keep",
        "Send Waybi on a short companion trip. Collect illustrated letters, maps, scrolls and little treats, then tap each keepsake to see it up close."
      ]
    ],
    "friendsEntry": "Find it in Me → Waybi & Friends.",
    "friendsCaption": "Inside the Waybi iPhone app",
    "friendsButton": "Meet your travelling companions",
    "characterLabels": [
      "THE CURIOUS KIWI",
      "THE WINDOW WATCHER",
      "YOUR CHEERFUL COMPANION"
    ],
    "characterNotes": [
      "A curious kiwi bird with a little backpack and always another journey in mind.",
      "At the window, on the sofa, or pretending not to notice you.",
      "A few tiny footsteps, a favourite ball, and a very warm welcome home."
    ],
    "faqLabel": "BEFORE YOU SET OFF",
    "faqTitle": "Good to know.",
    "faqs": [
      [
        "Where can I navigate?",
        "Waybi accepts destinations worldwide. Routes, place search, traffic, transit and lane information depend on the selected provider and local coverage. Official camera and speed-limit sources currently cover New Zealand; missing traffic or speed-limit data is shown as unavailable."
      ],
      [
        "Can I try it without an account?",
        "Yes. Explore places and routes, and visit Waybi & Friends as a guest. Sign in when you want the account features, saved places and trip history."
      ],
      [
        "Which maps can I use?",
        "Choose Google Maps or the independent Waybi Map. Both use the same Waybi navigation interface and road reminders. Map attribution stays visible."
      ],
      [
        "Can I open an address from my calendar?",
        "Use a Waybi navigation link or the Navigate with Waybi action in iPhone Shortcuts to pass an address. Google Calendar controls its own Open with list; Waybi cannot add itself to that list."
      ],
      [
        "Do my drives send Waybi on a companion trip?",
        "The companion room currently has its own short trips, postcards and souvenirs. A real drive does not automatically create a companion souvenir."
      ]
    ],
    "footer": "A clearer journey. A little company along the way.",
    "links": [
      "Get the app",
      "Dashboard",
      "Contact"
    ],
    "disclaimer": "Navigation and road information are driving aids. Follow local road signs, laws and current conditions."
  },
  "zh": {
    "skip": "跳转到正文",
    "nav": [
      "导航体验",
      "沿途提醒",
      "Waybi & Friends",
      "出发前了解"
    ],
    "open": "获取 App",
    "menu": "菜单",
    "eyebrow": "出发时陪着你，回家后等着你。",
    "title": "出发有方向，<br><em>回家有伙伴。</em>",
    "lead": "清楚的转向提示，有用的沿途提醒，还有 Waybi、Clover 和 Sett 生活的小屋。下一程去哪里，都多一点陪伴。",
    "start": "获取 iPhone 版 Waybi",
    "discover": "认识小伙伴",
    "note": "iPhone 版，即将登陆 App Store。",
    "sticker": "小小 Waybi，<br>大大冒险。",
    "preview": "界面示意 · 示例路线",
    "lane": "推荐车道",
    "turn": "左转，驶向 Queen Street",
    "camera": "前方安全摄像头",
    "destination": "Waybi 咖啡馆",
    "minutes": "6 分钟",
    "distance": "2.4 公里",
    "cameras": "2",
    "labels": [
      "剩余时间",
      "剩余距离",
      "沿途摄像头"
    ],
    "chips": [
      "语音 ✓",
      "车道 ✓",
      "路线总览"
    ],
    "promises": [
      "目的地不止新西兰",
      "NZ 官方摄像头数据",
      "Waybi & Friends"
    ],
    "featuresLabel": "让每一程，都舒服一点",
    "featuresTitle": "跟着前方，<br>从容出发。",
    "featuresLead": "清楚的转弯提示，跟得上你的地图，以及更方便的目的地入口。",
    "features": [
      [
        "地图，跟着你向前。",
        "自研地图随行驶方向转动，车速快时看得更远，接近转弯时看得更清楚。导航服务有车道数据时，也会显示推荐车道。"
      ],
      [
        "看到想去的地方，带过来。",
        "通过 Waybi 导航链接或 iPhone 快捷指令传入地址，先看路线，再决定什么时候出发。"
      ],
      [
        "走过的路，留得下来。",
        "到达后回顾路线、距离和用时。收藏地点与行程记录，让熟悉的旅程更容易再找到。"
      ]
    ],
    "safetyLabel": "多看清一点前方",
    "safetyTitle": "有用的提醒，<br>放在眼前。",
    "safetyLead": "有数据的地区可以看到沿途上报的事故、施工和封路。在新西兰，官方固定摄像头提醒就放在下一步转向卡片下方。",
    "safetyItems": [
      "转向卡片下方，醒目的摄像头提示",
      "社区上报使用各自清楚的事件图标",
      "中英文界面，Google Maps 或自研地图"
    ],
    "demo": "摄像头 · 300 米",
    "demoRoad": "Queen Street · 示例提醒",
    "source": "查看 NZTA 摄像头来源",
    "sourceNote": "官方固定摄像头目前覆盖新西兰。社区上报、交通和道路信息随地区及数据提供方而不同。",
    "friendsLabel": "有个小世界，在等你回家",
    "friendsTitle": "Waybi & Friends。<br>进来坐坐。",
    "friendsLead": "Clover 喜欢有阳光的窗边，Sett 会在地毯上小跑，Waybi 正准备下一次小冒险。你不在的时候，他们也有自己的生活节奏。",
    "friendsSteps": [
      [
        "一间会继续生活的小屋",
        "小小的脚步，懒洋洋的午后，熟悉的几个身影。回来看看，他们正在做什么。"
      ],
      [
        "打包一段小冒险",
        "相机、午餐、雨伞，或 Sett 的球。带一件、两件，或者轻装出门，都可以。"
      ],
      [
        "带回一个小故事",
        "让 Waybi 去一趟短短的伙伴旅行。收集有插画的信件、地图、卷轴和小点心，点开纪念品，还能放大查看。"
      ]
    ],
    "friendsEntry": "从 Me（我）→ Waybi & Friends 进入。",
    "friendsCaption": "Waybi iPhone App 内的小屋",
    "friendsButton": "认识你的旅途小伙伴",
    "characterLabels": [
      "爱出发的几维鸟",
      "喜欢窗边的好奇猫咪",
      "总是开心的小伙伴"
    ],
    "characterNotes": [
      "Waybi 是一只几维鸟（kiwi bird）。一个背包，一点好奇心，心里总惦记着下一段小旅行。",
      "待在窗台、窝在沙发，或假装没有注意到你回来。",
      "小小的脚步，一颗最爱的球，回家时总有个热情的迎接。"
    ],
    "faqLabel": "出发之前",
    "faqTitle": "你可能想了解。",
    "faqs": [
      [
        "可以在哪些地方导航？",
        "Waybi 可以接收世界各地的目的地。路线、地点、交通、公交与车道信息取决于所选服务和当地覆盖。官方摄像头及限速来源目前覆盖新西兰；缺失的交通或限速数据会显示为不可用。"
      ],
      [
        "不注册也能使用吗？",
        "可以。游客也能探索地点和路线、进入 Waybi & Friends。需要账户功能、保存地点或查看行程记录时，再登录。"
      ],
      [
        "可以用哪种地图？",
        "可以选择 Google Maps 或 Waybi 自研地图，两者共用 Waybi 的导航界面与沿途提醒，并保留必要的地图署名。"
      ],
      [
        "能从日历打开一个地址吗？",
        "可以通过 Waybi 导航链接，或 iPhone 快捷指令里的 Navigate with Waybi 动作传入地址。Google Calendar 的 Open with 列表由它自己控制，Waybi 无法自行加入。"
      ],
      [
        "真实导航会让伙伴自动带回纪念品吗？",
        "目前小屋有自己的短途旅行、明信片和纪念品循环。完成一次真实导航，还不会自动生成伙伴纪念品。"
      ]
    ],
    "footer": "看清前方，多一点 Waybi 陪伴。",
    "links": [
      "获取 App",
      "个人面板",
      "联系我们"
    ],
    "disclaimer": "导航和道路信息仅作为驾驶辅助。请遵守当地道路标志、法规和实际路况。"
  }
};

let menuListeners = new AbortController();
function render() {
  menuListeners.abort();
  menuListeners = new AbortController();
  const c = copy[language as keyof typeof copy];
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.title = language === 'zh'
    ? 'Waybi｜导航、沿途提醒与 Waybi & Friends'
    : 'Waybi — Navigation, Road Awareness & Friends';
  document.querySelector('meta[name="description"]')?.setAttribute(
    'content',
    language === 'zh'
      ? 'Waybi 为每一程提供路线规划、随方向跟随的导航和沿途提醒，还有 Waybi & Friends 伙伴小屋。官方摄像头目前覆盖新西兰。'
      : 'Waybi brings navigation, road awareness and Waybi & Friends together on iPhone. Plan your next route, then visit a cosy companion room. Official camera coverage is New Zealand.'
  );
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', '#F8FBEF');
  document.body.dataset.surface = 'marketing';
  document.body.innerHTML = `
    <a href="#main" class="skip-link">${c.skip}</a>
    <div class="site">
      <header class="header">
        <a class="brand" href="/" aria-label="Waybi">${logo}</a>
        <nav class="nav" id="site-nav" aria-label="${language === 'zh' ? '主导航' : 'Main navigation'}">
          ${c.nav.map((label, i) => `<a href="#${['experience', 'awareness', 'friends', 'faq'][i]}">${label}</a>`).join('')}
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
            <div class="hero-actions"><a class="button" href="#download">${c.start}<span aria-hidden="true">↗</span></a><a class="text-link" href="#friends">${c.discover}<span aria-hidden="true">↓</span></a></div>
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
            <div class="friends-steps">${c.friendsSteps.map(([title, description], i) => `<article><span aria-hidden="true">0${i+1}</span><div><h3>${title}</h3><p>${description}</p></div></article>`).join('')}</div>
            <p class="friends-entry">${c.friendsEntry}</p><a class="text-link" href="#download">${c.friendsButton}<span aria-hidden="true">↗</span></a>
          </div>
          <figure class="friends-preview"><span class="friends-preview-tag">WAYBI & FRIENDS</span><img src="/previews/waybi-friends.png" alt="${language === 'zh' ? 'Waybi、Clover 和 Sett 在 App 中的小屋生活' : 'Waybi, Clover and Sett in their companion room'}" width="446" height="960" loading="lazy" /><figcaption>${c.friendsCaption}</figcaption></figure>
          <div class="friend-introductions">${['Waybi','Clover','Sett'].map((name,i) => `<article class="friend-introduction friend-${name.toLowerCase()}"><div class="friend-portrait"><img src="/brand/${name.toLowerCase()}.png" alt="${name}" width="130" height="130" loading="lazy" /></div><span>${c.characterLabels[i]}</span><h3>${name}</h3><p>${c.characterNotes[i]}</p></article>`).join('')}</div>
        </section>
        <section class="seo-guides" aria-labelledby="seo-guides-title">
          <div class="section-heading"><div><span class="eyebrow">${language === 'zh' ? '深入了解 WAYBI' : 'EXPLORE WAYBI'}</span><h2 id="seo-guides-title">${language === 'zh' ? '不只是一个漂亮的地图。' : 'More than a pretty map.'}</h2></div><p>${language === 'zh' ? '看看 Waybi 如何处理路线、固定摄像头与每天重复走的通勤路线。' : 'See how Waybi handles routes, fixed safety-camera awareness and the journeys you repeat every day.'}</p></div>
          <div class="seo-guide-grid">
            <a class="seo-guide-card" href="/new-zealand-navigation/"><span>${language === 'zh' ? '导航' : 'NAVIGATION'}</span><h3>${language === 'zh' ? '新西兰路线规划' : 'New Zealand navigation'}</h3><p>${language === 'zh' ? '路线选择、交通信息、停车、多地图提供方与中英文导航。' : 'Route choices, traffic context, parking, multiple map providers and bilingual guidance.'}</p><b>${language === 'zh' ? '了解导航 →' : 'Explore navigation →'}</b></a>
            <a class="seo-guide-card" href="/safety-camera-navigation/"><span>${language === 'zh' ? '道路提醒' : 'ROAD AWARENESS'}</span><h3>${language === 'zh' ? 'NZTA 固定安全摄像头提醒' : 'NZ safety-camera guidance'}</h3><p>${language === 'zh' ? '了解官方数据来源、路线匹配、自动更新与明确的覆盖范围。' : 'How official fixed-camera data is validated, matched to your route and kept current.'}</p><b>${language === 'zh' ? '了解摄像头提醒 →' : 'How camera reminders work →'}</b></a>
            <a class="seo-guide-card" href="/route-watch/"><span>WAYBI PLUS</span><h3>Route Watch</h3><p>${language === 'zh' ? '用保存的通勤路线走廊检查 NZTA 道路事件，而不是全天持续上传实时 GPS。' : 'Monitor a saved commute corridor against official NZTA road events without continuously uploading live GPS.'}</p><b>${language === 'zh' ? '了解 Route Watch →' : 'Explore Route Watch →'}</b></a>
          </div>
        </section>
        <section class="faq" id="faq"><div><span class="eyebrow">${c.faqLabel}</span><h2>${c.faqTitle}</h2></div><div>${c.faqs.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join('')}</div></section>
        <section class="download cta" id="download" aria-labelledby="download-title">
          <div><span class="eyebrow">${language === 'zh' ? 'WAYBI · IPHONE 版' : 'WAYBI FOR IPHONE'}</span>
            <h2 id="download-title">${language === 'zh' ? '把 Waybi，<br>带上你的下一程。' : 'Your next adventure.<br>With Waybi along.'}</h2>
            <p>${language === 'zh' ? '熟悉的转向提示，贴心的道路提醒，还有等你回家的小伙伴。' : 'Clear turns, thoughtful road reminders, and a little world to come home to.'}</p>
            ${appStoreUrl ? `<a class="button lime store-button" href="${appStoreUrl}" target="_blank" rel="noopener noreferrer">${language === 'zh' ? '在 App Store 下载' : 'Download on the App Store'} <span aria-hidden="true">↗</span></a>` : `<button class="button lime store-button" type="button" disabled>${language === 'zh' ? 'App Store · 即将上线' : 'Coming soon on the App Store'}</button>`}
            <small class="release-note">${appStoreUrl ? (language === 'zh' ? '在 iPhone 上开启你的下一程。' : 'Start your next journey on iPhone.') : (language === 'zh' ? '目前尚未上架。发布后，这里将直接通往 App Store。' : 'Not listed yet. This will take you straight to the App Store when Waybi launches.')}</small>
          </div>${bird}
        </section>

      </main>
      <footer class="footer"><a class="brand" href="/">${logo}</a><div class="footer-links">${c.links.map((label, i) => `<a href="${['#download', '/dashboard', 'https://github.com/yaohuangguan/Waybi/issues'][i]}">${label}</a>`).join('')}<a href="/new-zealand-navigation/">${language === 'zh' ? '导航指南' : 'Navigation guide'}</a><a href="/safety-camera-navigation/">${language === 'zh' ? '摄像头提醒' : 'Safety cameras'}</a><a href="/route-watch/">Route Watch</a><a href="/zh/" lang="zh-CN">中文</a></div><p>${c.footer}<br>${c.disclaimer}</p><small>© ${new Date().getFullYear()} Waybi</small></footer>
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
