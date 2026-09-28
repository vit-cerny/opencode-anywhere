# Voxel Sandbox

A playable Minecraft-Classic-like voxel game in the browser. Three.js, no build step, no dependencies.

## Play

```sh
npx serve .
```

Open the printed URL in desktop Chrome, click the landscape to capture the mouse.

## Controls

| Input | Action |
|---|---|
| Mouse | Look |
| W A S D / arrows | Walk (double-tap W to sprint) |
| Shift | Sneak (slow) |
| Space | Jump / swim up |
| Left-click | Break block |
| Right-click | Place selected block |
| 1-9, wheel, click | Pick block (slot 10: wheel/click) |
| H | Toggle help |

## Tech

- Infinite chunked terrain (16x16 chunks, radius 3, seeded value noise)
- 10 blocks, one shared texture atlas, max 2 draw materials per chunk
- Day/night cycle (5 min), drifting clouds, swim physics
- Saves seed + player edits to localStorage
- Checks: `npm run check` (node --check on all sources + smoke test)

## Mods

Enable: `import "./mods/example.js"` once before boot.

```js
defineMod({ id: 15, name: "glow", paint(ctx, S) {} });
```

- Ids 15-16 reserved for mods (defineMod throws otherwise).
- `paint(ctx, S)`: ctx is a 2d context pre-translated to a
  16x16 tile, S = 16. Paint within 0..S.
