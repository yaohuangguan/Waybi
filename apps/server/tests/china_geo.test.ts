import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  allInMainlandChina, gcj02ToWgs84, gcjParameter, isMainlandChina, MAINLAND_CHINA_EXCLUSIONS,
  MAINLAND_CHINA_OUTLINE, outsideGcjExtent, parseGcjPoint, parseGcjPolyline, wgs84ToGcj02,
} from '../src/china_geo.ts';
import { distanceMeters } from '../src/geo.ts';

test('the app mirrors the exact same mainland outline and exclusions', () => {
  const dart = readFileSync(new URL('../../mobile/lib/domain/china_region.dart', import.meta.url), 'utf8');
  const block = dart.slice(dart.indexOf('// BEGIN MAINLAND_CHINA_POLYGON'), dart.indexOf('// END MAINLAND_CHINA_POLYGON'));
  const pairs = (text: string) => [...text.matchAll(/\((-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\)/g)]
    .map(match => [Number(match[1]), Number(match[2])]);
  const [outline, exclusions] = block.split('mainlandChinaExclusions');
  assert.deepEqual(pairs(outline), MAINLAND_CHINA_OUTLINE.map(point => [...point]));
  for (const [name, ring] of Object.entries(MAINLAND_CHINA_EXCLUSIONS)) {
    const start = exclusions.indexOf(`'${name}'`);
    assert.ok(start > 0, name);
    assert.deepEqual(pairs(exclusions.slice(start, exclusions.indexOf(']', start))), ring.map(point => [...point]), name);
  }
});

const MAINLAND: Record<string, [number, number]> = {
  Beijing: [116.4074, 39.9042], Shanghai: [121.4737, 31.2304], Shijiazhuang: [114.51, 38.04],
  Urumqi: [87.6168, 43.8256], Lhasa: [91.1322, 29.66], Kashgar: [75.99, 39.47], Harbin: [126.535, 45.8],
  Haikou: [110.33, 20.03], Sanya: [109.51, 18.25], Kunming: [102.83, 24.88], Nanning: [108.37, 22.82],
  Hailar: [119.76, 49.21], Manzhouli: [117.43, 49.6], Heihe: [127.497, 50.245], Mohe: [122.53, 52.97],
  'Shenzhen Futian': [114.0579, 22.5431], 'Shenzhen Luohu': [114.131, 22.548], 'Shenzhen Shekou': [113.91, 22.48],
  Zhuhai: [113.5767, 22.2707], 'Zhuhai Gongbei': [113.548, 22.222], 'Zhuhai Hengqin': [113.53, 22.12],
  Xiamen: [118.0894, 24.4798], 'Xiamen island east coast': [118.19, 24.44], 'Dadeng island': [118.33, 24.56],
  Fuzhou: [119.3, 26.08], Pingtan: [119.79, 25.5], Huangqi: [119.87, 26.33], Qingdao: [120.38, 36.07],
  Dalian: [121.61, 38.91], Dandong: [124.38, 40.13], Hunchun: [130.36, 42.87], Erenhot: [111.98, 43.65],
  Tashkurgan: [75.23, 37.77], Ruili: [97.85, 24.02], Hekou: [103.94, 22.52], Pingxiang: [106.75, 22.1],
  Dongxing: [107.97, 21.547], Weizhou: [109.1, 21.03], Zhoushan: [122.2, 30.0], Khorgas: [80.42, 44.21],
  Zhangmu: [85.98, 27.99], Yadong: [88.92, 27.48],
};

const NOT_MAINLAND: Record<string, [number, number]> = {
  'Hong Kong Central': [114.1589, 22.284], 'Tsim Sha Tsui': [114.172, 22.297], 'Tuen Mun': [113.975, 22.39],
  'Sheung Shui': [114.128, 22.501], 'Lo Wu': [114.1135, 22.5285], Lantau: [113.94, 22.26],
  'Tung Ping Chau': [114.43, 22.545], Macau: [113.5439, 22.1987], Taipa: [113.56, 22.155],
  Taipei: [121.56, 25.03], Kaohsiung: [120.3, 22.62], Penghu: [119.56, 23.57], Pratas: [116.72, 20.7],
  Kinmen: [118.3171, 24.4321], 'Lesser Kinmen': [118.24, 24.43], Guningtou: [118.3, 24.48],
  'Matsu Nangan': [119.94, 26.16], 'Matsu Beigan': [120.0, 26.22], 'Matsu Dongyin': [120.5, 26.37],
  'Matsu Juguang': [119.95, 25.96], Wuqiu: [119.45, 24.98],
  Seoul: [126.98, 37.57], Pyongyang: [125.75, 39.03], Sinuiju: [124.45, 40.08], Ulaanbaatar: [106.9, 47.9],
  'Zamyn-Uud': [111.9, 43.72], Hanoi: [105.85, 21.03], 'Lao Cai': [103.97, 22.47], 'Mong Cai': [107.96, 21.525],
  'Bach Long Vi': [107.72, 20.13], Vientiane: [102.6, 17.97], Mandalay: [96.08, 21.97], Myitkyina: [97.4, 25.38],
  Kathmandu: [85.32, 27.72], Thimphu: [89.64, 27.47], Gangtok: [88.61, 27.33], Tawang: [91.87, 27.59],
  Leh: [77.58, 34.16], Gilgit: [74.3, 35.92], Almaty: [76.9, 43.25], Bishkek: [74.6, 42.87],
  Vladivostok: [131.9, 43.12], Khabarovsk: [135.07, 48.48], Blagoveshchensk: [127.535, 50.275],
  Tokyo: [139.69, 35.69], Manila: [120.98, 14.6], Auckland: [174.76, -36.85], London: [-0.12, 51.5],
};

for (const [name, [lon, lat]] of Object.entries(MAINLAND)) {
  test(`mainland China: ${name}`, () => assert.equal(isMainlandChina(lon, lat), true));
}
for (const [name, [lon, lat]] of Object.entries(NOT_MAINLAND)) {
  test(`not mainland China: ${name}`, () => assert.equal(isMainlandChina(lon, lat), false));
}

test('a bounding box is not enough: neighbours inside China\'s bbox stay outside', () => {
  // All of these lie within the mainland's west/east/south/north extent.
  for (const name of ['Seoul', 'Pyongyang', 'Ulaanbaatar', 'Hanoi', 'Kathmandu', 'Taipei', 'Hong Kong Central']) {
    const [lon, lat] = NOT_MAINLAND[name];
    assert.ok(lon > 73 && lon < 135 && lat > 18 && lat < 54, name);
    assert.equal(isMainlandChina(lon, lat), false, name);
  }
});

test('boundary pairs a few kilometres apart resolve to different sides', () => {
  const pairs: Array<[string, string]> = [
    ['Shenzhen Futian', 'Hong Kong Central'], ['Shenzhen Luohu', 'Lo Wu'], ['Shenzhen Shekou', 'Tuen Mun'],
    ['Zhuhai Gongbei', 'Macau'], ['Zhuhai Hengqin', 'Taipa'], ['Xiamen', 'Kinmen'],
    ['Xiamen island east coast', 'Lesser Kinmen'], ['Dadeng island', 'Guningtou'], ['Huangqi', 'Matsu Beigan'],
  ];
  for (const [mainland, other] of pairs) {
    const a = MAINLAND[mainland];
    const b = NOT_MAINLAND[other];
    assert.ok(distanceMeters(a, b) < 35_000, `${mainland}/${other} are neighbours`);
    assert.equal(isMainlandChina(...a), true, mainland);
    assert.equal(isMainlandChina(...b), false, other);
  }
});

test('invalid coordinates are never mainland China', () => {
  assert.equal(isMainlandChina(Number.NaN, 30), false);
  assert.equal(isMainlandChina(114, Number.POSITIVE_INFINITY), false);
  assert.equal(allInMainlandChina([]), false);
  assert.equal(allInMainlandChina([MAINLAND.Beijing, MAINLAND.Shijiazhuang]), true);
  assert.equal(allInMainlandChina([MAINLAND['Shenzhen Futian'], NOT_MAINLAND['Hong Kong Central']]), false);
});

test('wgs84ToGcj02 matches the published reference transform', () => {
  // Reference values from the widely used coordtransform implementation.
  const [lon, lat] = wgs84ToGcj02(116.404, 39.915);
  assert.ok(Math.abs(lon - 116.41024449916938) < 1e-9);
  assert.ok(Math.abs(lat - 39.91640428150164) < 1e-9);
  // The offset in Beijing is several hundred metres, not a rounding error.
  const offset = distanceMeters([116.404, 39.915], [lon, lat]);
  assert.ok(offset > 400 && offset < 700, `${offset}`);
});

test('gcj02ToWgs84 inverts the forward transform to well below a metre', () => {
  for (const [name, point] of Object.entries(MAINLAND)) {
    const gcj = wgs84ToGcj02(...point);
    const back = gcj02ToWgs84(...gcj);
    assert.ok(distanceMeters(point, back) < 0.01, `${name}: ${distanceMeters(point, back)} m`);
  }
  // Within a metre of the common single-step approximation, and more precise.
  const approximate: [number, number] = [116.39775550083061, 39.91359571849836];
  const precise = gcj02ToWgs84(116.404, 39.915);
  assert.ok(distanceMeters(approximate, precise) < 1);
  const roundTrip = wgs84ToGcj02(...precise);
  assert.ok(distanceMeters(roundTrip, [116.404, 39.915]) < 0.001);
});

test('the datum shift is the identity outside the China extent', () => {
  assert.equal(outsideGcjExtent(174.76, -36.85), true);
  assert.deepEqual(wgs84ToGcj02(174.76, -36.85), [174.76, -36.85]);
  assert.deepEqual(gcj02ToWgs84(-0.12, 51.5), [-0.12, 51.5]);
});

test('Amap coordinate strings and polylines are parsed and converted', () => {
  const gcj = wgs84ToGcj02(114.51, 38.04);
  const parsed = parseGcjPoint(`${gcj[0]},${gcj[1]}`);
  assert.ok(parsed && distanceMeters(parsed, [114.51, 38.04]) < 0.01);
  assert.equal(parseGcjPoint(''), null);
  assert.equal(parseGcjPoint([]), null);
  assert.equal(parseGcjPoint('abc,def'), null);
  assert.equal(parseGcjPoint('200,10'), null);
  const line = parseGcjPolyline('116.41024449916938,39.91640428150164;bad;116.42,39.92');
  assert.equal(line.length, 2);
  assert.ok(distanceMeters(line[0], [116.404, 39.915]) < 0.01);
  assert.deepEqual(parseGcjPolyline(null), []);
  assert.equal(gcjParameter([116.404, 39.915]), '116.410244,39.916404');
});
