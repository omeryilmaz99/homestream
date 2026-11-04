/* Start-up: saved server -> saved profile -> home. */
'use strict';

HS.version = '1.0.0';

HS.app = {
  api: null,
  profile: null,
  serverName: '',

  /* Shows a full-screen page as the only layer. */
  show: function (root, opts) {
    var app = document.getElementById('app');
    HS.detailRefresh = null;
    HS.shellRefresh = null;
    HS.heroKeys = null;
    var layer = Object.assign({ root: root }, opts || {});
    HS.nav.reset(layer);
    HS.clear(app).appendChild(root);
    if (layer.focusFirst !== false && !HS.nav.current()) HS.nav.focus(HS.nav.first(root));
    return layer;
  },

  connect: function (url) {
    if (HS.discoverToken) HS.discoverToken.cancelled = true;
    var api = new HS.Api(url);
    return api.info(6000).then(function (info) {
      if (!info || info.app !== 'homestream') throw new Error('Bu adreste Home Stream sunucusu yok.');
      HS.store.set('server', url);
      HS.app.api = api;
      HS.app.serverName = info.name || '';
      HS.screens.profiles();
    });
  },

  selectProfile: function (p) {
    HS.app.profile = p;
    HS.app.api.profileId = p.id;
    HS.store.set('profile', p.id);
    HS.screens.shell('home');
  }
};

function start() {
  HS.store.set('theme', HS.applyTheme(HS.store.get('theme', 'violet')));
  HS.registerTvKeys();

  var m = /[?&]server=([^&]+)/.exec(location.search);
  var url = m ? HS.normalizeServerUrl(decodeURIComponent(m[1])) : HS.store.get('server', '');
  if (!url) { HS.screens.server(); return; }

  var api = new HS.Api(url);
  HS.app.show(HS.el('div.screen.splash', {}, [HS.el('img.setup-logo', { src: 'icon.png' }), HS.el('div.spinner.show')]));
  api.info(6000).then(function (info) {
    HS.store.set('server', url);
    HS.app.api = api;
    HS.app.serverName = info.name || '';
    return api.profiles().then(function (ps) {
      var last = HS.store.get('profile', '');
      var p = null;
      ps.forEach(function (x) { if (x.id === last) p = x; });
      // Same as the other apps: remember the profile, ask again if it's gone.
      if (p) HS.app.selectProfile(p);
      else HS.screens.profiles();
    });
  }).then(null, function (e) {
    HS.screens.server('Kayıtlı sunucuya (' + url.replace('http://', '') + ') bağlanılamadı: ' + e.message);
  });
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
else start();
