# Custom cat art

Drop your own cat designs into this folder. The renderer auto-detects them on next launch and replaces the default SVG.

## File layout

Two filenames, one per state. Use **any** of these extensions; the loader picks the first match in this order: `gif` → `webp` → `apng` → `png`.

```
pet-app/assets/cats/
├── working.gif      # cat while Claude is busy
└── idle.gif         # cat while idle / waiting for user
```

If a state file is missing, that state falls back to the default SVG cat.

## Specs

| | Recommended |
|---|---|
| Canvas size | **180 × 180 px** (matches the window) |
| Background | **Fully transparent** (alpha) |
| Animation | GIF, animated WebP, or APNG. Loop forever. |
| Frame rate | 8–15 fps is plenty; the window is small |
| File size | Keep under ~200 KB each — they're loaded into a renderer process |
| Color profile | sRGB |

The image is rendered with `object-fit: contain`, so non-square art still works — it'll be letterboxed inside 180×180 transparently.

## Tips

- **Animated GIF** is the most compatible and easiest to author (Photoshop, Procreate, ezgif.com all export it).
- **APNG / animated WebP** give you 24-bit color and proper alpha — better quality but tooling is sparser.
- For pixel art: export at native resolution (e.g. 60×60) and the renderer will scale up. Add `image-rendering: pixelated;` to `.custom-art` in `pet-app/renderer/style.css` if you want crisp scaling instead of smoothing.
- The whole window is the drag target — nothing in your art needs to be "click-aware". Pure visual.

## Reload after editing

The Electron app caches images for the lifetime of the renderer. To pick up new art:

1. Quit the pet from the macOS menu-bar tray, **or**
2. `kill $(cat ~/.claude/plugins/claude-pet/data/app.pid)`

Then trigger any Claude Code hook (e.g. start a new `claude` session) and the pet respawns with the new art.
