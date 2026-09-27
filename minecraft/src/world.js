import { isSolid } from "./blocks.js";
export const CHUNK = 16;
function key(x, y, z) { return x + "," + y + "," + z; }
function isInt(n) { return Number.isInteger(n); }
export function chunkOf(x, z) { return [Math.floor(x / CHUNK), Math.floor(z / CHUNK)]; }
export function chunkKey(cx, cz) { return cx + "," + cz; }
export function createWorld(size, seed) {
  size = size || 32;
  if (seed === undefined || !Number.isInteger(seed)) seed = 1337;
  // ponytail: edits map grows with player edits; cap if it ever matters.
  return { size: size, seed: seed, blocks: new Map(), edits: {}, chunks: {}, spill: {}, chunkMeshes: {}, dirtyChunks: {} };
}
export function getBlock(w, x, y, z) {
  if (!w || !isInt(x) || !isInt(y) || !isInt(z)) return 0;
  var v = w.blocks.get(key(x, y, z));
  return v === undefined ? 0 : v;
}
export function setBlock(w, x, y, z, id, edit) {
  if (!w || !isInt(x) || !isInt(y) || !isInt(z)) return false;
  if (!isInt(id) || id < 0 || id > 10) return false;
  var k = key(x, y, z);
  if (id === 0) w.blocks.delete(k);
  else w.blocks.set(k, id);
  if (edit) w.edits[k] = id;
  var cc = chunkOf(x, z);
  w.dirtyChunks[chunkKey(cc[0], cc[1])] = true;
  // ponytail: border edits leak into the neighbor chunk's culled faces.
  var lx = ((x % CHUNK) + CHUNK) % CHUNK, lz = ((z % CHUNK) + CHUNK) % CHUNK;
  if (lx === 0) w.dirtyChunks[chunkKey(cc[0] - 1, cc[1])] = true;
  if (lx === CHUNK - 1) w.dirtyChunks[chunkKey(cc[0] + 1, cc[1])] = true;
  if (lz === 0) w.dirtyChunks[chunkKey(cc[0], cc[1] - 1)] = true;
  if (lz === CHUNK - 1) w.dirtyChunks[chunkKey(cc[0], cc[1] + 1)] = true;
  w._dirty = true;
  return true;
}
export function hasBlock(w, x, y, z) {
  return getBlock(w, x, y, z) !== 0;
}
export function generateFlat(w, n) {
  if (!w) return w;
  n = n || w.size || 32;
  if (!Number.isInteger(n) || n <= 0) n = 32;
  var x, z;
  for (x = 0; x < n; x++) {
    for (z = 0; z < n; z++) {
      setBlock(w, x, 0, z, 1);
      setBlock(w, x, -1, z, 2);
      setBlock(w, x, -2, z, 3);
    }
  }
  return w;
}
// ponytail: Math.imul keeps 32-bit exact; plain * loses low bits past 2^53
// and biases every output below 0.5 (flat world, no h>=3, no trees).
function hash2(x, z, s) {
  var h = (Math.imul(x, 374761393) + Math.imul(z, 668265263) + Math.imul(s | 0, 974711)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h = h ^ (h >>> 16);
  return (h >>> 0) / 4294967295;
}
function smooth(t) { return t * t * (3 - 2 * t); }
function noise2(x, z, s) {
  var xi = Math.floor(x), zi = Math.floor(z);
  var xf = x - xi, zf = z - zi;
  var a = hash2(xi, zi, s), b = hash2(xi + 1, zi, s);
  var c = hash2(xi, zi + 1, s), d = hash2(xi + 1, zi + 1, s);
  var u = smooth(xf), v = smooth(zf);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function heightAt(x, z, s) {
  var n = noise2(x * 0.15, z * 0.15, s) * 0.7 + noise2(x * 0.35 + 9, z * 0.35 + 9, s) * 0.3;
  return 1 + Math.floor(n * 4);
}
function nearSpawn(x, z) {
  // ponytail: r14 pad covers every trunk whose crown could touch x1..15,z-2..8
  // (max dist^2 185); plus the 11-wide view corridor to the world edge.
  var dx = x - 8, dz = z - 8;
  if (dx * dx + dz * dz <= 196) return true;
  return Math.abs(x - 8) <= 5 && z <= 12;
}
function addTree(w, x, h, z, cx, cz) {
  var dx, dz, dy, bx, bz, bk;
  for (dy = h + 1; dy <= h + 3; dy++) {
    if (!nearSpawn(x, z)) setBlock(w, x, dy, z, 4);
  }
  for (dx = -1; dx <= 1; dx++) {
    for (dz = -1; dz <= 1; dz++) {
      bx = x + dx; bz = z + dz;
      if (nearSpawn(bx, bz)) continue;
      for (dy = h + 2; dy <= h + 3; dy++) {
        if (dx === 0 && dz === 0 && dy <= h + 3) continue;
        if (getBlock(w, bx, dy, bz) !== 0) continue;
        setBlock(w, bx, dy, bz, 5);
        // ponytail: out-of-range crown cells are tracked spill, not chunk data.
        if ((bx < cx * CHUNK || bx >= cx * CHUNK + CHUNK || bz < cz * CHUNK || bz >= cz * CHUNK + CHUNK)) {
          bk = key(bx, dy, bz);
          if (w._acc && w._acc.indexOf(bk) < 0) w._acc.push(bk);
        }
      }
    }
  }
  if (!nearSpawn(x, z) && getBlock(w, x, h + 4, z) === 0) setBlock(w, x, h + 4, z, 5);
}
function columnAt(w, x, z, cx, cz) {
  var h = heightAt(x, z, w.seed), y;
  setBlock(w, x, h, z, h <= 2 ? 6 : 1);
  for (y = h - 1; y >= h - 2 && y >= -2; y--) setBlock(w, x, y, z, 2);
  for (y = h - 3; y >= -2; y--) setBlock(w, x, y, z, 3);
  // ponytail: sea level 2 fills low columns.
  for (y = h + 1; y <= 2; y++) setBlock(w, x, y, z, 10);
  if (h >= 3 && !nearSpawn(x, z) && hash2(x * 3 + 1, z * 3 + 7, w.seed) < 0.03) {
    addTree(w, x, h, z, cx, cz);
  }
}
export function generateChunk(w, cx, cz) {
  if (!w) return null;
  var k = chunkKey(cx, cz), x, z, ek, p, id;
  if (w.chunks[k]) return k;
  w._acc = [];
  for (x = cx * CHUNK; x < cx * CHUNK + CHUNK; x++) {
    for (z = cz * CHUNK; z < cz * CHUNK + CHUNK; z++) columnAt(w, x, z, cx, cz);
  }
  w.spill[k] = w._acc;
  w._acc = null;
  // ponytail: spill lands in neighbor ranges; remesh them if loaded.
  for (var si = 0; si < w.spill[k].length; si++) {
    var sp = w.spill[k][si].split(",");
    var scc = chunkOf(+sp[0], +sp[2]);
    var sk = chunkKey(scc[0], scc[1]);
    if (sk !== k && w.chunks[sk]) w.dirtyChunks[sk] = true;
  }
  // ponytail: O(edits) scan per chunk; fine until edits get huge.
  for (ek in w.edits) {
    p = ek.split(",");
    x = +p[0]; z = +p[2];
    if (x < cx * CHUNK || x >= cx * CHUNK + CHUNK) continue;
    if (z < cz * CHUNK || z >= cz * CHUNK + CHUNK) continue;
    id = w.edits[ek];
    if (id === 0) w.blocks.delete(ek);
    else w.blocks.set(ek, id);
  }
  w.chunks[k] = true;
  w.dirtyChunks[k] = true;
  return k;
}
export function generateProcedural(w, n) {
  if (!w) return w;
  n = n || w.size || 32;
  if (!Number.isInteger(n) || n <= 0) n = 32;
  var cx, cz;
  for (cx = 0; cx * CHUNK < n; cx++) {
    for (cz = 0; cz * CHUNK < n; cz++) generateChunk(w, cx, cz);
  }
  return w;
}
// ponytail: dropping data is safe; player edits live in w.edits, save persists them.
export function dropChunk(w, scene, cx, cz) {
  if (!w) return false;
  var k = chunkKey(cx, cz);
  if (!w.chunks[k]) return false;
  disposeMesh(scene, w.chunkMeshes[k]);
  delete w.chunkMeshes[k];
  // ponytail: scan beats y-range guess; player towers exceed gen heights.
  // ponytail: edits are NOT kept here; w.edits restores them on regen.
  // ponytail: spill deletes only untouched leaves; neighbor terrain wins ties.
  var del = [];
  w.blocks.forEach(function (v, bk) {
    var p = bk.split(",");
    var x = +p[0], z = +p[2];
    if (x < cx * CHUNK || x >= cx * CHUNK + CHUNK) return;
    if (z < cz * CHUNK || z >= cz * CHUNK + CHUNK) return;
    del.push(bk);
  });
  for (var d = 0; d < del.length; d++) w.blocks.delete(del[d]);
  var sp2 = w.spill[k] || [], s2, sq;
  for (s2 = 0; s2 < sp2.length; s2++) {
    sq = sp2[s2].split(",");
    if (getBlock(w, +sq[0], +sq[1], +sq[2]) === 5) w.blocks.delete(sp2[s2]);
  }
  delete w.spill[k];
  var nx, nz, nk;
  for (nx = cx - 1; nx <= cx + 1; nx++) {
    for (nz = cz - 1; nz <= cz + 1; nz++) {
      nk = chunkKey(nx, nz);
      if (nk !== k && w.chunks[nk]) w.dirtyChunks[nk] = true;
    }
  }
  delete w.chunks[k];
  delete w.dirtyChunks[k];
  return true;
}
// ponytail: DDA raycast, validates input at boundary
export function raycast(w, o, d, maxDist) {
  if (!w || !o || !d) return null;
  if (!isFinite(o[0]) || !isFinite(o[1]) || !isFinite(o[2])) return null;
  if (!isFinite(d[0]) || !isFinite(d[1]) || !isFinite(d[2])) return null;
  maxDist = maxDist || 6;
  if (!(maxDist > 0) || maxDist > 64) maxDist = 6;
  var x = Math.floor(o[0]);
  var y = Math.floor(o[1]);
  var z = Math.floor(o[2]);
  var sx = d[0] > 0 ? 1 : -1;
  var sy = d[1] > 0 ? 1 : -1;
  var sz = d[2] > 0 ? 1 : -1;
  var tdx = d[0] !== 0 ? Math.abs(1 / d[0]) : Infinity;
  var tdy = d[1] !== 0 ? Math.abs(1 / d[1]) : Infinity;
  var tdz = d[2] !== 0 ? Math.abs(1 / d[2]) : Infinity;
  var fx = d[0] !== 0 ? (sx > 0 ? (x + 1 - o[0]) : (o[0] - x)) * tdx : Infinity;
  var fy = d[1] !== 0 ? (sy > 0 ? (y + 1 - o[1]) : (o[1] - y)) * tdy : Infinity;
  var fz = d[2] !== 0 ? (sz > 0 ? (z + 1 - o[2]) : (o[2] - z)) * tdz : Infinity;
  var nx = 0, ny = 0, nz = 0, t = 0;
  var i;
  for (i = 0; i < 128; i++) {
    if (fx < fy && fx < fz) { x += sx; t = fx; fx += tdx; nx = -sx; ny = 0; nz = 0; }
    else if (fy < fz) { y += sy; t = fy; fy += tdy; nx = 0; ny = -sy; nz = 0; }
    else { z += sz; t = fz; fz += tdz; nx = 0; ny = 0; nz = -sz; }
    if (t > maxDist) return null;
    var id = getBlock(w, x, y, z);
    if (isSolid(id)) return { x: x, y: y, z: z, nx: nx, ny: ny, nz: nz, id: id };
  }
  return null;
}
var FACES = [
  { n: [1, 0, 0], c: [[1, 0, 0], [1, 1, 0], [1, 1, 1], [1, 0, 1]] },
  { n: [-1, 0, 0], c: [[0, 0, 1], [0, 1, 1], [0, 1, 0], [0, 0, 0]] },
  { n: [0, 1, 0], c: [[0, 1, 1], [1, 1, 1], [1, 1, 0], [0, 1, 0]] },
  { n: [0, -1, 0], c: [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]] },
  { n: [0, 0, 1], c: [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]] },
  { n: [0, 0, -1], c: [[1, 0, 0], [0, 0, 0], [0, 1, 0], [1, 1, 0]] }
];
// ponytail: bounds limit the scan to one chunk; omitted bounds keep whole-map behavior.
export function buildGeometry(w, x0, x1, z0, z1) {
  var pos = [], nor = [], uv = [], idx = [], tiles = [];
  if (!w) return { pos: pos, nor: nor, uv: uv, idx: idx, tiles: tiles };
  var bounded = isInt(x0) && isInt(x1) && isInt(z0) && isInt(z1);
  var done = 0;
  w.blocks.forEach(function (id, k) {
    var p = k.split(",");
    var x = +p[0], y = +p[1], z = +p[2];
    if (bounded && (x < x0 || x >= x1 || z < z0 || z >= z1)) return;
    var f;
    for (f = 0; f < 6; f++) {
      var n = FACES[f].n;
      var nb = getBlock(w, x + n[0], y + n[1], z + n[2]);
      if (isSolid(nb)) continue;
      // ponytail: water shows only faces touching air, hides water-water seams.
      if (id === 10 && nb !== 0) continue;
      var base = pos.length / 3;
      var c = FACES[f].c;
      var q;
      for (q = 0; q < 4; q++) {
        pos.push(x + c[q][0], y + c[q][1], z + c[q][2]);
        nor.push(n[0], n[1], n[2]);
        uv.push(q === 0 || q === 3 ? 0 : 1, q < 2 ? 0 : 1);
      }
      idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
      tiles.push(id, f);
      done++;
    }
  });
  return { pos: pos, nor: nor, uv: uv, idx: idx, tiles: tiles };
}
export function countVoxels(w) { return w ? w.blocks.size : 0; }
// ponytail: sync data rebuild for tests, no three import.
export function rebuild(w) { return buildGeometry(w); }
function faceName(ny) {
  if (ny > 0) return "top";
  if (ny < 0) return "bottom";
  return "side";
}
// ponytail: async three wiring, keeps node smoke free of CDN.
export function refreshMesh(w, scene) {
  if (!w || !scene) return false;
  if (typeof window === "undefined") return false;
  w._dirty = false;
  Promise.all([import("three"), import("./textures.js")]).then(function (m) {
    var mesh = meshFromGeometry(m[0], m[1], buildGeometry(w));
    disposeMesh(scene, w._mesh);
    w._mesh = mesh;
    if (mesh) scene.add(mesh);
  });
  return true;
}
// ponytail: one shared atlas, max 2 materials (opaque + water). Old per-bucket
// materials are disposed by callers via disposeMesh (fixes the GPU leak).
export function disposeMesh(scene, mesh) {
  if (!mesh) return;
  try { if (scene) scene.remove(mesh); } catch (e) {}
  try { if (mesh.geometry) mesh.geometry.dispose(); } catch (e) {}
  try {
    var ms = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    for (var i = 0; i < ms.length; i++) { if (ms[i]) ms[i].dispose(); }
  } catch (e) {}
}
function meshFromGeometry(THREE, tex, g) {
  if (!g.idx.length) return null;
  var atlas = tex.getAtlas(), nt = tex.tileCount(), TS = tex.TILE;
  var nf = g.idx.length / 6;
  var pos = [], nor = [], uv = [], oidx = [], widx = [], count = 0;
  var f, v, id, tile, wet, uu, vv;
  for (f = 0; f < nf; f++) {
    id = g.tiles[f * 2];
    wet = id === 10;
    tile = tex.tileIndex(id, faceName(FACES[g.tiles[f * 2 + 1]].n[1]));
    var base = count * 4;
    for (v = 0; v < 4; v++) {
      // ponytail: half-texel inset keeps edge samples inside the tile.
      uu = (tile * TS + 0.5 + g.uv[(f * 4 + v) * 2] * (TS - 1)) / (nt * TS);
      vv = (0.5 + g.uv[(f * 4 + v) * 2 + 1] * (TS - 1)) / TS;
      pos.push(g.pos[(f * 4 + v) * 3], g.pos[(f * 4 + v) * 3 + 1], g.pos[(f * 4 + v) * 3 + 2]);
      nor.push(g.nor[(f * 4 + v) * 3], g.nor[(f * 4 + v) * 3 + 1], g.nor[(f * 4 + v) * 3 + 2]);
      uv.push(uu, vv);
    }
    if (wet) widx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    else oidx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    count++;
  }
  var geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  geo.setAttribute("normal", new THREE.Float32BufferAttribute(nor, 3));
  geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  var mats = [];
  var mat0 = new THREE.MeshLambertMaterial({ map: atlas });
  mats.push(mat0);
  geo.addGroup(0, oidx.length, 0);
  var idx = oidx;
  if (widx.length) {
    var mat1 = new THREE.MeshLambertMaterial({ map: atlas, transparent: true, opacity: 0.7 });
    mats.push(mat1);
    geo.addGroup(oidx.length, widx.length, 1);
    idx = oidx.concat(widx);
  }
  geo.setIndex(idx);
  geo.computeBoundingSphere();
  return new THREE.Mesh(geo, mats.length > 1 ? mats : mat0);
}
export function refreshChunk(w, scene, cx, cz) {
  if (!w) return null;
  var k = chunkKey(cx, cz);
  var g = buildGeometry(w, cx * CHUNK, cx * CHUNK + CHUNK, cz * CHUNK, cz * CHUNK + CHUNK);
  delete w.dirtyChunks[k];
  if (typeof window === "undefined" || !scene) return k;
  Promise.all([import("three"), import("./textures.js")]).then(function (m) {
    // ponytail: drop-during-build guard; a stale upload must not resurrect.
    if (!w.chunks[k]) return;
    var mesh = meshFromGeometry(m[0], m[1], g);
    disposeMesh(scene, w.chunkMeshes[k]);
    if (mesh) { w.chunkMeshes[k] = mesh; scene.add(mesh); }
    else delete w.chunkMeshes[k];
  });
  return k;
}
// ponytail: data ensure is sync and complete; only mesh builds take budget.
export function streamChunks(w, scene, px, pz, radius, budget) {
  var out = { ensured: [], dropped: [], built: [], chunks: 0 };
  if (!w) return out;
  if (!isFinite(px) || !isFinite(pz)) return out;
  if (!Number.isInteger(radius) || radius < 0) radius = 3;
  if (!Number.isInteger(budget) || budget < 1) budget = 1;
  var pc = chunkOf(Math.floor(px), Math.floor(pz));
  var need = {}, dx, dz, k;
  for (dx = -radius; dx <= radius; dx++) {
    for (dz = -radius; dz <= radius; dz++) {
      need[chunkKey(pc[0] + dx, pc[1] + dz)] = true;
    }
  }
  for (k in w.chunks) {
    if (need[k]) continue;
    var p = k.split(",");
    var d = Math.max(Math.abs(+p[0] - pc[0]), Math.abs(+p[1] - pc[1]));
    if (d > radius + 1 && dropChunk(w, scene, +p[0], +p[1])) out.dropped.push(k);
  }
  for (k in need) {
    if (w.chunks[k]) continue;
    var q = k.split(",");
    generateChunk(w, +q[0], +q[1]);
    out.ensured.push(k);
  }
  var dirty = [];
  for (k in need) {
    if (!w.dirtyChunks[k] || !w.chunks[k]) continue;
    var r = k.split(",");
    dirty.push({ k: k, d: Math.max(Math.abs(+r[0] - pc[0]), Math.abs(+r[1] - pc[1])) });
  }
  dirty.sort(function (a, b) { return a.d - b.d; });
  for (var i = 0; i < dirty.length && out.built.length < budget; i++) {
    var s = dirty[i].k.split(",");
    refreshChunk(w, scene, +s[0], +s[1]);
    out.built.push(dirty[i].k);
  }
  out.chunks = Object.keys(w.chunks).length;
  return out;
}
export function buildMesh(w, scene) {
  if (!w || !scene) return null;
  if (!w._mesh) {
    try { refreshMesh(w, scene); } catch (e) { return null; }
  } else if (w._dirty) {
    try { refreshMesh(w, scene); } catch (e) {}
  }
  return w._mesh || null;
}
export function update(w, scene) {
  if (w && w._dirty && scene) refreshMesh(w, scene);
  return false;
}
