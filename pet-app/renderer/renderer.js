const EXTS = ['gif', 'webp', 'apng', 'png']; // animated formats first
const MAX_DOTS = 5;
const petEl = document.getElementById('pet');
const badgeEl = document.getElementById('session-badge');

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

function tryLoadCustom(state, exts, scene) {
  if (!exts.length) return;
  const ext = exts[0];
  const url = `../assets/cats/${state}.${ext}`;
  const probe = new Image();
  probe.onload = () => {
    if (probe.naturalWidth === 0) {
      tryLoadCustom(state, exts.slice(1), scene);
      return;
    }
    const img = document.createElement('img');
    img.src = url;
    img.alt = '';
    img.className = 'custom-art';
    // The default scenes are <svg>; HTML <img> can't render as a child of SVG.
    // Replace the whole SVG container with an HTML <div> that mirrors the scene classes.
    if (scene.tagName.toLowerCase() === 'svg') {
      const div = document.createElement('div');
      div.className = `scene scene-${state} has-custom`;
      div.appendChild(img);
      scene.replaceWith(div);
    } else {
      scene.replaceChildren(img);
      scene.classList.add('has-custom');
    }
  };
  probe.onerror = () => tryLoadCustom(state, exts.slice(1), scene);
  probe.src = url;
}

['working', 'idle'].forEach((state) => {
  const scene = document.querySelector(`.scene-${state}`);
  if (scene) tryLoadCustom(state, EXTS.slice(), scene);
});

window.pet.onState((payload) => applyState(payload));
window.pet.getState().then(applyState).catch(() => {});
