import assert from "node:assert";
import { createWorld, setBlock, getBlock } from "../src/world.js";
import { BLOCKS, isSolid } from "../src/blocks.js";
import { saveWorld, loadWorld } from "../src/save.js";
// ponytail: node shim for browser storage
const store = new Map();
globalThis.localStorage = {
  getItem: (k) => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => store.set(k, String(v)),
  removeItem: (k) => store.delete(k),
};
const w = createWorld();
assert.equal(getBlock(w, 0, 0, 0), 0);
setBlock(w, 1, 2, 3, 1, true);
assert.equal(getBlock(w, 1, 2, 3), 1);
setBlock(w, 1, 2, 3, 3, true);
assert.equal(getBlock(w, 1, 2, 3), 3);
assert.equal(isSolid(0), false);
for (const id of [1, 2, 3, 4, 5, 6, 7, 8, 9]) assert.equal(isSolid(id), true);
assert.ok(BLOCKS[1]);
assert.equal(saveWorld(w), true);
const loaded = loadWorld();
const entries = loaded instanceof Map ? loaded : loaded.blocks;
assert.equal(entries.get("1,2,3"), 3);
console.log("smoke ok");
