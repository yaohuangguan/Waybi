import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.join(path.dirname(fileURLToPath(import.meta.url)), 'artifact');
const manifest = JSON.parse(await readFile(path.join(directory, 'manifest.json'), 'utf8'));
if (manifest.region !== 'NZ' || manifest.engine !== 'Valhalla 3.9.1') throw new Error('Unexpected graph manifest');
for (const name of ['valhalla_tiles.tar', 'admins.sqlite', 'timezones.sqlite']) {
  const file = path.join(directory, name);
  if ((await stat(file)).size < (name.endsWith('.tar') ? 10_000_000 : 4096)) throw new Error(`Incomplete ${name}`);
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  if (hash.digest('hex') !== manifest.hashes[name]) throw new Error(`Hash mismatch: ${name}`);
}
const config = JSON.parse(await readFile(path.join(directory, 'valhalla.json'), 'utf8'));
if (config.mjolnir.tile_extract !== '/data/valhalla_tiles.tar' ||
    config.mjolnir.admin !== '/data/admins.sqlite' || config.mjolnir.timezone !== '/data/timezones.sqlite' ||
    config.httpd.service.listen !== 'tcp://*:8002' ||
    JSON.stringify([...config.loki.actions].sort()) !== JSON.stringify(['route', 'status'])) {
  throw new Error('Unexpected serving configuration');
}
console.log(`Verified NZ graph, built ${manifest.generatedAt}; data hashes match the manifest.`);
