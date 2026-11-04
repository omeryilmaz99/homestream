/* Screens: server setup, profiles, home, library, search, detail, settings. */
'use strict';

(function () {
  var el = HS.el;

  /* ---------------- shared pieces ---------------- */

  var lazyObserver = null;
  function lazyImg(cls, src) {
    var img = el('img.' + cls, { alt: '' });
    img.dataset.src = src;
    if (!lazyObserver && window.IntersectionObserver) {
      lazyObserver = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) {
            e.target.src = e.target.dataset.src;
            lazyObserver.unobserve(e.target);
          }
        });
      }, { rootMargin: '700px 900px' });
    }
    if (lazyObserver) lazyObserver.observe(img);
    else img.src = src;
    img.onerror = function () { img.style.visibility = 'hidden'; };
    return img;
  }

  function progressBar(it) {
    var p = HS.progress(it);
    if (!HS.inProgress(it) || p <= 0) return null;
    return el('div.card-progress', {}, [el('div', { style: { width: (p * 100) + '%' } })]);
  }

  /* landscape: 16:9 thumb with title under it (episodes, "Devam Et") */
  function card(it, landscape) {
    var api = HS.app.api;
    var c;
    if (landscape) {
      var img = it.type === 'episode' ? (it.thumb || it.backdrop) : (it.backdrop || it.thumb);
      c = el('div.card.land.focusable', {}, [
        el('div.card-frame', {}, [lazyImg('card-img', api.image(img, 480)), progressBar(it)]),
        el('div.card-caption', { text: it.type === 'episode' ? (it.seriesTitle || it.title) : it.title }),
        it.type === 'episode' ? el('div.card-sub', { text: HS.episodeCode(it) + (it.title ? ' · ' + it.title : '') }) : null
      ]);
    } else {
      c = el('div.card.focusable', {}, [
        el('div.card-frame', {}, [
          lazyImg('card-img', api.image(it.poster, 320)),
          it.posterGenerated ? el('div.card-gen-title', { text: it.title }) : null,
          it.userData && it.userData.played && it.type !== 'series' ? el('div.card-badge', { text: '✓' }) : null,
          it.type === 'series' && it.unwatchedCount > 0 ? el('div.card-badge.count', { text: String(it.unwatchedCount) }) : null,
          progressBar(it)
        ])
      ]);
    }
    c.onclick = function () { HS.openItem(it); };
    return c;
  }
  HS.card = card;

  function row(title, items, landscape) {
    var track = el('div.row-track.hscroll.fgroup', { data: { padLeft: '64' } },
      items.map(function (it) { return card(it, landscape); }));
    return el('div.row.vanchor', {}, [el('div.row-title', { text: title }), track]);
  }

  function loading() { return el('div.loading', {}, [el('div.spinner.show')]); }
  function errorBox(msg, retry) {
    return el('div.error-box', {}, [
      el('div.error-text', { text: msg }),
      retry ? el('div.btn.primary.focusable', { text: 'Tekrar dene', onclick: retry }) : null
    ]);
  }

  /* A list to pick one option from (audio, subtitles, sort, ...). */
  HS.listDialog = function (title, options, onPick) {
    var first = null;
    var list = el('div.dlg-list.vscroll', { data: { padTop: '20' } }, options.map(function (o) {
      var b = el('div.dlg-item.focusable' + (o.selected ? '.selected' : ''), {}, [
        el('span.dlg-check', { text: o.selected ? '✓' : '' }), el('span', { text: o.label })
      ]);
      if (o.selected || !first) first = o.selected ? b : first || b;
      b.onclick = function () { HS.nav.pop(layer); onPick(o.value); };
      return b;
    }));
    var box = el('div.dialog', {}, [el('div.dlg-title', { text: title }), list]);
    var scrim = el('div.scrim', {}, [box]);
    document.body.appendChild(scrim);
    var layer = HS.nav.push({
      root: box, focusFirst: first,
      onClose: function () { if (scrim.parentNode) scrim.parentNode.removeChild(scrim); }
    });
  };

  /* ---------------- server setup ---------------- */

  HS.screens = {};

  HS.screens.server = function (errorMsg) {
    var found = el('div.server-found');
    var status = el('div.setup-status', { text: 'Ağdaki sunucular aranıyor…' });
    var input = el('input.text-input.focusable', {
      type: 'text', placeholder: 'Sunucu adresi (ör. 192.168.1.20)',
      value: (HS.store.get('server', '') || '').replace(/^https?:\/\//, '').replace(/:8420$/, '')
    });
    var connectBtn = el('div.btn.primary.focusable', { text: 'Bağlan', onclick: function () { tryConnect(input.value); } });
    input.onsubmit2 = function (v) { tryConnect(v); };

    function tryConnect(v) {
      var url = HS.normalizeServerUrl(v);
      if (!url) { HS.toast('Sunucu adresini yazın'); return; }
      status.textContent = 'Bağlanılıyor…';
      HS.app.connect(url).then(null, function (e) { status.textContent = e.message; });
    }

    var root = el('div.screen.setup', {}, [
      el('div.setup-box', {}, [
        el('img.setup-logo', { src: 'icon.png' }),
        el('div.setup-title', { text: 'Home Stream' }),
        el('div.setup-text', { text: 'Ev sunucunuza bağlanın. Sunucu ve TV aynı ağda olmalı.' }),
        errorMsg ? el('div.setup-error', { text: errorMsg }) : null,
        found,
        el('div.setup-manual', {}, [input, connectBtn]),
        status
      ])
    ]);
    HS.app.show(root);

    var any = false;
    if (HS.discoverToken) HS.discoverToken.cancelled = true;
    var token = HS.discoverToken = { cancelled: false };
    HS.discover(function (url, info) {
      any = true;
      var b = el('div.server-item.focusable', {}, [
        el('div.server-name', { text: info.name || 'Home Stream' }),
        el('div.server-addr', { text: url.replace('http://', '') + ' · ' + (info.movieCount || 0) + ' film, ' + (info.seriesCount || 0) + ' dizi' })
      ]);
      b.onclick = function () { HS.app.connect(url).then(null, function (e) { status.textContent = e.message; }); };
      found.appendChild(b);
      var cur = HS.nav.current();
      if (!cur || cur === input) HS.nav.focus(b);
    }, function (done, total) {
      if (done < total) status.textContent = 'Ağdaki sunucular aranıyor… %' + Math.round(done * 100 / total);
    }, token).then(function () {
      if (token.cancelled || !document.body.contains(status)) return;
      status.textContent = any ? '' : 'Sunucu bulunamadı. Adresi elle yazın (sunucunun ekranında veya Home Dosya uygulamasında görünür).';
    });
  };

  /* ---------------- profiles ---------------- */

  function avatar(p, size) {
    var a = el('div.avatar', { style: { background: p.color || '#8B5CF6', width: size + 'px', height: size + 'px', fontSize: Math.round(size * 0.5) + 'px' } });
    if (p.photo) {
      var img = el('img', { src: HS.app.api.image(p.photo, 320) });
      img.onerror = function () { a.removeChild(img); a.textContent = p.avatar || p.name.charAt(0); };
      a.appendChild(img);
    } else a.textContent = p.avatar || (p.name || '?').charAt(0).toUpperCase();
    return a;
  }
  HS.avatar = avatar;

  HS.screens.profiles = function () {
    var list = el('div.profile-list', {}, [loading()]);
    var root = el('div.screen.profiles', {}, [
      el('div.profiles-title', { text: 'Kim izliyor?' }),
      list,
      el('div.profiles-hint', { text: HS.app.serverName ? 'Sunucu: ' + HS.app.serverName : '' })
    ]);
    HS.app.show(root);
    HS.app.api.profiles().then(function (ps) {
      HS.clear(list);
      var last = HS.store.get('profile', '');
      var focus = null;
      ps.forEach(function (p) {
        var b = el('div.profile.focusable', {}, [avatar(p, 180), el('div.profile-name', { text: p.name })]);
        b.onclick = function () { HS.app.selectProfile(p); };
        list.appendChild(b);
        if (p.id === last) focus = b;
      });
      var add = el('div.profile.focusable', {}, [
        el('div.avatar.add', { text: '+', style: { width: '180px', height: '180px' } }),
        el('div.profile-name', { text: 'Profil ekle' })
      ]);
      add.onclick = newProfile;
      list.appendChild(add);
      var change = el('div.btn.small.focusable', { text: 'Sunucuyu değiştir', onclick: function () { HS.screens.server(); } });
      root.appendChild(el('div.profiles-actions', {}, [change]));
      HS.nav.focus(focus || HS.nav.first(list));
    }, function (e) {
      HS.clear(list).appendChild(errorBox(e.message, HS.screens.profiles));
      HS.nav.focus(HS.nav.first(list));
    });
  };

  var EMOJIS = ['😀', '😎', '🦊', '🐼', '🐱', '🦁', '🐸', '🚀', '🎮', '⚽', '🌸', '🍿'];
  var COLORS = ['#8B5CF6', '#E50914', '#06B6D4', '#10B981', '#F59E0B', '#EC4899', '#3B82F6', '#F97316'];

  function newProfile() {
    var input = el('input.text-input.focusable', { type: 'text', placeholder: 'Ad' });
    var pickEmoji = EMOJIS[Math.floor(Math.random() * EMOJIS.length)];
    var pickColor = COLORS[Math.floor(Math.random() * COLORS.length)];
    var preview = el('div.avatar', { text: pickEmoji, style: { background: pickColor, width: '120px', height: '120px', fontSize: '60px' } });
    var emojiRow = el('div.emoji-row', {}, EMOJIS.map(function (e) {
      var b = el('div.emoji.focusable', { text: e });
      b.onclick = function () { pickEmoji = e; preview.textContent = e; };
      return b;
    }));
    var colorRow = el('div.emoji-row', {}, COLORS.map(function (c) {
      var b = el('div.swatch.focusable', { style: { background: c } });
      b.onclick = function () { pickColor = c; preview.style.background = c; };
      return b;
    }));
    function save() {
      var name = input.value.trim();
      if (!name) { HS.toast('Bir ad yazın'); HS.nav.focus(input); return; }
      HS.app.api.createProfile(name, pickColor, pickEmoji).then(function (p) {
        HS.nav.pop(layer);
        HS.app.selectProfile(p);
      }, function (e) { HS.toast(e.message); });
    }
    input.onsubmit2 = function () { HS.nav.focus(saveBtn); };
    var saveBtn = el('div.btn.primary.focusable', { text: 'Kaydet', onclick: save });
    var box = el('div.dialog.wide', {}, [
      el('div.dlg-title', { text: 'Yeni profil' }),
      el('div.newprof', {}, [preview, input]),
      emojiRow, colorRow,
      el('div.dlg-actions', {}, [saveBtn, el('div.btn.focusable', { text: 'Vazgeç', onclick: function () { HS.nav.pop(layer); } })])
    ]);
    var scrim = el('div.scrim', {}, [box]);
    document.body.appendChild(scrim);
    var layer = HS.nav.push({ root: box, focusFirst: input, onClose: function () { scrim.parentNode.removeChild(scrim); } });
  }

  /* ---------------- shell (top menu + pages) ---------------- */

  var TABS = [
    ['home', 'Ana Sayfa'], ['movies', 'Filmler'], ['series', 'Diziler'], ['search', 'Ara'], ['settings', 'Ayarlar']
  ];

  HS.screens.shell = function (tab) {
    tab = tab || 'home';
    var page = el('div.page.vscroll', { data: { padTop: '150', snapTop: '1' } });
    var navItems = {};
    var navRow = el('div.topnav-items.fgroup', {}, TABS.map(function (t) {
      var b = el('div.navitem.focusable', { text: t[1] });
      b.onclick = function () { open(t[0], true); };
      navItems[t[0]] = b;
      return b;
    }));
    var p = HS.app.profile;
    var prof = el('div.navprofile.focusable', {}, [avatar(p, 56)]);
    prof.onclick = function () { HS.screens.profiles(); };
    var top = el('div.topnav.scrolltop', {}, [
      el('div.brand', {}, [el('img', { src: 'icon.png' }), el('span', { text: 'Home Stream' })]),
      navRow, prof
    ]);
    var root = el('div.screen.shell', {}, [page, top]);
    page.addEventListener('scroll', function () { top.classList.toggle('solid', page.scrollTop > 40); });
    var current = null;

    function open(id, focusContent) {
      current = id;
      Object.keys(navItems).forEach(function (k) { navItems[k].classList.toggle('active', k === id); });
      navRow._last = navItems[id];
      HS.clear(page);
      page.scrollTop = 0;
      var builder = { home: homePage, movies: libraryPage('movies'), series: libraryPage('series'), search: searchPage, settings: settingsPage }[id];
      builder(page, function (preferred) {
        // content loaded: move focus into it
        if (current !== id || HS.nav.depth() !== 1) return;
        var cur = HS.nav.current();
        if (focusContent || !cur || !document.body.contains(cur)) {
          var f = preferred || HS.nav.first(page);
          if (f) HS.nav.focus(f);
        }
      });
    }

    HS.app.show(root, {
      onBack: function () {
        // back: first to the menu, then to the home page, then exit
        var cur = HS.nav.current();
        if (cur && !top.contains(cur)) { HS.nav.focus(navItems[current]); page.scrollTop = 0; return true; }
        if (current !== 'home') { open('home', false); HS.nav.focus(navItems.home); return true; }
        return false;
      },
      onKey: function (code) { return current === 'home' && HS.heroKeys ? HS.heroKeys(code) : false; },
      focusFirst: false
    });
    HS.nav.focus(navItems[tab]);
    open(tab, true);
    HS.shellRefresh = function () { if (current === 'home') open('home', false); };
  };

  /* ---------------- home ---------------- */

  function homePage(page, ready) {
    page.appendChild(loading());
    HS.app.api.home().then(function (data) {
      HS.clear(page);
      var heroItems = data.hero || [];
      if (heroItems.length) page.appendChild(hero(heroItems));
      (data.rows || []).forEach(function (r) {
        if (!r.items || !r.items.length) return;
        var land = r.id === 'continue' || r.id === 'nextup';
        page.appendChild(row(r.title, r.items, land));
      });
      if (!heroItems.length && !(data.rows || []).length) {
        page.appendChild(el('div.empty', { text: 'Kütüphane boş. Sunucudaki HomeStream klasörüne film ve dizi ekleyin.' }));
      }
      ready();
    }, function (e) {
      HS.clear(page).appendChild(errorBox(e.message, function () { HS.clear(page); homePage(page, ready); }));
      ready();
    });
  }

  function hero(items) {
    var api = HS.app.api;
    var idx = 0;
    var bg = el('img.hero-bg', { alt: '' });
    var title = el('div.hero-title');
    var meta = el('div.hero-meta');
    var over = el('div.hero-overview');
    var dots = el('div.hero-dots', {}, items.map(function () { return el('span'); }));
    var playBtn = el('div.btn.primary.focusable', { text: '▶  Oynat' });
    var infoBtn = el('div.btn.focusable', { text: 'ⓘ  Ayrıntılar' });
    var box = el('div.hero.vanchor.scrolltop', {}, [
      bg, el('div.hero-shade'),
      el('div.hero-content', {}, [title, meta, over, el('div.hero-actions.fgroup', {}, [playBtn, infoBtn])]),
      dots
    ]);
    function show(i) {
      idx = (i + items.length) % items.length;
      var it = items[idx];
      bg.src = api.image(it.backdrop, 1280);
      title.textContent = it.title;
      meta.textContent = metaLine(it);
      over.textContent = it.overview || '';
      for (var d = 0; d < dots.children.length; d++) dots.children[d].className = d === idx ? 'on' : '';
    }
    playBtn.onclick = function () { HS.playItem(items[idx]); };
    infoBtn.onclick = function () { HS.openItem(items[idx]); };
    show(0);
    var timer = setInterval(function () {
      if (!document.body.contains(box)) { clearInterval(timer); return; }
      if (HS.nav.depth() === 1 && !document.body.classList.contains('playing')) show(idx + 1);
    }, 12000);
    // left on "Oynat" / right on "Ayrıntılar" changes the hero item
    HS.heroKeys = function (code) {
      var cur = HS.nav.current();
      if (cur === playBtn && code === HS.KEY.LEFT) { show(idx - 1); return true; }
      if (cur === infoBtn && code === HS.KEY.RIGHT) { show(idx + 1); return true; }
      return false;
    };
    return box;
  }

  function metaLine(it) {
    var parts = [];
    if (it.year) parts.push(String(it.year));
    if (it.type === 'series') {
      if (it.seasonCount) parts.push(it.seasonCount + ' sezon');
      if (it.episodeCount) parts.push(it.episodeCount + ' bölüm');
    } else if (it.duration) parts.push(HS.duration(it.duration));
    if (it.rating) parts.push('★ ' + it.rating.toFixed(1));
    if (it.genres && it.genres.length) parts.push(it.genres.slice(0, 3).join(', '));
    return parts.join('   ·   ');
  }

  /* ---------------- movies / series ---------------- */

  var SORTS = [['added', 'Son eklenen', 'desc'], ['title', 'A–Z', 'asc'], ['year', 'Yıl', 'desc'], ['rating', 'Puan', 'desc'], ['lastPlayed', 'Son izlenen', 'desc']];
  var FILTERS = [['', 'Tümü'], ['unwatched', 'İzlenmemiş'], ['watched', 'İzlenmiş'], ['liked', 'Beğendiklerim']];

  function libraryPage(kind) {
    return function (page, ready) {
      var st = HS.store.get('lib.' + kind, { sort: 'added', filter: '', genre: '' });
      var grid = el('div.grid');
      var sortBtn = el('div.chip.focusable');
      var filterBtn = el('div.chip.focusable');
      var genreBtn = el('div.chip.focusable');
      var count = el('div.lib-count');
      var bar = el('div.lib-bar.vanchor.scrolltop.fgroup', {}, [
        el('div.lib-title', { text: kind === 'movies' ? 'Filmler' : 'Diziler' }), sortBtn, filterBtn, genreBtn, count
      ]);
      page.appendChild(bar);
      page.appendChild(grid);

      function labels() {
        SORTS.forEach(function (s) { if (s[0] === st.sort) sortBtn.textContent = 'Sırala: ' + s[1]; });
        FILTERS.forEach(function (f) { if (f[0] === st.filter) filterBtn.textContent = f[1]; });
        genreBtn.textContent = st.genre || 'Tüm türler';
      }
      function load(first) {
        labels();
        HS.store.set('lib.' + kind, st);
        HS.clear(grid).appendChild(loading());
        var order = 'desc';
        SORTS.forEach(function (s) { if (s[0] === st.sort) order = s[2]; });
        HS.app.api[kind]({ sort: st.sort, order: order, filter: st.filter, genre: st.genre }).then(function (items) {
          HS.clear(grid);
          count.textContent = items.length + (kind === 'movies' ? ' film' : ' dizi');
          items.forEach(function (it) {
            var c = card(it, false);
            c.classList.add('vanchor');
            grid.appendChild(c);
          });
          if (!items.length) grid.appendChild(el('div.empty', { text: 'Burada bir şey yok.' }));
          if (first) ready(grid.querySelector('.card'));
        }, function (e) {
          HS.clear(grid).appendChild(errorBox(e.message, function () { load(false); }));
          if (first) ready();
        });
      }
      sortBtn.onclick = function () {
        HS.listDialog('Sırala', SORTS.map(function (s) { return { label: s[1], value: s[0], selected: s[0] === st.sort }; }),
          function (v) { st.sort = v; load(false); });
      };
      filterBtn.onclick = function () {
        HS.listDialog('Göster', FILTERS.map(function (f) { return { label: f[1], value: f[0], selected: f[0] === st.filter }; }),
          function (v) { st.filter = v; load(false); });
      };
      genreBtn.onclick = function () {
        HS.app.api.genres().then(function (gs) {
          var opts = [{ label: 'Tüm türler', value: '', selected: !st.genre }].concat((gs || []).map(function (g) {
            return { label: g, value: g, selected: g === st.genre };
          }));
          HS.listDialog('Tür', opts, function (v) { st.genre = v; load(false); });
        }, function (e) { HS.toast(e.message); });
      };
      load(true);
    };
  }

  /* ---------------- search ---------------- */

  function searchPage(page, ready) {
    var input = el('input.text-input.search-input.focusable', { type: 'text', placeholder: 'Film, dizi veya bölüm ara' });
    var results = el('div.search-results');
    var timer = null, seq = 0;
    function run(q) {
      q = q.trim();
      var my = ++seq;
      if (!q) { HS.clear(results); return; }
      HS.clear(results).appendChild(loading());
      HS.app.api.search(q).then(function (r) {
        if (my !== seq) return;
        HS.clear(results);
        if (r.movies && r.movies.length) results.appendChild(row('Filmler', r.movies, false));
        if (r.series && r.series.length) results.appendChild(row('Diziler', r.series, false));
        if (r.episodes && r.episodes.length) results.appendChild(row('Bölümler', r.episodes, true));
        if (!results.children.length) results.appendChild(el('div.empty', { text: '"' + q + '" için sonuç yok.' }));
      }, function (e) {
        if (my === seq) HS.clear(results).appendChild(errorBox(e.message));
      });
    }
    input.oninput = function () {
      clearTimeout(timer);
      timer = setTimeout(function () { run(input.value); }, 450);
    };
    input.onsubmit2 = function (v) {
      clearTimeout(timer);
      run(v);
      setTimeout(function () {
        var f = HS.nav.first(results);
        if (f) HS.nav.focus(f);
      }, 600);
    };
    page.appendChild(el('div.search-bar.vanchor.scrolltop', {}, [input]));
    page.appendChild(results);
    ready();
  }

  /* ---------------- settings ---------------- */

  function settingsPage(page, ready) {
    var s = HS.app;
    function line(label, value, onclick) {
      var v = el('div.set-value', { text: value });
      var b = el('div.set-row.focusable.vanchor', {}, [el('div.set-label', { text: label }), v]);
      b.onclick = function () { onclick(v); };
      return b;
    }
    var subNames = { tur: 'Türkçe', eng: 'İngilizce', off: 'Kapalı' };
    var themeName = '';
    HS.themes.forEach(function (t) { if (t[0] === HS.store.get('theme', 'violet')) themeName = t[1]; });
    page.appendChild(el('div.settings', {}, [
      el('div.lib-title', { text: 'Ayarlar' }),
      line('Sunucu', (s.serverName ? s.serverName + ' · ' : '') + s.api.baseUrl.replace('http://', ''), function () { HS.screens.server(); }),
      line('Profil', s.profile.name, function () { HS.screens.profiles(); }),
      line('Tercih edilen altyazı', subNames[HS.store.get('subLang', 'tur')] || 'Türkçe', function (v) {
        HS.listDialog('Tercih edilen altyazı', ['tur', 'eng', 'off'].map(function (k) {
          return { label: subNames[k], value: k, selected: k === HS.store.get('subLang', 'tur') };
        }), function (k) {
          HS.store.set('subLang', k);
          HS.store.set('subChoice', '');
          v.textContent = subNames[k];
        });
      }),
      line('Tema rengi', themeName, function (v) {
        HS.listDialog('Tema rengi', HS.themes.map(function (t) {
          return { label: t[1], value: t, selected: t[0] === HS.store.get('theme', 'violet') };
        }), function (t) {
          HS.store.set('theme', HS.applyTheme(t[0]));
          v.textContent = t[1];
        });
      }),
      el('div.set-about', { text: 'Home Stream Tizen ' + HS.version + (HS.hasAvplay() ? ' · Samsung oynatıcı' : ' · tarayıcı oynatıcısı') })
    ]));
    ready();
  }

  /* ---------------- detail ---------------- */

  HS.openItem = function (it) {
    if (it.type === 'episode') { HS.playItem(it); return; }
    detail(it);
  };

  /* Plays a movie or episode (resuming), or a series' next episode. */
  HS.playItem = function (it, fromStart) {
    var api = HS.app.api;
    api.item(it.id).then(function (full) {
      if (full.type === 'series') {
        if (!full.nextUp) { HS.toast('Bu dizide bölüm yok'); return; }
        return api.item(full.nextUp.id).then(function (ep) { start(ep); });
      }
      start(full);
    }).then(null, function (e) { HS.toast(e.message); });
    function start(item) {
      var pos = !fromStart && HS.inProgress(item) ? item.userData.position : 0;
      HS.openPlayer(item, pos, function () {
        if (HS.detailRefresh) HS.detailRefresh();
        else if (HS.shellRefresh && HS.nav.depth() === 1) HS.shellRefresh();
      });
    }
  };

  function detail(summary) {
    var api = HS.app.api;
    var bg = el('img.detail-bg', { src: api.image(summary.backdrop, 1280), alt: '' });
    var body = el('div.detail-body', {}, [loading()]);
    var scroller = el('div.detail-scroll.vscroll', { data: { padTop: '60' } }, [body]);
    var root = el('div.screen.detail', {}, [bg, el('div.detail-shade'), scroller]);
    document.getElementById('app').appendChild(root);
    var seasonIdx = -1;
    var layer = HS.nav.push({
      root: root, focusFirst: false,
      onClose: function () {
        if (root.parentNode) root.parentNode.removeChild(root);
        HS.detailRefresh = null;
        if (changed && HS.shellRefresh) HS.shellRefresh();
      }
    });
    var changed = false;
    HS.detailRefresh = function () { changed = true; render(true); };

    function render(keepFocus) {
      var focusedText = keepFocus && HS.nav.current() ? HS.nav.current().dataset.key : null;
      api.item(summary.id).then(function (it) {
        if (!document.body.contains(root)) return;
        HS.clear(body);
        var u = it.userData || {};
        var info = el('div.detail-info.vanchor.scrolltop', {}, [
          el('div.detail-title', { text: it.title }),
          el('div.detail-meta', { text: metaLine(it) + (it.file && HS.resolutionLabel(it.file) ? '   ·   ' + HS.resolutionLabel(it.file) + (it.file.hdr ? ' HDR' : '') : '') }),
          it.overview ? el('div.detail-overview', { text: it.overview }) : null
        ]);
        var actions = el('div.detail-actions.fgroup');
        function action(key, text, cls, fn) {
          var b = el('div.btn.focusable' + (cls ? '.' + cls : ''), { text: text, data: { key: key } });
          b.onclick = fn;
          actions.appendChild(b);
          return b;
        }
        var main;
        if (it.type === 'series') {
          var nu = it.nextUp;
          var label = '▶  Oynat';
          if (nu) {
            label = (HS.inProgress(nu) ? '▶  Devam et ' : '▶  Oynat ') + HS.episodeCode(nu);
          }
          main = action('play', label, 'primary', function () { if (nu) HS.playItem(nu); });
        } else {
          main = action('play', HS.inProgress(it) ? '▶  Devam et (' + HS.clock(u.position) + ')' : '▶  Oynat', 'primary', function () { HS.playItem(it); });
          if (HS.inProgress(it)) action('restart', '↺  Baştan başla', '', function () { HS.playItem(it, true); });
        }
        action('like', u.liked ? '♥  Beğenildi' : '♡  Beğen', u.liked ? 'on' : '', function () {
          api.setLiked(it.id, !u.liked).then(function () { changed = true; render(true); }, function (e) { HS.toast(e.message); });
        });
        var played = it.type === 'series' ? it.unwatchedCount === 0 : u.played;
        action('played', played ? '✓  İzlendi' : '○  İzlendi say', played ? 'on' : '', function () {
          api.setPlayed(it.id, !played).then(function () { changed = true; render(true); }, function (e) { HS.toast(e.message); });
        });
        if (HS.inProgress(it)) {
          action('remove', '✕  Devam Et\'ten çıkar', '', function () {
            api.removeProgress(it.id).then(function () { changed = true; render(true); }, function (e) { HS.toast(e.message); });
          });
        }
        info.appendChild(actions);
        body.appendChild(info);

        if (it.type === 'series' && it.seasons && it.seasons.length) {
          if (seasonIdx < 0) {
            seasonIdx = 0;
            if (it.nextUp) it.seasons.forEach(function (s, i) { if (s.number === it.nextUp.season) seasonIdx = i; });
          }
          var eps = el('div.episodes');
          var tabs = el('div.season-tabs.vanchor.fgroup', {}, it.seasons.map(function (s, i) {
            var t = el('div.chip.focusable' + (i === seasonIdx ? '.active' : ''), { text: s.title || (s.number + '. Sezon'), data: { key: 'season' + i } });
            t.onclick = function () {
              seasonIdx = i;
              for (var k = 0; k < tabs.children.length; k++) tabs.children[k].classList.toggle('active', k === i);
              fillEpisodes(eps, it.seasons[i]);
            };
            return t;
          }));
          body.appendChild(tabs);
          body.appendChild(eps);
          fillEpisodes(eps, it.seasons[seasonIdx]);
        } else {
          api.related(it.id).then(function (r) {
            if (r && r.recommended && r.recommended.length && document.body.contains(body)) {
              body.appendChild(row('Benzerleri', r.recommended, false));
            }
          }, function () { });
        }
        var target = null;
        if (focusedText) {
          var q = body.querySelector('[data-key="' + focusedText + '"]');
          if (q) target = q;
        }
        if (HS.nav.top() === layer) HS.nav.focus(target || main);
      }, function (e) {
        HS.clear(body).appendChild(errorBox(e.message, function () { render(false); }));
        if (HS.nav.top() === layer) HS.nav.focus(HS.nav.first(body));
      });
    }

    function fillEpisodes(box, season) {
      HS.clear(box);
      (season.episodes || []).forEach(function (ep) {
        var u = ep.userData || {};
        var b = el('div.episode.focusable.vanchor', { data: { key: 'ep' + ep.id } }, [
          el('div.ep-frame', {}, [lazyImg('ep-img', api.image(ep.thumb || ep.backdrop, 480)), progressBar(ep)]),
          el('div.ep-text', {}, [
            el('div.ep-title', { text: ep.episode + '. ' + (ep.title || ('Bölüm ' + ep.episode)) }),
            el('div.ep-meta', { text: [HS.duration(ep.duration), u.played ? '✓ İzlendi' : HS.inProgress(ep) ? HS.clock(u.position) + ' kaldığın yer' : ''].filter(Boolean).join('   ·   ') }),
            ep.overview ? el('div.ep-overview', { text: ep.overview }) : null
          ])
        ]);
        b.onclick = function () { HS.playItem(ep); };
        box.appendChild(b);
      });
    }

    render(false);
  }
})();
