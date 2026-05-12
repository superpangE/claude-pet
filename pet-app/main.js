const { app, BrowserWindow, Tray, Menu, ipcMain, screen, nativeImage } = require('electron');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DATA_DIR =
  process.env.CLAUDE_PET_DATA_DIR ||
  path.join(os.homedir(), '.claude', 'plugins', 'claude-pet', 'data');
const POSITION_FILE = path.join(DATA_DIR, 'position.json');
const SESSIONS_DIR = path.join(DATA_DIR, 'sessions');

const WIN_SIZE = { width: 180, height: 180 };
// Quit if no active CC sessions for this many ms.
const IDLE_QUIT_GRACE_MS = 8000;
const SESSION_POLL_MS = 2000;
// Session files older than this are treated as dead (terminal SIGKILL'd).
const STALE_MS = 4 * 60 * 60 * 1000;
// Upper bound for a "working" session without any heartbeat. PreToolUse /
// PostToolUse refresh updated_at while tools run, so this only kicks in when
// the run is genuinely stuck or interrupted (ESC / SIGHUP / window-close where
// SessionEnd never fires). Long text-only responses without tools sit under
// this without issue; 5 minutes is well past any realistic single response.
const WORKING_MAX_MS = 5 * 60 * 1000;
// A "stopping" session (mid-turn Stop with stop_hook_active=true) that hasn't
// been touched by a new UserPromptSubmit / ToolUse for this long is considered
// idle. Subagent / internal-continuation Stops typically resume within seconds.
const STOP_GRACE_MS = 15 * 1000;

// Coalesce bursts of fs events.
const WATCH_DEBOUNCE_MS = 80;
// Re-evaluate periodically so timer-only state changes (grace expiry, stuck
// working) surface even without an fs.watch event.
const TICK_MS = 5 * 1000;

const PRIORITY = { working: 2, idle: 1 };

const DEBUG = process.env.CLAUDE_PET_DEBUG === '1';
const dlog = (...args) => { if (DEBUG) console.log(...args); };

let mainWindow = null;
let tray = null;
let watcher = null;
let pushTimer = null;
let currentAggregate = { state: 'idle', sessionCount: 0, breakdown: {}, sessionStates: [] };

function ensureDataDir() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.mkdirSync(SESSIONS_DIR, { recursive: true });
}

function readActiveSessions() {
  let entries;
  try {
    entries = fs.readdirSync(SESSIONS_DIR);
  } catch (_) {
    return [];
  }
  const now = Date.now();
  const cutoffSec = (now - STALE_MS) / 1000;
  const out = [];
  for (const name of entries) {
    if (!name.endsWith('.json')) continue;
    const full = path.join(SESSIONS_DIR, name);
    try {
      const raw = fs.readFileSync(full, 'utf8');
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed.state !== 'string') continue;
      if (typeof parsed.updated_at === 'number' && parsed.updated_at < cutoffSec) continue;
      out.push(parsed);
    } catch (_) {
      // partial write or malformed — skip this round, will recheck on next event
    }
  }
  // GC leftover .attention markers from older plugin versions.
  for (const name of entries) {
    if (!name.endsWith('.attention')) continue;
    try { fs.unlinkSync(path.join(SESSIONS_DIR, name)); } catch (_) {}
  }
  return out;
}

function aggregateState() {
  const list = readActiveSessions();
  const breakdown = { working: 0, idle: 0 };
  const nowSec = Date.now() / 1000;
  const workingCutoff = nowSec - WORKING_MAX_MS / 1000;
  const stopGraceCutoff = nowSec - STOP_GRACE_MS / 1000;
  const effective = list.map((s) => {
    if (s.state === 'working') {
      // Demote stuck working sessions: ESC / SIGHUP / window-close paths
      // where neither Stop nor SessionEnd is guaranteed to fire.
      if (typeof s.updated_at === 'number' && s.updated_at < workingCutoff) {
        return { ...s, state: 'idle' };
      }
      return s;
    }
    if (s.state === 'stopping') {
      // Tentative idle from a mid-turn Stop. Hold "working" until the grace
      // window expires; if a new turn lands first, on-prompt-submit /
      // on-tool-use will overwrite this entry with state=working.
      if (typeof s.updated_at === 'number' && s.updated_at >= stopGraceCutoff) {
        return { ...s, state: 'working' };
      }
      return { ...s, state: 'idle' };
    }
    return { ...s, state: 'idle' };
  });
  for (const s of effective) {
    if (breakdown[s.state] !== undefined) breakdown[s.state]++;
  }
  const sessionStates = [
    ...Array(breakdown.working).fill('working'),
    ...Array(breakdown.idle).fill('idle'),
  ];
  if (effective.length === 0) {
    return { state: 'idle', sessionCount: 0, breakdown, sessionStates };
  }
  let winner = 'idle';
  for (const s of effective) {
    if ((PRIORITY[s.state] || 0) > (PRIORITY[winner] || 0)) winner = s.state;
  }
  return { state: winner, sessionCount: effective.length, breakdown, sessionStates };
}

function pushState() {
  currentAggregate = aggregateState();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('pet:state', currentAggregate);
  }
}

function schedulePush() {
  if (pushTimer) clearTimeout(pushTimer);
  pushTimer = setTimeout(() => {
    pushTimer = null;
    pushState();
  }, WATCH_DEBOUNCE_MS);
}

function watchSessionsDir() {
  if (watcher) {
    try { watcher.close(); } catch (_) {}
  }
  watcher = fs.watch(SESSIONS_DIR, (eventType, filename) => {
    dlog(`[claude-pet] fs.watch event=${eventType} file=${filename}`);
    schedulePush();
  });
  watcher.on('error', (err) => {
    console.error('[claude-pet] watcher error, rebinding:', err);
    setTimeout(watchSessionsDir, 500);
  });
  dlog(`[claude-pet] watching ${SESSIONS_DIR}`);
}

// Belt-and-suspenders: poll sessions/ even if fs.watch silently misses events.
// macOS fs.watch is known to drop rename-overwrite events on some volumes.
setInterval(() => {
  try {
    const next = aggregateState();
    if (
      next.state !== currentAggregate.state ||
      next.sessionCount !== currentAggregate.sessionCount
    ) {
      dlog(`[claude-pet] poll detected change ${currentAggregate.state} -> ${next.state}`);
      pushState();
    }
  } catch (_) {}
}, 1000);

let emptySince = null;
function startSessionLifecycleWatcher() {
  setInterval(() => {
    const n = readActiveSessions().length;
    if (n > 0) {
      emptySince = null;
      return;
    }
    if (emptySince === null) {
      emptySince = Date.now();
      return;
    }
    if (Date.now() - emptySince >= IDLE_QUIT_GRACE_MS) {
      dlog('[claude-pet] no active sessions; quitting');
      app.quit();
    }
  }, SESSION_POLL_MS);
}

function loadPosition() {
  try {
    const raw = fs.readFileSync(POSITION_FILE, 'utf8');
    const { x, y } = JSON.parse(raw);
    if (Number.isFinite(x) && Number.isFinite(y)) return { x, y };
  } catch (_) {}
  const { workArea } = screen.getPrimaryDisplay();
  return {
    x: workArea.x + workArea.width - WIN_SIZE.width - 24,
    y: workArea.y + workArea.height - WIN_SIZE.height - 24,
  };
}

function savePosition(x, y) {
  try {
    fs.writeFileSync(POSITION_FILE, JSON.stringify({ x, y }));
  } catch (e) {
    console.error('savePosition failed', e);
  }
}

function createWindow() {
  const pos = loadPosition();
  mainWindow = new BrowserWindow({
    ...WIN_SIZE,
    x: pos.x,
    y: pos.y,
    transparent: true,
    frame: false,
    resizable: false,
    movable: true,
    hasShadow: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    fullscreenable: false,
    minimizable: false,
    maximizable: false,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      autoplayPolicy: 'no-user-gesture-required',
    },
  });

  mainWindow.setAlwaysOnTop(true, 'floating');
  mainWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  mainWindow.setMenu(null);

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    if (process.env.CLAUDE_PET_DEBUG === '1') {
      mainWindow.webContents.openDevTools({ mode: 'detach' });
    }
    pushState();
  });

  mainWindow.webContents.on('console-message', (_e, level, message) => {
    // Suppress Chromium's CSP warning; surface renderer logs only in debug.
    if (level === 2 && message.includes('Content-Security-Policy')) return;
    if (DEBUG || level >= 2) console.log(`[renderer:${level}] ${message}`);
  });

  mainWindow.webContents.on('did-fail-load', (_e, code, desc) => {
    console.error(`[claude-pet] renderer load failed code=${code} desc=${desc}`);
  });

  mainWindow.webContents.on('render-process-gone', (_e, details) => {
    console.error(`[claude-pet] renderer crashed:`, details);
  });

  mainWindow.on('moved', () => {
    const [x, y] = mainWindow.getPosition();
    savePosition(x, y);
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function buildTrayIcon() {
  const png = nativeImage.createFromDataURL(
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAS0lEQVQ4jWNgGAWjgP6A8T+jARMDAwMDw38GBgYGBgYGBgYGBgYGBgYGRgYGBgYGBgYGBgYGBgYGBgYGRgYGBgYGBgYGBgZGABxgAk0Bx2cOAAAAAElFTkSuQmCC'
  );
  return png.isEmpty() ? nativeImage.createEmpty() : png;
}

function formatBreakdown(agg) {
  const { sessionCount, breakdown } = agg;
  if (sessionCount === 0) return 'no sessions';
  const parts = [];
  for (const k of ['working', 'idle']) {
    if (breakdown[k]) parts.push(`${breakdown[k]} ${k}`);
  }
  return `${sessionCount} session${sessionCount === 1 ? '' : 's'}: ${parts.join(', ')}`;
}

function buildTrayMenu() {
  return Menu.buildFromTemplate([
    {
      label: 'Show / Hide',
      click: () => {
        if (!mainWindow) return;
        if (mainWindow.isVisible()) mainWindow.hide();
        else mainWindow.show();
      },
    },
    {
      label: 'Reset position',
      click: () => {
        if (!mainWindow) return;
        const { workArea } = screen.getPrimaryDisplay();
        const x = workArea.x + workArea.width - WIN_SIZE.width - 24;
        const y = workArea.y + workArea.height - WIN_SIZE.height - 24;
        mainWindow.setPosition(x, y);
        savePosition(x, y);
      },
    },
    { type: 'separator' },
    { label: `State: ${currentAggregate.state}`, enabled: false },
    { label: `  ${formatBreakdown(currentAggregate)}`, enabled: false },
    { type: 'separator' },
    { label: 'Quit', role: 'quit' },
  ]);
}

function createTray() {
  tray = new Tray(buildTrayIcon());
  tray.setToolTip('Claude Pet');
  tray.setContextMenu(buildTrayMenu());
  setInterval(() => {
    if (!tray) return;
    tray.setContextMenu(buildTrayMenu());
  }, 2000);
}

ipcMain.handle('pet:get-state', () => aggregateState());

// scripts/pet-control.sh sends these to toggle visibility from the
// /pet slash command. SIGUSR1 = hide, SIGUSR2 = show.
function installControlSignals() {
  process.on('SIGUSR1', () => {
    if (mainWindow && !mainWindow.isDestroyed() && mainWindow.isVisible()) {
      mainWindow.hide();
    }
  });
  process.on('SIGUSR2', () => {
    if (mainWindow && !mainWindow.isDestroyed() && !mainWindow.isVisible()) {
      mainWindow.show();
    }
  });
}

app.whenReady().then(() => {
  ensureDataDir();
  if (process.platform === 'darwin' && app.dock) app.dock.hide();
  createWindow();
  createTray();
  watchSessionsDir();
  startSessionLifecycleWatcher();
  installControlSignals();
  // Tick to detect working->idle demotion without relying on fs events.
  setInterval(schedulePush, TICK_MS);
});

app.on('before-quit', () => {
  if (watcher) {
    try { watcher.close(); } catch (_) {}
  }
  try {
    fs.unlinkSync(path.join(DATA_DIR, 'app.pid'));
  } catch (_) {}
});

app.on('window-all-closed', (e) => {
  e.preventDefault();
});
