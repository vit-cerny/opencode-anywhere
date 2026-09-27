// ui: hotbar help selection events, DOM only.
// ponytail: no deps, guards for node --check.
import { BLOCKS } from "./blocks.js";
export let selected = 1;
// ponytail: slot 10 has no digit key (keys 1-9); wheel and click reach it.
const IDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
function doc() {
  return typeof document === "undefined" ? null : document;
}
function slots() {
  const d = doc();
  return d ? Array.from(d.querySelectorAll("#hotbar .slot")) : [];
}
function paint() {
  const d = doc();
  if (!d) return;
  for (const s of slots()) {
    const i = Number(s.dataset.i);
    s.classList.toggle("sel", i === selected);
    s.textContent = i + ":" + (BLOCKS[i] || i);
    s.setAttribute("aria-selected", i === selected ? "true" : "false");
  }
  const hud = d.getElementById("hud");
  if (hud) hud.dataset.slot = String(selected);
}
export function getSelected() { return selected; }
export function setHotbar(n) {
  if (n === undefined || n === null) { paint(); return selected; }
  n = Number(n);
  if (!IDS.includes(n)) return selected;
  selected = n;
  paint();
  return selected;
}
export function onPick(fn) {
  const d = doc();
  if (d) d.addEventListener("uipick", (e) => fn(e.detail));
}
function pick(n, src) {
  const d = doc();
  if (!d || !IDS.includes(n)) return;
  selected = n;
  paint();
  d.dispatchEvent(new CustomEvent("uipick", { detail: n }));
  if (src && src.blur) src.blur();
}
function helpEl() {
  const d = doc();
  return d ? d.getElementById("help") : null;
}
export function toggleHelp() {
  const h = helpEl();
  if (h) h.hidden = !h.hidden;
}
export function hideHelp() {
  const h = helpEl();
  if (h) h.hidden = true;
}
export function showHelp() {
  const h = helpEl();
  if (h) h.hidden = false;
}
export function initUI() {
  const d = doc();
  if (!d) return null;
  paint();
  d.addEventListener("keydown", (e) => {
    if (e.key >= "1" && e.key <= "9") pick(Number(e.key));
    if (e.key === "h" || e.key === "H") toggleHelp();
  });
  d.addEventListener("wheel", (e) => {
    const i = IDS.indexOf(selected);
    const s = e.deltaY > 0 ? 1 : -1;
    pick(IDS[(i + s + IDS.length) % IDS.length]);
  }, { passive: true });
  for (const s of slots()) {
    s.setAttribute("tabindex", "0");
    s.addEventListener("click", () => pick(Number(s.dataset.i), s));
    s.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") pick(Number(s.dataset.i), s);
    });
  }
  const help = d.getElementById("help");
  if (help) help.addEventListener("click", () => hideHelp());
  return d.getElementById("hud");
}
