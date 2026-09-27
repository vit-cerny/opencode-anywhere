import { isSolid, WATER } from "./blocks.js";
import { getBlock } from "./world.js";

export const EYE = 1.62;
export const SPEED = 4.3;
export const JUMP = 8.0;
export const GRAV = 22.0;
const HALF = 0.3;
const HEIGHT = 1.8;

function spawnOf(s) {
  if (s && typeof s.x === "number") return { x: s.x, y: s.y, z: s.z };
  if (Array.isArray(s)) return { x: s[0], y: s[1], z: s[2] };
  return { x: 8.5, y: 8.0, z: 8.5 };
}

export function createPlayer(spawn) {
  return {
    pos: spawnOf(spawn),
    yaw: 0,
    pitch: 0,
    vy: 0,
    onGround: false,
    keys: {},
    _lastW: 0,
    _sprint: false,
  };
}

export function setLook(p, yaw, pitch) {
  p.yaw = yaw;
  const lim = 1.55;
  p.pitch = Math.max(-lim, Math.min(lim, pitch));
  return p;
}

function solidAt(world, x, y, z) {
  let id = 0;
  try {
    id = getBlock(world, x, y, z);
  } catch {
    return false;
  }
  return isSolid(id);
}

// ponytail: waist-deep check drives swim physics, nothing else.
function inWater(world, p) {
  if (!world) return false;
  let id = 0;
  try {
    id = getBlock(world, Math.floor(p.pos.x), Math.floor(p.pos.y + 0.5), Math.floor(p.pos.z));
  } catch {
    return false;
  }
  return id === WATER;
}

export function hitsWorld(world, px, py, pz) {
  const x0 = Math.floor(px - HALF);
  const x1 = Math.floor(px + HALF);
  const y0 = Math.floor(py);
  const y1 = Math.floor(py + HEIGHT);
  const z0 = Math.floor(pz - HALF);
  const z1 = Math.floor(pz + HALF);
  for (let x = x0; x <= x1; x++) {
    for (let y = y0; y <= y1; y++) {
      for (let z = z0; z <= z1; z++) {
        if (solidAt(world, x, y, z)) return true;
      }
    }
  }
  return false;
}

function moveAxis(world, p, ax, amt) {
  if (!amt) return;
  const n = { x: p.pos.x, y: p.pos.y, z: p.pos.z };
  n[ax] += amt;
  if (!hitsWorld(world, n.x, n.y, n.z)) {
    p.pos[ax] = n[ax];
    return;
  }
  // ponytail: step in small increments to slide near walls
  const steps = Math.ceil(Math.abs(amt) / 0.05);
  for (let i = 0; i < steps; i++) {
    const t = { x: p.pos.x, y: p.pos.y, z: p.pos.z };
    t[ax] += amt / steps;
    if (hitsWorld(world, t.x, t.y, t.z)) break;
    p.pos[ax] = t[ax];
  }
}

export function movePlayer(p, dx, dz) {
  const s = Math.sin(p.yaw);
  const c = Math.cos(p.yaw);
  p.pos.x += dx * c - dz * s;
  p.pos.z += dz * c + dx * s;
  return p;
}

function wishDir(p) {
  const k = p.keys;
  let f = 0;
  let s = 0;
  if (k.KeyW || k.ArrowUp) f += 1;
  if (k.KeyS || k.ArrowDown) f -= 1;
  if (k.KeyD || k.ArrowRight) s += 1;
  if (k.KeyA || k.ArrowLeft) s -= 1;
  const len = Math.hypot(f, s);
  if (len > 0) {
    f /= len;
    s /= len;
  }
  const sy = Math.sin(p.yaw);
  const cy = Math.cos(p.yaw);
  // ponytail: camera faces -Z at yaw 0, so forward is (-sin,-cos).
  return { x: s * cy - f * sy, z: -(f * cy + s * sy) };
}

export function updatePlayer(p, world, dt, camera) {
  const step = Math.max(0, Math.min(dt || 0.016, 0.05));
  const w = wishDir(p);
  const wet = inWater(world, p);
  const drag = wet ? 0.6 : 1;
  const k = p.keys;
  const fwd = k.KeyW || k.ArrowUp;
  // ponytail: sneak halves speed, overrides sprint.
  let mult = 1;
  if (k.ShiftLeft || k.ShiftRight) mult = 0.5;
  else if (p._sprint && fwd) mult = 1.5;
  if (!fwd) p._sprint = false;
  moveAxis(world, p, "x", w.x * SPEED * mult * drag * step);
  moveAxis(world, p, "z", w.z * SPEED * mult * drag * step);
  if (!wet && (k.Space) && p.onGround) {
    p.vy = JUMP;
    p.onGround = false;
  }
  if (wet) {
    if (k.Space) p.vy = 3.5;
    else {
      p.vy -= 8 * step;
      if (p.vy < -3) p.vy = -3;
    }
  } else {
    p.vy -= GRAV * step;
    if (p.vy < -20) p.vy = -20;
  }
  const before = p.pos.y;
  moveAxis(world, p, "y", p.vy * step);
  if (p.pos.y === before && p.vy <= 0) {
    p.vy = 0;
    p.onGround = true;
  } else if (p.vy !== 0) {
    p.onGround = false;
  }
  if (camera) syncCamera(p, camera);
  return p;
}

export function syncCamera(p, camera) {
  camera.position.set(p.pos.x, p.pos.y + EYE, p.pos.z);
  camera.rotation.order = "YXZ";
  camera.rotation.y = p.yaw;
  camera.rotation.x = p.pitch;
  camera.rotation.z = 0;
  return camera;
}

export function requestLock(el) {
  if (!el || !el.requestPointerLock) return;
  try {
    const r = el.requestPointerLock();
    if (r && r.catch) r.catch(() => {});
  } catch {}
}

export function update(p, camera, dt) {
  return updatePlayer(p, null, dt, camera);
}

export function tick(p, dt) {
  return updatePlayer(p, null, dt, null);
}

export function attachControls(p, el, camera) {
  if (!el || typeof window === "undefined") return () => {};
  const doc = el.ownerDocument || document;
  function onClick() {
    if (doc.pointerLockElement !== el && el.requestPointerLock) {
      try {
        const r = el.requestPointerLock();
        if (r && r.catch) r.catch(() => {});
      } catch {}
    }
  }
  function onMove(e) {
    if (doc.pointerLockElement !== el) return;
    setLook(p, p.yaw - e.movementX * 0.0025, p.pitch - e.movementY * 0.0025);
    if (camera) syncCamera(p, camera);
  }
  function onKey(e, down) {
    if (e.code === "Space") e.preventDefault();
    // ponytail: double-tap W/Up sprints, no Ctrl (browser hijack).
    const fk = e.code === "KeyW" || e.code === "ArrowUp";
    if (down && fk && !e.repeat) {
      const now = Date.now();
      if (now - (p._lastW || 0) < 300) p._sprint = true;
      p._lastW = now;
    }
    p.keys[e.code] = down;
    if (!down && fk) {
      if (!p.keys.KeyW && !p.keys.ArrowUp) p._sprint = false;
    }
  }
  const kd = (e) => onKey(e, true);
  const ku = (e) => onKey(e, false);
  el.addEventListener("click", onClick);
  doc.addEventListener("mousemove", onMove);
  doc.addEventListener("keydown", kd);
  doc.addEventListener("keyup", ku);
  return function detach() {
    el.removeEventListener("click", onClick);
    doc.removeEventListener("mousemove", onMove);
    doc.removeEventListener("keydown", kd);
    doc.removeEventListener("keyup", ku);
  };
}
