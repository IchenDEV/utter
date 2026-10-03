// Detailed vector parts shared by every place: laptop, desk, the protagonist, props.
const SCREEN = { x: 680, y: 300, w: 560, h: 315 };
const lin = (id, stops, x1 = 0, y1 = 0, x2 = 0, y2 = 1) =>
  `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">${stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join("")}</linearGradient>`;
const rad = (id, stops, cx = 0.5, cy = 0.5, r = 0.5) =>
  `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">${stops.map(([o, c]) => `<stop offset="${o}" stop-color="${c}"/>`).join("")}</radialGradient>`;

function partsDefs() {
  return `
    ${lin("gAlu", [[0, "#eceef2"], [0.55, "#d3d6dd"], [1, "#b7bbc5"]])}
    ${lin("gAluEdge", [[0, "#f7f8fa"], [1, "#9ea2ad"]])}
    ${lin("gBezel", [[0, "#2a2c33"], [1, "#16171b"]])}
    ${lin("gKeyWell", [[0, "#c4c7cf"], [1, "#d9dce2"]])}
    ${lin("gHair", [[0, "#3a3340"], [0.6, "#231f28"], [1, "#1b181f"]], 0, 0, 0.3, 1)}
    ${lin("gSweater", [[0, "#e6d9c8"], [0.5, "#d6c5b0"], [1, "#bfac96"]], 0, 0, 1, 1)}
    ${lin("gSkin", [[0, "#f0d2bd"], [1, "#d9b29a"]])}
    ${lin("gMug", [[0, "#ffffff"], [0.7, "#eef0f4"], [1, "#d6d9e0"]], 0, 0, 1, 0)}
    ${lin("gPhone", [[0, "#3b3e47"], [1, "#22242a"]])}
    ${rad("gShadow", [[0, "rgba(30,30,50,.32)"], [1, "rgba(30,30,50,0)"]])}
    <filter id="fSoft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="10"/></filter>
    <filter id="fBlur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter>`;
}

// Interpolates a point inside the keyboard-deck trapezoid (u across, v front-to-back).
function deckPoint(u, v) {
  const y = lerp(646, 704, v);
  const half = lerp(300, 372, v);
  return [960 + (u - 0.5) * 2 * half, y];
}

function keyboardSVG() {
  let keys = "";
  const rows = 5, cols = 14;
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const u0 = 0.08 + (c / cols) * 0.84, u1 = u0 + 0.84 / cols - 0.008;
      const v0 = 0.06 + (r / rows) * 0.5, v1 = v0 + 0.5 / rows - 0.02;
      const p = [deckPoint(u0, v0), deckPoint(u1, v0), deckPoint(u1, v1), deckPoint(u0, v1)];
      const isFn = r === rows - 1 && c === 0;
      keys += `<polygon points="${p.map((q) => q.join(",")).join(" ")}" fill="${isFn ? "#5b6ff0" : "#2d2f36"}" opacity="${isFn ? 0.9 : 0.92}"/>`;
    }
  }
  const tp = [deckPoint(0.36, 0.64), deckPoint(0.64, 0.64), deckPoint(0.66, 0.93), deckPoint(0.34, 0.93)];
  return `${keys}<polygon points="${tp.map((q) => q.join(",")).join(" ")}" fill="#c9ccd4" stroke="#b3b7c0" stroke-width="1"/>`;
}

function laptopSVG() {
  const { x, y, w, h } = SCREEN;
  const deck = [deckPoint(0, 0), deckPoint(1, 0), deckPoint(1, 1), deckPoint(0, 1)];
  return `
    <ellipse cx="960" cy="716" rx="470" ry="30" fill="url(#gShadow)" filter="url(#fSoft)"/>
    <rect x="${x - 20}" y="${y - 20}" width="${w + 40}" height="${h + 40}" rx="22" fill="#c4c8d0"/>
    <rect x="${x - 17}" y="${y - 17}" width="${w + 34}" height="${h + 34}" rx="19" fill="url(#gBezel)"/>
    <circle cx="960" cy="${y - 9}" r="3" fill="#3a3d46"/><circle cx="960" cy="${y - 9}" r="1.2" fill="#5a6070"/>
    <rect x="${x - 20}" y="${y + h + 18}" width="${w + 40}" height="9" fill="#9da1ab"/>
    <polygon points="${deck.map((q) => q.join(",")).join(" ")}" fill="url(#gAlu)"/>
    <polygon points="${[deckPoint(0.05, 0.03), deckPoint(0.95, 0.03), deckPoint(0.95, 0.58), deckPoint(0.05, 0.58)].map((q) => q.join(",")).join(" ")}" fill="url(#gKeyWell)" opacity=".7"/>
    ${keyboardSVG()}
    <path d="M${deck[3].join(" ")} L${deck[2].join(" ")} L${deck[2][0] + 4} ${deck[2][1] + 8} L${deck[3][0] - 4} ${deck[3][1] + 8} Z" fill="#a4a8b2"/>
    <path d="M${deck[3][0] + 6} ${deck[3][1] + 1} L${deck[2][0] - 6} ${deck[2][1] + 1}" stroke="#f4f5f8" stroke-width="1.5"/>
    <rect x="915" y="${deck[2][1] + 2}" width="90" height="5" rx="2.5" fill="#8e929c"/>`;
}

// Desk surface with grain, a front edge and an under-shadow. tone: { top, back, edge, grain }.
function deskSVG(t) {
  let grain = "";
  for (let i = 0; i < 26; i++) {
    const y = 640 + i * 10 + (i % 3) * 2;
    grain += `<path d="M0 ${y} C 480 ${y - 6 + (i % 4) * 3}, 1300 ${y + 7 - (i % 5) * 2}, 1920 ${y - 2}" stroke="${t.grain}" stroke-width="${1 + (i % 3) * 0.6}" fill="none" opacity="${0.22 + (i % 4) * 0.06}"/>`;
  }
  return `
    <defs>${lin("gDesk", [[0, t.back], [1, t.top]])}${lin("gDeskEdge", [[0, t.edge], [1, "#00000000"]])}</defs>
    <rect x="0" y="628" width="1920" height="282" fill="url(#gDesk)"/>${grain}
    <rect x="0" y="628" width="1920" height="3" fill="#ffffff" opacity=".35"/>
    <rect x="0" y="906" width="1920" height="26" fill="${t.edge}"/><rect x="0" y="906" width="1920" height="2" fill="#ffffff" opacity=".45"/>
    <rect x="0" y="932" width="1920" height="148" fill="url(#gDeskEdge)" opacity=".55"/>`;
}

function mugSVG(x, y, s = 1, accent = "#8d86f4") {
  return `<g transform="translate(${x} ${y}) scale(${s})">
    <ellipse cx="0" cy="62" rx="44" ry="9" fill="url(#gShadow)"/>
    <path d="M40 10 q34 2 34 26 q0 24 -34 26" fill="none" stroke="#e3e6ec" stroke-width="10"/>
    <path d="M-40 0 h80 v52 q0 12 -12 12 h-56 q-12 0 -12 -12 z" fill="url(#gMug)"/>
    <ellipse cx="0" cy="0" rx="40" ry="8" fill="#6b4a36"/><ellipse cx="0" cy="0" rx="40" ry="8" fill="none" stroke="#f4f5f8" stroke-width="3"/>
    <rect x="-40" y="16" width="80" height="10" fill="${accent}" opacity=".55"/>
    <g class="steam" fill="none" stroke="rgba(160,160,180,.45)" stroke-width="4" stroke-linecap="round">
      <path d="M-12 -10 q-10 -18 0 -36 q10 -18 0 -36"/><path d="M14 -10 q-10 -18 0 -36 q10 -18 0 -36"/></g></g>`;
}

function notebookSVG(x, y, rot = -8) {
  return `<g transform="translate(${x} ${y}) rotate(${rot})">
    <rect x="6" y="10" width="240" height="160" rx="10" fill="rgba(40,40,60,.18)" filter="url(#fBlur)"/>
    <rect width="240" height="160" rx="10" fill="#f7f4ee"/><rect width="18" height="160" rx="6" fill="#7a83d8"/>
    ${[38, 66, 94, 122].map((ly, i) => `<path d="M40 ${ly} h${150 - i * 22}" stroke="#d4cec4" stroke-width="5" stroke-linecap="round"/>`).join("")}
    <rect x="150" y="96" width="120" height="9" rx="4.5" fill="#3a3d47" transform="rotate(-24 150 96)"/></g>`;
}

function phoneSVG(x, y, rot = 10) {
  return `<g transform="translate(${x} ${y}) rotate(${rot})"><rect x="4" y="8" width="84" height="40" rx="10" fill="rgba(40,40,60,.2)" filter="url(#fBlur)"/>
    <rect width="84" height="40" rx="10" fill="url(#gPhone)"/><rect x="4" y="4" width="76" height="32" rx="7" fill="#3f4350"/></g>`;
}

// The protagonist from behind, three-quarter view. pose: "type" | "mug". flip mirrors her to the left side.
function personSVG({ x, y, s = 1, flip = false, pose = "type", id = "fg" }) {
  const arm = pose === "mug"
    ? `<path d="M150 230 C 230 300, 250 420, 205 470 L 160 440 C 190 400, 175 330, 120 290 Z" fill="url(#gSweater)"/>
       <path d="M205 470 C 230 420, 250 330, 236 250 L 196 256 C 206 330, 188 400, 160 440 Z" fill="url(#gSweater)"/>
       <ellipse cx="222" cy="236" rx="30" ry="34" fill="url(#gSkin)"/>
       <g transform="translate(232 150) scale(.9)"><path d="M40 10 q34 2 34 26 q0 24 -34 26" fill="none" stroke="#e3e6ec" stroke-width="10"/>
       <path d="M-40 0 h80 v52 q0 12 -12 12 h-56 q-12 0 -12 -12 z" fill="url(#gMug)"/><rect x="-40" y="16" width="80" height="10" fill="#8d86f4" opacity=".55"/>
       <g class="steam" fill="none" stroke="rgba(160,160,180,.5)" stroke-width="4" stroke-linecap="round"><path d="M-10 -10 q-10 -18 0 -36 q10 -18 0 -36"/><path d="M14 -10 q-10 -18 0 -36 q10 -18 0 -36"/></g></g>`
    : "";
  const reach = `<path d="M-170 268 C -220 262, -270 250, -312 244 L -312 290 C -270 296, -224 308, -178 322 Z" fill="url(#gSweater)"/>
       <path d="M-300 242 C -306 258, -306 278, -300 292" stroke="#c2ae96" stroke-width="5" fill="none"/>
       <path d="M-306 248 C -330 244, -356 250, -366 264 C -360 280, -334 290, -306 288 Z" fill="url(#gSkin)"/>`;
  return `<g id="${id}" transform="translate(${x} ${y}) scale(${flip ? -s : s} ${s})">
    <ellipse cx="0" cy="760" rx="330" ry="40" fill="url(#gShadow)"/>
    ${reach}
    <path d="M-262 820 C -272 520, -252 316, -186 252 C -116 196, 116 196, 186 252 C 252 316, 274 520, 264 820 Z" fill="url(#gSweater)"/>
    <path d="M-150 230 C -100 250, -60 300, -40 360" stroke="#c2ae96" stroke-width="5" fill="none" opacity=".6"/>
    <path d="M150 230 C 110 260, 80 310, 70 380" stroke="#c2ae96" stroke-width="5" fill="none" opacity=".5"/>
    <g transform="translate(0 34) scale(.84)">
    <path d="M-62 150 L -46 222 L 46 222 L 60 150 Z" fill="url(#gSkin)"/>
    <path d="M-70 196 C -40 230, 40 230, 72 196 L 82 228 C 40 262, -40 262, -80 228 Z" fill="#f8f8f6"/>
    <path d="M-104 30 C -116 -86, -40 -132, 10 -128 C 80 -124, 124 -70, 112 34 C 108 100, 86 160, 40 176 C 10 186, -30 184, -60 172 C -96 156, -102 100, -104 30 Z" fill="url(#gHair)"/>
    <path d="M-60 -96 C -30 -40, -40 60, -50 150" stroke="#4a4252" stroke-width="3" fill="none" opacity=".7"/>
    <path d="M10 -120 C 30 -50, 40 60, 30 168" stroke="#4a4252" stroke-width="3" fill="none" opacity=".6"/>
    <path d="M70 -96 C 90 -30, 86 70, 70 150" stroke="#4a4252" stroke-width="3" fill="none" opacity=".5"/>
    <ellipse cx="-108" cy="58" rx="14" ry="24" fill="url(#gSkin)"/>
    <path d="M-30 -126 C -10 -60, -20 20, -40 80" stroke="#15131a" stroke-width="4" fill="none" opacity=".8"/>
    <path d="M40 -110 C 80 -80, 96 -20, 92 40" stroke="#6a6074" stroke-width="10" fill="none" opacity=".35" stroke-linecap="round"/>
    </g>
    ${arm}
  </g>`;
}

// Background colleagues: soft, out-of-focus figures.
function colleagueSVG(x, y, s, color) {
  return `<g transform="translate(${x} ${y}) scale(${s})" filter="url(#fBlur)" opacity=".75">
    <circle cx="0" cy="0" r="34" fill="#2e2a33"/><circle cx="0" cy="8" r="30" fill="#e8c9b3"/>
    <path d="M-34 -6 C -30 -44, 30 -44, 34 -6 C 20 -24, -20 -24, -34 -6 Z" fill="#2e2a33"/>
    <path d="M-70 60 C -64 44, -40 38, 0 38 C 40 38, 64 44, 70 60 L 82 260 L -82 260 Z" fill="${color}"/>
    <rect x="-56" y="250" width="40" height="160" rx="16" fill="#3a3d47"/><rect x="16" y="250" width="40" height="160" rx="16" fill="#3a3d47"/></g>`;
}
