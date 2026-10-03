// Deterministic animation helpers: every visual is a pure function of time t.
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, p) => a + (b - a) * p;
const seg = (t, a, b) => clamp((t - a) / (b - a));
const ease = {
  inOut: (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2),
  out: (p) => 1 - Math.pow(1 - p, 3),
  outExpo: (p) => (p >= 1 ? 1 : 1 - Math.pow(2, -10 * p)),
  in: (p) => p * p * p,
  // Critically damped-ish spring used for UI pops.
  spring: (p) => 1 - Math.exp(-7 * p) * Math.cos(9 * p) * (1 - p * 0.2),
};
// Fade-in over [a, a+fi], hold, fade-out over [b-fo, b].
const window01 = (t, a, b, fi = 0.4, fo = 0.4) =>
  Math.min(ease.out(seg(t, a, a + fi)), 1 - ease.inOut(seg(t, b - fo, b)));

const $ = (id) => document.getElementById(id);
const css = (el, styles) => Object.assign(el.style, styles);
const el = (tag, cls, html, parent) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (html !== undefined) node.innerHTML = html;
  if (parent) parent.appendChild(node);
  return node;
};

// Keyframed scalar: [[t, value, easing?], ...]; easing applies into that key.
function keys(t, frames) {
  if (t <= frames[0][0]) return frames[0][1];
  for (let i = 1; i < frames.length; i++) {
    const [t1, v1, e] = frames[i];
    const [t0, v0] = frames[i - 1];
    if (t <= t1) return lerp(v0, v1, (e || ease.inOut)(seg(t, t0, t1)));
  }
  return frames[frames.length - 1][1];
}

// Simplified glyphs drawn to match the SF Symbols the app uses.
const ICON = {
  mic: '<svg viewBox="0 0 24 24"><rect x="8.5" y="2.5" width="7" height="12" rx="3.5" fill="currentColor"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3.2M8.8 21.2h6.4" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round"/></svg>',
  wifi: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"><path d="M2.6 9.2a13.5 13.5 0 0 1 18.8 0"/><path d="M5.9 12.6a8.8 8.8 0 0 1 12.2 0"/><path d="M9.2 16a4.1 4.1 0 0 1 5.6 0"/><circle cx="12" cy="19.2" r="1.1" fill="currentColor" stroke="none"/></svg>',
  wifiOff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"><path d="M2.6 9.2a13.5 13.5 0 0 1 18.8 0" opacity=".35"/><path d="M5.9 12.6a8.8 8.8 0 0 1 12.2 0" opacity=".35"/><path d="M9.2 16a4.1 4.1 0 0 1 5.6 0" opacity=".35"/><circle cx="12" cy="19.2" r="1.1" fill="currentColor" stroke="none" opacity=".35"/><path d="M4 3.5l16 17"/></svg>',
  battery: '<svg viewBox="0 0 30 24"><rect x="1.5" y="6.5" width="23" height="11" rx="3" fill="none" stroke="currentColor" stroke-width="1.3" opacity=".55"/><rect x="3.4" y="8.4" width="16" height="7.2" rx="1.6" fill="currentColor"/><path d="M26.4 10v4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" opacity=".55"/></svg>',
  controls: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="18" height="5.5" rx="2.75"/><rect x="3" y="13.5" width="18" height="5.5" rx="2.75"/><circle cx="7.5" cy="7.75" r="1.6" fill="currentColor"/><circle cx="16.5" cy="16.25" r="1.6" fill="currentColor"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/></svg>',
  xmark: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M7 7l10 10M17 7L7 17"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5.5 12.5l4.2 4.2L18.5 7.5"/></svg>',
  transcribing: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 10v4M6.5 7v10M10 9v6"/><circle cx="16" cy="12" r="3.6"/><path d="M18.6 14.6L21 17"/></svg>',
  textformat: '<svg viewBox="0 0 24 24"><text x="1" y="18" font-size="15" font-weight="600" fill="currentColor" font-family="sans-serif">A</text><text x="11.5" y="18" font-size="11" font-weight="600" fill="currentColor" font-family="sans-serif">a</text></svg>',
  cursor: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M9 4.5c1.6 0 3 .5 3 1.5 0-1 1.4-1.5 3-1.5M9 19.5c1.6 0 3-.5 3-1.5 0 1 1.4 1.5 3 1.5"/></svg>',
  globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="8.5"/><ellipse cx="12" cy="12" rx="3.8" ry="8.5"/><path d="M3.5 12h17M5.2 7.5h13.6M5.2 16.5h13.6"/></svg>',
  pointer: '<svg viewBox="0 0 24 34"><path d="M2 2v25.5l6.4-6.1 4.2 9.7 4.3-1.9-4.2-9.5H21L2 2z" fill="#111" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/></svg>',
  cloud: '<svg viewBox="0 0 48 32" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M13 28h23a8 8 0 0 0 1.2-15.9A11 11 0 0 0 16 10.2 8.9 8.9 0 0 0 13 28z"/></svg>',
  chip: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="6" y="6" width="12" height="12" rx="2.5"/><path d="M9 2.5v3M15 2.5v3M9 18.5v3M15 18.5v3M2.5 9h3M2.5 15h3M18.5 9h3M18.5 15h3"/></svg>',
  translate: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 5h9M7.5 3v2M5 5c.6 3.2 2.8 5.8 6 7M10 5c-.8 3.6-3.2 6.5-6.5 8"/><path d="M12.5 21l4.2-10 4.3 10M14 17.5h5.4"/></svg>',
  sparkle: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.5l1.9 5.6 5.6 1.9-5.6 1.9L12 17.5l-1.9-5.6L4.5 10l5.6-1.9z"/><path d="M18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z"/></svg>',
  list: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.2" fill="currentColor"/><circle cx="4.5" cy="12" r="1.2" fill="currentColor"/><circle cx="4.5" cy="18" r="1.2" fill="currentColor"/></svg>',
  book: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5"/></svg>',
  sliders: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2.2"/><circle cx="10" cy="17" r="2.2"/></svg>',
  screen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="4" width="18" height="12.5" rx="2"/><path d="M9 20.5h6M12 16.5v4"/></svg>',
  apps: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/></svg>',
  lock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg>',
  shift: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 3.5l8 8.5h-4.5v8h-7v-8H4z"/></svg>',
};

// World transform: world point (fx, fy) lands at frame centre, scaled by s.
function cameraTransform(c) {
  return `translate(${960 - c.fx * c.s}px, ${540 - c.fy * c.s}px) scale(${c.s})`;
}

// Table rows [start, end, ...payload]; returns the active row or undefined.
const activeRow = (t, rows) => rows.find(([a, b]) => t >= a && t < b);
