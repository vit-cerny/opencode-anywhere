// Dependency-free gate: controls, placement guard, atlas UV math.
// Run: node tests/verify.mjs  (from the repo root; also via npm run check)
// ponytail: assert only, no framework, mirrors browser e2e where Node can.
import assert from "node:assert";
import { createWorld, generateFlat, setBlock, raycast, tileUV } from "../src/world.js";
import { createPlayer, updatePlayer, setLook, hitsWorld, occupies } from "../src/player.js";
import { BLOCKS, isSolid } from "../src/blocks.js";

// --- controls: directions, jump, ratios (60 x 0.05s steps = 3s) ---
function walk(keys, extra) {
  var p = createPlayer({ x: 0, y: 5, z: 0 });
  setLook(p, 0, 0);
  p.keys = keys;
  if (extra) Object.assign(p, extra);
  for (var i = 0; i < 60; i++) updatePlayer(p, null, 0.05, null);
  return p.pos;
}
var r = walk({ KeyW: true });
assert.ok(Math.abs(r.x) < 1e-9 && r.z < -12, "W -Z no drift, got " + r.x + "," + r.z);
r = walk({ KeyS: true });
assert.ok(r.z > 12, "S +Z, got " + r.z);
r = walk({ KeyD: true });
assert.ok(r.x > 12, "D +X, got " + r.x);
r = walk({ KeyA: true });
assert.ok(r.x < -12, "A -X, got " + r.x);
r = walk({ KeyW: true });
assert.ok(Math.abs(r.z - -12.9) < 1e-6, "walk 4.3/s, got " + r.z);
r = walk({ KeyW: true }, { _sprint: true });
assert.ok(Math.abs(r.z - -19.35) < 1e-6, "sprint 1.5x, got " + r.z);
r = walk({ KeyW: true, ShiftLeft: true }, { _sprint: true });
assert.ok(Math.abs(r.z - -6.45) < 1e-6, "sneak overrides 0.5x, got " + r.z);
console.log("verify controls PASS");

// --- guard: straight-down raycast target refused, neighbour allowed ---
var w = createWorld(32);
generateFlat(w);
var h = raycast(w, [8.5, 5, 8.5], [0, -1, 0], 8);
assert.ok(h && h.x === 8 && h.z === 8, "raycast hits below, got " + JSON.stringify(h));
var p = createPlayer();
setLook(p, 0, 0);
p.pos.y = 4;
for (var i = 0; i < 120; i++) updatePlayer(p, w, 1 / 60, null);
assert.equal(occupies(p, 8, 1, 8), true, "own cell refused");
assert.equal(occupies(p, 8, 3, 8), false, "clear cell allowed");
assert.equal(occupies(p, 9, 1, 8), false, "side cell allowed");
setBlock(w, 8, 1, 8, 1, true);
assert.equal(hitsWorld(w, p.pos.x, p.pos.y, p.pos.z), true, "trap is real");
p.keys = { KeyW: true };
var zx = p.pos.z;
for (var j = 0; j < 60; j++) updatePlayer(p, w, 1 / 60, null);
assert.equal(p.pos.z, zx, "trapped without guard");
assert.ok(BLOCKS[10] === "water" && isSolid(10) === false, "water def");
console.log("verify guard PASS");

// --- atlas: tileUV (the real code path) keeps samples inside tiles 0/16/29 ---
[0, 16, 29].forEach(function (tile) {
  [0, 1].forEach(function (u) {
    var t = tileUV(tile, u, 0);
    var px = t[0] * 480;
    assert.ok(Math.abs((px % 1) - 0.5) < 1e-6, "tile " + tile + " u=" + u + " inside, got " + px);
  });
  var tv = tileUV(tile, 0, 1);
  assert.ok(tv[1] * 16 === 15.5, "v=1 texel center, got " + tv[1] * 16);
});
assert.equal(tileUV(29, 1, 0)[0] * 480, 479.5, "last tile inside atlas");
console.log("verify atlas PASS");
console.log("verify ok");
