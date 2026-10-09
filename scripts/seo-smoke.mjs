import fs from 'node:fs';
import path from 'node:path';

const dist = path.resolve('apps/web/dist');
const site = 'https://waybi.co';
const sitemapPath = path.join(dist, 'sitemap.xml');

function fail(message) {
  console.error('SEO check failed:', message);
  process.exitCode = 1;
}

function visibleText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&(?:[a-zA-Z]+|#\d+|#x[\da-fA-F]+);/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

if (!fs.existsSync(sitemapPath)) {
  fail('apps/web/dist/sitemap.xml is missing; run the web build first');
  process.exit(1);
}

const sitemap = fs.readFileSync(sitemapPath, 'utf8');
const urls = [...sitemap.matchAll(/<loc>(https:\/\/waybi\.co\/[^<]*)<\/loc>/g)].map((m) => m[1]);
if (new Set(urls).size !== urls.length) fail('sitemap contains duplicate URLs');

const titles = new Map();
const canonicals = new Map();

for (const url of urls) {
  const pathname = new URL(url).pathname;
  const file = pathname === '/'
    ? path.join(dist, 'index.html')
    : path.join(dist, pathname.replace(/^\//, ''), 'index.html');

  if (!fs.existsSync(file)) {
    fail(`${pathname}: sitemap URL has no built HTML file (${path.relative(process.cwd(), file)})`);
    continue;
  }

  const html = fs.readFileSync(file, 'utf8');
  const title = html.match(/<title>([\s\S]*?)<\/title>/i)?.[1]?.trim() || '';
  const descTag = html.match(/<meta\s+[^>]*name=["']description["'][^>]*>/i)?.[0] || '';
  const desc = descTag.match(/content=["']([^"']*)["']/i)?.[1]?.trim() || '';
  const canonicalTag = html.match(/<link\s+[^>]*rel=["']canonical["'][^>]*>/i)?.[0] || '';
  const canonical = canonicalTag.match(/href=["']([^"']+)["']/i)?.[1] || '';
  const robotsTag = html.match(/<meta\s+[^>]*name=["']robots["'][^>]*>/i)?.[0] || '';
  const robots = robotsTag.match(/content=["']([^"']+)["']/i)?.[1]?.toLowerCase() || '';
  const h1Count = (html.match(/<h1(?:\s|>)/gi) || []).length;
  const text = visibleText(html);
  const words = text.split(/\s+/).filter(Boolean).length;
  const cjkChars = (text.match(/[\u3400-\u9fff]/g) || []).length;
  const lang = html.match(/<html[^>]*lang=["']([^"']+)["']/i)?.[1]?.toLowerCase() || '';
  const contentUnits = lang.startsWith('zh') ? words + Math.floor(cjkChars / 2) : words;
  const minDescriptionLength = lang.startsWith('zh') ? 25 : 50;

  if (!title) fail(`${pathname}: missing title`);
  if (title.length > 70) fail(`${pathname}: title is too long (${title.length})`);
  if (!desc || desc.length < minDescriptionLength || desc.length > 180) {
    fail(`${pathname}: meta description length is ${desc.length}`);
  }
  if (canonical !== url) fail(`${pathname}: canonical is ${canonical || 'missing'}, expected ${url}`);
  if (robots.includes('noindex')) fail(`${pathname}: sitemap URL is noindex`);
  if (h1Count !== 1) fail(`${pathname}: expected exactly one H1, found ${h1Count}`);
  if (pathname === '/about/' || pathname === '/zh/about/') {
    for (const target of ['https://waybi.co/about/', 'https://waybi.co/zh/about/']) {
      if (!html.includes(`href="${target}"`)) fail(`${pathname}: missing alternate language page ${target}`);
    }
    if (!html.includes('application/ld+json')) fail(`${pathname}: missing about page structured data`);
    if (!html.includes('/brand/waybi.png')) fail(`${pathname}: missing Waybi artwork`);
  }
  if (contentUnits < 180) fail(`${pathname}: page is unexpectedly thin (${contentUnits} content units)`);

  for (const match of html.matchAll(/<script\s+[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      JSON.parse(match[1]);
    } catch (error) {
      fail(`${pathname}: invalid JSON-LD: ${error.message}`);
    }
  }

  if (titles.has(title)) fail(`${pathname}: duplicate title also used by ${titles.get(title)}`);
  titles.set(title, pathname);
  if (canonicals.has(canonical)) fail(`${pathname}: duplicate canonical also used by ${canonicals.get(canonical)}`);
  canonicals.set(canonical, pathname);
}

if (!process.exitCode) {
  console.log(`SEO smoke passed for ${urls.length} sitemap pages on ${site}.`);
}
