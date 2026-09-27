# Brief
Goal: Playable 3D voxel sandbox in browser plus loop that keeps working until human stops it.
Non-goals: Multiplayer, mobs, crafting, redstone, infinite terrain, texture packs, mobile touch, auto-deploy without user creds.
Acceptance criteria: Serve opens in desktop Chrome, pointer-lock look, WASD walk, Space jump, click break, right-click place, hotbar 1-4 select, localStorage persist, 60fps on 32x32, STATUS.md updated each cycle, never exits on its own.

# Assumptions
- Prior stop came from no persistent loop state plus blocked Oracle deploy plus swarm billing fail plus context compaction, so loop now resumes from STATUS.md and keeps building locally.
- Three.js 0.160.0 via unpkg importmap, no bundler, no npm deps.
- Single 32x32 flat world, Map key store, hidden-face culling only.
- Procedural canvas textures only, no binary assets.
- Desktop Chrome only, keyboard plus mouse, ASCII only.

# Structure
- index.html: canvas mount plus HUD plus importmap.
- styles.css: fullscreen canvas plus crosshair plus hotbar.
- src/main.js: boot scene plus loop wiring only.
- src/world.js: voxel Map store plus raycast plus mesh.
- src/player.js: pointer-lock plus WASD plus gravity.
- src/blocks.js: id table plus solidity.
- src/textures.js: canvas textures per face.
- src/ui.js: hotbar plus help plus select events.
- src/save.js: localStorage save plus load.
- package.json: serve plus smoke plus check scripts.
- tests/smoke.mjs: voxel plus block asserts.
- AGENTS.md: owned paths plus exact commands plus loop rule.
- STATUS.md: loop state resumed each cycle until human stops.

# Conventions
- ES modules only, no build step, three from CDN.
- ASCII only, short lines, stub-first.
- One mesh per world, shared materials.
- Validate input at raycast and storage load.
- Mark cuts with ponytail: comment.

# Roles
- scene-dev: owns main.js plus render loop.
- voxel-dev: owns world.js plus meshing.
- controls-dev: owns player.js movement.
- content-dev: owns blocks.js content.
- texture-dev: owns textures.js content.
- ui-dev: owns ui.js plus index.html plus styles.css split per task.
- persist-dev: owns save.js storage.
- qa-dev: owns package.json plus smoke test split per task.
- loop-dev: owns AGENTS.md plus STATUS.md split per task.

# Definition of done
- `node minecraft/tests/smoke.mjs`
- `node --check minecraft/src/main.js`
- `node --check minecraft/src/world.js`
- `node --check minecraft/src/player.js`
- `npx serve minecraft`

# Tasks
## T1 Shell page wiring
- owns: minecraft/index.html
- role: ui-dev
- do: Canvas mount HUD hotbar importmap module script.
- check: `node -e "require('fs').readFileSync('minecraft/index.html','utf8').includes('importmap')||process.exit(1)"`

## T2 Fullscreen HUD style
- owns: minecraft/styles.css
- role: ui-dev
- do: Fullscreen canvas crosshair hotbar overlay style.
- check: `node -e "require('fs').readFileSync('minecraft/styles.css','utf8').includes('#app')||process.exit(1)"`

## T3 Scene boot loop
- owns: minecraft/src/main.js
- role: scene-dev
- do: Init renderer scene light loop wiring world player ui.
- check: `node --check minecraft/src/main.js`

## T4 Voxel store mesh
- owns: minecraft/src/world.js
- role: voxel-dev
- do: Map store get set raycast flat-gen mesh builder.
- check: `node --check minecraft/src/world.js`

## T5 Walk look jump
- owns: minecraft/src/player.js
- role: controls-dev
- do: Pointer-lock WASD jump gravity collision.
- check: `node --check minecraft/src/player.js`

## T6 Block table
- owns: minecraft/src/blocks.js
- role: content-dev
- do: Grass dirt stone wood air plus solidity.
- check: `node --check minecraft/src/blocks.js`

## T7 Canvas textures
- owns: minecraft/src/textures.js
- role: texture-dev
- do: 16x16 canvas textures per block face.
- check: `node --check minecraft/src/textures.js`

## T8 Crosshair hotbar
- owns: minecraft/src/ui.js
- role: ui-dev
- do: Hotbar help selection events DOM only.
- check: `node --check minecraft/src/ui.js`

## T9 Local save load
- owns: minecraft/src/save.js
- role: persist-dev
- do: Save load Map to localStorage try-catch.
- check: `node --check minecraft/src/save.js`

## T10 Serve smoke scripts
- owns: minecraft/package.json
- role: qa-dev
- do: Serve dev and smoke check scripts.
- check: `node -e "JSON.parse(require('fs').readFileSync('minecraft/package.json','utf8')).scripts.dev||process.exit(1)"`

## T11 Voxel smoke test
- owns: minecraft/tests/smoke.mjs
- role: qa-dev
- do: Assert set get solidity persist roundtrip.
- check: `node minecraft/tests/smoke.mjs`

## T12 Agent rules
- owns: minecraft/AGENTS.md
- role: loop-dev
- do: Owned paths plus exact serve check test plus loop rule.
- check: `node -e "require('fs').readFileSync('minecraft/AGENTS.md','utf8').includes('STATUS.md')||process.exit(1)"`

## T13 Loop state
- owns: minecraft/STATUS.md
- role: loop-dev
- do: Loop resume state updated each cycle until human stops.
- check: `node -e "require('fs').readFileSync('minecraft/STATUS.md','utf8').includes('Status')||process.exit(1)"`

# Open questions
- Flat 32x32 enough or want hills?
- Keep unpkg CDN or vendor three locally?
- Where to host serve when Oracle creds missing?
