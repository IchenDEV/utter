// Utter — Transcript Demo
// Zero dependencies. Reads pre-recorded audio + timing JSON and drives
// the waveform (Web Audio API) + per-word reveal (setTimeout chain).

(() => {
  const SAMPLES = {
    en: 'assets/demos/en-sample.json',
    zh: 'assets/demos/zh-sample.json',
    'voice-cmd': 'assets/demos/voice-cmd-sample.json'
  };

  const $play      = document.getElementById('demo-play');
  const $playLabel = document.getElementById('demo-play-label');
  const $audio     = document.getElementById('demo-audio');
  const $wave      = document.querySelector('.waveform');
  const $bars      = $wave.querySelectorAll('.bar');
  const $trans     = document.querySelector('.transcript');
  const $verb      = $trans.querySelector('.verbatim-text');
  const $smart     = $trans.querySelector('.smart-result');
  const $context   = document.getElementById('demo-context');
  const $samples   = document.querySelectorAll('.demo-samples button');
  const $modes     = document.querySelectorAll('.mode-toggle button');

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let currentSampleId = 'en';
  let currentMode     = 'smart';
  let currentData     = null;
  let audioCtx        = null;
  let analyser        = null;
  let rafId           = null;
  let revealTimers    = [];
  let playing         = false;

  async function loadSample(id) {
    const res = await fetch(SAMPLES[id]);
    return res.json();
  }

  function setSample(id) {
    currentSampleId = id;
    $samples.forEach(b => b.setAttribute('aria-pressed', b.dataset.sample === id ? 'true' : 'false'));
    $context.classList.toggle('visible', id === 'voice-cmd');
    stop();
    loadSample(id).then(data => {
      currentData = data;
      $audio.src = 'assets/demos/' + data.audio;
      resetTranscript();
    });
  }

  function setMode(mode) {
    currentMode = mode;
    $modes.forEach(b => b.setAttribute('aria-pressed', b.dataset.mode === mode ? 'true' : 'false'));
    if (playing) restart();
  }

  function resetTranscript() {
    $trans.classList.remove('show-smart');
    $trans.classList.add('placeholder');
    $verb.textContent  = 'Press play to see it transcribe.';
    $smart.textContent = '';
  }

  function clearTimers() {
    revealTimers.forEach(t => clearTimeout(t));
    revealTimers = [];
  }

  function setupAudioGraph() {
    if (audioCtx) return;
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      audioCtx = new Ctx();
      const source = audioCtx.createMediaElementSource($audio);
      analyser = audioCtx.createAnalyser();
      analyser.fftSize = 64;
      source.connect(analyser);
      analyser.connect(audioCtx.destination);
    } catch (_) {
      audioCtx = null;
      analyser = null;
    }
  }

  function pumpWaveform() {
    if (!analyser) return;
    const bins = analyser.frequencyBinCount;
    const data = new Uint8Array(bins);
    const step = () => {
      analyser.getByteFrequencyData(data);
      $bars.forEach((bar, i) => {
        const v = data[i % bins] / 255;
        const h = Math.max(4, Math.round(v * 44));
        bar.style.height = h + 'px';
      });
      rafId = requestAnimationFrame(step);
    };
    step();
  }

  function stopWaveform() {
    if (rafId) cancelAnimationFrame(rafId);
    rafId = null;
    $bars.forEach(b => { b.style.height = ''; });
  }

  function revealVerbatim() {
    $verb.textContent = '';
    $trans.classList.remove('placeholder');
    for (const { w, t } of currentData.verbatim) {
      revealTimers.push(setTimeout(() => {
        $verb.textContent += (w + ' ');
      }, t * 1000));
    }
  }

  function showSmart() {
    $smart.textContent = currentData.smart;
    $trans.classList.add('show-smart');
  }

  function play() {
    if (!currentData) return;
    if (reducedMotion) {
      resetTranscript();
      $trans.classList.remove('placeholder');
      $verb.textContent = currentData.verbatim.map(v => v.w).join(' ');
      if (currentMode === 'smart') showSmart();
      return;
    }
    setupAudioGraph();
    if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
    clearTimers();
    $wave.classList.add('playing');
    resetTranscript();
    $audio.currentTime = 0;
    $audio.play().catch(() => {});
    pumpWaveform();
    revealVerbatim();
    if (currentMode === 'smart') {
      const lastT = currentData.verbatim[currentData.verbatim.length - 1].t;
      revealTimers.push(setTimeout(showSmart, (lastT + 0.6) * 1000));
    }
    playing = true;
    $playLabel.textContent = 'Stop';
  }

  function stop() {
    clearTimers();
    $audio.pause();
    stopWaveform();
    $wave.classList.remove('playing');
    playing = false;
    $playLabel.textContent = 'Play';
  }

  function restart() { stop(); play(); }

  $play.addEventListener('click', () => (playing ? stop() : play()));
  $audio.addEventListener('ended', () => stop());
  $samples.forEach(b => b.addEventListener('click', () => setSample(b.dataset.sample)));
  $modes.forEach(b => b.addEventListener('click', () => setMode(b.dataset.mode)));

  document.addEventListener('keydown', (e) => {
    const onSampleChip = e.target.matches && e.target.matches('.demo-samples button');
    if (onSampleChip && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
      e.preventDefault();
      const ids  = ['en', 'zh', 'voice-cmd'];
      const i    = ids.indexOf(currentSampleId);
      const next = (i + (e.key === 'ArrowRight' ? 1 : ids.length - 1)) % ids.length;
      setSample(ids[next]);
      document.querySelector('[data-sample="' + ids[next] + '"]').focus();
    }
    if ((e.metaKey || e.ctrlKey) && (e.key === 'm' || e.key === 'M')) {
      e.preventDefault();
      setMode(currentMode === 'smart' ? 'verbatim' : 'smart');
    }
  });

  // install command copy
  const $code  = document.getElementById('install-code');
  const $label = document.getElementById('copy-label');
  if ($code) {
    const copy = async () => {
      const txt = $code.querySelector('code').textContent;
      try { await navigator.clipboard.writeText(txt); } catch (_) {}
      $label.textContent = 'copied';
      setTimeout(() => { $label.textContent = 'copy'; }, 1800);
    };
    $code.addEventListener('click', copy);
    $code.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        copy();
      }
    });
  }

  setSample('en');
})();
