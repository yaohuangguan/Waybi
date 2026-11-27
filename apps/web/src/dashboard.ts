import './account.css';
import './site.css';
import { currentProfile, initAccount, renderAccount, rememberPreferences, type AccountProfile } from './account';
import { renderProfileView } from './profile-view';
import { lockupSvg } from './brand';
import { t, translateTree, type Language } from './i18n';
import { applyTheme, LANGUAGE_EVENT, readLanguage, writeLanguage } from './preferences';

// Guests see the language they chose on the website or in the map.
let language: Language = readLanguage();
let voiceEnabled = true;

applyTheme();
document.body.dataset.surface = 'dashboard';
document.body.innerHTML = `
  <div class="dashboard-shell">
    <header class="dashboard-header">
      <a class="site-brand" href="/" data-i18n-aria-label="home">${lockupSvg('Waybi Maps & Navigation', 'site-lockup', 155)}</a>
      <nav>
        <a href="/" data-i18n="dashboardWebsite">Website</a>
        <button id="dashboardLanguage" class="dashboard-language" type="button"></button>
        <a class="site-primary-button compact" href="/app"><span data-i18n="dashboardOpenNavigator">Open navigator</span> <span aria-hidden="true">↗</span></a>
      </nav>
    </header>
    <main class="dashboard-layout">
      <aside class="dashboard-sidebar">
        <span class="dashboard-label" data-i18n="dashboardAccountLabel">ACCOUNT</span>
        <h1 id="dashboardTitle" data-i18n="dashboardTitle">Your Waybi</h1>
        <p id="dashboardIntro" data-i18n="dashboardIntro"></p>
        <div id="dashboardAccount" class="dashboard-account"></div>
        <div class="dashboard-help"><strong data-i18n="dashboardHelpTitle"></strong><p data-i18n="dashboardHelpBody"></p><a href="/app" data-i18n="dashboardContinueGuest"></a></div>
      </aside>
      <section class="dashboard-main">
        <div class="dashboard-topline"><div><span class="dashboard-label" data-i18n="dashboardLabel">DASHBOARD</span><h2 id="dashboardGreeting"></h2></div><span class="dashboard-status"><i aria-hidden="true"></i><span id="dashboardStatusText"></span></span></div>
        <div id="dashboardEmpty" class="dashboard-empty">
          <div class="dashboard-empty-intro">
            <div class="dashboard-empty-icon" aria-hidden="true">◎</div>
            <div><h3 data-i18n="dashboardEmptyTitle"></h3><p data-i18n="dashboardEmptyBody"></p></div>
          </div>
          <div class="dashboard-empty-grid">
            <article><span aria-hidden="true">↗</span><strong data-i18n="dashboardRecentTitle"></strong><p data-i18n="dashboardRecentBody"></p></article>
            <article><span aria-hidden="true">♥</span><strong data-i18n="dashboardSavedTitle"></strong><p data-i18n="dashboardSavedBody"></p></article>
            <article><span aria-hidden="true">★</span><strong data-i18n="dashboardReviewsTitle"></strong><p data-i18n="dashboardReviewsBody"></p></article>
          </div>
          <div class="dashboard-empty-actions"><a class="site-primary-button" href="/app"><span data-i18n="dashboardOpenNavigator">Open navigator</span> <span aria-hidden="true">→</span></a><small data-i18n="dashboardOptional"></small></div>
        </div>
        <div id="dashboardContent" class="dashboard-content" hidden></div>
      </section>
    </main>
  </div>`;

const accountRoot = document.getElementById('dashboardAccount') as HTMLElement;
const contentRoot = document.getElementById('dashboardContent') as HTMLElement;
const languageButton = document.getElementById('dashboardLanguage') as HTMLButtonElement;

function renderDashboard() {
  const profile = currentProfile();
  const signedIn = Boolean(profile);
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en-NZ';
  document.title = t(language, 'dashboardDocumentTitle');
  translateTree(language);
  // Shows the other language, in that language.
  languageButton.textContent = t(language, 'languageToggleLabel');
  languageButton.lang = language === 'zh' ? 'en' : 'zh-CN';
  languageButton.setAttribute('aria-label', t(language, language === 'zh' ? 'switchToEnglish' : 'switchToChinese'));
  (document.getElementById('dashboardEmpty') as HTMLElement).hidden = signedIn;
  contentRoot.hidden = !signedIn;
  (document.getElementById('dashboardStatusText') as HTMLElement).textContent = t(language, signedIn ? 'accountSynced' : 'guestMode');
  (document.getElementById('dashboardGreeting') as HTMLElement).textContent = t(language, signedIn ? 'dashboardGreetingSignedIn' : 'dashboardGreetingGuest');
  if (profile) renderProfileView(contentRoot, language, () => {});
}

function setLanguage(next: Language, persistToAccount: boolean) {
  if (next === language) return;
  language = next;
  writeLanguage(next);
  renderDashboard();
  renderAccount();
  if (persistToAccount) void rememberPreferences(language, voiceEnabled);
}

languageButton.addEventListener('click', () => setLanguage(language === 'zh' ? 'en' : 'zh', true));
window.addEventListener(LANGUAGE_EVENT, (event) => {
  const next = (event as CustomEvent<Language>).detail;
  if (next !== language && (next === 'en' || next === 'zh')) setLanguage(next, false);
});
window.addEventListener('kiwi-account-change', renderDashboard);
renderDashboard();
void initAccount(accountRoot, () => language, () => voiceEnabled, (profile: AccountProfile) => {
  voiceEnabled = profile.voiceEnabled;
  // A signed-in account's language becomes the shared choice on every surface.
  if (profile.language === 'en' || profile.language === 'zh') {
    if (profile.language !== language) { language = profile.language; writeLanguage(language); }
  }
  renderDashboard();
});
