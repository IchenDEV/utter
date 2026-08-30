// Utter site — language toggle, color theme toggle, sticky nav state, copy button.
// Zero dependencies.

(() => {
  "use strict";

  const store = {
    get(key) { try { return localStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); } catch { /* private mode */ } },
  };

  const setQueryParam = (key, value) => {
    const url = new URL(location.href);
    url.searchParams.set(key, value);
    history.replaceState(null, "", url);
  };

  // ---- Language (EN / 简体中文) ------------------------------------------
  const langToggle = document.getElementById("lang-toggle");
  let lang = new URLSearchParams(location.search).get("lang")
    || store.get("utter-lang")
    || (navigator.language && navigator.language.startsWith("zh") ? "zh" : "en");

  const applyLang = (next) => {
    lang = next;
    store.set("utter-lang", lang);
    document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
    document.querySelectorAll("[data-en]").forEach((el) => {
      el.innerHTML = lang === "zh" ? el.dataset.zh : el.dataset.en;
    });
    if (langToggle) langToggle.textContent = lang === "zh" ? "EN" : "中文";
    setQueryParam("lang", lang);
  };
  if (langToggle) langToggle.addEventListener("click", () => applyLang(lang === "zh" ? "en" : "zh"));
  applyLang(lang);

  // ---- Color theme (light / dark, follows prefers-color-scheme by default)
  const themeToggle = document.getElementById("theme-toggle");
  let theme = new URLSearchParams(location.search).get("theme")
    || store.get("utter-theme")
    || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");

  const applyTheme = (next) => {
    theme = next;
    store.set("utter-theme", theme);
    document.documentElement.dataset.theme = theme;
    if (themeToggle) themeToggle.textContent = theme === "dark" ? "☾" : "◐";
    setQueryParam("theme", theme);
  };
  if (themeToggle) themeToggle.addEventListener("click", () => applyTheme(theme === "dark" ? "light" : "dark"));
  applyTheme(theme);

  // ---- Sticky nav hairline + blur once the page scrolls ------------------
  const nav = document.getElementById("site-nav");
  const syncNav = () => {
    if (nav) nav.classList.toggle("scrolled", window.scrollY > 24);
  };
  window.addEventListener("scroll", syncNav, { passive: true });
  syncNav();

  // ---- Copy the Gatekeeper command ---------------------------------------
  const installCode = document.getElementById("install-code");
  const copyLabel = document.getElementById("copy-label");
  if (installCode && copyLabel) {
    const original = () => (copyLabel.dataset[lang] || "copy");
    installCode.addEventListener("click", async () => {
      const command = installCode.querySelector("code")?.textContent.trim() ?? "";
      try {
        await navigator.clipboard.writeText(command);
        copyLabel.textContent = lang === "zh" ? "已复制 ✓" : "copied ✓";
      } catch {
        copyLabel.textContent = lang === "zh" ? "复制失败" : "copy failed";
      }
      setTimeout(() => { copyLabel.textContent = original(); }, 1600);
    });
  }
})();
