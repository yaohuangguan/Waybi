import test from 'node:test';
import assert from 'node:assert/strict';
import {parseLcov,evaluateFile,checkCoverage,checkFeatureManifest,checkSuiteCoverage} from './check-mobile-coverage.mjs';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

test('duplicate LCOV records merge by executable line, including unexecuted lines',()=>{
  const records=parseLcov('SF:lib/a.dart\nDA:3,0\nDA:4,1\nend_of_record\nSF:lib/a.dart\nDA:3,2\nDA:4,0\nDA:5,0\n','/repo/app','/repo');
  assert.deepEqual([...records.get('app/lib/a.dart')],[[3,2],[4,1],[5,0]]);
});
test('an imported but never executed module cannot pass',()=>{
  assert.match(evaluateFile('a',new Map([[1,0]]),{minimumLinePercent:1}).error,/No executed/);
  assert.match(evaluateFile('a',undefined,{minimumLinePercent:1}).error,/No executed/);
});
test('declaration exemptions cannot hide executable logic',()=>{
  assert.match(evaluateFile('a',new Map([[1,0]]),{kind:'declarations',reason:'exports'}).error,/Executable/);
  assert.equal(evaluateFile('a',undefined,{kind:'declarations',reason:'exports'}).kind,'declarations');
});
test('regression, unreviewed files and invalid thresholds fail',()=>{
  assert.match(evaluateFile('a',new Map([[1,1],[2,0]]),{minimumLinePercent:75}).error,/regressed/);
  assert.match(evaluateFile('a',new Map([[1,1]]),undefined).error,/no reviewed/);
  assert.match(evaluateFile('a',new Map([[1,1]]),{minimumLinePercent:0}).error,/positive/);
});
test('source discovery catches an unimported newly added component',()=>{
  const root=mkdtempSync(join(tmpdir(),'waybi-coverage-'));
  try {
    mkdirSync(join(root,'app/lib'),{recursive:true});
    writeFileSync(join(root,'app/lib/new_widget.dart'),'class NewWidget {}');
    writeFileSync(join(root,'app/lcov.info'),'');
    const results=checkCoverage(root,{suites:[{root:'app',report:'app/lcov.info'}],files:{}});
    assert.equal(results.length,1);
    assert.match(results[0].error,/no reviewed/);
  } finally {rmSync(root,{recursive:true,force:true});}
});
test('corrupt coverage cannot silently improve the report',()=>{
  assert.throws(()=>parseLcov('SF:lib/a.dart\nDA:1,NaN','/repo/app','/repo'),/Malformed/);
});

test('capability evidence cannot be a deleted file or an empty test template',()=>{
  const root=mkdtempSync(join(tmpdir(),'waybi-features-'));
  try {
    writeFileSync(join(root,'empty.dart'),'void main() {}');
    assert.equal(checkFeatureManifest(root,{features:[{id:'gps',tests:['missing.dart','empty.dart']}]}).length,2);
    writeFileSync(join(root,'valid.dart'),"void main() { test('gps', () { expect(true, isTrue); }); }");
    assert.deepEqual(checkFeatureManifest(root,{features:[{id:'gps',tests:['valid.dart']}]}),[]);
  } finally {rmSync(root,{recursive:true,force:true});}
});

test('suite gate weights all executable lines rather than averaging file percentages',()=>{
  const policy={suites:[{root:'app',minimumLinePercent:90}]};
  const files=[{path:'app/lib/big.dart',total:1000,hit:890},{path:'app/lib/small.dart',total:1,hit:1}];
  assert.match(checkSuiteCoverage(files,policy)[0].error,/below/);
  files[0].hit=900;
  assert.equal(checkSuiteCoverage(files,policy)[0].error,undefined);
});
test('each package has its own floor and missing or invalid suite targets fail',()=>{
  const files=[{path:'a/lib/app.dart',total:100,hit:100},{path:'b/lib/map.dart',total:100,hit:89}];
  const result=checkSuiteCoverage(files,{suites:[{root:'a',minimumLinePercent:90},{root:'b',minimumLinePercent:90}]});
  assert.equal(result[0].error,undefined);
  assert.match(result[1].error,/below/);
  assert.match(checkSuiteCoverage(files,{suites:[{root:'a'}]})[0].error,/threshold/);
  assert.match(checkSuiteCoverage(files,{suites:[{root:'missing',minimumLinePercent:90}]})[0].error,/no executable/);
});
test('rounded presentation cannot turn sub-threshold coverage into a pass',()=>{
  const result=checkSuiteCoverage([{path:'app/lib/app.dart',total:100000,hit:89999}],{suites:[{root:'app',minimumLinePercent:90}]})[0];
  assert.equal(result.percent,90);
  assert.match(result.error,/below/);
});
