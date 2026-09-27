# minecraft AGENTS

Scope: docs only. Do not change behaviour.

## Owned paths
- scene-dev: src/main.js
- voxel-dev: src/world.js
- controls-dev: src/player.js
- content-dev: src/blocks.js
- texture-dev: src/textures.js
- ui-dev: index.html, styles.css, src/ui.js
- persist-dev: src/save.js
- qa-dev: package.json, tests/smoke.mjs
- loop-dev: AGENTS.md, STATUS.md

## Rules
- Stub-first, no deps except three CDN.
- Edit only owned paths.
- ASCII only, short lines.
- ES modules only, no build step.

## Serve
- `npx serve minecraft`

## Check
- `node --check minecraft/src/main.js`
- `node --check minecraft/src/world.js`
- `node --check minecraft/src/player.js`
- `node --check minecraft/src/blocks.js`
- `node --check minecraft/src/textures.js`
- `node --check minecraft/src/ui.js`
- `node --check minecraft/src/save.js`

## Test
- `node minecraft/tests/smoke.mjs`

## Loop
- Keep working until human stops.
- Resume from STATUS.md each cycle.
- Update STATUS.md each cycle.
- Never exit on your own.
