/**
 * Generates crawlable About Us pages for Waybi's two site languages.
 * Run: node scripts/generate-about-pages.mjs
 * Do not inject external content into these literal translations.
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../apps/web/public');

const translations = {
  en: {
    lang: 'en-NZ',
    url: '/about/',
    alt: '/zh/about/',
    title: 'About Waybi — Why We Built a Different Kind of Map',
    description: 'Why build another map? Waybi began with a bus-lane fine in New Zealand and a belief in more useful road reminders and a little company along the way.',
    home: 'Home', whyNav: 'Our story', ideasNav: 'Our thinking', friendsNav: 'The companions', altLabel: '中文',
    eyebrow: 'OUR STORY · WHY WAYBI',
    h1: 'Maps get us there.<br><em>What about the journey?</em>',
    lead: 'Google Maps is genuinely useful. This is not a story about a bad map. It is a story about the little things we still wished our map could do — and the small world we wanted to bring along for the ride.',
    heroPrimary: 'How it started', heroSecondary: 'Meet Waybi & Friends',
    stickerOne: 'One wrong lane.', stickerOneSub: 'One very expensive lesson.',
    stickerTwo: 'A different direction.', stickerTwoSub: 'Not a different destination.',
    openerEyebrow: 'THE SMALL MOMENT',
    openerTitle: 'A fine. A question. A beginning.',
    openerQuote: '“I wish my map had told me that before I got here.”',
    opener: [
      'It started with an ordinary drive in New Zealand. One of us was still learning the local roads, missed the significance of a bus lane, and ended up with a fine. It was frustrating — and, looking back, a little funny. But it raised a genuine question.',
      'Our map knew the destination and the route. <strong>Could it also help us notice the things that matter along the way?</strong> A camera coming up. A bus lane with particular operating hours. A road closure that changes the next decision.',
      'We did not need another app to shout instructions at us. We wanted one that could make the unfamiliar feel a little less unfamiliar. That curiosity became Waybi.',
    ],
    pillarsEyebrow: 'WHY WE ARE MAKING THIS',
    pillarsTitle: 'Three things worth doing differently.',
    pillarsLead: 'Not a checklist of features Google forgot. Three beliefs about what a journey can feel like.',
    pillars: [
      ['01','◉','Fewer surprises on the road.',
        'In a new city, small local rules can be easy to miss. We are building clearer reminders for things such as fixed safety cameras, bus-lane rules and reported road events where dependable data exists. Helpful context, not a promise that every road is covered.'],
      ['02','↗','Room for another kind of map.',
        'A great market leader does not mean everyone wants the same experience. Waze is a reminder that different navigation habits matter. Some people want more road awareness, others want a gentler interface. We are building for those preferences, not trying to win every feature comparison.'],
      ['03','♡','A companion, not just a blue dot.',
        'A route ends when you arrive. A good journey can stay with you. Meet Waybi, Clover and Sett — a small, character-filled world with tiny adventures and keepsakes inspired by your travels. Your map helps with the drive; your companions make it feel personal.'],
    ],
    perspectiveEyebrow:'NOT GOOGLE VERSUS WAYBI',
    perspectiveTitle:'We are not trying to prove Google Maps wrong.',
    perspective: [
      'Google Maps is a remarkably capable product, and we respect the work behind it. It solves an enormous problem for millions of people. We use it ourselves. We are not claiming that Waybi has better directions, more places or more complete coverage everywhere.',
      '<strong>We just believe there is still room to care about different things.</strong> A map can be excellent at finding the fastest route and still leave people wanting more context, reassurance, personality or delight. Waybi starts from that gap.',
    ],
    quote:'The world does not need every map to feel the same. Sometimes what you need is not a new road — just a new way to travel it.',
    quoteSign:'The thinking behind Waybi',
    friendsEyebrow:'A LITTLE COMPANY',
    friendsTitle:'Meet the friends who travel with you.',
    friends: [
      'Waybi is our curious little kiwi bird. Clover prefers a sunny spot by the window. Sett is always ready for another walk. Together, they have a life beyond the next turn.',
      'That part is inspired by the cosy feeling of games where a little companion goes on adventures and comes back with stories. We wanted a similar sense of warmth in a travel app — without making you play a game while driving.',
      'Complete a journey, collect a small country-themed keepsake, and visit their little world when you are parked or back home. Getting somewhere is practical. Feeling connected to the journey is something else.',
    ],
    principlesEyebrow:'WHAT WE BELIEVE',
    principlesTitle:'Some promises to keep ourselves honest.',
    principles: [
      ['A helpful alert is not certainty.',
       'Camera, lane and traffic coverage depends on local data. A missing warning never means a road restriction does not exist. Road signs and local laws always come first.'],
      ['The road has your attention.',
       'Driving information should be quick to understand. Character interactions and souvenirs belong outside moments when you need to focus on the road.'],
      ['Start in New Zealand. Stay curious about everywhere.',
       'New Zealand is where our road-awareness work began. We are building a navigation experience for journeys beyond NZ, with location-specific features growing only where reliable sources allow.'],
    ],
    faqEyebrow:'GOOD QUESTIONS',
    faqTitle:'A few things you might ask.',
    faqs: [
      ['Why build a map when Google Maps exists?',
       'Because people have different needs. We admire Google Maps, but wanted more attention to local road reminders and a distinctive sense of companionship. That is a reason to build something different, not to claim everything else is worse.'],
      ['Will Waybi warn me about every camera or bus lane?',
       'No. Coverage is not universal, data changes and road signs take precedence. NZ fixed-camera reminders are one of our starting points; lane and incident information varies by location and confidence. Waybi is a driving aid, never a substitute for the law or your judgement.'],
      ['Is Waybi only for New Zealand?',
       'No. Waybi aims to support journeys worldwide, while independent map detail, routing, road events and special lane information vary by region and provider. We are building outward from New Zealand rather than pretending our coverage is equally deep everywhere.'],
      ['Do the characters distract from driving?',
       'They should not. The navigation screen prioritises guidance and road awareness. The cosy companion experience — exploration, collecting and visiting their home — is designed for before or after the drive.'],
    ],
    ctaEyebrow:'THE JOURNEY IS JUST BEGINNING',
    ctaTitle:'Find your way. Bring a little Waybi along.',
    ctaLead:'A clearer look at the road ahead, and a few friends waiting when you arrive.',
    ctaAction:'Explore Waybi',
    footDisclaimer:'Waybi provides driving aids, not legal advice. Road rules, signs and conditions take priority. Google Maps and Waze are products of their respective owners; Waybi is not affiliated with them.',
    footCompany:'Made with curiosity in New Zealand.',
  },
  zh: {
    lang:'zh-CN',
    url:'/zh/about/',
    alt:'/about/',
    title:'关于 Waybi｜为什么我们想做一张不一样的地图',
    description:'我们为什么要做 Waybi？从一次新西兰公交车道罚单说起，聊聊更贴心的道路提醒、地图产品的不同选择，以及 Waybi、Clover、Sett 带来的陪伴式出行。',
    home:'首页', whyNav:'我们的故事', ideasNav:'我们的想法', friendsNav:'旅途伙伴', altLabel:'EN',
    eyebrow:'关于我们 · 为什么做 WAYBI',
    h1:'地图告诉你怎么走。<br><em>那一路上的感受呢？</em>',
    lead:'Google Maps 其实很好用。我们做 Waybi，不是因为它不够好，而是因为一次次出行中，我们总觉得还有一些重要的小事可以做得更贴心——还有一点温暖，能陪着我们一起上路。',
    heroPrimary:'故事从这里开始', heroSecondary:'认识 Waybi 和伙伴们',
    stickerOne:'走错一条车道。', stickerOneSub:'换来一堂不便宜的课。',
    stickerTwo:'不一定要换条路。', stickerTwoSub:'可以换一种出行方式。',
    openerEyebrow:'从一件小事开始',
    openerTitle:'一张罚单，和一个念头。',
    openerQuote:'“要是地图能提前提醒我一下就好了。”',
    opener: [
      '刚来到新西兰时，面对不熟悉的道路规则，很多小细节真的很容易忽略。我们中的一个人就因为公交车道吃过罚单。现在回头看有点好笑，但当时的感觉，恐怕不少刚来的司机都懂。',
      '那天我们想到：地图已经知道我们要去哪里、该走哪条路。<strong>可它能不能也提醒我们，路上有哪些值得提前注意的事？</strong> 比如前方的固定摄像头、只在特定时段生效的公交车道，或者突然出现的施工与封路。',
      '我们并不是想再做一个不断催促司机的导航 App。我们想让陌生的城市不那么陌生，让每一程少一点措手不及。Waybi 就从这个念头开始了。',
    ],
    pillarsEyebrow:'我们想做得不一样的三件事',
    pillarsTitle:'地图不只是把人送到目的地。',
    pillarsLead:'不是列一张 Google 没做什么的清单，而是我们对出行体验的三个坚持。',
    pillars: [
      ['01','◉','前方的事，提前知道。',
       '对刚到一座城市的人来说，道路上的小规则也可能带来大麻烦。我们希望用更直观的方式提醒固定摄像头、公交车道时段、道路事件等信息——前提是当地有足够可靠的数据。这是多一分参考，不是保证零罚单。'],
      ['02','↗','地图可以有不同的答案。',
       'Google Maps 很强大，但强大不等于所有人都偏爱同一种体验。Waze 的存在就说明，不同的人会选择不同的导航方式。有人更在意道路提醒，有人更喜欢轻松的界面。Waybi 不想在每个功能上都争第一，而是认真服务喜欢这种体验的人。'],
      ['03','♡','从工具，变成旅途伙伴。',
       '一般导航在到达时就结束了，我们希望美好的体验能继续。Waybi、Clover 和 Sett 有自己的小世界、小冒险，还有旅行带回的纪念品。开车时地图带路，停下来以后还有伙伴陪着你。'],
    ],
    perspectiveEyebrow:'不是 GOOGLE MAPS VS. WAYBI',
    perspectiveTitle:'我们真的没有觉得 Google Maps 不好。',
    perspective: [
      'Google Maps 是非常出色的产品，帮助无数人每天出行。我们自己也使用它，更不会说 Waybi 在全球路线、地点数量或实时交通上已经超过 Google。',
      '<strong>但一款成熟产品解决了大多数问题，不代表所有人的需求都被满足了。</strong> 最快的路线之外，还有对当地规则的了解、第一次开车上路的不安、对旅途的期待，以及让人愿意打开 App 的那一点个性。',
      '我们想把这些被忽略的小感受，认真地做进地图里。',
    ],
    quote:'这个世界不需要所有地图都长得一样。有时候我们缺的不是一条新路，而是一种新的出行感受。',
    quoteSign:'Waybi 想做的事',
    friendsEyebrow:'旅途中，不必只有自己',
    friendsTitle:'Waybi、Clover、Sett，一直都在。',
    friends: [
      'Waybi 是爱冒险的几维鸟；Clover 喜欢待在阳光照进来的窗边；Sett 是随时准备出门的小伙伴。对我们来说，他们不是导航画面上贴几个表情就算完成的吉祥物。',
      '我们很喜欢《旅行青蛙》那种感受：一个小生命有自己的生活，偶尔出发，带着小故事回来。我们希望把相似的温柔和期待感带进出行产品，而不是让司机开车时还要玩游戏。',
      '完成一段行程，收下一份国家主题的小纪念品；停车或回家后，看看伙伴们在做什么。导航解决“怎么到达”，陪伴则让“到达”之外也有些值得记住的东西。',
    ],
    principlesEyebrow:'我们坚持的原则',
    principlesTitle:'温柔的体验，也要对现实负责。',
    principles: [
      ['提醒是帮助，不是绝对保证。',
       '摄像头、公交车道和路况依赖当地数据。没出现提醒，不代表某条规则不存在；现场路牌、法律和实际路况永远优先。'],
      ['开车时，把注意力留给道路。',
       '导航信息应该直观、简洁。角色互动、探险和纪念品属于出发前、停车后或到家时，而不是需要专心驾驶的时刻。'],
      ['从新西兰开始，但不止于新西兰。',
       '新西兰是我们首先深耕道路提醒的地方。Waybi 的目标是陪你去世界各地，但每个地区的数据完整度不同，我们会在有可靠来源时再逐步扩大能力。'],
    ],
    faqEyebrow:'你可能还想问',
    faqTitle:'关于 Waybi 的几个问题。',
    faqs: [
      ['都已经有 Google Maps 了，为什么还要做地图？',
       '因为地图不仅是路线算法，也是一种体验。我们尊重 Google Maps 的成熟能力，但想把更贴近当地道路规则的提醒、伙伴角色和旅途纪念带进同一个产品。不是要证明别人不好，而是想做出不同的选择。'],
      ['Waybi 能提醒所有摄像头和公交车道吗？',
       '不能。数据覆盖并不完整，而且道路规则会变化。Waybi 目前重点建设新西兰的官方固定摄像头等数据；公交车道、道路事件等能力会因城市与数据可信度而异。导航仅是辅助，最终请以现场标志、法规和实际路况为准。'],
      ['Waybi 只能在新西兰用吗？',
       '不是。Waybi 希望支持全球出行；但是各地地图、搜索、路线、实时交通及特殊车道的数据完整度并不一致。我们选择先把新西兰做好，再谨慎拓展，不会假装每个国家的覆盖都一样。'],
      ['有小伙伴会不会影响开车注意力？',
       '我们不希望这样。驾驶时以路线、转向和道路提醒为主；小伙伴的日常、探险和纪念品适合在出发前、停车后或回到家时体验。'],
    ],
    ctaEyebrow:'旅途才刚刚开始',
    ctaTitle:'方向交给地图。<br>把一点陪伴带上路。',
    ctaLead:'清楚地看见前方，也期待到达以后的那一点小惊喜。',
    ctaAction:'探索 Waybi',
    footDisclaimer:'Waybi 是驾驶辅助工具，不能代替现场路牌、当地法规和实时路况。Google Maps 与 Waze 属于各自权利人，Waybi 与其没有隶属关系。',
    footCompany:'从新西兰出发，带着一点好奇心。',
  },
};

function esc(value) {
  return String(value).replaceAll('&','&amp;').replaceAll('<','&lt;')
    .replaceAll('>','&gt;').replaceAll('"','&quot;');
}
function renderPage(c) {
  const localized = c.lang.startsWith('zh');
  const rootHome = localized ? '/zh/' : '/';
  const pageUrl = 'https://waybi.co' + c.url;
  const altUrl = 'https://waybi.co' + c.alt;
  const faqSchema = c.faqs.map(([q, a]) => ({
    '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a },
  }));
  const schema = {
    '@context': 'https://schema.org',
    '@graph': [
      { '@type': 'AboutPage', '@id': pageUrl + '#about', url: pageUrl,
        name: c.title, description: c.description,
        inLanguage: c.lang, mainEntity: {'@id':'https://waybi.co/#organization'},
        isPartOf:{'@id':'https://waybi.co/#website'} },
      { '@type':'FAQPage', mainEntity:faqSchema },
    ],
  };
  return `<!doctype html>
<html lang="${c.lang}">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
  <meta name="theme-color" content="#F8FBEF"/>
  <title>${esc(c.title)}</title>
  <meta name="description" content="${esc(c.description)}"/>
  <meta name="robots" content="index,follow,max-image-preview:large"/>
  <link rel="canonical" href="${pageUrl}"/>
  <link rel="alternate" hreflang="en-NZ" href="https://waybi.co/about/"/>
  <link rel="alternate" hreflang="zh-CN" href="https://waybi.co/zh/about/"/>
  <link rel="alternate" hreflang="x-default" href="https://waybi.co/about/"/>
  <link rel="icon" type="image/png" href="/brand/waybi-icon.png"/>
  <link rel="preconnect" href="https://fonts.googleapis.com"/>
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
  <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@400;500;600;700&family=Noto+Sans+SC:wght@400;500;600;700&display=swap" rel="stylesheet"/>
  <link rel="stylesheet" href="/about.css"/>
  <meta property="og:type" content="website"/>
  <meta property="og:site_name" content="Waybi"/>
  <meta property="og:locale" content="${localized?'zh_CN':'en_NZ'}"/>
  <meta property="og:title" content="${esc(c.title)}"/>
  <meta property="og:description" content="${esc(c.description)}"/>
  <meta property="og:url" content="${pageUrl}"/>
  <meta property="og:image" content="https://waybi.co/og-waybi.png"/>
  <meta name="twitter:card" content="summary_large_image"/>
  <meta name="twitter:title" content="${esc(c.title)}"/>
  <meta name="twitter:description" content="${esc(c.description)}"/>
  <script type="application/ld+json">${JSON.stringify(schema)}</script>
</head>
<body>
  <a class="about-skip" href="#main">${localized?'跳转到正文':'Skip to content'}</a>
  <div class="about-wrap">
    <header class="about-nav">
      <a class="brand" href="${rootHome}" aria-label="Waybi"><img src="/brand/waybi-lockup.svg" alt="Waybi" width="155" height="40"/></a>
      <nav class="about-nav-links" aria-label="${localized?'主导航':'Main navigation'}">
        <a class="nav-hide-mobile" href="#story">${esc(c.whyNav)}</a>
        <a class="nav-hide-mobile" href="#why">${esc(c.ideasNav)}</a>
        <a class="nav-hide-mobile" href="#friends">${esc(c.friendsNav)}</a>
        <a href="${rootHome}">${esc(c.home)}</a>
        <a class="about-lang" href="${c.alt}" hreflang="${localized?'en-NZ':'zh-CN'}" aria-label="${localized?'Switch to English':'切换到中文'}">${c.altLabel}</a>
      </nav>
    </header>
    <main id="main">
      <section class="about-hero" aria-labelledby="hero-title">
        <div>
          <span class="about-eyebrow">${esc(c.eyebrow)}</span>
          <h1 id="hero-title">${c.h1}</h1>
          <p class="about-lead">${esc(c.lead)}</p>
          <div class="about-hero-actions">
            <a class="about-pill" href="#story">${esc(c.heroPrimary)} <span aria-hidden="true">↘</span></a>
            <a class="about-underlink" href="#friends">${esc(c.heroSecondary)} ↗</a>
          </div>
        </div>
        <div class="about-hero-art" aria-label="Waybi, the curious kiwi bird">
          <svg class="about-route" viewBox="0 0 500 490" fill="none" role="presentation" aria-hidden="true">
            <path d="M10 361 C95 355 80 178 173 178 S260 300 340 251 429 82 494 101" stroke="#84a868" stroke-width="5" stroke-linecap="round" stroke-dasharray="8 15"/>
            <circle cx="10" cy="361" r="8" fill="#84a868"/><circle cx="492" cy="101" r="9" fill="#476b35"/>
          </svg>
          <img class="big-waybi" src="/brand/waybi.png" alt="Waybi the kiwi bird" width="290" height="290" decoding="async"/>
          <div class="about-sticker left">${esc(c.stickerOne)}<span>${esc(c.stickerOneSub)}</span></div>
          <div class="about-sticker right">${esc(c.stickerTwo)}<span>${esc(c.stickerTwoSub)}</span></div>
        </div>
      </section>

      <section class="about-opener about-rule" id="story">
        <div><span class="about-eyebrow">${esc(c.openerEyebrow)}</span><h2>${esc(c.openerTitle)}</h2></div>
        <div class="about-opener-copy">
          <blockquote class="about-quote">${esc(c.openerQuote)}</blockquote>
          ${c.opener.map(x=>`<p>${x}</p>`).join('')}
        </div>
      </section>

      <section class="about-section" id="why">
        <div class="about-section-header">
          <div><span class="about-eyebrow">${esc(c.pillarsEyebrow)}</span><h2>${esc(c.pillarsTitle)}</h2></div>
          <p>${esc(c.pillarsLead)}</p>
        </div>
        <div class="about-cards">
          ${c.pillars.map(([n, icon, title, desc])=>`<article class="about-card"><span class="about-card-number">${n} / 03</span><span class="about-card-mark" aria-hidden="true">${icon}</span><h3>${esc(title)}</h3><p>${esc(desc)}</p></article>`).join('')}
        </div>
      </section>

      <section class="about-perspective" id="perspective">
        <div><span class="about-eyebrow">${esc(c.perspectiveEyebrow)}</span><h2>${esc(c.perspectiveTitle)}</h2>${c.perspective.map(x=>`<p>${x}</p>`).join('')}</div>
        <div class="about-perspective-mark"><blockquote>${esc(c.quote)}</blockquote><small>— ${esc(c.quoteSign)}</small></div>
      </section>

      <section class="about-friends" id="friends">
        <div><span class="about-eyebrow">${esc(c.friendsEyebrow)}</span><h2>${esc(c.friendsTitle)}</h2>${c.friends.map(x=>`<p>${esc(x)}</p>`).join('')}<a class="about-underlink" href="${localized?'/zh/waybi-friends/':'/waybi-friends/'}">${localized?'了解 Waybi & Friends':'Explore Waybi & Friends'} ↗</a></div>
        <div class="about-friends-visual" aria-label="Waybi, Clover and Sett">
          <img src="/brand/clover.png" alt="Clover the cat" loading="lazy" width="240" height="260"/>
          <img src="/brand/waybi.png" alt="Waybi the kiwi bird" loading="lazy" width="240" height="260"/>
          <img src="/brand/sett.png" alt="Sett the dog" loading="lazy" width="240" height="260"/>
        </div>
      </section>

      <section class="about-guidelines" id="principles">
        <span class="about-eyebrow">${esc(c.principlesEyebrow)}</span>
        <h2>${esc(c.principlesTitle)}</h2>
        <div class="about-guideline-list">${c.principles.map(([title,desc])=>`<div><strong>${esc(title)}</strong><p>${esc(desc)}</p></div>`).join('')}</div>
      </section>

      <section class="about-faq" id="questions">
        <div><span class="about-eyebrow">${esc(c.faqEyebrow)}</span><h2>${esc(c.faqTitle)}</h2></div>
        <div>${c.faqs.map(([q,a])=>`<details><summary>${esc(q)}</summary><p>${esc(a)}</p></details>`).join('')}</div>
      </section>

      <section class="about-cta">
        <div><span class="about-eyebrow">${esc(c.ctaEyebrow)}</span><h2>${c.ctaTitle}</h2><p>${esc(c.ctaLead)}</p><a class="about-pill" href="${rootHome}#download">${esc(c.ctaAction)} ↗</a></div>
        <img src="/brand/waybi.png" alt="" loading="lazy" width="150" height="160"/>
      </section>
    </main>
    <footer class="about-footer">
      <div><a href="${rootHome}">${esc(c.home)}</a><p>${esc(c.footCompany)}</p></div>
      <nav class="about-footer-links" aria-label="Footer">
        <a href="${localized?'/zh/new-zealand-navigation/':'/new-zealand-navigation/'}">${localized?'地图与导航':'Navigation'}</a>
        <a href="${localized?'/zh/safety-camera-navigation/':'/safety-camera-navigation/'}">${localized?'道路提醒':'Road awareness'}</a>
        <a href="${localized?'/zh/waybi-friends/':'/waybi-friends/'}">Waybi & Friends</a>
        <a href="https://github.com/yaohuangguan/Waybi/issues" target="_blank" rel="noopener noreferrer">${localized?'联系我们':'Contact'}</a>
      </nav>
      <small>© 2026 Waybi. ${esc(c.footDisclaimer)}</small>
    </footer>
  </div>
</body>
</html>`;
}
for (const c of Object.values(translations)) {
  const folder=path.join(root,c.url.replace(/^\//,''));
  await mkdir(folder,{recursive:true});
  await writeFile(path.join(folder,'index.html'),renderPage(c));
  console.log('Wrote', c.url);
}
