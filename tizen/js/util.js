/* Small helpers shared by every screen. Written for the Chromium versions
   inside Samsung TVs from 2018 on (Tizen 4+): no optional chaining, no
   object spread, no CSS grid. */
'use strict';

var HS = window.HS || {};
window.HS = HS;

/* Element builder: el('div.card.focusable', {onclick: f}, [children]) */
HS.el = function (spec, attrs, children) {
  var parts = spec.split('.');
  var node = document.createElement(parts[0] || 'div');
  if (parts.length > 1) node.className = parts.slice(1).join(' ');
  if (attrs) {
    Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (v === undefined || v === null || v === false) return;
      if (k === 'text') node.textContent = v;
      else if (k === 'html') node.innerHTML = v;
      else if (k === 'style' && typeof v === 'object') Object.assign(node.style, v);
      else if (k.indexOf('on') === 0 && typeof v === 'function') node[k] = v;
      else if (k === 'data' && typeof v === 'object') {
        Object.keys(v).forEach(function (d) { node.dataset[d] = v[d]; });
      } else node.setAttribute(k, v === true ? '' : v);
    });
  }
  if (children) {
    (Array.isArray(children) ? children : [children]).forEach(function (c) {
      if (c === null || c === undefined || c === false) return;
      node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    });
  }
  return node;
};

HS.clear = function (node) {
  while (node.firstChild) node.removeChild(node.firstChild);
  return node;
};

HS.pad2 = function (n) { return (n < 10 ? '0' : '') + n; };

/* 3725 -> "1:02:05", 125 -> "2:05" */
HS.clock = function (sec) {
  sec = Math.max(0, Math.floor(sec || 0));
  var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
  return (h > 0 ? h + ':' + HS.pad2(m) : m) + ':' + HS.pad2(s);
};

/* 5400 -> "1 sa 30 dk" */
HS.duration = function (sec) {
  if (!sec || sec <= 0) return '';
  var m = Math.round(sec / 60);
  if (m < 60) return m + ' dk';
  var h = Math.floor(m / 60);
  m = m % 60;
  return h + ' sa' + (m ? ' ' + m + ' dk' : '');
};

HS.episodeCode = function (it) {
  return 'S' + HS.pad2(it.season || 0) + 'E' + HS.pad2(it.episode || 0);
};

/* "Dizi · S01E02 · Bölüm adı" for episodes, the title otherwise. */
HS.displayTitle = function (it) {
  if (it.type !== 'episode') return it.title;
  var t = (it.seriesTitle ? it.seriesTitle + ' · ' : '') + HS.episodeCode(it);
  return t + (it.title ? ' · ' + it.title : '');
};

HS.progress = function (it) {
  var u = it.userData || {};
  if (!it.duration || !u.position) return 0;
  return Math.min(1, Math.max(0, u.position / it.duration));
};

HS.inProgress = function (it) {
  var u = it.userData || {};
  return u.position > 5 && !u.played;
};

HS.resolutionLabel = function (f) {
  if (!f) return '';
  var w = f.width || 0, h = f.height || 0;
  if (w >= 3200 || h >= 2000) return '4K';
  if (w >= 2400 || h >= 1400) return '1440p';
  if (w >= 1800 || h >= 1000) return '1080p';
  if (w >= 1200 || h >= 700) return '720p';
  if (h > 0) return 'SD';
  return '';
};

var LANGS = {
  tur: 'Türkçe', tr: 'Türkçe', eng: 'İngilizce', en: 'İngilizce', ger: 'Almanca', deu: 'Almanca',
  de: 'Almanca', fre: 'Fransızca', fra: 'Fransızca', fr: 'Fransızca', spa: 'İspanyolca', es: 'İspanyolca',
  ita: 'İtalyanca', it: 'İtalyanca', jpn: 'Japonca', ja: 'Japonca', kor: 'Korece', ko: 'Korece',
  rus: 'Rusça', ru: 'Rusça', ara: 'Arapça', ar: 'Arapça', und: ''
};
HS.langName = function (code) {
  if (!code) return '';
  var c = String(code).toLowerCase();
  return LANGS.hasOwnProperty(c) ? LANGS[c] : code.toUpperCase();
};

HS.store = {
  get: function (k, def) {
    try {
      var v = localStorage.getItem('hs.' + k);
      return v === null ? def : JSON.parse(v);
    } catch (e) { return def; }
  },
  set: function (k, v) {
    try {
      if (v === undefined || v === null) localStorage.removeItem('hs.' + k);
      else localStorage.setItem('hs.' + k, JSON.stringify(v));
    } catch (e) { /* storage full or blocked: settings just aren't kept */ }
  }
};

var toastTimer = null;
HS.toast = function (msg, ms) {
  var t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'show';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(function () { t.className = ''; }, ms || 3000);
};

HS.isTizen = function () {
  return typeof window.tizen !== 'undefined';
};
HS.hasAvplay = function () {
  return typeof window.webapis !== 'undefined' && !!window.webapis.avplay;
};

/* Accent colours, the same pairs as the other apps. */
HS.themes = [
  ['violet', 'Mor Gece', '#8B5CF6', '#EC4899'],
  ['ocean', 'Okyanus', '#06B6D4', '#3B82F6'],
  ['sunset', 'Gün Batımı', '#F97316', '#EF4444'],
  ['emerald', 'Zümrüt', '#10B981', '#84CC16'],
  ['cinema', 'Sinema', '#E50914', '#FF5F6D'],
  ['gold', 'Altın Saat', '#F59E0B', '#F43F5E'],
  ['aurora', 'Kuzey Işıkları', '#22D3EE', '#A78BFA'],
  ['rose', 'Gül Kurusu', '#F472B6', '#FB923C']
];
HS.applyTheme = function (id) {
  var t = HS.themes[0];
  HS.themes.forEach(function (x) { if (x[0] === id) t = x; });
  document.documentElement.style.setProperty('--accent', t[2]);
  document.documentElement.style.setProperty('--accent2', t[3]);
  return t[0];
};
