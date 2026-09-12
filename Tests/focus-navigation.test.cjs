const test = require("node:test");
const assert = require("node:assert/strict");

const {
  scoreCandidate,
  directionFromVector,
  isSupportedAction
} = require("../BiliPad/Resources/focus-navigation.js");

function rect(left, top, width = 100, height = 60) {
  return { left, top, width, height };
}

test("directionFromVector applies the dead zone", () => {
  assert.equal(directionFromVector(0.2, 0.3, 0.55), null);
  assert.equal(directionFromVector(0.8, 0.1, 0.55), "right");
  assert.equal(directionFromVector(-0.8, 0.1, 0.55), "left");
  assert.equal(directionFromVector(0.1, 0.8, 0.55), "up");
  assert.equal(directionFromVector(0.1, -0.8, 0.55), "down");
});

test("scoreCandidate excludes elements behind the requested direction", () => {
  const current = rect(200, 200);
  assert.equal(scoreCandidate(current, rect(50, 200), "right"), Infinity);
  assert.equal(scoreCandidate(current, rect(350, 200), "left"), Infinity);
  assert.equal(scoreCandidate(current, rect(200, 50), "down"), Infinity);
  assert.equal(scoreCandidate(current, rect(200, 350), "up"), Infinity);
});

test("scoreCandidate prefers alignment over a diagonal neighbor", () => {
  const current = rect(200, 200);
  const aligned = scoreCandidate(current, rect(400, 210), "right");
  const diagonal = scoreCandidate(current, rect(330, 420), "right");
  assert.ok(aligned < diagonal);
});

test("scoreCandidate permits uneven grids", () => {
  const score = scoreCandidate(rect(0, 0), rect(140, 80), "right");
  assert.ok(Number.isFinite(score));
  assert.ok(score > 0);
});

test("player actions are accepted by the bridge", () => {
  assert.equal(isSupportedAction("danmaku"), true);
  assert.equal(isSupportedAction("fullscreen"), true);
  assert.equal(isSupportedAction("disableAutoplay"), true);
  assert.equal(isSupportedAction("volumeUp"), false);
});
