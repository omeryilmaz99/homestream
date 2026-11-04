/* Text subtitle files (srt, vtt, ass/ssa) -> cues drawn over the video. */
'use strict';

function parseTime(s) {
  // 01:02:03,456 | 01:02:03.456 | 02:03.456 | 0:02:03.45 (ass)
  var m = /(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?/.exec(s.trim());
  if (!m) return NaN;
  var frac = m[4] ? parseInt(m[4], 10) / Math.pow(10, m[4].length) : 0;
  return (parseInt(m[1] || '0', 10) * 3600) + parseInt(m[2], 10) * 60 + parseInt(m[3], 10) + frac;
}

function cleanTags(t) {
  return t.replace(/\{\\[^}]*\}/g, '')        // ass override tags
    .replace(/\\N/gi, '\n')
    .replace(/<(?!\/?(i|b|u)>)[^>]+>/gi, '')   // keep only <i>, <b>, <u>
    .trim();
}

function parseSrtVtt(text) {
  var cues = [];
  var blocks = text.replace(/\r/g, '').split(/\n{2,}/);
  blocks.forEach(function (b) {
    var lines = b.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf('-->') >= 0) {
        var parts = lines[i].split('-->');
        var start = parseTime(parts[0]);
        var end = parseTime(parts[1].trim().split(/\s+/)[0]);
        var body = cleanTags(lines.slice(i + 1).join('\n'));
        if (!isNaN(start) && !isNaN(end) && body) cues.push({ start: start, end: end, text: body });
        break;
      }
    }
  });
  return cues;
}

function parseAss(text) {
  var cues = [];
  var format = null;
  text.replace(/\r/g, '').split('\n').forEach(function (line) {
    if (/^Format:/i.test(line) && !format) {
      var f = line.slice(7).split(',').map(function (x) { return x.trim().toLowerCase(); });
      if (f.indexOf('text') >= 0) format = f;
    } else if (/^Dialogue:/i.test(line)) {
      var f2 = format || ['layer', 'start', 'end', 'style', 'name', 'marginl', 'marginr', 'marginv', 'effect', 'text'];
      var parts = line.slice(9).split(',');
      var head = parts.slice(0, f2.length - 1);
      var body = parts.slice(f2.length - 1).join(',');
      var start = parseTime(head[f2.indexOf('start')] || '');
      var end = parseTime(head[f2.indexOf('end')] || '');
      body = cleanTags(body);
      if (!isNaN(start) && !isNaN(end) && body) cues.push({ start: start, end: end, text: body });
    }
  });
  cues.sort(function (a, b) { return a.start - b.start; });
  return cues;
}

HS.parseSubtitles = function (text, format) {
  var f = String(format || '').toLowerCase();
  if (f === 'ass' || f === 'ssa' || /^\s*\[Script Info\]/i.test(text)) return parseAss(text);
  return parseSrtVtt(text.replace(/^﻿/, ''));
};

HS.cuesAt = function (cues, t) {
  var out = [];
  // cues are sorted by start; a short linear scan is fine for one file
  for (var i = 0; i < cues.length; i++) {
    var c = cues[i];
    if (c.start > t) break;
    if (c.end >= t) out.push(c.text);
  }
  return out.join('\n');
};

/* Safe HTML for a cue: escape, then let <i>/<b>/<u> through. */
HS.cueHtml = function (text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/&lt;(\/?)(i|b|u)&gt;/gi, '<$1$2>')
    .replace(/\n/g, '<br>');
};
