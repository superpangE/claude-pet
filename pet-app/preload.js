const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pet', {
  onState: (handler) => {
    ipcRenderer.on('pet:state', (_evt, payload) => handler(payload));
  },
  getState: () => ipcRenderer.invoke('pet:get-state'),
  onTheme: (handler) => {
    ipcRenderer.on('pet:theme', (_evt, theme) => handler(theme));
  },
  getTheme: () => ipcRenderer.invoke('pet:get-theme'),
});
