const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('pet', {
  onState: (handler) => {
    ipcRenderer.on('pet:state', (_evt, payload) => handler(payload));
  },
  getState: () => ipcRenderer.invoke('pet:get-state'),
});
