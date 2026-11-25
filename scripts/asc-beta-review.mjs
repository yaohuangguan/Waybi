#!/usr/bin/env node
// Prepares a processed TestFlight build for external (public) testing and
// submits it to Beta App Review through the App Store Connect API.
//
// Steps, each idempotent so the script can be re-run safely:
//  1. wait until the build has finished processing;
//  2. answer the export-compliance question (standard HTTPS only, exempt);
//  3. fill in TestFlight Test Information (beta description, feedback email,
//     privacy policy) and the Beta App Review notes;
//  4. set "What to Test" for the build;
//  5. create or reuse the external group with a public link and add the build;
//  6. submit the build to Beta App Review.
//
// Contact name/phone for Beta App Review are never stored in the repo: existing
// values in App Store Connect are kept, and missing ones may come from the
// optional ASC_REVIEW_CONTACT_* secrets.
//
// Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUILD_NUMBER, APP_VERSION,
// optional BUNDLE_ID, GROUP_NAME, DRY_RUN=true, ASC_REVIEW_CONTACT_{FIRST_NAME,
// LAST_NAME,PHONE,EMAIL}, GITHUB_STEP_SUMMARY.
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync, appendFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const API = 'https://api.appstoreconnect.apple.com';
const b64url = value => Buffer.from(value).toString('base64url');

export function ascToken({ keyId, issuerId, privateKeyPem, now = Date.now() }) {
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }));
  const iat = Math.floor(now / 1000);
  const payload = b64url(JSON.stringify({ iss: issuerId, iat, exp: iat + 15 * 60, aud: 'appstoreconnect-v1' }));
  const data = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(data), {
    key: createPrivateKey(privateKeyPem), dsaEncoding: 'ieee-p1363',
  });
  return `${data}.${signature.toString('base64url')}`;
}

export const TEST_INFO = {
  feedbackEmail: 'support@waybi.co',
  privacyPolicyUrl: 'https://waybi.co/privacy/',
  marketingUrl: 'https://waybi.co/',
  description: 'Waybi brings navigation, road awareness and a little companionship to journeys in New Zealand. ' +
    'Search for an address or place, compare available route options and follow your journey with voice guidance. ' +
    'Review recent trips and saved places, and meet Waybi & Friends, a travel companion and journal. ' +
    'Basic map and navigation use does not require an account; an optional account syncs saved information across devices.',
};

export const WHAT_TO_TEST = `Please test Waybi on familiar New Zealand journeys: address search, route options, rerouting, voice and lock-screen navigation, Trips, and account sign-in (Apple, Google or email code) from Me. Follow actual road signs; have a passenger record issues or stop safely. Send feedback through TestFlight or support@waybi.co with the build number, device and steps.

请在熟悉的新西兰路线测试 Waybi：地址搜索、备选路线、偏航重算、语音和锁屏导航、行程页，以及在“我的”页面用 Apple、Google 或邮箱验证码登录。请遵守实际道路标志，由乘客记录或安全停车后反馈。可通过 TestFlight 或 support@waybi.co 反馈 build、设备和复现步骤。`;

export const REVIEW_NOTES = `No account is needed to review Waybi. Open the app, allow location (optional), search a public Auckland place such as "Sky Tower", pick a route and preview or start guidance. Me shows sign-in (Apple, Google or a one-time email code), Waybi & Friends, Plus, privacy policy, terms and support. A signed-in account can be deleted from Me > Delete account. Waybi is a navigation app: please follow road rules when testing while driving.`;

/** Fields required by Beta App Review that are still empty after merging. */
export function missingContact(detail) {
  return ['contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'].filter(key => !detail[key]);
}

export function mergeReviewDetail(current = {}, env = {}) {
  const pick = (key, envKey) => current[key] || env[envKey] || null;
  return {
    contactFirstName: pick('contactFirstName', 'ASC_REVIEW_CONTACT_FIRST_NAME'),
    contactLastName: pick('contactLastName', 'ASC_REVIEW_CONTACT_LAST_NAME'),
    contactPhone: pick('contactPhone', 'ASC_REVIEW_CONTACT_PHONE'),
    contactEmail: pick('contactEmail', 'ASC_REVIEW_CONTACT_EMAIL') || TEST_INFO.feedbackEmail,
    demoAccountRequired: false,
    notes: REVIEW_NOTES,
  };
}

/** externalBuildState values after which the build must not be submitted again. */
export const ALREADY_SUBMITTED = new Set(['WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW', 'BETA_APPROVED', 'IN_BETA_TESTING']);

export function createClient({ token, fetcher = fetch, dryRun = false, log = console.log }) {
  async function call(method, path, body) {
    if (dryRun && method !== 'GET') {
      log(`[dry run] ${method} ${path}`);
      return { data: body?.data ? { id: 'dry-run', ...body.data } : null };
    }
    const response = await fetcher(API + path, {
      method,
      headers: { authorization: `Bearer ${token()}`, ...(body ? { 'content-type': 'application/json' } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.status === 204) return {};
    const json = await response.json().catch(() => ({}));
    if (!response.ok) {
      const detail = (json.errors || []).map(e => `${e.code}: ${e.detail || e.title}`).join('; ');
      throw Object.assign(new Error(`${method} ${path} failed (${response.status}) ${detail}`), { status: response.status, errors: json.errors || [] });
    }
    return json;
  }
  return {
    get: path => call('GET', path),
    post: (path, body) => call('POST', path, body),
    patch: (path, body) => call('PATCH', path, body),
  };
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export async function submitForBetaReview(api, options) {
  const { bundleId, appVersion, buildNumber, groupName, env = {}, log = console.log,
    pollMs = 30000, maxWaitMs = 45 * 60000 } = options;
  const apps = await api.get(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&fields[apps]=bundleId,primaryLocale,name`);
  const app = apps.data?.[0];
  if (!app) throw new Error(`No App Store Connect app for ${bundleId}`);
  const locale = app.attributes.primaryLocale || 'en-US';
  log(`App ${app.attributes.name} (${app.id}), primary locale ${locale}`);

  // 1. Wait for processing.
  let build;
  for (const started = Date.now(); ;) {
    const builds = await api.get(`/v1/builds?filter[app]=${app.id}&filter[version]=${encodeURIComponent(buildNumber)}` +
      `&filter[preReleaseVersion.version]=${encodeURIComponent(appVersion)}&limit=1`);
    build = builds.data?.[0];
    const state = build?.attributes?.processingState;
    log(`Build ${appVersion} (${buildNumber}): ${state || 'not found yet'}`);
    if (state === 'VALID') break;
    if (state === 'FAILED' || state === 'INVALID') throw new Error(`Build processing ${state}`);
    if (Date.now() - started > maxWaitMs) throw new Error('Timed out waiting for the build to finish processing');
    await sleep(pollMs);
  }

  // 2. Export compliance.
  if (build.attributes.usesNonExemptEncryption == null) {
    await api.patch(`/v1/builds/${build.id}`, { data: { type: 'builds', id: build.id, attributes: { usesNonExemptEncryption: false } } });
    log('Export compliance: standard HTTPS/OS encryption only (exempt)');
  }

  // 3. Test Information and Beta App Review details.
  const localizations = await api.get(`/v1/apps/${app.id}/betaAppLocalizations`);
  const existing = localizations.data?.find(item => item.attributes.locale === locale);
  if (existing) {
    await api.patch(`/v1/betaAppLocalizations/${existing.id}`, { data: { type: 'betaAppLocalizations', id: existing.id, attributes: TEST_INFO } });
  } else {
    await api.post('/v1/betaAppLocalizations', { data: { type: 'betaAppLocalizations',
      attributes: { locale, ...TEST_INFO }, relationships: { app: { data: { type: 'apps', id: app.id } } } } });
  }
  const reviewDetail = (await api.get(`/v1/apps/${app.id}/betaAppReviewDetail`)).data;
  const merged = mergeReviewDetail(reviewDetail?.attributes, env);
  const missing = missingContact(merged);
  if (missing.length) {
    throw Object.assign(new Error(`Beta App Review contact is incomplete: ${missing.join(', ')}. Fill them once in ` +
      'App Store Connect (TestFlight > Test Information > Beta App Review Information) or add the ASC_REVIEW_CONTACT_* secrets, then re-run.'),
    { missing });
  }
  await api.patch(`/v1/betaAppReviewDetails/${reviewDetail.id}`, { data: { type: 'betaAppReviewDetails', id: reviewDetail.id, attributes: merged } });
  log('Test Information and Beta App Review details are set');

  // 4. What to Test.
  const buildLocalizations = await api.get(`/v1/builds/${build.id}/betaBuildLocalizations`);
  const whatsNew = buildLocalizations.data?.find(item => item.attributes.locale === locale);
  if (whatsNew) {
    await api.patch(`/v1/betaBuildLocalizations/${whatsNew.id}`, { data: { type: 'betaBuildLocalizations', id: whatsNew.id, attributes: { whatsNew: WHAT_TO_TEST } } });
  } else {
    await api.post('/v1/betaBuildLocalizations', { data: { type: 'betaBuildLocalizations',
      attributes: { locale, whatsNew: WHAT_TO_TEST }, relationships: { build: { data: { type: 'builds', id: build.id } } } } });
  }

  // 5. External group with a public link.
  const groups = await api.get(`/v1/betaGroups?filter[app]=${app.id}&limit=200`);
  let group = groups.data?.find(item => !item.attributes.isInternalGroup && item.attributes.name === groupName);
  const groupAttributes = { publicLinkEnabled: true, publicLinkLimitEnabled: false, feedbackEnabled: true };
  if (group) {
    if (!group.attributes.publicLinkEnabled) {
      group = (await api.patch(`/v1/betaGroups/${group.id}`, { data: { type: 'betaGroups', id: group.id, attributes: groupAttributes } })).data || group;
    }
  } else {
    group = (await api.post('/v1/betaGroups', { data: { type: 'betaGroups', attributes: { name: groupName, ...groupAttributes },
      relationships: { app: { data: { type: 'apps', id: app.id } } } } })).data;
    log(`Created external group "${groupName}"`);
  }
  await api.post(`/v1/betaGroups/${group.id}/relationships/builds`, { data: [{ type: 'builds', id: build.id }] });
  log(`Build added to "${groupName}"`);

  // 6. Submit to Beta App Review.
  const betaDetail = (await api.get(`/v1/builds/${build.id}/buildBetaDetail`)).data;
  const externalState = betaDetail?.attributes?.externalBuildState;
  let submitted = false;
  if (ALREADY_SUBMITTED.has(externalState)) {
    log(`Already submitted (${externalState})`);
  } else {
    try {
      await api.post('/v1/betaAppReviewSubmissions', { data: { type: 'betaAppReviewSubmissions',
        relationships: { build: { data: { type: 'builds', id: build.id } } } } });
      submitted = true;
      log('Submitted to Beta App Review');
    } catch (error) {
      // Re-runs race with Apple's own state change; an existing submission is success.
      if (error.status !== 409 || !/already|submitted/i.test(error.message)) throw error;
      log('A Beta App Review submission already exists');
    }
  }
  const refreshed = group.id === 'dry-run' ? group : (await api.get(`/v1/betaGroups/${group.id}`)).data;
  return { appId: app.id, buildId: build.id, externalState, submitted, publicLink: refreshed?.attributes?.publicLink || null };
}

async function main() {
  const env = process.env;
  for (const key of ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_KEY_PATH', 'BUILD_NUMBER', 'APP_VERSION']) {
    if (!env[key]) throw new Error(`Missing ${key}`);
  }
  const privateKeyPem = readFileSync(env.ASC_KEY_PATH, 'utf8');
  const api = createClient({
    token: () => ascToken({ keyId: env.ASC_KEY_ID, issuerId: env.ASC_ISSUER_ID, privateKeyPem }),
    dryRun: env.DRY_RUN === 'true',
  });
  const result = await submitForBetaReview(api, {
    bundleId: env.BUNDLE_ID || 'co.waybi.ios', appVersion: env.APP_VERSION, buildNumber: env.BUILD_NUMBER,
    groupName: env.GROUP_NAME || 'Public testers', env,
  });
  const summary = [
    `### Beta App Review: Waybi ${env.APP_VERSION} (${env.BUILD_NUMBER})`,
    result.submitted ? 'Submitted to Beta App Review. Apple usually reviews within 24–48 hours.' : `Review state: ${result.externalState}`,
    result.publicLink ? `Public link (works once the build is approved): ${result.publicLink}` : 'Public link: shown in TestFlight once Apple generates it.',
  ].join('\n\n');
  console.log(summary);
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, summary + '\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(`::error::${error.message}`);
    process.exit(1);
  });
}
