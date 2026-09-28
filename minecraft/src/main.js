import * as THREE from "three";
import { createWorld, setBlock, raycast, streamChunks } from "./world.js";
import { createPlayer, updatePlayer, attachControls, occupies } from "./player.js";
import { initUI, getSelected } from "./ui.js";
import { loadInto, saveWorld } from "./save.js";

var SIZE = 32;

function getApp() {
  return document.getElementById("app");
}

function makeRenderer(app) {
  var r = new THREE.WebGLRenderer({ antialias: true });
  r.setSize(window.innerWidth, window.innerHeight);
  r.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  r.shadowMap.enabled = true;
  r.shadowMap.type = THREE.PCFSoftShadowMap;
  app.appendChild(r.domElement);
  return r;
}

function makeScene() {
  var s = new THREE.Scene();
  s.background = null;
  s.fog = new THREE.Fog(0x87ceeb, 40, 120);
  return s;
}

function addLights(scene) {
  var hemi = new THREE.HemisphereLight(0xffffff, 0x557755, 0.9);
  scene.add(hemi);
  var sun = new THREE.DirectionalLight(0xffffff, 0.8);
  sun.position.set(20, 40, 10);
  sun.castShadow = true;
  sun.shadow.camera.left = -45;
  sun.shadow.camera.right = 45;
  sun.shadow.camera.top = 45;
  sun.shadow.camera.bottom = -45;
  sun.shadow.mapSize.set(1024, 1024);
  scene.add(sun);
  return { sun: sun, hemi: hemi };
}

var DAY = new THREE.Color(0x87ceeb);
var NIGHT = new THREE.Color(0x0b1026);
var SKY_TOP_DAY = new THREE.Color(0x87ceeb);
var SKY_BOT_DAY = new THREE.Color(0xe8f4f8);
var SKY_TOP_NIGHT = new THREE.Color(0x060a1a);
var SKY_BOT_NIGHT = new THREE.Color(0x0b1026);
var TMP = new THREE.Color();

function makeSky(scene) {
  var g = new THREE.SphereGeometry(400, 16, 12);
  var m = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    fog: false,
    depthWrite: false,
    uniforms: {
      topColor: { value: SKY_TOP_DAY.clone() },
      bottomColor: { value: SKY_BOT_DAY.clone() }
    },
    vertexShader: [
      "varying vec3 vPos;",
      "void main() {",
      "  vPos = position;",
      "  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);",
      "}"
    ].join("\n"),
    fragmentShader: [
      "uniform vec3 topColor;",
      "uniform vec3 bottomColor;",
      "varying vec3 vPos;",
      "void main() {",
      "  float h = normalize(vPos).y * 0.5 + 0.5;",
      "  gl_FragColor = vec4(mix(bottomColor, topColor, h), 1.0);",
      "}"
    ].join("\n")
  });
  var sky = new THREE.Mesh(g, m);
  // ponytail: dome follows camera; never casts shadows.
  sky.userData.noShadow = true;
  sky.frustumCulled = false;
  scene.add(sky);
  return sky;
}

function tickShadows(scene, frame) {
  if (frame % 60 !== 0) return;
  scene.traverse(function (o) {
    if (!o.isMesh) return;
    if (o.userData.noShadow) return;
    if (o.material && o.material.isShaderMaterial) return;
    o.castShadow = true;
    o.receiveShadow = true;
  });
}

function tickDay(scene, sun, hemi, sky, t) {
  var ang = 2 * Math.PI * t / 300;
  var f = 0.5 + 0.5 * Math.cos(ang);
  TMP.copy(NIGHT).lerp(DAY, f);
  scene.fog.color.copy(TMP);
  sky.material.uniforms.topColor.value.copy(SKY_TOP_NIGHT).lerp(SKY_TOP_DAY, f);
  sky.material.uniforms.bottomColor.value.copy(SKY_BOT_NIGHT).lerp(SKY_BOT_DAY, f);
  sun.intensity = 0.05 + 0.75 * f;
  hemi.intensity = 0.25 + 0.65 * f;
  sun.position.set(20 * Math.cos(ang), 40 * Math.sin(ang) + 10, 10);
}

function makeClouds(scene) {
  var g = new THREE.PlaneGeometry(12, 12);
  var m = new THREE.MeshBasicMaterial({ color: 0xffffff });
  m.transparent = true;
  m.opacity = 0.6;
  var arr = [];
  var i = 0;
  for (i = 0; i < 10; i++) {
    var c = new THREE.Mesh(g, m);
    c.rotation.x = -Math.PI / 2;
    // ponytail: clouds skip shadow flag pass.
    c.userData.noShadow = true;
    c.position.set((Math.random() * 2 - 1) * 72, 34, (Math.random() * 2 - 1) * 72);
    scene.add(c);
    arr.push(c);
  }
  return arr;
}

function tickClouds(clouds, camera, dt) {
  var i = 0;
  for (i = 0; i < clouds.length; i++) {
    var c = clouds[i];
    c.position.x += 0.5 * dt;
    if (c.position.x - camera.position.x > 72) c.position.x -= 144;
    if (c.position.x - camera.position.x < -72) c.position.x += 144;
    if (c.position.z - camera.position.z > 72) c.position.z -= 144;
    if (c.position.z - camera.position.z < -72) c.position.z += 144;
  }
}

function camDir(camera) {
  var v = new THREE.Vector3();
  camera.getWorldDirection(v);
  return [v.x, v.y, v.z];
}

function camPos(camera) {
  var p = camera.position;
  return [p.x, p.y, p.z];
}

function bindEdit(world, scene, camera, renderer, player) {
  var el = renderer.domElement;
  el.addEventListener("contextmenu", function (e) {
    e.preventDefault();
  });
  el.addEventListener("mousedown", function (e) {
    if (document.pointerLockElement !== el) return;
    var hit = raycast(world, camPos(camera), camDir(camera), 6);
    if (!hit) return;
    if (e.button === 0) {
      setBlock(world, hit.x, hit.y, hit.z, 0, true);
    } else if (e.button === 2) {
      var tx = hit.x + hit.nx, ty = hit.y + hit.ny, tz = hit.z + hit.nz;
      // ponytail: never entomb the player; vanilla blocks self-placement too.
      if (!occupies(player, tx, ty, tz)) setBlock(world, tx, ty, tz, getSelected(), true);
    } else {
      return;
    }
    // ponytail: edits-only save is tiny, so persist every edit, not just 5s.
    saveWorld(world);
    // ponytail: dirty-chunk remesh happens in the frame loop via streamChunks.
  });
}

function bindResize(renderer, camera) {
  window.addEventListener("resize", function () {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });
}

export function boot() {
  var app = getApp();
  var renderer = makeRenderer(app);
  var scene = makeScene();
  var lights = addLights(scene);
  var sun = lights.sun;
  var hemi = lights.hemi;
  var sky = makeSky(scene);
  var clouds = makeClouds(scene);
  var camera = new THREE.PerspectiveCamera(
    75,
    window.innerWidth / window.innerHeight,
    0.1,
    500
  );
  var world = createWorld(SIZE);
  loadInto(world);
  // ponytail: streamChunks generates from seed + reapplies saved edits.
  streamChunks(world, scene, 8.5, 8.5, 3, 100);
  var player = createPlayer();
  attachControls(player, renderer.domElement, camera);
  initUI();
  bindResize(renderer, camera);
  bindEdit(world, scene, camera, renderer, player);
  var clock = new THREE.Clock();
  var acc = 0;
  var dayT = 0;
  var frame = 0;
  renderer.setAnimationLoop(function () {
    var dt = Math.min(clock.getDelta(), 0.05);
    dayT += dt;
    frame++;
    // ponytail: 300s orbit drives sky, fog, sun, hemi.
    tickDay(scene, sun, hemi, sky, dayT);
    sky.position.copy(camera.position);
    tickShadows(scene, frame);
    tickClouds(clouds, camera, dt);
    // ponytail: stream first so physics never collides with unloaded air.
    streamChunks(world, scene, player.pos.x, player.pos.z, 3, 1);
    updatePlayer(player, world, dt, camera);
    acc += dt;
    if (acc > 5) {
      acc = 0;
      saveWorld(world);
    }
    renderer.render(scene, camera);
  });
  window.addEventListener("beforeunload", function () {
    saveWorld(world);
  });
  return { renderer: renderer, scene: scene, camera: camera };
}

if (typeof document !== "undefined") boot();
