// NUI locale helper. English text stays in the HTML as the default, so the page is never blank if the
// dictionary is late; once the dictionary arrives applyI18n() swaps in the chosen language.
// Markup: put the English text in the element and the key in an attribute - data-i18n (text), data-i18n-placeholder,
// data-i18n-title or data-i18n-aria-label. Once the dictionary arrives applyI18n() swaps the text for the chosen language.
// In JS use t(key, a, b) with a quoted key: %s / %d placeholders are filled in order; a missing key returns the key.
var I18N = {};
function t(key) {
    var s = Object.prototype.hasOwnProperty.call(I18N, key) ? I18N[key] : key;
    var args = Array.prototype.slice.call(arguments, 1), i = 0;
    return String(s).replace(/%[sd]/g, function () { return i < args.length ? args[i++] : ''; });
}
function applyI18n(root) {
    root = root || document;
    root.querySelectorAll('[data-i18n]').forEach(function (el) { if (I18N[el.dataset.i18n] != null) el.textContent = t(el.dataset.i18n); });
    ['placeholder', 'title', 'aria-label'].forEach(function (a) {
        root.querySelectorAll('[data-i18n-' + a + ']').forEach(function (el) {
            var k = el.getAttribute('data-i18n-' + a); if (I18N[k] != null) el.setAttribute(a, t(k));
        });
    });
}
// RESOURCE = this resource's name. client/main.lua answers the 'as-postalprime/locale' NUI callback with LocaleDict();
// like every other callback of this resource the URL is https://as-postalprime/as-postalprime/<name>.
var RESOURCE = 'as-postalprime';
// The page can load a moment before client/main.lua has registered the callback (resource start), so a failed
// request is retried a few times; cb runs once the dictionary is in (or after the last attempt).
var I18N_LOADED = false;
function loadLocale(cb, attempt) {
    attempt = attempt || 0;
    fetch('https://' + RESOURCE + '/' + RESOURCE + '/locale', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })
        .then(function (r) { return r.json(); })
        .then(function (d) { if (d && typeof d === 'object') { I18N = d; I18N_LOADED = true; } applyI18n(); if (cb) cb(); },
            function () {
                if (attempt < 8) setTimeout(function () { loadLocale(cb, attempt + 1); }, 1000 + attempt * 500);
                else if (cb) cb();
            });
}
