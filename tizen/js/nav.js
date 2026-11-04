/* Remote control input and focus movement.

   Screens and dialogs are "layers" on a stack; only the top layer gets keys.
   Anything with class "focusable" can take focus; arrow keys move to the
   nearest one in that direction. A container with class "fgroup" (a row of
   cards) remembers its last focused child, so going down and back up lands
   on the same card. */
'use strict';

HS.KEY = {
  LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13,
  BACK: 10009, ESC: 27, BACKSPACE: 8,
  PLAY_PAUSE: 10252, PLAY: 415, PAUSE: 19, STOP: 413,
  FF: 417, RW: 412, CH_UP: 427, CH_DOWN: 428,
  RED: 403, GREEN: 404, YELLOW: 405, BLUE: 406,
  IME_DONE: 65376, IME_CANCEL: 65385, INFO: 457
};

HS.registerTvKeys = function () {
  if (!(window.tizen && tizen.tvinputdevice)) return;
  ['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop', 'MediaFastForward',
    'MediaRewind', 'ColorF0Red', 'ColorF1Green', 'ColorF2Yellow', 'ColorF3Blue',
    'ChannelUp', 'ChannelDown', 'Info'].forEach(function (k) {
    try { tizen.tvinputdevice.registerKey(k); } catch (e) { /* key not on this model */ }
  });
};

var layers = [];

HS.nav = {
  /* layer = {root: Element, onKey?: fn(code, ev) -> bool, onBack?: fn() -> bool,
              onClose?: fn(), focusFirst?: Element} */
  push: function (layer) {
    var top = layers[layers.length - 1];
    if (top) top.saved = top.current;
    layers.push(layer);
    layer.current = null;
    if (layer.focusFirst !== false) HS.nav.focus(layer.focusFirst || HS.nav.first(layer.root));
    return layer;
  },
  pop: function (layer) {
    var i = layer ? layers.indexOf(layer) : layers.length - 1;
    if (i < 0) return;
    var l = layers.splice(i, 1)[0];
    if (l.onClose) l.onClose();
    var top = layers[layers.length - 1];
    if (top && i === layers.length) {
      var target = top.saved && document.body.contains(top.saved) ? top.saved : HS.nav.first(top.root);
      top.current = null;
      HS.nav.focus(target);
    }
  },
  /* Replaces every layer (going to a new top-level page). */
  reset: function (layer) {
    while (layers.length) {
      var l = layers.pop();
      if (l.onClose) l.onClose();
    }
    return HS.nav.push(layer);
  },
  top: function () { return layers[layers.length - 1]; },
  depth: function () { return layers.length; },
  current: function () {
    var t = HS.nav.top();
    return t ? t.current : null;
  },
  first: function (root) {
    if (!root) return null;
    var all = visibleFocusables(root);
    return all[0] || null;
  },
  focus: function (el) {
    var t = HS.nav.top();
    if (!t || !el) return;
    if (t.current && t.current !== el) t.current.classList.remove('focused');
    t.current = el;
    el.classList.add('focused');
    var g = closestClass(el, 'fgroup');
    if (g) g._last = el;
    ensureVisible(el);
    if (el.onfocusin2) el.onfocusin2(el);
  },
  move: function (dir) {
    var t = HS.nav.top();
    if (!t) return false;
    var cur = t.current;
    if (!cur || !document.body.contains(cur)) {
      HS.nav.focus(HS.nav.first(t.root));
      return true;
    }
    var next = findNext(t.root, cur, dir);
    if (next) {
      HS.nav.focus(next);
      return true;
    }
    return false;
  },
  activate: function () {
    var el = HS.nav.current();
    if (!el) return;
    if (el.tagName === 'INPUT') {
      el.focus();
      return;
    }
    if (el.onclick) el.onclick({ target: el, fromKey: true });
  },
  back: function () {
    var t = HS.nav.top();
    if (!t) return;
    if (t.onBack && t.onBack()) return;
    if (layers.length > 1) HS.nav.pop();
    else HS.exitApp();
  }
};

function closestClass(el, cls) {
  while (el && el.classList) {
    if (el.classList.contains(cls)) return el;
    el = el.parentNode;
  }
  return null;
}

function visibleFocusables(root) {
  var list = root.querySelectorAll('.focusable');
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var e = list[i];
    if (e.offsetParent !== null && !e.classList.contains('disabled')) out.push(e);
  }
  return out;
}

function findNext(root, cur, dir) {
  var a = cur.getBoundingClientRect();
  var acx = a.left + a.width / 2, acy = a.top + a.height / 2;
  var best = null, bestScore = Infinity;
  var horizontal = dir === 'left' || dir === 'right';
  visibleFocusables(root).forEach(function (e) {
    if (e === cur) return;
    var b = e.getBoundingClientRect();
    var bcx = b.left + b.width / 2, bcy = b.top + b.height / 2;
    var primary, cross;
    if (dir === 'right') { if (bcx <= acx + 1 || b.left < a.right - a.width / 2) return; primary = Math.max(0, b.left - a.right); }
    if (dir === 'left') { if (bcx >= acx - 1 || b.right > a.left + a.width / 2) return; primary = Math.max(0, a.left - b.right); }
    if (dir === 'down') { if (bcy <= acy + 1 || b.top < a.bottom - a.height / 2) return; primary = Math.max(0, b.top - a.bottom); }
    if (dir === 'up') { if (bcy >= acy - 1 || b.bottom > a.top + a.height / 2) return; primary = Math.max(0, a.top - b.bottom); }
    if (horizontal) {
      // overlap in height counts as "same line"
      var ov = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      cross = ov > 0 ? 0 : Math.abs(bcy - acy);
      primary += cross * 3;
    } else {
      var ovx = Math.min(a.right, b.right) - Math.max(a.left, b.left);
      cross = ovx > 0 ? Math.abs(bcx - acx) * 0.2 : Math.abs(bcx - acx);
      primary = primary * 2 + cross;
    }
    if (primary < bestScore) { bestScore = primary; best = e; }
  });
  if (best && !horizontal) {
    // Entering another row: go back to the card last used there.
    var g = closestClass(best, 'fgroup');
    if (g && g !== closestClass(cur, 'fgroup') && g._last && g.contains(g._last) &&
      g._last.offsetParent !== null) best = g._last;
  }
  return best;
}

/* Scrolls "hscroll" / "vscroll" ancestors so the element is fully visible. */
function ensureVisible(el) {
  var r = el.getBoundingClientRect();
  var p = el.parentNode;
  while (p && p !== document.body && p.classList) {
    if (p.classList.contains('hscroll')) {
      var pr = p.getBoundingClientRect();
      var padL = parseInt(p.dataset.padLeft || '64', 10);
      if (r.left < pr.left + padL) p.scrollLeft -= (pr.left + padL - r.left);
      else if (r.right > pr.right - 64) p.scrollLeft += (r.right - (pr.right - 64));
    }
    if (p.classList.contains('vscroll')) {
      var vr = p.getBoundingClientRect();
      var topPad = parseInt(p.dataset.padTop || '140', 10);
      var anchor = closestClass(el, 'vanchor') || el;
      var ar = anchor.getBoundingClientRect();
      if (p.dataset.snapTop && anchor !== el) {
        // rows: keep the focused row near the top
        p.scrollTop += ar.top - (vr.top + topPad);
      } else if (ar.top < vr.top + topPad) p.scrollTop -= (vr.top + topPad - ar.top);
      else if (ar.bottom > vr.bottom - 40) p.scrollTop += (ar.bottom - (vr.bottom - 40));
      if (closestClass(el, 'scrolltop')) p.scrollTop = 0;
    }
    p = p.parentNode;
  }
}
HS.ensureVisible = ensureVisible;

HS.exitApp = function () {
  try {
    if (window.tizen && tizen.application) {
      tizen.application.getCurrentApplication().exit();
      return;
    }
  } catch (e) { /* not on a TV */ }
  HS.toast('Çıkmak için TV\'nin ana ekran tuşunu kullanın.');
};

document.addEventListener('keydown', function (ev) {
  var code = ev.keyCode;
  var active = document.activeElement;
  // Typing in a text box (the TV keyboard is open)
  if (active && active.tagName === 'INPUT') {
    if (code === HS.KEY.ENTER || code === HS.KEY.IME_DONE) {
      ev.preventDefault();
      active.blur();
      if (active.onsubmit2) active.onsubmit2(active.value);
      return;
    }
    if (code === HS.KEY.IME_CANCEL || code === HS.KEY.BACK || code === HS.KEY.ESC) {
      ev.preventDefault();
      active.blur();
      return;
    }
    if (code === HS.KEY.UP || code === HS.KEY.DOWN) {
      active.blur();
    } else {
      return; // let the input handle letters, backspace, left/right
    }
  }
  var t = HS.nav.top();
  if (t && t.onKey && t.onKey(code, ev)) {
    ev.preventDefault();
    return;
  }
  switch (code) {
    case HS.KEY.LEFT: HS.nav.move('left'); break;
    case HS.KEY.RIGHT: HS.nav.move('right'); break;
    case HS.KEY.UP: HS.nav.move('up'); break;
    case HS.KEY.DOWN: HS.nav.move('down'); break;
    case HS.KEY.ENTER: HS.nav.activate(); break;
    case HS.KEY.BACK: case HS.KEY.ESC: case HS.KEY.BACKSPACE: HS.nav.back(); break;
    default: return;
  }
  ev.preventDefault();
});

/* Pointer (Samsung smart remote / mouse while testing in a browser). */
document.addEventListener('mouseover', function (ev) {
  var el = closestClass(ev.target, 'focusable');
  var t = HS.nav.top();
  if (el && t && t.root.contains(el) && el !== t.current) HS.nav.focus(el);
});
