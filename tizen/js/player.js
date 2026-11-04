/* Video player. On a Samsung TV it uses AVPlay (the TV's own hardware
   player: mkv, hevc, hdr, eac3 and embedded subtitles work as on the TV's
   USB player). In a desktop browser it falls back to <video> for testing. */
'use strict';

var LANG3 = { tr: 'tur', turkish: 'tur', 'türkçe': 'tur', en: 'eng', english: 'eng', de: 'ger', deu: 'ger',
  fr: 'fre', fra: 'fre', es: 'spa', it: 'ita', ja: 'jpn', ko: 'kor', ru: 'rus', ar: 'ara' };
function lang3(l) {
  var s = String(l || '').toLowerCase();
  return LANG3[s] || s;
}
HS.langMatches = function (a, b) {
  return !!a && !!b && lang3(a) === lang3(b);
};

/* ---------------- AVPlay engine ---------------- */
function AvplayEngine() {
  this.av = webapis.avplay;
}
AvplayEngine.prototype.open = function (url, startSec, cb, opts) {
  var av = this.av, self = this;
  this.cb = cb;
  return new Promise(function (resolve, reject) {
    try {
      try { av.stop(); av.close(); } catch (e) { /* nothing open */ }
      av.open(url);
      av.setDisplayRect(0, 0, 1920, 1080);
      try { av.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX'); } catch (e) { /* older firmware */ }
      if (opts && opts.uhd) {
        try { av.setStreamingProperty('SET_MODE_4K', 'TRUE'); } catch (e) { /* not a 4K TV */ }
      }
      av.setListener({
        onbufferingstart: function () { cb.onBuffering(true); },
        onbufferingprogress: function () { },
        onbufferingcomplete: function () { cb.onBuffering(false); },
        oncurrentplaytime: function (ms) { cb.onTime(ms / 1000); },
        onstreamcompleted: function () { cb.onEnded(); },
        onerror: function (e) { cb.onError('Oynatma hatası: ' + e); },
        onevent: function () { },
        onsubtitlechange: function (duration, text) { cb.onSubtitle(text || '', duration); },
        ondrmevent: function () { }
      });
      av.prepareAsync(function () {
        var go = function () {
          try { av.play(); } catch (e) { reject(e); return; }
          cb.onDuration(self.duration());
          resolve();
        };
        if (startSec > 1) av.seekTo(Math.floor(startSec * 1000), go, go);
        else go();
      }, function (e) {
        reject(new Error('Video açılamadı (' + (e && e.name ? e.name : e) + ')'));
      });
    } catch (e) {
      reject(new Error('Video açılamadı: ' + (e.message || e.name || e)));
    }
  });
};
AvplayEngine.prototype.state = function () {
  try { return this.av.getState(); } catch (e) { return 'NONE'; }
};
AvplayEngine.prototype.play = function () { try { this.av.play(); } catch (e) { /* wrong state */ } };
AvplayEngine.prototype.pause = function () { try { this.av.pause(); } catch (e) { /* wrong state */ } };
AvplayEngine.prototype.paused = function () { return this.state() === 'PAUSED'; };
AvplayEngine.prototype.time = function () {
  try { return this.av.getCurrentTime() / 1000; } catch (e) { return 0; }
};
AvplayEngine.prototype.duration = function () {
  try { return this.av.getDuration() / 1000; } catch (e) { return 0; }
};
AvplayEngine.prototype.seek = function (sec, done) {
  var cb = done || function () { };
  try { this.av.seekTo(Math.max(0, Math.floor(sec * 1000)), cb, cb); } catch (e) { cb(); }
};
AvplayEngine.prototype.tracks = function (kind) {
  var out = [];
  try {
    var info = this.av.getTotalTrackInfo();
    for (var i = 0; i < info.length; i++) {
      var t = info[i];
      if (t.type !== kind) continue;
      var extra = {};
      try { extra = JSON.parse(t.extra_info || '{}'); } catch (e) { /* not JSON */ }
      out.push({
        index: t.index,
        language: extra.language || extra.track_lang || '',
        channels: parseInt(extra.channels || '0', 10) || 0,
        codec: extra.fourCC || ''
      });
    }
  } catch (e) { /* no track info yet */ }
  return out;
};
AvplayEngine.prototype.currentTrack = function (kind) {
  try {
    var cur = this.av.getCurrentStreamInfo();
    for (var i = 0; i < cur.length; i++) if (cur[i].type === kind) return cur[i].index;
  } catch (e) { /* not ready */ }
  return -1;
};
AvplayEngine.prototype.setAudio = function (index) {
  try { this.av.setSelectTrack('AUDIO', index); } catch (e) { HS.toast('Ses dili değiştirilemedi'); }
};
AvplayEngine.prototype.setText = function (index) {
  try {
    if (index < 0) { this.av.setSilentSubtitle(true); return; }
    this.av.setSelectTrack('TEXT', index);
    this.av.setSilentSubtitle(false);
  } catch (e) { HS.toast('Altyazı açılamadı'); }
};
AvplayEngine.prototype.suspend = function () { try { this.av.suspend(); } catch (e) { /* not playing */ } };
AvplayEngine.prototype.restore = function () { try { this.av.restore(); } catch (e) { /* not suspended */ } };
AvplayEngine.prototype.close = function () {
  try { this.av.stop(); } catch (e) { /* already stopped */ }
  try { this.av.close(); } catch (e) { /* already closed */ }
};

/* ---------------- <video> engine (desktop browser) ---------------- */
function VideoEngine(host) {
  this.v = HS.el('video.html5video', { playsinline: true });
  host.appendChild(this.v);
}
VideoEngine.prototype.open = function (url, startSec, cb) {
  var v = this.v;
  return new Promise(function (resolve, reject) {
    var started = false;
    v.onwaiting = function () { cb.onBuffering(true); };
    v.onplaying = function () { cb.onBuffering(false); };
    v.ontimeupdate = function () { cb.onTime(v.currentTime); };
    v.onended = function () { cb.onEnded(); };
    v.onerror = function () {
      var msg = 'Bu tarayıcı videoyu açamadı (dosya biçimi desteklenmiyor olabilir).';
      if (!started) reject(new Error(msg)); else cb.onError(msg);
    };
    v.onloadedmetadata = function () {
      if (startSec > 1) v.currentTime = startSec;
      cb.onDuration(v.duration || 0);
      var p = v.play();
      started = true;
      if (p && p.catch) p.catch(function () { /* autoplay blocked: user presses play */ });
      resolve();
    };
    v.src = url;
  });
};
VideoEngine.prototype.play = function () { var p = this.v.play(); if (p && p.catch) p.catch(function () { }); };
VideoEngine.prototype.pause = function () { this.v.pause(); };
VideoEngine.prototype.paused = function () { return this.v.paused; };
VideoEngine.prototype.time = function () { return this.v.currentTime || 0; };
VideoEngine.prototype.duration = function () { return isFinite(this.v.duration) ? this.v.duration : 0; };
VideoEngine.prototype.seek = function (sec, done) { this.v.currentTime = Math.max(0, sec); if (done) done(); };
VideoEngine.prototype.tracks = function (kind) {
  var out = [];
  if (kind === 'AUDIO' && this.v.audioTracks) {
    for (var i = 0; i < this.v.audioTracks.length; i++) {
      out.push({ index: i, language: this.v.audioTracks[i].language || '', channels: 0 });
    }
  }
  return out;
};
VideoEngine.prototype.currentTrack = function (kind) {
  if (kind === 'AUDIO' && this.v.audioTracks) {
    for (var i = 0; i < this.v.audioTracks.length; i++) if (this.v.audioTracks[i].enabled) return i;
  }
  return -1;
};
VideoEngine.prototype.setAudio = function (index) {
  var at = this.v.audioTracks;
  if (!at) return;
  for (var i = 0; i < at.length; i++) at[i].enabled = i === index;
};
VideoEngine.prototype.setText = function () { };
VideoEngine.prototype.suspend = function () { this.v.pause(); };
VideoEngine.prototype.restore = function () { };
VideoEngine.prototype.close = function () {
  this.v.pause();
  this.v.removeAttribute('src');
  try { this.v.load(); } catch (e) { /* ignore */ }
  if (this.v.parentNode) this.v.parentNode.removeChild(this.v);
};

/* ---------------- Player screen ---------------- */
var el = HS.el;

HS.openPlayer = function (item, startSec, onClosed) {
  var api = HS.app.api;
  var P = {
    item: item, ended: false, closing: false, lastReported: 0, lastPos: startSec || 0,
    dur: item.duration || 0, ctrlTimer: null, seekTarget: null, seekTimer: null,
    extCues: null, extId: null, avText: '', avTextTimer: null, textIndex: -1
  };

  var root = el('div.player', {}, []);
  var videoHost = el('div.player-video');
  var subsBox = el('div.player-subs');
  var spinner = el('div.spinner');
  var title = el('div.player-title', {}, [
    el('div.pt-main', { text: item.type === 'episode' ? (item.seriesTitle || item.title) : item.title }),
    item.type === 'episode' ? el('div.pt-sub', { text: HS.episodeCode(item) + (item.title ? ' · ' + item.title : '') }) : null
  ]);
  var timeCur = el('span.ptime', { text: '0:00' });
  var timeDur = el('span.ptime', { text: HS.clock(P.dur) });
  var barFill = el('div.pbar-fill');
  var barSeek = el('div.pbar-seek');
  var bar = el('div.pbar.focusable', {}, [el('div.pbar-track', {}, [barFill, barSeek])]);
  var btnPlay = el('div.pbtn.focusable', { text: '❚❚', onclick: togglePlay });
  var btnBack = el('div.pbtn.focusable', { text: '↺ 10', onclick: function () { seekBy(-10); } });
  var btnFwd = el('div.pbtn.focusable', { text: '30 ↻', onclick: function () { seekBy(30); } });
  var btnAudio = el('div.pbtn.wide.focusable', { text: 'Ses', onclick: function () { trackMenu('AUDIO'); } });
  var btnSubs = el('div.pbtn.wide.focusable', { text: 'Altyazı', onclick: function () { trackMenu('TEXT'); } });
  var btnNext = el('div.pbtn.wide.focusable', { text: item.type === 'episode' ? 'Sonraki bölüm ▸' : 'Sonraki ▸', style: { display: 'none' }, onclick: playNext });
  var controls = el('div.player-controls', {}, [
    title,
    el('div.player-bottom', {}, [
      el('div.pbar-row', {}, [timeCur, bar, timeDur]),
      el('div.pbtn-row', {}, [btnBack, btnPlay, btnFwd, el('div.spacer'), btnAudio, btnSubs, btnNext])
    ])
  ]);
  var osd = el('div.player-osd');
  root.appendChild(videoHost);
  root.appendChild(subsBox);
  root.appendChild(spinner);
  root.appendChild(osd);
  root.appendChild(controls);
  document.body.appendChild(root);
  document.body.classList.add('playing');

  var engine = HS.hasAvplay() ? new AvplayEngine() : new VideoEngine(videoHost);
  var nextItem = null;

  var layer = HS.nav.push({
    root: controls,
    focusFirst: false,
    onKey: onKey,
    onBack: function () { close(); return true; },
    onClose: function () { }
  });

  function showControls(autoHide) {
    var wasHidden = !root.classList.contains('show-ui');
    root.classList.add('show-ui');
    if (wasHidden || !HS.nav.current()) HS.nav.focus(btnPlay);
    clearTimeout(P.ctrlTimer);
    if (autoHide !== false) {
      P.ctrlTimer = setTimeout(function () {
        if (!engine.paused() && !P.ended) hideControls();
      }, 5000);
    }
  }
  function hideControls() {
    root.classList.remove('show-ui');
    clearTimeout(P.ctrlTimer);
  }
  function uiVisible() { return root.classList.contains('show-ui'); }

  function flash(text) {
    osd.textContent = text;
    osd.classList.add('show');
    clearTimeout(osd._t);
    osd._t = setTimeout(function () { osd.classList.remove('show'); }, 1200);
  }

  function updateTime(t) {
    if (P.seekTarget === null) P.lastPos = t;
    var d = P.dur || engine.duration();
    timeCur.textContent = HS.clock(P.seekTarget !== null ? P.seekTarget : t);
    barFill.style.width = d > 0 ? (Math.min(1, t / d) * 100) + '%' : '0';
    if (P.extCues) {
      var txt = HS.cuesAt(P.extCues, t);
      if (txt !== subsBox._txt) {
        subsBox._txt = txt;
        subsBox.innerHTML = txt ? '<span>' + HS.cueHtml(txt) + '</span>' : '';
      }
    }
  }

  function togglePlay() {
    if (P.ended) return;
    if (engine.paused()) {
      engine.play();
      btnPlay.textContent = '❚❚';
      flash('▶');
      showControls();
    } else {
      engine.pause();
      btnPlay.textContent = '▶';
      flash('❚❚');
      report(true);
      showControls(false);
    }
  }

  /* Several presses add up; the seek runs once they stop. */
  function seekBy(delta) {
    var d = P.dur || engine.duration();
    var base = P.seekTarget !== null ? P.seekTarget : engine.time();
    var t = Math.max(0, base + delta);
    if (d > 0) t = Math.min(d - 2, t);
    P.seekTarget = t;
    timeCur.textContent = HS.clock(t);
    barSeek.style.left = d > 0 ? (t / d * 100) + '%' : '0';
    root.classList.add('seeking');
    flash((delta > 0 ? '» ' : '« ') + HS.clock(t));
    clearTimeout(P.seekTimer);
    P.seekTimer = setTimeout(function () {
      var target = P.seekTarget;
      spinner.classList.add('show');
      engine.seek(target, function () {
        P.seekTarget = null;
        P.lastPos = target;
        root.classList.remove('seeking');
        spinner.classList.remove('show');
        updateTime(target);
      });
    }, 700);
  }

  function onKey(code) {
    var K = HS.KEY;
    if (P.ended) return false;
    switch (code) {
      case K.PLAY_PAUSE: togglePlay(); return true;
      case K.PLAY: if (engine.paused()) togglePlay(); return true;
      case K.PAUSE: if (!engine.paused()) togglePlay(); return true;
      case K.STOP: close(); return true;
      case K.FF: seekBy(30); showControls(); return true;
      case K.RW: seekBy(-10); showControls(); return true;
      case K.CH_UP: seekBy(300); return true;
      case K.CH_DOWN: seekBy(-300); return true;
    }
    if (!uiVisible()) {
      if (code === K.LEFT) { seekBy(-10); return true; }
      if (code === K.RIGHT) { seekBy(10); return true; }
      if (code === K.ENTER) { togglePlay(); return true; }
      if (code === K.UP || code === K.DOWN || code === K.INFO) { showControls(); return true; }
      return false;
    }
    showControls(!engine.paused());
    if (HS.nav.current() === bar && (code === K.LEFT || code === K.RIGHT)) {
      seekBy(code === K.LEFT ? -10 : 10);
      return true;
    }
    if (code === K.ENTER && HS.nav.current() === bar) { togglePlay(); return true; }
    return false; // arrows move between buttons
  }

  function report(force) {
    if (P.ended) return;
    var pos = P.lastPos, d = P.dur || engine.duration();
    if (d <= 0 || pos <= 0) return;
    if (!force && Math.abs(pos - P.lastReported) < 2) return;
    P.lastReported = pos;
    api.progress(item.id, pos, d).catch(function () { /* next report retries */ });
  }
  var reportTimer = setInterval(function () { if (!engine.paused()) report(false); }, 10000);

  function onVisibility() {
    if (document.hidden) {
      report(true);
      engine.suspend();
    } else {
      engine.restore();
    }
  }
  document.addEventListener('visibilitychange', onVisibility);

  /* ---- tracks ---- */
  function audioLabel(t, i) {
    var meta = item.file && item.file.audio ? item.file.audio[i] : null;
    var lang = (meta && meta.language) || t.language;
    var name = (meta && meta.title) || HS.langName(lang) || ('Ses ' + (i + 1));
    var ch = (meta && meta.channels) || t.channels;
    if (ch) name += ch >= 6 ? ' · ' + (ch - 1) + '.1' : ch === 2 ? ' · Stereo' : '';
    return name;
  }
  function textOptions() {
    var opts = [{ label: 'Kapalı', kind: 'off' }];
    var meta = (item.file && item.file.subtitles) || [];
    engine.tracks('TEXT').forEach(function (t, i) {
      var m = meta[i] || {};
      var lang = m.language || t.language;
      var lbl = m.title || HS.langName(lang) || ('Altyazı ' + (i + 1));
      if (m.forced && lbl.toLowerCase().indexOf('forced') < 0) lbl += ' (zorunlu)';
      opts.push({ label: lbl, kind: 'emb', index: t.index, language: lang, forced: !!m.forced || /forced/i.test(m.title || '') });
    });
    ((item.file && item.file.externalSubtitles) || []).forEach(function (s) {
      if (['srt', 'vtt', 'ass', 'ssa'].indexOf(String(s.format).toLowerCase()) < 0) return;
      opts.push({ label: (s.title || HS.langName(s.language) || 'Altyazı') + ' · dosya', kind: 'ext', sub: s,
        language: s.language, forced: /forced/i.test(s.title || '') });
    });
    return opts;
  }
  function currentTextKey() {
    if (P.extId) return 'ext:' + P.extId;
    if (P.textIndex >= 0) return 'emb:' + P.textIndex;
    return 'off';
  }
  function selectText(o, remember) {
    subsBox.innerHTML = '';
    subsBox._txt = '';
    P.extCues = null;
    P.extId = null;
    P.textIndex = -1;
    if (o.kind === 'off') {
      engine.setText(-1);
    } else if (o.kind === 'emb') {
      P.textIndex = o.index;
      engine.setText(o.index);
    } else {
      engine.setText(-1);
      P.extId = o.sub.id;
      api.subtitleText(o.sub.url).then(function (text) {
        if (P.extId !== o.sub.id) return;
        P.extCues = HS.parseSubtitles(text, o.sub.format);
        if (!P.extCues.length) HS.toast('Altyazı dosyası okunamadı');
      }, function (e) { HS.toast(e.message); });
    }
    if (remember) HS.store.set('subChoice', o.kind === 'off' ? 'off' : 'on:' + lang3(o.language || ''));
  }
  function autoPickTracks() {
    // Audio: the user's last pick in the session, else the file's default.
    var audioLang = '';
    var at = engine.tracks('AUDIO');
    var curA = engine.currentTrack('AUDIO');
    at.forEach(function (t, i) { if (t.index === curA) audioLang = ((item.file && item.file.audio && item.file.audio[i]) || {}).language || t.language; });

    var opts = textOptions().slice(1);
    if (!opts.length) return;
    var choice = HS.store.get('subChoice', '');
    var pref = HS.store.get('subLang', 'tur');
    var full = opts.filter(function (o) { return !o.forced; });
    var pick = null;
    if (choice === 'off') pick = null;
    else if (choice.indexOf('on:') === 0) {
      var pool = full.length ? full : opts;
      var l = choice.slice(3);
      pick = pool.filter(function (o) { return l && HS.langMatches(o.language, l); })[0] ||
        pool.filter(function (o) { return HS.langMatches(o.language, pref); })[0] || pool[0];
    } else if (pref !== 'off') {
      var matching = opts.filter(function (o) { return HS.langMatches(o.language, pref); });
      if (HS.langMatches(audioLang, pref)) pick = matching.filter(function (o) { return o.forced; })[0] || null;
      else pick = matching.filter(function (o) { return !o.forced; })[0] || matching[0] || null;
    }
    if (pick) selectText(pick, false);
  }

  function trackMenu(kind) {
    var opts, curKey;
    if (kind === 'AUDIO') {
      var cur = engine.currentTrack('AUDIO');
      opts = engine.tracks('AUDIO').map(function (t, i) {
        return { label: audioLabel(t, i), key: 'a:' + t.index, index: t.index };
      });
      curKey = 'a:' + cur;
      if (!opts.length) { HS.toast('Başka ses dili yok'); return; }
    } else {
      opts = textOptions().map(function (o) {
        o.key = o.kind === 'off' ? 'off' : o.kind === 'emb' ? 'emb:' + o.index : 'ext:' + o.sub.id;
        return o;
      });
      curKey = currentTextKey();
      if (opts.length === 1) { HS.toast('Bu videoda altyazı yok'); return; }
    }
    clearTimeout(P.ctrlTimer);
    HS.listDialog(kind === 'AUDIO' ? 'Ses' : 'Altyazı', opts.map(function (o) {
      return { label: o.label, selected: o.key === curKey, value: o };
    }), function (o) {
      if (kind === 'AUDIO') engine.setAudio(o.index);
      else selectText(o, true);
      showControls();
    });
  }

  /* ---- end / next ---- */
  function loadNext() {
    api.related(item.id).then(function (r) {
      nextItem = r && r.next ? r.next : null;
      if (nextItem) btnNext.style.display = '';
    }, function () { });
  }
  function playNext() {
    if (!nextItem) return;
    var n = nextItem;
    report(true);
    finish(function () {
      api.item(n.id).then(function (full) {
        HS.openPlayer(full, HS.inProgress(full) ? full.userData.position : 0, onClosed);
      }, function (e) { HS.toast(e.message); if (onClosed) onClosed(); });
    });
  }
  function onEnded() {
    if (P.ended || P.closing) return;
    var d = P.dur || engine.duration();
    if (d > 0) api.progress(item.id, d, d).catch(function () { });
    P.ended = true;
    if (!nextItem) { close(true); return; }
    hideControls();
    var secs = 10;
    var count = el('div.end-count', { text: '' });
    var playBtn = el('div.btn.primary.focusable', { text: '▶  Şimdi oynat', onclick: function () { stop(); playNext(); } });
    var closeBtn = el('div.btn.focusable', { text: 'Kapat', onclick: function () { stop(); close(true); } });
    var box = el('div.endcard', {}, [
      el('img.endcard-img', { src: api.image(nextItem.backdrop || nextItem.thumb, 780) }),
      el('div.endcard-body', {}, [
        el('div.endcard-label', { text: nextItem.type === 'episode' ? 'Sıradaki bölüm' : 'Sıradaki' }),
        el('div.endcard-title', { text: HS.displayTitle(nextItem) }),
        count,
        el('div.endcard-actions', {}, [playBtn, closeBtn])
      ])
    ]);
    root.appendChild(box);
    var endLayer = HS.nav.push({ root: box, focusFirst: playBtn, onBack: function () { stop(); close(true); return true; } });
    var timer = setInterval(tick, 1000);
    function tick() {
      count.textContent = secs + ' saniye içinde başlayacak';
      if (secs-- <= 0) { stop(); playNext(); }
    }
    tick();
    function stop() {
      clearInterval(timer);
      HS.nav.pop(endLayer);
    }
  }

  function finish(then) {
    if (P.closing) return;
    P.closing = true;
    clearInterval(reportTimer);
    clearTimeout(P.ctrlTimer);
    clearTimeout(P.seekTimer);
    document.removeEventListener('visibilitychange', onVisibility);
    engine.close();
    HS.nav.pop(layer);
    if (root.parentNode) root.parentNode.removeChild(root);
    document.body.classList.remove('playing');
    then();
  }
  function close(skipReport) {
    if (!skipReport) report(true);
    finish(function () { if (onClosed) onClosed(); });
  }

  /* ---- start ---- */
  spinner.classList.add('show');
  var cb = {
    onTime: function (t) { if (!P.closing) updateTime(t); },
    onDuration: function (d) { if (d > 0) { P.dur = d; timeDur.textContent = HS.clock(d); } },
    onBuffering: function (b) { spinner.classList.toggle('show', b); },
    onEnded: onEnded,
    onError: function (msg) { HS.toast(msg, 5000); },
    onSubtitle: function (text, durationMs) {
      if (P.extId || P.textIndex < 0) return;
      subsBox.innerHTML = text ? '<span>' + HS.cueHtml(String(text).replace(/<(?!\/?(i|b|u)>)[^>]+>/gi, '')) + '</span>' : '';
      clearTimeout(P.avTextTimer);
      if (durationMs > 0) P.avTextTimer = setTimeout(function () { subsBox.innerHTML = ''; }, durationMs);
    }
  };
  var uhd = item.file && (item.file.width >= 3200 || item.file.height >= 2000);
  engine.open(api.streamUrl(item), startSec || 0, cb, { uhd: uhd }).then(function () {
    if (P.closing) return;
    spinner.classList.remove('show');
    autoPickTracks();
    showControls();
    loadNext();
  }, function (e) {
    if (P.closing) return;
    spinner.classList.remove('show');
    HS.toast(e.message || String(e), 6000);
    close(true);
  });
};
