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

  const FOCUSED_CLASS = "bilipad-focused";
  const STORAGE_PREFIX = "bilipad.navigation.";
  const VALID_ACTIONS = new Set(["up", "down", "left", "right", "confirm", "back"]);

  const state = {
    nodes: [],
    focused: null,
    observer: null,
    scanTimer: null,
    lastURL: ""
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
    if (document.fullscreenElement && document.exitFullscreen) {
      document.exitFullscreen().catch(() => {});
      return true;
    }
    if (document.webkitFullscreenElement && document.webkitExitFullscreen) {
      document.webkitExitFullscreen();
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
    addEventListener("popstate", () => setTimeout(() => rescan({ restore: true }), 80));
    addEventListener("pageshow", () => setTimeout(() => rescan({ restore: true }), 80));
    addEventListener("pagehide", savePosition);

    const root = globalScope.__bilipad = globalScope.__bilipad || {};
    root.navigation = { handleAction, rescan };
  }

  const testAPI = { scoreCandidate, directionFromVector };
  if (typeof module !== "undefined" && module.exports) module.exports = testAPI;
  if (typeof document !== "undefined") initialize();
})(typeof window !== "undefined" ? window : globalThis);
