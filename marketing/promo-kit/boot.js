// Shared bootstrap: the renderer calls initScene(cues); opening index.html directly
// (served over http) loops a silent preview instead.
window.initScene = async (cues) => {
  window.CUES = cues;
  buildScene(cues);
  await document.fonts.ready;
  await Promise.all([...document.images].map((img) => img.decode().catch(() => {})));
  setupScene(cues);
  window.renderAt(0);
  return true;
};
if (!navigator.webdriver) {
  fetch("cues.json").then((r) => r.json()).then(async (cues) => {
    await window.initScene(cues);
    const t0 = performance.now();
    const tick = () => { window.renderAt(((performance.now() - t0) / 1000) % cues.duration); requestAnimationFrame(tick); };
    tick();
  });
}
