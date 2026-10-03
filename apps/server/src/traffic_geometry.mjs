// Build-time road matching. Live requests only read the resulting geometry.
// OSM node IDs preserve connectivity; nearby parallel carriageways never join.
const R = 6371000;
const rad = Math.PI / 180;
export function distance(a, b) {
  const x = (a[0] - b[0]) * rad * Math.cos((a[1] + b[1]) * rad / 2);
  const y = (a[1] - b[1]) * rad;
  return Math.hypot(x, y) * R;
}
function project(p, a, b) {
  const cos = Math.cos(p[1] * rad);
  const dx = (b[0] - a[0]) * cos, dy = b[1] - a[1];
  const t = Math.max(0, Math.min(1,
    ((p[0] - a[0]) * cos * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy || 1)));
  const point = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
  return { point, t, distance: distance(p, point) };
}
class Heap {
  values = [];
  push(v) {
    let i = this.values.length; this.values.push(v);
    while (i > 0) {
      const parent = (i - 1) >> 1;
      if (this.values[parent][0] <= v[0]) break;
      this.values[i] = this.values[parent]; i = parent;
    }
    this.values[i] = v;
  }
  pop() {
    const first = this.values[0], last = this.values.pop();
    if (this.values.length) {
      let i = 0;
      while (i * 2 + 1 < this.values.length) {
        let child = i * 2 + 1;
        if (child + 1 < this.values.length && this.values[child + 1][0] < this.values[child][0]) child++;
        if (this.values[child][0] >= last[0]) break;
        this.values[i] = this.values[child]; i = child;
      }
      this.values[i] = last;
    }
    return first;
  }
}
export function createRoadGraph(elements) {
  const graph = new Map(), edges = [];
  const add = (a, b, length, pa, pb) => {
    if (!graph.has(a)) graph.set(a, []);
    const edge = { a, b, length, pa, pb };
    graph.get(a).push(edge); edges.push(edge);
  };
  for (const way of elements) {
    if (way.type !== 'way' || !Array.isArray(way.geometry) || !Array.isArray(way.nodes)) continue;
    for (let i = 1; i < way.geometry.length; i++) {
      const pa = [way.geometry[i - 1].lon, way.geometry[i - 1].lat];
      const pb = [way.geometry[i].lon, way.geometry[i].lat];
      const length = distance(pa, pb);
      if (!Number.isFinite(length) || !length) continue;
      const reverse = way.tags?.oneway === '-1';
      const oneWay = reverse || ['yes', '1', 'true'].includes(way.tags?.oneway) || way.tags?.junction === 'roundabout';
      if (!reverse) add(way.nodes[i - 1], way.nodes[i], length, pa, pb);
      if (!oneWay || reverse) add(way.nodes[i], way.nodes[i - 1], length, pb, pa);
    }
  }
  return { graph, edges };
}
export function matchTrafficGeometry(network, start, end, maxSnap = 130) {
  const candidates = (p) => network.edges.map(edge => ({ edge, ...project(p, edge.pa, edge.pb) }))
    .filter(c => c.distance <= maxSnap).sort((a, b) => a.distance - b.distance).slice(0, 12);
  const starts = candidates(start), ends = candidates(end);
  if (!starts.length || !ends.length) return null;
  const costs = new Map(), parents = new Map(), queue = new Heap();
  const directDistance = distance(start, end), limit = directDistance * 2.3 + 500;
  let best = null;
  for (const s of starts) {
    const cost = s.edge.length * (1 - s.t) + s.distance * 8;
    if (cost < (costs.get(s.edge.b) ?? Infinity)) {
      costs.set(s.edge.b, cost); parents.set(s.edge.b, { root: s }); queue.push([cost, s.edge.b]);
    }
    for (const e of ends) {
      if (s.edge === e.edge && e.t >= s.t) {
        const score = (e.t - s.t) * s.edge.length + (s.distance + e.distance) * 8;
        if (!best || score < best.score) best = { score, coordinates: [s.point, e.point] };
      }
    }
  }
  while (queue.values.length) {
    const [cost, node] = queue.pop();
    if (cost !== costs.get(node) || cost > limit || (best && cost >= best.score)) continue;
    for (const e of ends.filter(e => e.edge.a === node)) {
      const score = cost + e.edge.length * e.t + e.distance * 8;
      if (!best || score < best.score) {
        const tail = []; let n = node;
        while (parents.get(n)?.edge) {
          const parent = parents.get(n); tail.push(parent.edge.pb); n = parent.edge.a;
        }
        const root = parents.get(n)?.root;
        if (root) best = { score, coordinates: [root.point, root.edge.pb, ...tail.reverse(), e.point] };
      }
    }
    for (const edge of network.graph.get(node) || []) {
      const next = cost + edge.length;
      if (next < (costs.get(edge.b) ?? Infinity) && next <= limit) {
        costs.set(edge.b, next); parents.set(edge.b, { edge }); queue.push([next, edge.b]);
      }
    }
  }
  if (!best || best.coordinates.length < 2) return null;
  const coordinates = best.coordinates.filter((p, i, all) => !i || distance(p, all[i - 1]) > 0.1);
  const length = coordinates.slice(1).reduce((sum, p, i) => sum + distance(p, coordinates[i]), 0);
  if (length < directDistance * .85 || length > limit || coordinates.length < 2) return null;
  return coordinates;
}
