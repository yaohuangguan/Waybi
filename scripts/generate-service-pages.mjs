import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../apps/web/public/', import.meta.url));
const updated = '2026-10-30';
const email = 'support@waybi.co';
const appleTerms = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const documents = {
  en: {
    privacy: {
      title: 'Privacy policy',
      description: 'How Waybi uses location, account information and saved journeys, which providers receive requests, and how to manage or delete your data.',
      intro: 'This policy covers the Waybi app and waybi.co. Waybi uses information to provide navigation, account sync and the features you choose. Contact Waybi at '+email+' about privacy, access, corrections or deletion.',
      sections: [
        ['Location and navigation', 'With your permission, Waybi uses your location to show your position, calculate routes, follow a journey and provide navigation alerts. Active navigation can use background location and audio while the screen is locked. You can change these permissions in device Settings. Searching an address or calculating a route sends the relevant query, origin, destination, waypoints and sometimes nearby coordinates to the services needed to answer it. Location is sensitive even when no account is used.'],
        ['Accounts and saved information', 'An account is optional for basic map and navigation use. If you create one, we store your email, account identifier, password salt/hash for password accounts, preferences and the information you choose to save or sync. This can include Home and Work coordinates, recent destinations, saved places, route history, place notes/reviews and companion journals or travel totals. Connected Google or Apple sign-in uses provider identifiers; Waybi does not receive your Google or Apple password. Apple sign-in is available only when its configuration is enabled.'],
        ['On-device storage and cloud sync', 'The app stores settings and navigation state on your device, and uses secure storage for account sessions. Live GPS updates support navigation on the device; they are not continuously uploaded as a live tracking stream. This does not mean that no location leaves the device: route requests, saved destinations, completed journeys, reports and account backups can contain location. Route Watch checks a saved route corridor on the server rather than following your live position.'],
        ['Service providers and international processing', 'Cloudflare hosts the website/API, account database and caches. Google Cloud hosts Waybi’s private New Zealand Valhalla route service. Google Places UI Kit supplies Google address search when available. Depending on the selected feature and region, requests can reach independent map, search, routing, public transport or official road-data providers, including OpenFreeMap and OpenStreetMap-based services. Google Maps/Navigation services receive data when their features are used. These services can receive IP addresses, request details and technical logs and may process data outside New Zealand. Their own privacy policies apply to their services.'],
        ['Usage, logs, reports and support', 'Waybi records API usage and quota counters to control reliability and costs. Hosting and upstream providers can process IP addresses, timestamps, errors and request metadata. Community road reports include a location, type and time so nearby users can see the event; do not include private information in reports. Navigation feedback can include route details or coordinates. If you contact support, we receive the message, your contact information and any attachments you choose to send. Support mail is forwarded to the operator’s support inbox.'],
        ['Payments', 'Where subscriptions are enabled, Apple handles iOS payments. Waybi stores transaction identifiers, product and membership status to verify and restore access. Waybi does not receive your full card details from Apple. A future web purchase channel may use Stripe and its hosted payment pages; enabling a billing feature requires its separate configuration. Deleting a Waybi account does not itself cancel an App Store subscription. Manage subscriptions in your Apple account.'],
        ['Retention and deletion', 'Saved account information remains while needed to provide your account and chosen features, until you change or delete it. The current service limits recent destinations and route history rather than keeping unlimited journey lists. Sessions expire or are revoked when you sign out or delete the account. In Me, signed-in users can choose Delete account and confirm their email: this removes the active account and associated cloud records and clears account-scoped local app data handled by that flow. Provider logs, support correspondence, billing-provider records and recovery copies can have separate retention; active-account deletion does not erase every provider log or backup immediately. Ask support about information you cannot remove in the app.'],
        ['Your choices and contact', 'You can use basic navigation without creating an account, adjust location/audio/notification permissions, change saved information, sign out, or delete your account. Contact '+email+' to request access or correction, ask about retention, or raise a privacy concern. We may need to verify that a request concerns your own information. Avoid sending passwords, Apple/Google codes or full journey histories by email. We update this policy when the service changes and show the update date here.'],
      ],
    },
    support: {
      title: 'Support',
      description: 'Contact Waybi support, report a navigation or account issue, find privacy and deletion guidance, and troubleshoot location, search or audio.',
      intro: 'For Waybi app help, privacy requests or a problem with your account, email '+email+'. You do not need to sign in to read this page. Waybi is a navigation aid; for an immediate emergency use the relevant emergency services.',
      sections: [
        ['Tell us what happened', 'Include your Waybi version/build, phone model, iOS or Android version, app language, the feature you were using, the expected result and what happened. A screenshot and the approximate time can help. For a route problem, include the affected road or junction and direction of travel. Share only the minimum location detail needed; you can redact Home, Work, names and unrelated map areas. Do not email passwords, verification codes or payment-card information.'],
        ['Location, voice and weak connections', 'Check location permission and Precise Location in device Settings, volume and the selected audio output. Active navigation may need background location to continue while locked. A weak connection can delay a new search or reroute. If guidance conflicts with signs or conditions, follow the actual road rules and stop safely before changing the app. Report an incorrect instruction after the journey or ask a passenger to record it.'],
        ['Accounts, privacy and deletion', 'Account settings are in Me. You can sign out or use Delete account with the requested confirmation. Deletion removes your active Waybi account and associated synced information; app deletion alone does not delete cloud account data. If you cannot access your account, email support for assistance. Review the Privacy policy for provider processing, retention and your choices.'],
        ['Subscriptions and refunds', 'If Apple subscriptions are enabled, use Restore purchases with the original Waybi and Apple accounts. Manage or cancel an App Store subscription through Apple account subscription settings. A Waybi account deletion does not automatically cancel Apple renewal. Apple handles its purchase/refund process. Do not send a card number to support; a transaction reference and the product name are enough to start investigating.'],
        ['TestFlight feedback', 'For a beta issue, include the build number and reproducible steps. You can also use TestFlight feedback. Never operate the phone or inspect logs while driving; have a passenger record the issue or stop in a safe place. Features and coverage can vary by build and region. A beta availability notice is not a promise of an App Store launch date.'],
      ],
    },
    terms: {
      title: 'Terms of use',
      description: 'Waybi service terms covering safe navigation, map coverage, accounts, subscriptions, data providers, support and your applicable rights.',
      intro: 'These terms explain use of the Waybi app and website. For questions contact '+email+'. The Privacy policy explains how information is handled. Your applicable statutory consumer and privacy rights are not excluded by these terms.',
      sections: [
        ['Navigation and road conditions', 'Waybi provides supplementary route guidance and road awareness. Maps, suggested routes, ETAs, closures, lane guidance, cameras and parking information can be incomplete, delayed or incorrect. A suggested route does not confirm a legal turn, available parking, road access or that a road is safe. Follow road signs, actual conditions and applicable traffic laws. Do not interact with the app while driving; plan before setting off or stop safely. Waybi is not an emergency service.'],
        ['Coverage and availability', 'New Zealand is Waybi’s primary tested navigation region. Features, data freshness and provider coverage differ by region. Live congestion and road-closure coverage are not complete; an ETA is an estimate. Search and routing services have quotas and may fall back to another available source or temporarily become unavailable. Waybi does not guarantee every camera, closure or road restriction will be detected.'],
        ['Accounts and responsible use', 'Basic map/navigation features can be used without an account. Keep account access secure and provide only information you are entitled to use. Do not bypass request limits, interfere with the service, impersonate others or post unlawful, misleading or abusive reports. Public road reports should describe the road event and avoid private information about people. You can request help or delete your account in Me.'],
        ['Subscriptions when available', 'A listed planned price or a disabled upgrade control is not a completed purchase. If you choose an Apple subscription, confirm its price, duration and renewal information in Apple’s purchase sheet. Apple account settings provide subscription management and cancellation; access and refunds follow the applicable store process and your consumer rights. Restore uses the original purchase and account. Deleting a Waybi account does not cancel an Apple subscription. These service terms supplement the App Store app licence; Apple’s standard EULA is linked below.'],
        ['Third-party content and updates', 'Maps, road data, imagery and other provider content remain subject to their applicable licences and attribution. Credits are available in Me → Map data & licences. Service features and these terms may change; the update date appears on this page. Contact support if a change or an error affects your use. These terms do not replace the policies of Apple, Google or other providers for their own services.'],
      ],
    },
  },
  zh: {
    privacy: {
      title: '隐私政策',
      description: '了解 Waybi 如何处理定位、账号、保存地点与行程，哪些服务商会接收请求，以及如何管理、更正或删除你的数据。',
      intro: '本政策适用于 Waybi App 和 waybi.co。Waybi 为提供导航、账号同步和你选择的功能处理信息。有关隐私、访问、更正或删除的请求，请联系 '+email+'。',
      sections: [
        ['定位与导航', '获得你的系统权限后，Waybi 使用定位显示位置、计算路线、跟随行程并提供导航提醒。导航期间，锁屏或切到后台后可能继续使用定位和音频权限；你可以在设备设置中调整。搜索和算路会把相关搜索词、起终点、途经点，以及部分请求中的附近坐标发送给完成请求所需的服务。即使未登录，位置信息仍然敏感。'],
        ['账号与保存的信息', '基础地图和导航无需注册账号。创建账号后，我们保存邮箱、账号标识、密码账号的盐值和密码哈希、偏好，以及你选择保存或同步的信息。相关信息可能包括家和公司的坐标、最近目的地、收藏地点、行程记录、地点备注/评价、旅伴日记和旅行统计。Google 或 Apple 登录使用其提供的账号标识，Waybi 不接收你的 Google 或 Apple 密码；Apple 登录仅在完成相关配置后可用。'],
        ['本机数据与云同步', 'App 在设备上保存设置和导航状态，并使用安全存储保存账号会话。实时 GPS 更新主要用于本机导航，不作为持续实时追踪流上传。这不代表定位从不离开设备：算路、保存地点、已完成行程、道路报告和账号备份可能含有位置。Route Watch 在服务器检查已保存的路线走廊，而非持续跟踪你的当前位置。'],
        ['服务商及跨境处理', 'Cloudflare 提供网站、API、账号数据库和缓存；Google Cloud 托管 Waybi 的新西兰私有 Valhalla 路由服务。Google Places UI Kit 在可用时提供 Google 地点搜索。根据地区和所用功能，请求也可能发送给独立地图、搜索、路线、公交或官方道路数据服务，包括 OpenFreeMap 和基于 OpenStreetMap 的服务。使用 Google 地图或导航功能时，相应 Google 服务也会接收数据。服务商可能处理 IP 地址、请求详情和技术日志，并可能在新西兰以外处理数据；其自身服务适用其隐私政策。'],
        ['用量、日志、报告与支持', 'Waybi 记录 API 用量和配额计数，以维护可靠性和控制成本。托管或上游服务可能处理 IP、时间、错误和请求元数据。社区道路报告包含位置、类型和时间，用于向附近用户显示事件；请勿在报告中填写他人的隐私。导航反馈可能包含路线详情或坐标。联系支持时，我们会收到邮件、联系方式及你自愿发送的附件；支持邮件会转发至运营者的支持收件箱。'],
        ['付款', '订阅启用后，iOS 付款由 Apple 处理，Waybi 保存交易标识、产品和会员状态以验证及恢复权益，不接收 Apple 付款中的完整银行卡资料。未来网页付款渠道可能使用 Stripe 的托管付款页，相关功能需另行配置。删除 Waybi 账号不会自动取消 App Store 订阅，请在 Apple 账号中管理订阅。'],
        ['保存期限与删除', '为提供账号和所选功能，已保存信息会保留至你修改、删除或服务不再需要该信息；当前服务对最近地点和历史行程数量设有限制。会话会过期，退出或删号时会撤销相应会话。登录后可在“我的”选择“删除账号”并确认邮箱，删除当前账号和关联云记录，并清理该删除流程处理的本机账号数据。服务商日志、支持往来、支付平台记录和恢复副本可能各有保存期限，删除当前账号不表示所有日志或备份会立即消失。无法在 App 中处理的信息，请联系支持。'],
        ['你的选择与联系方式', '你可以不注册就使用基础导航，调整定位、音频和通知权限，修改保存信息、退出或删除账号。有关数据访问、更正、保存期限或隐私问题，请联系 '+email+'；我们可能需要核实请求对应你自己的信息。请勿通过邮件发送密码、验证码或完整出行轨迹。服务变化时我们会更新本政策，并在此显示更新日期。'],
      ],
    },
    support: {
      title: '帮助与支持',
      description: '联系 Waybi 支持，反馈导航、搜索、定位、语音或账号问题，了解隐私、账号删除、订阅与 TestFlight 反馈方法。',
      intro: '有关 App 使用、账号或隐私问题，请发邮件至 '+email+'。阅读本页无需登录。Waybi 是辅助导航工具，紧急情况请联系当地相应的紧急服务。',
      sections: [
        ['反馈时提供什么', '请附上 Waybi 版本/build、手机型号、系统版本、App 语言、操作步骤、预期结果及实际现象。截图和大致发生时间有助于排查。路线问题可说明相关道路、路口和行进方向，只提供排查所需的最少位置资料；可遮住家、公司、姓名和无关区域。请勿发送密码、验证码或银行卡资料。'],
        ['定位、语音与弱网', '请在设备设置中检查定位与精确定位权限、音量和音频输出设备。锁屏导航可能需要后台定位权限。网络较弱时，新搜索或重新算路可能变慢。导航与道路标志或实际情况不一致时，请以道路规则为准，并在安全停车后再操作 App；可在行程结束后反馈或请乘客记录。'],
        ['账号、隐私与删除', '账号设置位于“我的”，可退出登录，或选择“删除账号”并按提示确认。删除账号会移除当前云账号和相关同步信息；只卸载 App 不会删除云账号。无法登录时可联系支持协助。有关服务商处理、保存期限与选择，请阅读隐私政策。'],
        ['订阅与退款', 'Apple 订阅启用后，请使用原 Waybi 账号和 Apple 账号恢复购买，在 Apple 订阅设置中管理或取消自动续订。删除 Waybi 账号不会自动取消续订；Apple 处理其商店的购买和退款流程。反馈支付问题只需提供交易参考号和产品名称，请勿发送卡号。'],
        ['TestFlight 反馈', '测试版问题请注明 build 和复现步骤，也可以通过 TestFlight 反馈。行车期间不要操作手机或查看日志，请乘客记录或安全停车后处理。功能与数据覆盖可能随版本和地区不同；测试版开放不代表承诺某个 App Store 上线日期。'],
      ],
    },
    terms: {
      title: '使用条款',
      description: 'Waybi 使用条款说明辅助导航与道路信息的限制、地区覆盖、账号使用、订阅、第三方数据和联系支持的方法。',
      intro: '本条款说明 Waybi App 和网站的使用方式。疑问请联系 '+email+'；信息处理方式见隐私政策。本条款不排除你依法享有的消费者与隐私权利。',
      sections: [
        ['导航与道路情况', 'Waybi 提供辅助路线指引和道路提醒。地图、建议路线、预计到达时间、封路、车道、摄像头和停车资料可能不完整、延迟或有误。建议路线不保证转向合法、道路可通行、安全或存在可用停车位。请遵守实际道路标志、交通规则和现场情况；出发前规划，行车时不要操作 App，需要调整时请安全停车。Waybi 不提供紧急救援服务。'],
        ['覆盖与可用性', '新西兰是当前主要实测导航地区。不同地区的功能、覆盖和更新速度不同；实时拥堵和封路信息并不完整，预计时间只是估算。搜索和路由服务有配额，可能改用其他可用来源或暂时不可用。Waybi 不保证识别全部摄像头、封路或道路限制。'],
        ['账号与合理使用', '基础地图与导航无需注册。请保护账号，仅使用你有权提供的信息；勿绕过请求限制、干扰服务、冒充他人或提交违法、误导、辱骂性报告。公开道路报告应描述事件，避免泄露他人隐私。你可在“我的”删除账号或联系支持。'],
        ['订阅启用后', '计划价格或不可点击的升级按钮不代表已购买。选择 Apple 订阅时，请在 Apple 付款窗口核对价格、期限和续订信息；订阅管理、取消和退款按适用商店流程及消费者权利处理。恢复购买使用原购买与账号。删除 Waybi 账号不会取消 Apple 订阅。本服务条款补充 App Store 的 App 许可，页面下方提供 Apple 标准 EULA 链接。'],
        ['第三方内容与更新', '地图、道路资料、图片及第三方内容适用其许可和署名要求，可在“我的 → 地图数据与许可”查看来源。功能与条款可能更新，本页显示更新日期；变化或错误影响使用时请联系支持。本条款不取代 Apple、Google 等提供商对其自身服务的政策。'],
      ],
    },
  },
};

const esc = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const urlFor = (kind, language) => `${language === 'zh' ? '/zh' : ''}/${kind}/`;
for (const language of ['en', 'zh']) {
  for (const kind of ['privacy', 'support', 'terms']) {
    const zh = language === 'zh';
    const page = documents[language][kind];
    const canonical = `https://waybi.co${urlFor(kind, language)}`;
    const nav = Object.entries(documents[language]).map(([key, value]) => `<a href="${urlFor(key, language)}"${key === kind ? ' aria-current="page"' : ''}>${esc(value.title)}</a>`).join('');
    const html = `<!doctype html>
<html lang="${zh ? 'zh-Hans' : 'en-NZ'}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${esc(page.title)} · Waybi</title><meta name="description" content="${esc(page.description)}"><link rel="canonical" href="${canonical}"><link rel="alternate" hreflang="en-NZ" href="https://waybi.co${urlFor(kind, 'en')}"><link rel="alternate" hreflang="zh-Hans" href="https://waybi.co${urlFor(kind, 'zh')}"><link rel="stylesheet" href="/service-pages.css"><link rel="icon" href="/favicon.svg"></head>
<body><a class="skip" href="#main">${zh ? '跳到正文' : 'Skip to content'}</a><header><a class="brand" href="${zh ? '/zh/' : '/'}"><img src="/brand/waybi-lockup.svg" alt="Waybi" width="155" height="40"></a><nav aria-label="${zh ? '帮助与法律信息' : 'Help and legal information'}">${nav}<a href="${urlFor(kind, zh ? 'en' : 'zh')}" lang="${zh ? 'en' : 'zh-Hans'}">${zh ? 'English' : '中文'}</a></nav></header>
<main id="main"><p class="eyebrow">WAYBI · ${zh ? '帮助与法律信息' : 'HELP & LEGAL'}</p><h1>${esc(page.title)}</h1><p class="updated">${zh ? '更新日期' : 'Last updated'}: <time datetime="${updated}">${updated}</time></p><p class="intro">${esc(page.intro)}</p><a class="contact" href="mailto:${email}">${email} <span aria-hidden="true">↗</span></a><div class="contents"><p>${zh ? '本页内容' : 'On this page'}</p><ol>${page.sections.map(([title], i) => `<li><a href="#section-${i + 1}">${esc(title)}</a></li>`).join('')}</ol></div>${page.sections.map(([title, text], i) => `<section aria-labelledby="heading-${i + 1}" id="section-${i + 1}"><h2 id="heading-${i + 1}">${esc(title)}</h2><p>${esc(text)}</p></section>`).join('')}${kind === 'terms' ? `<p><a href="${appleTerms}">${zh ? 'Apple 标准最终用户许可协议（EULA）' : 'Apple standard end-user licence agreement (EULA)'}</a></p>` : ''}</main><footer><a href="${zh ? '/zh/about/' : '/about/'}">${zh ? '关于 Waybi' : 'About Waybi'}</a><span>${zh ? '支持与隐私联系' : 'Support and privacy contact'}: <a href="mailto:${email}">${email}</a></span></footer></body></html>`;
    const directory = path.join(root, urlFor(kind, language));
    await mkdir(directory, { recursive: true });
    await writeFile(path.join(directory, 'index.html'), html);
  }
}
console.log('Generated six English/Chinese Waybi privacy, terms and support pages.');
