// Five places of the day, built from illus-parts.js. The laptop always sits at SCREEN.
const OAK = { top: "#eadfcf", back: "#dccdb9", edge: "#c6b29a", grain: "#c3ab8d" };
const WHITE = { top: "#f7f8fa", back: "#eceef3", edge: "#d6d9e1", grain: "#e0e3e9" };
const WALNUT = { top: "#cfb397", back: "#bea184", edge: "#a2856a", grain: "#987a5e" };
const TRAY = { top: "#dadce2", back: "#cdd0d8", edge: "#b8bcc6", grain: "#c8cbd3" };

function wallSVG(a, b) {
  return `<defs>${lin("gWall" + a.slice(1), [[0, a], [1, b]])}</defs><rect width="1920" height="1080" fill="url(#gWall${a.slice(1)})"/>`;
}

function morningSVG() {
  return { bg: `${wallSVG("#f6f1ea", "#ece4d9")}
    <rect x="70" y="60" width="470" height="500" rx="10" fill="#fff"/>
    <defs>${lin("gSkyM", [[0, "#d9e6f8"], [1, "#f7f0e4"]])}</defs>
    <rect x="88" y="78" width="434" height="464" fill="url(#gSkyM)"/>
    <ellipse cx="300" cy="470" rx="260" ry="60" fill="#e6efe2" opacity=".9"/>
    <path d="M305 78V542M88 310H522" stroke="#fff" stroke-width="14"/>
    <polygon points="88,78 522,78 1120,640 560,640" fill="rgba(255,248,230,.28)"/>
    <rect x="1440" y="190" width="380" height="14" rx="4" fill="#d9cbb8"/>
    ${["#7a83d8", "#e0896b", "#5fa58a", "#c9b07a"].map((c, i) => `<rect x="${1470 + i * 34}" y="${100 + (i % 2) * 10}" width="26" height="${90 - (i % 2) * 10}" rx="3" fill="${c}"/>`).join("")}
    <path d="M1650 190 l-10 -60 h70 l-10 60z" fill="#d9a58b"/><ellipse cx="1675" cy="110" rx="46" ry="34" fill="#7fae95"/><ellipse cx="1650" cy="96" rx="22" ry="34" fill="#6a9a82"/>
    ${deskSVG(OAK)}
    <path d="M470 640 L458 560 H560 L548 640 Z" fill="#e1b39a"/><ellipse cx="510" cy="540" rx="58" ry="40" fill="#86b49b"/><ellipse cx="482" cy="520" rx="26" ry="38" fill="#6f9f87"/>
    ${notebookSVG(250, 700, -8)}${phoneSVG(470, 800, 12)}`, fg: `${personSVG({ x: 1600, y: 450, s: 0.95, pose: "mug" })}` };
}

function meetingSVG() {
  const notes = [[330, 140, "#ffe28a"], [450, 160, "#ffc9c4"], [570, 136, "#cfdcff"], [330, 270, "#d9d2ff"], [450, 282, "#ffe28a"]];
  return { bg: `${wallSVG("#f1f2f6", "#e5e7ee")}
    <rect x="240" y="80" width="1060" height="400" rx="14" fill="#fff" stroke="#d6d9e1" stroke-width="6"/>
    ${notes.map(([x, y, c], i) => `<rect x="${x}" y="${y}" width="100" height="100" rx="5" fill="${c}" transform="rotate(${(i % 3) * 3 - 3} ${x + 50} ${y + 50})"/>`).join("")}
    <path d="M720 180 C 800 140, 900 220, 990 170 S 1120 210, 1160 190" fill="none" stroke="#8d86f4" stroke-width="6" stroke-linecap="round"/>
    <path d="M740 280 h300 M740 320 h230 M740 360 h270" stroke="#c9ccd6" stroke-width="7" stroke-linecap="round"/>
    <rect x="1440" y="40" width="300" height="600" rx="8" fill="#dfe2ea"/><rect x="1460" y="60" width="260" height="580" fill="#f6f7fa"/>
    ${colleagueSVG(1560, 250, 0.85, "#7a83d8")}${colleagueSVG(1680, 280, 0.8, "#5fa58a")}
    ${deskSVG(WHITE)}
    ${notebookSVG(1360, 720, 6)}${mugSVG(1620, 640, 0.85, "#5fa58a")}`, fg: `${personSVG({ x: 330, y: 450, s: 0.95, flip: true, pose: "type" })}` };
}

function afternoonSVG() {
  const bld = [[120, 300, "#bcc2df"], [250, 210, "#a9b0d2"], [380, 330, "#c6cbe6"], [490, 170, "#b2b8da"], [1330, 250, "#b2b8da"],
    [1450, 190, "#a9b0d2"], [1570, 310, "#c6cbe6"], [1680, 230, "#bcc2df"]];
  return { bg: `${wallSVG("#f4efe8", "#eae3da")}
    <rect x="80" y="40" width="1760" height="560" rx="12" fill="#fff"/>
    <defs>${lin("gSkyA", [[0, "#cdd8f4"], [1, "#f6e2cf"]])}</defs>
    <rect x="100" y="60" width="1720" height="520" fill="url(#gSkyA)"/>
    <circle cx="1500" cy="170" r="58" fill="#fff3da" opacity=".9"/>
    ${bld.map(([x, top, c]) => `<rect x="${x}" y="${top}" width="104" height="${580 - top}" fill="${c}"/>` +
      Array.from({ length: Math.floor((580 - top - 30) / 36) }, (_, r) => `<rect x="${x + 16}" y="${top + 22 + r * 36}" width="72" height="9" rx="3" fill="rgba(255,255,255,.5)"/>`).join("")).join("")}
    <path d="M960 60V580" stroke="#fff" stroke-width="16"/>
    ${deskSVG(OAK)}
    ${mugSVG(450, 700, 0.9)}${notebookSVG(170, 760, -4)}
    <path d="M1700 900 v-260" stroke="#3a3d47" stroke-width="10"/>`, fg: `${personSVG({ x: 1610, y: 450, s: 0.95, pose: "type" })}` };
}

function eveningSVG() {
  const books = ["#8d86f4", "#e0896b", "#5fa58a", "#c9b07a", "#7a83d8", "#d9a58b", "#9aa3c2", "#5c72ef"];
  return { bg: `${wallSVG("#efe1d2", "#e2cfbb")}
    <rect x="1320" y="110" width="480" height="470" rx="8" fill="#d6c2ac"/>
    ${[0, 1, 2].map((r) => `<rect x="1320" y="${255 + r * 145}" width="480" height="12" fill="#c3ad95"/>` +
      books.map((c, i) => `<rect x="${1345 + i * 54}" y="${138 + r * 145 + (i % 3) * 8}" width="40" height="${116 - (i % 3) * 8}" rx="4" fill="${c}" opacity=".85"/>`).join("")).join("")}
    <circle cx="420" cy="200" r="86" fill="#fff" stroke="#d9cbbb" stroke-width="10"/>
    <path d="M420 200 V146 M420 200 L466 228" stroke="#3a3d47" stroke-width="8" stroke-linecap="round"/>
    <defs>${rad("gLampGlow", [[0, "rgba(255,210,140,.7)"], [1, "rgba(255,210,140,0)"]], 0.5, 0, 1)}</defs>
    <polygon points="1330,430 1180,720 1640,720 1500,430" fill="url(#gLampGlow)"/>
    ${deskSVG(WALNUT)}
    <path d="M1420 650 v-220" stroke="#3a3d47" stroke-width="10" stroke-linecap="round"/><path d="M1350 440 h140 l-30 -64 h-80z" fill="#3a3d47"/>
    <rect x="1370" y="640" width="100" height="14" rx="7" fill="#3a3d47"/>
    <path d="M1520 760 a70 50 0 1 1 140 0" fill="none" stroke="#2f3138" stroke-width="16" stroke-linecap="round"/>
    <rect x="1505" y="752" width="34" height="46" rx="12" fill="#2f3138"/><rect x="1641" y="752" width="34" height="46" rx="12" fill="#2f3138"/>`, fg: `${personSVG({ x: 320, y: 450, s: 0.95, flip: true, pose: "type" })}
    <rect width="1920" height="1080" fill="rgba(255,165,90,.07)"/>` };
}

function trainSVG() {
  return { bg: `${wallSVG("#e9e6ef", "#dcd8e4")}
    <clipPath id="cWin"><rect x="80" y="90" width="1500" height="430" rx="60"/></clipPath>
    <defs>${lin("gDusk", [[0, "#6d6bb5"], [0.55, "#d69aa6"], [1, "#f5c99a"]])}</defs>
    <g clip-path="url(#cWin)">
      <rect x="80" y="90" width="1500" height="430" fill="url(#gDusk)"/>
      <circle cx="1200" cy="420" r="46" fill="#ffe0b0" opacity=".9"/>
      <g id="hillsFar"><path d="M0 430 Q240 340 480 420 T960 410 T1440 420 T1920 400 T2400 420 T2880 410 T3360 420 T3840 400 V600 H0Z" fill="#8a82b8"/></g>
      <g id="hillsNear"><path d="M0 480 Q200 420 400 470 T800 460 T1200 475 T1600 455 T2000 470 T2400 460 T2800 475 T3200 455 T3600 470 T3840 460 V600 H0Z" fill="#5d5a8f"/></g>
      <g id="poles">${[0, 1, 2, 3].map((i) => `<rect x="${i * 640}" y="130" width="10" height="420" fill="#3b3a5a"/><path d="M${i * 640} 170 h640" stroke="#3b3a5a" stroke-width="2.5" opacity=".7"/>`).join("")}</g>
    </g>
    <rect x="80" y="90" width="1500" height="430" rx="60" fill="none" stroke="#d3cfdc" stroke-width="16"/>
    <path d="M60 560 h1560" stroke="#cfcadb" stroke-width="10"/>
    ${deskSVG(TRAY)}
    <path d="M1380 640 l10 -86 h60 l10 86z" fill="#f4f1ec"/><rect x="1386" y="574" width="68" height="14" fill="#8d86f4" opacity=".6"/>
`, fg: `<path d="M1460 1080 V420 C1460 360, 1500 330, 1560 330 H1820 C1880 330, 1910 370, 1910 420 V1080 Z" fill="#6c6f8f"/>
    <rect x="1500" y="350" width="370" height="120" rx="40" fill="#7d80a0"/>${personSVG({ x: 1640, y: 470, s: 0.92, pose: "type" })}` };
}

const PLACES = { morning: morningSVG, meeting: meetingSVG, afternoon: afternoonSVG, evening: eveningSVG, train: trainSVG };

function defsSVG() {
  return `<defs>${partsDefs()}</defs>`;
}

// Per-frame motion inside the illustrations (steam drift, train parallax).
function animateIllus(t) {
  document.querySelectorAll(".steam").forEach((g, i) => {
    g.setAttribute("transform", `translate(0 ${-((t * 18 + i * 7) % 30)})`);
    g.setAttribute("opacity", (0.55 + 0.4 * Math.sin(t * 2 + i)).toFixed(2));
  });
  const move = (id, speed, period) => {
    const g = document.getElementById(id);
    if (g) g.setAttribute("transform", `translate(${-((t * speed) % period)} 0)`);
  };
  move("hillsFar", 40, 960);
  move("hillsNear", 160, 800);
  move("poles", 900, 640);
}
