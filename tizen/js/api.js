/* Home Stream server API (docs/API.md). */
'use strict';

/* "192.168.1.5", "192.168.1.5:8420", "http://host:8420/" -> "http://host:8420" */
HS.normalizeServerUrl = function (input) {
  var s = String(input || '').trim();
  if (!s) return '';
  if (!/^https?:\/\//i.test(s)) s = 'http://' + s;
  var m = /^(https?):\/\/([^\/:]+)(?::(\d+))?/i.exec(s);
  if (!m) return s;
  return m[1].toLowerCase() + '://' + m[2] + ':' + (m[3] || '8420');
};

function withTimeout(promise, ms) {
  return new Promise(function (resolve, reject) {
    var done = false;
    var t = setTimeout(function () {
      if (done) return;
      done = true;
      reject(new Error('Sunucu yanıt vermedi (zaman aşımı).'));
    }, ms);
    promise.then(function (v) {
      if (done) return;
      done = true; clearTimeout(t); resolve(v);
    }, function (e) {
      if (done) return;
      done = true; clearTimeout(t); reject(e);
    });
  });
}

HS.Api = function (baseUrl, profileId) {
  this.baseUrl = baseUrl;
  this.profileId = profileId || null;
};

HS.Api.prototype.url = function (path, query) {
  if (!path) return '';
  var u = /^https?:\/\//.test(path) ? path : this.baseUrl + path;
  if (query) {
    var q = Object.keys(query).filter(function (k) {
      return query[k] !== undefined && query[k] !== null && query[k] !== '';
    }).map(function (k) {
      return encodeURIComponent(k) + '=' + encodeURIComponent(query[k]);
    }).join('&');
    if (q) u += (u.indexOf('?') >= 0 ? '&' : '?') + q;
  }
  return u;
};

HS.Api.prototype.image = function (path, width) {
  return this.url(path, width ? { w: width } : null);
};

HS.Api.prototype.streamUrl = function (item) {
  var p = (item.file && item.file.streamUrl) || ('/api/stream/' + item.id);
  return this.url(p, this.profileId ? { profile: this.profileId } : null);
};

HS.Api.prototype.send = function (method, path, query, body, timeoutMs) {
  var headers = { 'Accept': 'application/json' };
  if (this.profileId) headers['X-Profile'] = this.profileId;
  var opts = { method: method, headers: headers };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json; charset=utf-8';
    opts.body = JSON.stringify(body);
  }
  // Abort for real on timeout where possible, so a dead address doesn't
  // keep a connection busy (matters while scanning the network).
  var ctrl = window.AbortController ? new AbortController() : null;
  var ms = timeoutMs || 15000;
  if (ctrl) {
    opts.signal = ctrl.signal;
    setTimeout(function () { ctrl.abort(); }, ms + 50);
  }
  var req = fetch(this.url(path, query), opts).then(function (resp) {
    return resp.text().then(function (text) {
      if (!resp.ok) {
        var msg = 'Sunucu hatası (' + resp.status + ')';
        try {
          var j = JSON.parse(text);
          if (j && j.error) msg = j.error;
        } catch (e) { /* not JSON */ }
        throw new Error(msg);
      }
      if (!text) return null;
      try { return JSON.parse(text); } catch (e) { throw new Error('Sunucudan geçersiz yanıt geldi.'); }
    });
  }, function () {
    throw new Error('Sunucuya bağlanılamadı. Sunucu açık mı ve adres doğru mu?');
  });
  return withTimeout(req, ms);
};

HS.Api.prototype.get = function (path, query) { return this.send('GET', path, query); };
HS.Api.prototype.post = function (path, body) { return this.send('POST', path, null, body || {}); };

HS.Api.prototype.info = function (timeoutMs) { return this.send('GET', '/api/info', null, undefined, timeoutMs); };
HS.Api.prototype.profiles = function () { return this.get('/api/profiles'); };
HS.Api.prototype.createProfile = function (name, color, avatar) {
  return this.post('/api/profiles', { name: name, color: color, avatar: avatar });
};
HS.Api.prototype.home = function () { return this.get('/api/home'); };
HS.Api.prototype.movies = function (q) { return this.get('/api/movies', q); };
HS.Api.prototype.series = function (q) { return this.get('/api/series', q); };
HS.Api.prototype.genres = function () { return this.get('/api/genres'); };
HS.Api.prototype.item = function (id) { return this.get('/api/items/' + id); };
HS.Api.prototype.related = function (id) { return this.get('/api/items/' + id + '/related'); };
HS.Api.prototype.search = function (q) { return this.get('/api/search', { q: q }); };
HS.Api.prototype.progress = function (id, position, duration) {
  return this.post('/api/items/' + id + '/progress', { position: position, duration: duration });
};
HS.Api.prototype.setPlayed = function (id, played) {
  return this.post('/api/items/' + id + '/played', { played: played });
};
HS.Api.prototype.setLiked = function (id, liked) {
  return this.post('/api/items/' + id + '/like', { liked: liked });
};
HS.Api.prototype.removeProgress = function (id) {
  return this.send('DELETE', '/api/items/' + id + '/progress');
};
HS.Api.prototype.subtitleText = function (path) {
  return withTimeout(fetch(this.url(path)).then(function (r) {
    if (!r.ok) throw new Error('Altyazı yüklenemedi');
    return r.text();
  }), 15000);
};

/* The TV's own IPv4 address, when the Samsung network API is there. */
HS.localIp = function () {
  try {
    if (window.webapis && webapis.network && webapis.network.getIp) {
      var ip = webapis.network.getIp();
      if (/^\d+\.\d+\.\d+\.\d+$/.test(ip)) return ip;
    }
  } catch (e) { /* no permission or no network */ }
  return '';
};

/* Web apps can't send the UDP discovery broadcast, so look for the server
   by asking every address of the TV's /24 network for /api/info.
   onFound(url, info) is called for each server; resolves when done. */
HS.discover = function (onFound, onProgress, token) {
  token = token || {};
  var ip = HS.localIp();
  var prefixes = [];
  if (ip) prefixes.push(ip.split('.').slice(0, 3).join('.'));
  ['192.168.1', '192.168.0', '192.168.50'].forEach(function (p) {
    if (prefixes.indexOf(p) < 0) prefixes.push(p);
  });
  // Without the TV's own address, only try the most common home networks.
  if (ip) prefixes = prefixes.slice(0, 1);

  var hosts = [];
  prefixes.forEach(function (p) {
    for (var i = 1; i < 255; i++) hosts.push(p + '.' + i);
  });
  var found = {};
  var next = 0, done = 0;
  return new Promise(function (resolve) {
    function worker() {
      if (next >= hosts.length || token.cancelled) return Promise.resolve();
      var url = 'http://' + hosts[next++] + ':8420';
      return new HS.Api(url).info(1500).then(function (info) {
        if (!token.cancelled && info && info.app === 'homestream' && !found[info.id]) {
          found[info.id] = true;
          onFound(url, info);
        }
      }, function () { /* nothing there */ }).then(function () {
        done++;
        if (onProgress && !token.cancelled) onProgress(done, hosts.length);
        return worker();
      });
    }
    var workers = [];
    for (var w = 0; w < 48; w++) workers.push(worker());
    Promise.all(workers).then(resolve);
  });
};
