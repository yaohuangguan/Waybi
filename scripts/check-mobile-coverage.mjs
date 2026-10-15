import { readFileSync, readdirSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, relative, dirname, isAbsolute, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

export function parseLcov(raw, packageRoot, repoRoot) {
  const records = new Map();
  let current;
  for (const line of raw.split(/\r?\n/)) {
    if (line.startsWith('SF:')) {
      const name = line.slice(3);
      const absolute = name.startsWith('file:') ? fileURLToPath(name)
        : isAbsolute(name) ? name : resolve(packageRoot, name);
      const key = relative(repoRoot, absolute).replaceAll('\\', '/');
      current = records.get(key) ?? new Map();
      records.set(key, current);
    } else if (line.startsWith('DA:') && current) {
      const [number, count] = line.slice(3).split(',').map(Number);
      if (!Number.isInteger(number) || number < 1 || !Number.isFinite(count) || count < 0) {
        throw new Error('Malformed LCOV line counter: ' + line);
      }
      current.set(number, Math.max(current.get(number) ?? 0, count));
    }
  }
  return records;
}

export function evaluateFile(path, counters, rule) {
  if (!rule) return { path, error: 'Source file has no reviewed coverage rule' };
  const total = counters?.size ?? 0;
  const hit = [...(counters?.values() ?? [])].filter(count => count > 0).length;
  if (rule.kind === 'declarations') {
    if (!rule.reason || total > 0) return { path, error: 'Executable code cannot use a declaration-only exemption' };
    return { path, kind: rule.kind, reason: rule.reason, total, hit };
  }
  if (!total || !hit) return { path, error: 'No executed coverage; importing a module alone is insufficient', total, hit };
  if (!(rule.minimumLinePercent > 0 && rule.minimumLinePercent <= 100)) {
    return { path, error: 'A positive reviewed line threshold is required', total, hit };
  }
  const percent = hit / total * 100;
  return { path, total, hit, percent: Number(percent.toFixed(2)),
    minimum: rule.minimumLinePercent,
    ...(percent + 0.000001 < rule.minimumLinePercent ? {error:'Coverage regressed below the reviewed threshold'} : {}) };
}

function dartFiles(root) {
  return readdirSync(root, {withFileTypes:true}).flatMap(entry => {
    const path=resolve(root,entry.name);
    return entry.isDirectory() ? dartFiles(path) : entry.name.endsWith('.dart') ? [path] : [];
  });
}

export function checkCoverage(repoRoot, policy) {
  const results=[];
  for (const suite of policy.suites) {
    const packageRoot=resolve(repoRoot,suite.root);
    const report=resolve(repoRoot,suite.report);
    if (!existsSync(report)) throw new Error('Missing coverage report: '+suite.report);
    const counters=parseLcov(readFileSync(report,'utf8'), packageRoot, repoRoot);
    const sources=dartFiles(resolve(packageRoot,'lib')).map(path=>relative(repoRoot,path).replaceAll('\\','/')).sort();
    for (const path of sources) {
      const rule=policy.files[path];
      if (rule?.kind==='declarations' && rule.sha256!==createHash('sha256').update(readFileSync(resolve(repoRoot,path),'utf8').replaceAll('\r\n','\n')).digest('hex')) {
        results.push({path,error:'Declaration-only source changed and requires review'});
      } else results.push(evaluateFile(path,counters.get(path),rule));
    }
    for (const path of Object.keys(policy.files).filter(path=>path.startsWith(suite.root+'/lib/'))) {
      if (!sources.includes(path)) results.push({path,error:'Stale coverage rule for a removed source file'});
    }
  }
  return results;
}

export function checkFeatureManifest(repoRoot, manifest) {
  const failures=[];
  const ids=new Set();
  for (const feature of manifest.features ?? []) {
    if (!feature.id || ids.has(feature.id) || !feature.tests?.length) {
      failures.push({path:'feature:'+feature.id,error:'Each capability needs a unique ID and test evidence'});
    }
    ids.add(feature.id);
    for (const name of feature.tests ?? []) {
      const path=resolve(repoRoot,name);
      const relativePath=relative(repoRoot,path);
      if (relativePath==='..' || relativePath.startsWith('..'+sep) || isAbsolute(relativePath) || !existsSync(path)) {
        failures.push({path:name,error:'Capability test evidence is missing'});
      } else {
        const source=readFileSync(path,'utf8');
        if (!/\b(?:test|testWidgets)\s*\(|\bfunc\s+test/.test(source) || !/\bexpect(?:Later)?\s*\(|\bXCTAssert/.test(source)) {
          failures.push({path:name,error:'Capability evidence must contain executable tests and assertions'});
        }
      }
    }
  }
  if (!ids.size) failures.push({path:'features',error:'Capability inventory is empty'});
  return failures;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const repoRoot=resolve(dirname(fileURLToPath(import.meta.url)),'..');
  const policy=JSON.parse(readFileSync(resolve(repoRoot,'tests/mobile-coverage-policy.json'),'utf8'));
  const manifest=JSON.parse(readFileSync(resolve(repoRoot,'tests/mobile-features.json'),'utf8'));
  const results=[...checkCoverage(repoRoot,policy),...checkFeatureManifest(repoRoot,manifest)];
  const output=resolve(repoRoot,'coverage/mobile-inventory.json');
  mkdirSync(dirname(output),{recursive:true});
  writeFileSync(output,JSON.stringify({generatedAt:new Date().toISOString(),files:results},null,2)+'\n');
  const failures=results.filter(result=>result.error);
  for (const result of results) console.log(
    result.error ? 'FAIL '+result.path+': '+result.error
    : result.kind==='declarations' ? 'DECL '+result.path+': '+result.reason
    : 'PASS '+result.path+' '+result.percent+'% (minimum '+result.minimum+'%)'
  );
  console.log(results.length+' inventoried source files; '+failures.length+' coverage failures.');
  if (failures.length) process.exitCode=1;
}
