// persist-dev: localStorage save/load for seed + player edits.
// ponytail: try-catch only, no deps. Generated terrain replays from seed;
// only player edits are stored, so saves stay small forever.
var KEY = "mc-save-v2";
var LEGACY_KEY = "mc-save-v2-legacy";
var MAX_ENTRIES = 32 * 32 * 16;
function okKey(k) {
  var p = String(k).split(",");
  if (p.length !== 3) return false;
  for (var i = 0; i < 3; i++) {
    if (!/^-?\d+$/.test(p[i])) return false;
  }
  return true;
}
function okId(id) {
  return id === 0 || id === 1 || id === 2 || id === 3 || id === 4 ||
    id === 5 || id === 6 || id === 7 || id === 8 || id === 9 || id === 10;
}
function okSeed(s) {
  return typeof s === "number" && isFinite(s) && Math.floor(s) === s;
}
function store() {
  try {
    if (typeof localStorage === "undefined") return null;
    return localStorage;
  } catch (e) {
    return null;
  }
}
function randomSeed() {
  return Math.floor(Math.random() * 2147483647);
}
function cleanEdits(obj) {
  var e = {}, n = 0, k;
  if (!obj || typeof obj !== "object") return e;
  for (k in obj) {
    if (!okKey(k) || !okId(obj[k])) continue;
    e[k] = obj[k];
    n++;
    if (n >= MAX_ENTRIES) break;
  }
  return e;
}
function editsFromLegacy(arr) {
  var e = {}, n = 0, i, k, v;
  if (!Array.isArray(arr)) return e;
  for (i = 0; i < arr.length; i++) {
    if (!arr[i] || arr[i].length < 2) continue;
    k = arr[i][0]; v = arr[i][1];
    if (!okKey(k) || !okId(v)) continue;
    e[String(k)] = v;
    n++;
    if (n >= MAX_ENTRIES) break;
  }
  return e;
}
export function saveWorld(w) {
  try {
    var s = store();
    if (!s || !w || !okSeed(w.seed)) return false;
    if (!w.edits || typeof w.edits !== "object") return false;
    s.setItem(KEY, JSON.stringify({ seed: w.seed, edits: cleanEdits(w.edits) }));
    return true;
  } catch (e) {
    return false;
  }
}
// ponytail: legacy API kept for smoke; returns saved player edits as a Map.
export function loadWorld() {
  var m = new Map(), k, raw, o, e;
  try {
    var s = store();
    if (!s) return m;
    raw = s.getItem(KEY);
    if (!raw) return m;
    o = JSON.parse(raw);
    if (o && okSeed(o.seed)) e = cleanEdits(o.edits);
    else if (Array.isArray(o)) e = editsFromLegacy(o);
    else return m;
    for (k in e) m.set(k, e[k]);
  } catch (e2) {
  }
  return m;
}
export function loadInto(w) {
  try {
    if (!w) return false;
    if (!(w.blocks instanceof Map)) w.blocks = new Map();
    if (!w.edits || typeof w.edits !== "object") w.edits = {};
    var s = store();
    if (!s) {
      if (!okSeed(w.seed)) w.seed = randomSeed();
      return false;
    }
    var raw = s.getItem(KEY);
    if (raw) {
      var o = JSON.parse(raw);
      if (o && okSeed(o.seed) && o.edits && typeof o.edits === "object") {
        w.seed = o.seed;
        w.edits = cleanEdits(o.edits);
        w.blocks = new Map();
        return true;
      }
      if (Array.isArray(o)) {
        try { s.setItem(LEGACY_KEY, raw); } catch (e) {}
        w.edits = editsFromLegacy(o);
        if (!okSeed(w.seed)) w.seed = randomSeed();
        w.blocks = new Map();
        return true;
      }
    }
    if (!okSeed(w.seed)) w.seed = randomSeed();
    w.edits = {};
    return false;
  } catch (e) {
    return false;
  }
}
export function clearSave() {
  try {
    var s = store();
    if (!s) return false;
    s.removeItem(KEY);
    s.removeItem(LEGACY_KEY);
    return true;
  } catch (e) {
    return false;
  }
}
