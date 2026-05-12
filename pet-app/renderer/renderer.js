// Asset extensions to try, in order. Animated raster first, SVG last so a
// user-supplied gif/png in the same pet folder overrides the shipped svg.
const RASTER_EXTS = ['gif', 'webp', 'apng', 'png'];
const ALL_EXTS = [...RASTER_EXTS, 'svg'];
const MAX_DOTS = 5;
const DEFAULT_THEME = 'cat';

const petEl = document.getElementById('pet');
const badgeEl = document.getElementById('session-badge');
const loadedTheme = { idle: null, working: null };

function applyState(payload) {
  const raw = payload && payload.state;
  const next = raw === 'working' ? 'working' : 'idle';
  if (petEl.dataset.state !== next) {
    petEl.classList.remove('state-working', 'state-idle');
    petEl.classList.add(`state-${next}`);
    petEl.dataset.state = next;
  }
  renderBadge(payload);
}

function renderBadge(payload) {
  if (!badgeEl) return;
  const states = payload && payload.sessionStates;
  let dots = '';
  if (Array.isArray(states) && states.length >= 2) {
    const total = states.length;
    const shown = states.slice(0, MAX_DOTS);
    const overflow = total - MAX_DOTS;
    const inner = shown.map((s) => (s === 'working' ? '●' : '○')).join('');
    dots = overflow > 0 ? `${inner}+${overflow}` : inner;
  }
  if (dots) {
    badgeEl.textContent = dots;
    badgeEl.classList.add('visible');
  } else {
    badgeEl.replaceChildren();
    badgeEl.classList.remove('visible');
  }
}

// Pick the highest-priority asset for (theme, state). Raster wins so a user
// drop-in gif overrides the shipped svg. Resolves to {ext, url} or null.
function probeAsset(theme, state, exts) {
  return new Promise((resolve) => {
    if (!exts.length) { resolve(null); return; }
    const [ext, ...rest] = exts;
    const url = `../assets/pets/${theme}/${state}.${ext}`;
    const img = new Image();
    img.onload = () => {
      // Browsers sometimes "succeed" on a 404 with 0×0 — guard against that.
      if (img.naturalWidth === 0 && ext !== 'svg') {
        probeAsset(theme, state, rest).then(resolve);
        return;
      }
      resolve({ ext, url });
    };
    img.onerror = () => probeAsset(theme, state, rest).then(resolve);
    img.src = url;
  });
}

async function loadScene(state, theme) {
  const scene = document.querySelector(`.scene-${state}`);
  if (!scene) return;
  const hit = await probeAsset(theme, state, ALL_EXTS);
  if (!hit) {
    scene.replaceChildren();
    scene.classList.remove('has-custom', 'has-svg');
    return;
  }
  if (hit.ext === 'svg') {
    // Inline the SVG so CSS animation rules in style.css can reach the
    // .loaf-typing / .paw / .dot classes inside. <img src="*.svg"> would
    // sandbox them.
    try {
      const res = await fetch(hit.url);
      const text = await res.text();
      scene.innerHTML = text;
      scene.classList.add('has-svg');
      scene.classList.remove('has-custom');
    } catch (_) {
      scene.replaceChildren();
    }
    return;
  }
  // Raster (gif/png/webp/apng) → plain <img>.
  const img = document.createElement('img');
  img.src = hit.url;
  img.alt = '';
  img.className = 'custom-art';
  scene.replaceChildren(img);
  scene.classList.add('has-custom');
  scene.classList.remove('has-svg');
}

// theme can be either:
//   string                              (legacy — both states the same)
//   { idle: "cat", working: "dog" }     (per-state)
function normalizeTheme(theme) {
  if (typeof theme === 'string') return { idle: theme, working: theme };
  if (theme && typeof theme === 'object') {
    return {
      idle: typeof theme.idle === 'string' ? theme.idle : DEFAULT_THEME,
      working: typeof theme.working === 'string' ? theme.working : DEFAULT_THEME,
    };
  }
  return { idle: DEFAULT_THEME, working: DEFAULT_THEME };
}

async function applyTheme(rawTheme) {
  const next = normalizeTheme(rawTheme);
  const jobs = [];
  for (const state of ['idle', 'working']) {
    if (loadedTheme[state] !== next[state]) {
      loadedTheme[state] = next[state];
      jobs.push(loadScene(state, next[state]));
    }
  }
  await Promise.all(jobs);
}

window.pet.onState((payload) => applyState(payload));
window.pet.onTheme((theme) => applyTheme(theme));
window.pet.getState().then(applyState).catch(() => {});
window.pet.getTheme().then(applyTheme).catch(() => applyTheme(DEFAULT_THEME));
