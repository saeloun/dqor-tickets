/**
 * Theme — Deccan Queen on Rails
 * Runs immediately in <head> to apply theme before paint (no flash).
 * Toggle wiring is handled by nav.js after it injects the button.
 */
(function () {
  var STORAGE_KEY = 'dqor-theme';

  function getSystemTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(theme) {
    if (theme === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark');
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
  }

  function getStoredTheme() {
    try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }

  function storeTheme(theme) {
    try { localStorage.setItem(STORAGE_KEY, theme); } catch (e) {}
  }

  function getCurrentTheme() {
    return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
  }

  // Apply immediately — before body renders
  applyTheme(getStoredTheme() || getSystemTheme());

  // Re-apply when system preference changes (only if user hasn't overridden)
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function (e) {
    if (!getStoredTheme()) applyTheme(e.matches ? 'dark' : 'light');
  });

  // Expose for nav.js to wire up toggle buttons
  window.__dqorTheme = { applyTheme, storeTheme, getCurrentTheme };
})();
