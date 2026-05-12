# Pet themes

Each subfolder is one theme: `cat/`, `dog/`, `bunny/`, etc. The renderer
auto-discovers any folder with at least one valid `working.*` or `idle.*`
file and lists it in the tray menu (Pet ▶ submenu) and the `/pet list`
slash command.

## File layout

```
pet-app/assets/pets/
├── cat/
│   ├── working.svg   # default art (shipped)
│   ├── idle.svg
│   ├── working.gif   # optional user override (raster beats svg)
│   └── idle.png
├── dog/
│   ├── working.svg
│   └── idle.svg
└── bunny/
    ├── working.svg
    └── idle.svg
```

Extension priority (per state): `gif → webp → apng → png → svg`. A raster
file dropped in beside the shipped SVG silently overrides it on the next
restart. So you can keep the SVG for fallback and ship your custom GIF
on top.

## Adding a new theme

1. Make a new subfolder under `pet-app/assets/pets/<name>/`.
2. Drop `working.<ext>` and `idle.<ext>` into it. One of each state is
   enough; the other falls back to the shipped cat SVG.
3. Restart the pet (tray → Quit → next hook respawns it).
4. The new theme appears in the tray submenu and via `/pet set <name>`.

## Asset specs

| | Recommended |
|---|---|
| Canvas size | **180 × 180 px** (matches the window). SVG is auto-scaled. |
| Background | **Fully transparent** (alpha) |
| Animation | GIF, animated WebP, or APNG. Loop forever. |
| Frame rate | 8–15 fps. The window is small. |
| File size | < ~200 KB per file |
| Color profile | sRGB |

The image renders with `object-fit: contain`, so non-square art still
works — letterboxed inside 180×180 transparently.

## SVG quirks

SVG assets are **inlined into the DOM** (not loaded via `<img>`) so the
CSS keyframes in `pet-app/renderer/style.css` can reach class names like
`.loaf-typing`, `.paw-left`, `.dot`, `.loaf-breathe`, `.z`. If you make a
new SVG and want the same wiggle animation, copy the class names from
`cat/working.svg` and `cat/idle.svg` and CSS will animate them for free.

## Switching themes

Three ways:

- Tray icon → **Pet** submenu → click a name.
- `/pet set <name>` from Claude Code.
- Edit `~/.claude/plugins/claude-pet/data/config.json` (`{"theme":"dog"}`)
  — `fs.watch` picks it up live.

The chosen theme persists across restarts.

## Reload after editing existing art

Renderer caches images for the lifetime of the process. To pick up edits
to a theme's files:

1. Tray → Quit, **or**
2. `kill $(cat ~/.claude/plugins/claude-pet/data/app.pid)`

Then trigger any Claude Code hook and the pet respawns with the fresh art.
