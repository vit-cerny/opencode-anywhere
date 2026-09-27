import * as THREE from "three";
const S = 16;
const cache = new Map();
function rnd(x, y, s) {
  let h = (x * 374761393 + y * 668265263 + s * 974634) | 0;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) >>> 0) / 4294967295;
}
function px(ctx, x, y, c) {
  ctx.fillStyle = c;
  ctx.fillRect(x, y, 1, 1);
}
function shade(base, v) {
  const n = Math.round((v - 0.5) * 24);
  const r = Math.max(0, Math.min(255, base[0] + n));
  const g = Math.max(0, Math.min(255, base[1] + n));
  const b = Math.max(0, Math.min(255, base[2] + n));
  return "rgb(" + r + "," + g + "," + b + ")";
}
function draw(id, face, ctx) {
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const v = rnd(x, y, id * 7 + face.length);
      let c = "#888";
      if (id === 1 && face === "top") c = shade([106, 170, 64], v);
      else if (id === 1 && face === "side") {
        c = y < 4 ? shade([106, 170, 64], v) : shade([134, 96, 67], v);
      }
      else if (id === 1) c = shade([134, 96, 67], v);
      else if (id === 2) c = shade([134, 96, 67], v);
      else if (id === 3) c = shade([128, 128, 128], v);
      else if (id === 4) {
        c = (x % 4 === 0) ? shade([90, 60, 35], v) : shade([110, 75, 45], v);
      }
      else if (id === 5) {
        c = (v < 0.15) ? shade([30, 70, 25], v) : shade([55, 130, 45], v);
      }
      else if (id === 6) c = shade([220, 200, 140], v);
      else if (id === 7) {
        c = (y % 4 === 3) ? shade([80, 55, 30], v) : shade([150, 110, 60], v);
      }
      else if (id === 8) {
        const row = (y >> 2), off = (row % 2) * 2;
        c = (y % 4 === 3 || (x + off) % 4 === 3) ? shade([180, 170, 165], v) : shade([165, 70, 55], v);
      }
      else if (id === 9) {
        c = (x === 0 || y === 0 || x === 15 || y === 15) ? shade([200, 220, 230], v) : shade([225, 240, 245], v);
      }
      else if (id === 10) c = shade([60, 120, 200], v);
      px(ctx, x, y, c);
    }
  }
}
export function faceOf(id, ny) {
  if (!Number.isInteger(id) || id < 1 || id > 10) return "side";
  if (ny > 0) return "top";
  if (ny < 0) return "bottom";
  return "side";
}
function normFace(face) {
  if (face === "top" || face === "bottom") return face;
  return "side";
}
function normId(id) {
  if (id >= 1 && id <= 10) return id;
  return 3;
}
export function makeTexture(id, face) {
  id = normId(id);
  face = normFace(face);
  const key = id + ":" + face;
  if (cache.has(key)) return cache.get(key);
  const cv = document.createElement("canvas");
  cv.width = S;
  cv.height = S;
  draw(id, face, cv.getContext("2d"));
  const tx = new THREE.CanvasTexture(cv);
  tx.magFilter = THREE.NearestFilter;
  tx.minFilter = THREE.NearestFilter;
  tx.colorSpace = THREE.SRGBColorSpace;
  cache.set(key, tx);
  return tx;
}
const FACES3 = ["top", "side", "bottom"];
export function tileCount() { return 30; }
export function tileIndex(id, face) {
  if (!Number.isInteger(id) || id < 1 || id > 10) id = 3;
  var f = FACES3.indexOf(face);
  if (f < 0) f = 1;
  return (id - 1) * 3 + f;
}
var atlas = null;
export function getAtlas() {
  if (atlas) return atlas;
  var cv = document.createElement("canvas");
  cv.width = S * tileCount();
  cv.height = S;
  var ctx = cv.getContext("2d");
  var id, f;
  for (id = 1; id <= 10; id++) {
    for (f = 0; f < 3; f++) {
      ctx.save();
      ctx.translate(((id - 1) * 3 + f) * S, 0);
      draw(id, FACES3[f], ctx);
      ctx.restore();
    }
  }
  atlas = new THREE.CanvasTexture(cv);
  atlas.magFilter = THREE.NearestFilter;
  atlas.minFilter = THREE.NearestFilter;
  atlas.colorSpace = THREE.SRGBColorSpace;
  return atlas;
}
export function clearCache() { cache.clear(); atlas = null; }
