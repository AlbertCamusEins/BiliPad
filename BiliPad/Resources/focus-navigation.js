(function (globalScope) {
  "use strict";

  const SELECTORS = Object.freeze([
    'a[href*="/video/BV"]',
    'a[href*="/bangumi/play/"]',
    'a[href*="/list/"]',
    'input[type="search"]',
    'button',
    '[role="button"]'
  ]);

  const PLAYER_SELECTORS = Object.freeze({
    danmakuToggle: Object.freeze([
      '[aria-label*="开启弹幕"]',
      '[aria-label*="关闭弹幕"]',
      '[title*="开启弹幕"]',
      '[title*="关闭弹幕"]',
      '.bpx-player-dm-switch input',
      '.bpx-player-dm-switch'
    ]),
    autoplayToggle: Object.freeze([
      'input[aria-label*="自动连播"]',
      '[role="switch"][aria-label*="自动连播"]',
      '[title*="自动连播"]',
      '.bpx-player-ctrl-setting-autoplay input',
      '.bpx-player-ctrl-setting-autoplay'
    ]),
    fullscreenExit: Object.freeze([
      '[aria-label*="退出全屏"]',
      '[title*="退出全屏"]',
      '.bpx-player-ctrl-web-leave',
      '.bpx-player-ctrl-full[aria-label*="退出"]'
    ])
  });

  const FOCUSED_CLASS = "bilipad-focused";
  const STORAGE_PREFIX = "bilipad.navigation.";
  const VALID_ACTIONS = new Set([
    "up",
    "down",
    "left",
    "right",
    "confirm",
    "back",
    "danmaku",
    "fullscreen",
    "disableAutoplay"
  ]);

  const state = {
    nodes: [],
    focused: null,
    observer: null,
    scanTimer: null,
    lastURL: "",
    autoplayDisabled: false
  };

  function center(rect) {
    return {
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2
    };
  }

  function scoreCandidate(currentRect, candidateRect, direction) {
    const from = center(currentRect);
    const to = center(candidateRect);
    const dx = to.x - from.x;
    const dy = to.y - from.y;

    let main;
    let cross;
    switch (direction) {
      case "left":
        if (dx >= -1) return Infinity;
        main = -dx;
        cross = Math.abs(dy);
        break;
      case "right":
        if (dx <= 1) return Infinity;
        main = dx;
        cross = Math.abs(dy);
        break;
      case "up":
        if (dy >= -1) return Infinity;
        main = -dy;
        cross = Math.abs(dx);
        break;
      case "down":
        if (dy <= 1) return Infinity;
        main = dy;
        cross = Math.abs(dx);
        break;
      default:
        return Infinity;
    }

    // Penalize diagonal candidates while still allowing navigation across uneven grids.
    return main + cross * 1.8 + (cross * cross) / Math.max(main, 1) * 0.25;
  }

  function directionFromVector(x, y, deadZone) {
    const threshold = deadZone ?? 0.55;
    if (Math.max(Math.abs(x), Math.abs(y)) < threshold) return null;
    if (Math.abs(x) > Math.abs(y)) return x > 0 ? "right" : "left";
    return y > 0 ? "up" : "down";
  }

  function isRendered(element) {
    if (!(element instanceof Element)) return false;
    const rect = element.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return false;
    const style = getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden") return false;
    if (Number(style.opacity) <= 0.02) return false;
    return rect.bottom > -50 && rect.right > -50;
  }

  function isVisibleInViewport(element) {
    if (!isRendered(element)) return false;
    const rect = element.getBoundingClientRect();
    return rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
  }

  function normalizeCandidate(element) {
    const videoCard = element.closest('a[href*="/video/BV"], a[href*="/bangumi/play/"]');
    return videoCard || element;
  }

  function discoverNodes() {
    const seen = new Set();
    const nodes = [];
    for (const candidate of document.querySelectorAll(SELECTORS.join(","))) {
      const node = normalizeCandidate(candidate);
      if (seen.has(node) || !isRendered(node)) continue;
      seen.add(node);
      nodes.push(node);
    }
    return nodes;
  }

  function focusKey(element) {
    if (!element) return null;
    const href = element.getAttribute("href");
    if (href) return `href:${href}`;
    const label = element.getAttribute("aria-label") || element.getAttribute("title");
    if (label) return `label:${label}`;
    if (element.id) return `id:${element.id}`;
    return null;
  }

  function storageKey() {
    return `${STORAGE_PREFIX}${location.pathname}${location.search}`;
  }

  function savePosition() {
    try {
      sessionStorage.setItem(storageKey(), JSON.stringify({
        focusKey: focusKey(state.focused),
        scrollX,
        scrollY
      }));
    } catch (_) {
      // Session storage can be disabled without affecting navigation.
    }
  }

  function loadPosition() {
    try {
      const raw = sessionStorage.getItem(storageKey());
      return raw ? JSON.parse(raw) : null;
    } catch (_) {
      return null;
    }
  }

  function setFocused(element, shouldScroll) {
    state.focused?.classList.remove(FOCUSED_CLASS);
    state.focused = element || null;
    if (!state.focused) return;
    state.focused.classList.add(FOCUSED_CLASS);
    if (shouldScroll) {
      state.focused.scrollIntoView({ behavior: "smooth", block: "center", inline: "center" });
    }
  }

  function restoreFocus() {
    const saved = loadPosition();
    if (saved && Number.isFinite(saved.scrollY)) {
      scrollTo({ left: saved.scrollX || 0, top: saved.scrollY, behavior: "auto" });
    }

    const matching = saved?.focusKey
      ? state.nodes.find((node) => focusKey(node) === saved.focusKey)
      : null;
    setFocused(matching || state.nodes[0] || null, false);
  }

  function rescan(options) {
    const previousKey = focusKey(state.focused);
    state.nodes = discoverNodes();
    const previous = previousKey
      ? state.nodes.find((node) => focusKey(node) === previousKey)
      : null;

    if (previous) {
      setFocused(previous, false);
    } else if (options?.restore) {
      restoreFocus();
    } else if (!state.focused || !state.focused.isConnected) {
      setFocused(state.nodes[0] || null, false);
    }
  }

  function scheduleRescan() {
    clearTimeout(state.scanTimer);
    state.scanTimer = setTimeout(() => {
      const urlChanged = state.lastURL !== location.href;
      state.lastURL = location.href;
      rescan({ restore: urlChanged });
      applyAutoplayPolicy();
    }, 140);
  }

  function move(direction) {
    if (!state.nodes.length) rescan({ restore: true });
    if (!state.focused || !isRendered(state.focused)) {
      setFocused(state.nodes[0] || null, true);
      return Boolean(state.focused);
    }

    const currentRect = state.focused.getBoundingClientRect();
    let best = null;
    let bestScore = Infinity;
    for (const candidate of state.nodes) {
      if (candidate === state.focused || !isRendered(candidate)) continue;
      const score = scoreCandidate(currentRect, candidate.getBoundingClientRect(), direction);
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best) {
      setFocused(best, true);
      savePosition();
      return true;
    }

    // Give lazy-loaded feeds a chance to append another row at the page edge.
    if (direction === "up" || direction === "down") {
      scrollBy({
        top: (direction === "down" ? 1 : -1) * innerHeight * 0.72,
        behavior: "smooth"
      });
      setTimeout(() => rescan({ restore: false }), 220);
      return true;
    }
    return false;
  }

  function visibleVideo() {
    const videos = Array.from(document.querySelectorAll("video")).filter((video) => {
      if (!isVisibleInViewport(video)) return false;
      const rect = video.getBoundingClientRect();
      const viewportArea = Math.max(innerWidth * innerHeight, 1);
      return rect.width >= innerWidth * 0.42 && rect.width * rect.height >= viewportArea * 0.16;
    });
    return videos.sort((a, b) => {
      const areaA = a.getBoundingClientRect().width * a.getBoundingClientRect().height;
      const areaB = b.getBoundingClientRect().width * b.getBoundingClientRect().height;
      return areaB - areaA;
    })[0] || null;
  }

  function firstVisible(selectors) {
    for (const selector of selectors) {
      const match = Array.from(document.querySelectorAll(selector)).find(isRendered);
      if (match) return match;
    }
    return null;
  }

  function activationTarget(element) {
    if (!element) return null;
    return element.closest('button, label, [role="button"], [role="switch"]') || element;
  }

  function dispatchKeyboardShortcut(key, code, keyCode) {
    const focused = document.activeElement;
    if (focused?.matches?.('input, textarea, [contenteditable="true"]')) focused.blur();
    const target = document.activeElement || document.body || document.documentElement;

    for (const type of ["keydown", "keyup"]) {
      const event = new KeyboardEvent(type, {
        key,
        code,
        bubbles: true,
        cancelable: true
      });
      try {
        Object.defineProperty(event, "keyCode", { value: keyCode });
        Object.defineProperty(event, "which", { value: keyCode });
      } catch (_) {
        // Modern handlers use key/code; legacy numeric fields are best-effort.
      }
      target.dispatchEvent(event);
    }
    return true;
  }

  function toggleDanmaku() {
    const toggle = firstVisible(PLAYER_SELECTORS.danmakuToggle);
    if (toggle) {
      activationTarget(toggle).click();
      return true;
    }
    return dispatchKeyboardShortcut("d", "KeyD", 68);
  }

  function toggleFullscreen() {
    return dispatchKeyboardShortcut("f", "KeyF", 70);
  }

  function explicitToggleState(element) {
    const input = element.matches?.('input[type="checkbox"]')
      ? element
      : element.querySelector?.('input[type="checkbox"]');
    if (input && typeof input.checked === "boolean") return input.checked;

    for (const name of ["aria-checked", "aria-pressed"]) {
      const value = element.getAttribute?.(name);
      if (value === "true") return true;
      if (value === "false") return false;
    }
    return null;
  }

  function applyAutoplayPolicy() {
    if (!state.autoplayDisabled) return;
    for (const video of document.querySelectorAll("video")) {
      video.autoplay = false;
      video.loop = false;
      video.removeAttribute("autoplay");
    }
  }

  function disableAutoplay() {
    state.autoplayDisabled = true;
    applyAutoplayPolicy();

    const toggle = firstVisible(PLAYER_SELECTORS.autoplayToggle);
    if (toggle && explicitToggleState(toggle) !== false) {
      activationTarget(toggle).click();
    }
    return true;
  }

  function stopAutoplayAtEnd(event) {
    if (!state.autoplayDisabled || event.target?.tagName !== "VIDEO") return;
    event.stopImmediatePropagation();
    event.target.autoplay = false;
    event.target.loop = false;
  }

  function reportPlaybackError(error) {
    const message = `播放操作失败：${error?.message || String(error)}`;
    globalScope.__bilipad?.reportError?.(message);
  }

  function togglePlayback(video) {
    if (video.paused) {
      const result = video.play();
      if (result?.catch) result.catch(reportPlaybackError);
    } else {
      video.pause();
    }
  }

  function seek(video, delta) {
    const duration = Number.isFinite(video.duration) ? video.duration : Infinity;
    video.currentTime = Math.max(0, Math.min(duration, video.currentTime + delta));
  }

  function closeTransientLayer() {
    const fullscreenVideo = Array.from(document.querySelectorAll("video"))
      .find((video) => video.webkitDisplayingFullscreen);
    if (fullscreenVideo && typeof fullscreenVideo.webkitExitFullscreen === "function") {
      fullscreenVideo.webkitExitFullscreen();
      return true;
    }

    if (document.fullscreenElement && document.exitFullscreen) {
      document.exitFullscreen().catch(() => {});
      return true;
    }
    if (document.webkitFullscreenElement && document.webkitExitFullscreen) {
      document.webkitExitFullscreen();
      return true;
    }

    const fullscreenExit = firstVisible(PLAYER_SELECTORS.fullscreenExit);
    if (fullscreenExit) {
      activationTarget(fullscreenExit).click();
      return true;
    }

    const closeButton = Array.from(document.querySelectorAll(
      '[aria-label*="关闭"], [title*="关闭"], .close, [class*="close"]'
    )).find(isVisibleInViewport);
    if (closeButton) {
      closeButton.click();
      return true;
    }
    return false;
  }

  function handleAction(action) {
    if (!VALID_ACTIONS.has(action)) return false;
    const video = visibleVideo();

    if (video) {
      if (action === "danmaku") return toggleDanmaku();
      if (action === "fullscreen") return toggleFullscreen();
      if (action === "disableAutoplay") return disableAutoplay();
      if (action === "confirm") {
        togglePlayback(video);
        return true;
      }
      if (action === "left" || action === "right") {
        seek(video, action === "left" ? -10 : 10);
        return true;
      }
      if (action === "back") {
        savePosition();
        if (!closeTransientLayer()) history.back();
        return true;
      }
      // Up/down intentionally fall through to page navigation so users can reach controls.
    }

    if (["up", "down", "left", "right"].includes(action)) return move(action);
    if (action === "disableAutoplay") return disableAutoplay();
    if (action === "confirm" && state.focused) {
      savePosition();
      state.focused.click();
      return true;
    }
    if (action === "back") {
      savePosition();
      if (!closeTransientLayer()) history.back();
      return true;
    }
    return false;
  }

  function initialize() {
    if (typeof document === "undefined") return;
    state.lastURL = location.href;
    rescan({ restore: true });
    state.observer = new MutationObserver(scheduleRescan);
    state.observer.observe(document.documentElement, { childList: true, subtree: true });
    document.addEventListener("ended", stopAutoplayAtEnd, true);
    addEventListener("popstate", () => setTimeout(() => rescan({ restore: true }), 80));
    addEventListener("pageshow", () => setTimeout(() => rescan({ restore: true }), 80));
    addEventListener("pagehide", savePosition);

    const root = globalScope.__bilipad = globalScope.__bilipad || {};
    root.navigation = { handleAction, rescan };
  }

  const testAPI = {
    scoreCandidate,
    directionFromVector,
    isSupportedAction: (action) => VALID_ACTIONS.has(action)
  };
  if (typeof module !== "undefined" && module.exports) module.exports = testAPI;
  if (typeof document !== "undefined") initialize();
})(typeof window !== "undefined" ? window : globalThis);
