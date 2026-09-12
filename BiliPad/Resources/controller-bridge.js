(() => {
  "use strict";

  const root = window.__bilipad = window.__bilipad || {};

  root.postMessage = (payload) => {
    try {
      window.webkit?.messageHandlers?.bilipadBridge?.postMessage(payload);
    } catch (_) {
      // Native diagnostics are best-effort and must never break page interaction.
    }
  };

  root.reportError = (message) => {
    root.postMessage({ type: "error", message: String(message).slice(0, 300) });
  };

  root.receiveAction = (action) => {
    if (!root.navigation?.handleAction) return false;
    return root.navigation.handleAction(action);
  };
})();

