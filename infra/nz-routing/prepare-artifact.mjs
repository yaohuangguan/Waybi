import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
const directory = path.join(root, 'artifact');
const container = process.argv[2] ?? 'waybi-nz-routing-valhalla-1';
if (!/^waybi-nz-routing[-\w]+$/.test(container)) throw new Error('Expected an owned NZ build container');
const docker = process.env.WAYBI_DOCKER_BIN || 'docker';
await mkdir(directory, { recursive: true });
for (const name of ['valhalla_tiles.tar', 'admins.sqlite', 'timezones.sqlite', 'valhalla.json']) {
  execFileSync(docker, ['cp', `${container}:/custom_files/${name}`, path.join(directory, name)], { stdio: 'inherit' });
}
for (const name of ['admins.sqlite', 'timezones.sqlite']) {
  const file = path.join(directory, name);
  if ((await stat(file)).size < 4096 || !(await readFile(file)).subarray(0, 16).equals(Buffer.from('SQLite format 3\0'))) {
    throw new Error(`Invalid ${name}; do not publish an incomplete graph`);
  }
}
if ((await stat(path.join(directory, 'valhalla_tiles.tar'))).size < 10_000_000) throw new Error('NZ graph is incomplete');
const configPath = path.join(directory, 'valhalla.json');
const configuration = JSON.parse((await readFile(configPath, 'utf8')).replaceAll('/custom_files', '/data'));
configuration.loki.actions = ['route', 'status'];
configuration.httpd.service.listen = 'tcp://*:8002';
configuration.logging.type = 'std_out';
configuration.logging.level = 'WARN';
await writeFile(configPath, JSON.stringify(configuration, null, 2) + '\n');
const hashes = {};
for (const name of ['valhalla_tiles.tar', 'admins.sqlite', 'timezones.sqlite']) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path.join(directory, name))) hash.update(chunk);
  hashes[name] = hash.digest('hex');
}
const manifest = { generatedAt: new Date().toISOString(), engine: 'Valhalla 3.9.1',
  region: 'NZ', source: 'https://download.geofabrik.de/australia-oceania/new-zealand.html',
  attribution: '© OpenStreetMap contributors. ODbL 1.0.', hashes };
await writeFile(path.join(directory, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log('Prepared immutable NZ routing artifact:', manifest);
