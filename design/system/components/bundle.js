/* Ingest chart and preview helpers. Plain DOM and SVG, no libraries. Colours are token names. */
(function () {
  var NS = 'http://www.w3.org/2000/svg';
  function s(tag, attrs, parent) {
    var n = document.createElementNS(NS, tag);
    for (var k in attrs) {
      if (k === 'text') n.textContent = attrs[k];
      else if (k === 'style') n.setAttribute('style', attrs[k]);
      else n.setAttribute(k, attrs[k]);
    }
    if (parent) parent.appendChild(n);
    return n;
  }
  function v(name) { return 'var(--' + name + ')'; }
  function root(target, w, h, label) {
    var el = typeof target === 'string' ? document.querySelector(target) : target;
    var svg = s('svg', { viewBox: '0 0 ' + w + ' ' + h, role: 'img', 'aria-label': label || '' });
    el.appendChild(svg);
    return svg;
  }
  function axisText(svg, x, y, text, anchor) {
    return s('text', { x: x, y: y, 'text-anchor': anchor || 'middle', style: 'fill:' + v('muted') + ';font:500 11px ' + v('font-sans') + ';font-variant-numeric:tabular-nums', text: text }, svg);
  }
  // Seeded PRNG so synthetic data is the same on every render.
  function rng(seed) { var x = seed || 7; return function () { x = (x * 16807) % 2147483647; return (x - 1) / 2147483646; }; }

  /* EWMA trend with the gap rule from SPEC.md: weight 1 - (1 - alpha)^d for a gap of d days. */
  function trend(points, alpha) {
    alpha = alpha || 0.1;
    var out = [], t = null, last = null;
    points.forEach(function (p) {
      if (t === null) t = p.lb;
      else { var w = 1 - Math.pow(1 - alpha, p.day - last); t = t + w * (p.lb - t); }
      last = p.day; out.push({ day: p.day, lb: p.lb, trend: t });
    });
    return out;
  }

  /* Sparkline: values may hold null (absent). Absent days break the line; never drawn as 0. */
  function spark(target, values, opts) {
    opts = opts || {};
    var w = 72, h = 28, pad = 3, color = opts.color || 'ink';
    var svg = root(target, w, h, opts.label);
    svg.setAttribute('class', 'ig-spark');
    var nums = values.filter(function (x) { return x !== null; });
    if (!nums.length) { s('line', { x1: pad, x2: w - pad, y1: h / 2, y2: h / 2, style: 'stroke:' + v('track') + ';stroke-width:1.5;stroke-dasharray:3 3' }, svg); return svg; }
    var lo = Math.min.apply(null, nums), hi = Math.max.apply(null, nums); if (hi === lo) { hi += 1; lo -= 1; }
    var step = (w - 2 * pad) / (values.length - 1);
    function y(x) { return h - pad - (x - lo) / (hi - lo) * (h - 2 * pad); }
    if (opts.bars) {
      var bw = Math.max(3, step * 0.6);
      values.forEach(function (x, i) {
        var cx = pad + i * step;
        if (x === null) s('rect', { x: cx - bw / 2, y: h - pad - 4, width: bw, height: 4, rx: 1.5, style: 'fill:none;stroke:' + v('track') + ';stroke-width:1' }, svg);
        else { var top = h - pad - Math.max(3, (x - 0) / hi * (h - 2 * pad)); s('rect', { x: cx - bw / 2, y: top, width: bw, height: h - pad - top, rx: 1.5, style: 'fill:' + v(color) }, svg); }
      });
      return svg;
    }
    var d = '', pen = false;
    values.forEach(function (x, i) {
      if (x === null) { pen = false; return; }
      d += (pen ? 'L' : 'M') + (pad + i * step).toFixed(1) + ' ' + y(x).toFixed(1); pen = true;
    });
    s('path', { d: d, style: 'fill:none;stroke:' + v(color) + ';stroke-width:1.75;stroke-linecap:round;stroke-linejoin:round' }, svg);
    var lastI = -1; values.forEach(function (x, i) { if (x !== null) lastI = i; });
    values.forEach(function (x, i) {
      if (x === null) return;
      var lone = (i === 0 || values[i - 1] === null) && (i === values.length - 1 || values[i + 1] === null);
      if (lone || i === lastI) s('circle', { cx: pad + i * step, cy: y(x), r: i === lastI ? 2.5 : 1.75, style: 'fill:' + v(color) }, svg);
    });
    return svg;
  }

  /* Week bars: one bar per week (oldest left). An absent week is a dashed empty slot labelled "--".
     A week with a range draws the band and a midpoint tick. */
  function weekBars(target, weeks, opts) {
    opts = opts || {};
    var w = 340, h = 150, top = 14, base = 120, color = opts.color || 'ink';
    var svg = root(target, w, h, opts.label);
    var nums = []; weeks.forEach(function (k) { if (k.v !== null) nums.push(k.hi !== undefined ? k.hi : k.v); });
    var hi = Math.max.apply(null, nums.concat([1])) * 1.08, lo = opts.floor || 0;
    function y(x) { return base - (x - lo) / (hi - lo) * (base - top); }
    [0.5, 1].forEach(function (f) { var gy = base - f * (base - top); s('line', { x1: 0, x2: w, y1: gy, y2: gy, style: 'stroke:' + v('track') + ';stroke-width:1' }, svg); });
    s('line', { x1: 0, x2: w, y1: base, y2: base, style: 'stroke:' + v('track') + ';stroke-width:1' }, svg);
    var slot = w / weeks.length, bw = slot * 0.56;
    weeks.forEach(function (k, i) {
      var cx = slot * i + slot / 2, sel = i === weeks.length - 1 - (opts.selected || 0);
      if (k.v === null) {
        s('rect', { x: cx - bw / 2, y: base - 26, width: bw, height: 26, rx: 4, style: 'fill:none;stroke:' + v('track') + ';stroke-width:1.25;stroke-dasharray:3 3' }, svg);
        axisText(svg, cx, base - 32, '--');
      } else if (k.lo !== undefined) {
        s('rect', { x: cx - bw / 2, y: y(k.hi), width: bw, height: Math.max(2, y(k.lo) - y(k.hi)), rx: 4, style: 'fill:' + v(color + '-band') }, svg);
        s('rect', { x: cx - bw / 2, y: y(k.v) - 1.5, width: bw, height: 3, rx: 1.5, style: 'fill:' + v(color) }, svg);
      } else {
        s('rect', { x: cx - bw / 2, y: y(k.v), width: bw, height: base - y(k.v), rx: 4, style: 'fill:' + v(color) + ';opacity:' + (sel ? 1 : 0.55) }, svg);
      }
      axisText(svg, cx, base + 15, k.label);
      if (k.cov !== undefined) axisText(svg, cx, base + 28, k.cov);
    });
    return svg;
  }

  /* Weight: weigh-in dots (data-sample) and the EWMA trend (data-trend) over N days. */
  function weightChart(target, points, opts) {
    opts = opts || {};
    var w = 340, h = 150, top = 10, base = 122, days = opts.days || 56;
    var svg = root(target, w, h, opts.label);
    var t = trend(points);
    var all = []; t.forEach(function (p) { all.push(p.lb, p.trend); });
    var lo = Math.min.apply(null, all) - 0.6, hi = Math.max.apply(null, all) + 0.6;
    function x(d) { return 28 + d / (days - 1) * (w - 34); }
    function y(lb) { return base - (lb - lo) / (hi - lo) * (base - top); }
    [Math.ceil(lo), Math.round((lo + hi) / 2), Math.floor(hi)].forEach(function (g) {
      s('line', { x1: 28, x2: w, y1: y(g), y2: y(g), style: 'stroke:' + v('track') + ';stroke-width:1' }, svg);
      axisText(svg, 0, y(g) + 4, String(g), 'start');
    });
    for (var wk = 0; wk < days; wk += 7) {
      if (wk) s('line', { x1: x(wk), x2: x(wk), y1: base, y2: base + 4, style: 'stroke:' + v('track') }, svg);
    }
    (opts.weekLabels || []).forEach(function (l, i) { axisText(svg, x(i * 7 + 3), base + 18, l); });
    t.forEach(function (p) { s('circle', { cx: x(p.day), cy: y(p.lb), r: 2.6, style: 'fill:' + v('data-sample') }, svg); });
    var d = t.map(function (p, i) { return (i ? 'L' : 'M') + x(p.day).toFixed(1) + ' ' + y(p.trend).toFixed(1); }).join('');
    s('path', { d: d, style: 'fill:none;stroke:' + v('data-trend') + ';stroke-width:2;stroke-linejoin:round;stroke-linecap:round' }, svg);
    var end = t[t.length - 1];
    s('circle', { cx: x(end.day), cy: y(end.trend), r: 4, style: 'fill:' + v('data-trend') + ';stroke:' + v('surface') + ';stroke-width:2' }, svg);
    return { svg: svg, last: end };
  }

  /* Hypnogram: rows top to bottom awake, REM, core, deep. segs: [{st, a, b}] in minutes from start. */
  var STAGES = ['awake', 'rem', 'core', 'deep'], NAMES = { awake: 'Awake', rem: 'REM', core: 'Core', deep: 'Deep' };
  function hypnogram(target, segs, opts) {
    opts = opts || {};
    var w = 340, rowH = 22, gap = 4, left = 44, h = STAGES.length * (rowH + gap) + 18;
    var svg = root(target, w, h, opts.label);
    var total = segs[segs.length - 1].b;
    function x(m) { return left + m / total * (w - left); }
    STAGES.forEach(function (st, r) {
      var y = r * (rowH + gap);
      s('rect', { x: left, y: y, width: w - left, height: rowH, rx: 4, style: 'fill:' + v('ground') }, svg);
      axisText(svg, 0, y + 15, NAMES[st], 'start');
    });
    segs.forEach(function (g) {
      var r = STAGES.indexOf(g.st), y = r * (rowH + gap);
      s('rect', { x: x(g.a), y: y, width: Math.max(1.5, x(g.b) - x(g.a)), height: rowH, rx: 3, style: 'fill:' + v('sleep-' + g.st) }, svg);
    });
    (opts.ticks || []).forEach(function (t) { axisText(svg, x(t.m), h - 2, t.l); });
    return svg;
  }
  function stageTotals(segs) {
    var t = { awake: 0, rem: 0, core: 0, deep: 0 };
    segs.forEach(function (g) { t[g.st] += g.b - g.a; });
    return t;
  }
  function synthNight(seed) {
    var r = rng(seed || 11), segs = [], m = 0;
    var plan = ['core', 'deep', 'core', 'rem', 'awake', 'core', 'deep', 'core', 'rem', 'core', 'rem', 'awake', 'core', 'rem', 'core', 'rem', 'awake'];
    plan.forEach(function (st) {
      var len = st === 'awake' ? 3 + r() * 8 : st === 'deep' ? 25 + r() * 25 : st === 'rem' ? 15 + r() * 25 : 30 + r() * 35;
      segs.push({ st: st, a: m, b: m + len }); m += len;
    });
    return segs;
  }

  /* Day timeline: 0 to 24 h. Lanes: sleep, heart rate, food, training, steps. */
  function dayTimeline(target, day, opts) {
    opts = opts || {};
    var w = 340, left = 52, lanes = { sleep: 8, hr: 40, food: 104, train: 134, steps: 162 }, h = 210;
    var svg = root(target, w, h, opts.label);
    function x(hour) { return left + hour / 24 * (w - left); }
    [0, 6, 12, 18, 24].forEach(function (hr) {
      s('line', { x1: x(hr), x2: x(hr), y1: 0, y2: h - 18, style: 'stroke:' + v('track') + ';stroke-width:1' }, svg);
      axisText(svg, x(hr), h - 4, hr === 24 ? '' : (hr < 10 ? '0' : '') + hr + ':00', hr === 0 ? 'start' : 'middle');
    });
    axisText(svg, 0, lanes.sleep + 13, 'Sleep', 'start');
    axisText(svg, 0, lanes.hr + 26, 'Heart', 'start');
    axisText(svg, 0, lanes.food + 13, 'Food', 'start');
    axisText(svg, 0, lanes.train + 13, 'Training', 'start');
    axisText(svg, 0, lanes.steps + 13, 'Steps', 'start');
    (day.sleep || []).forEach(function (g) {
      s('rect', { x: x(g.a / 60), y: lanes.sleep + (g.st === 'awake' ? 0 : 4), width: Math.max(1, x(g.b / 60) - x(g.a / 60)), height: g.st === 'awake' ? 18 : 14, style: 'fill:' + v('sleep-' + g.st) }, svg);
    });
    if (day.hr) {
      var lo = 45, hi = 160;
      var d = day.hr.map(function (p, i) { var yy = lanes.hr + 50 - (p[1] - lo) / (hi - lo) * 50; return (i ? 'L' : 'M') + x(p[0]).toFixed(1) + ' ' + yy.toFixed(1); }).join('');
      s('path', { d: d, style: 'fill:none;stroke:' + v('data-heart') + ';stroke-width:1.5;stroke-linejoin:round' }, svg);
    }
    (day.meals || []).forEach(function (m) {
      s('rect', { x: x(m.h) - 5, y: lanes.food, width: 10, height: 18, rx: 3, style: 'fill:' + v('data-energy') }, svg);
    });
    (day.train || []).forEach(function (t) {
      s('rect', { x: x(t.a), y: lanes.train, width: x(t.b) - x(t.a), height: 18, rx: 4, style: 'fill:' + v('ink') }, svg);
    });
    if (day.steps) {
      var mx = Math.max.apply(null, day.steps.map(function (q) { return q === null ? 0 : q; })) || 1;
      day.steps.forEach(function (q, hr) {
        if (q === null || q === 0) return;
        var bh = q / mx * 20;
        s('rect', { x: x(hr) + 1, y: lanes.steps + 20 - bh, width: (w - left) / 24 - 2, height: bh, rx: 1, style: 'fill:' + v('ink') + ';opacity:.7' }, svg);
      });
    }
    return svg;
  }
  function synthDay(seed) {
    var r = rng(seed || 5), night = synthNight(seed || 11), shift = 23.2 * 60 - 24 * 60;
    var sleep = night.map(function (g) { return { st: g.st, a: Math.max(0, g.a + shift), b: Math.max(0, g.b + shift) }; }).filter(function (g) { return g.b > 0; });
    var hr = [];
    for (var t = 0; t <= 24; t += 0.25) {
      var base = t < 6.8 ? 52 : t > 22.8 ? 60 : 70;
      if (t >= 17.5 && t <= 18.6) base = 112 + r() * 34;
      if (t >= 8.1 && t <= 8.5) base = 96;
      hr.push([t, base + r() * 9]);
    }
    var steps = []; for (var q = 0; q < 24; q++) steps.push(q < 7 || q > 22 ? 0 : Math.round(150 + r() * 900 + (q === 8 || q === 12 ? 1400 : 0)));
    return { sleep: sleep, hr: hr, steps: steps, meals: [{ h: 8.9 }, { h: 12.6 }, { h: 19.4 }], train: [{ a: 17.5, b: 18.6 }] };
  }

  /* Coverage dots: array of true (has data), false (missing), null (future day). */
  function dots(target, days, label) {
    var el = typeof target === 'string' ? document.querySelector(target) : target;
    el.classList.add('ig-dots'); el.setAttribute('role', 'img'); el.setAttribute('aria-label', label || '');
    days.forEach(function (d) { var i = document.createElement('i'); i.className = 'ig-dot' + (d === false ? ' is-empty' : d === null ? ' is-future' : ''); el.appendChild(i); });
    return el;
  }

  /* Fill every [data-spark], [data-dots] in a preview from its attributes. */
  function hydrate(scope) {
    scope = scope || document;
    scope.querySelectorAll('[data-spark]').forEach(function (el) {
      var vals = el.getAttribute('data-spark').split(',').map(function (x) { return x === '-' ? null : +x; });
      spark(el, vals, { color: el.getAttribute('data-color') || 'ink', bars: el.hasAttribute('data-bars'), label: el.getAttribute('aria-label') });
      el.removeAttribute('aria-label');
    });
    scope.querySelectorAll('[data-dots]').forEach(function (el) {
      var arr = el.getAttribute('data-dots').split('').map(function (c) { return c === '1' ? true : c === '0' ? false : null; });
      var n = arr.filter(function (d) { return d === true; }).length, of = arr.filter(function (d) { return d !== null; }).length;
      dots(el, arr, n + ' of ' + of + ' days');
    });
  }

  var icons = {
    house: 'M4 11.5 12 5l8 6.5V20h-5v-5H9v5H4z',
    gear: 'M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4zM19 12l2-1.2-2-3.5-2.3.6-1.6-.9L14.5 4h-5l-.6 2.9-1.6.9L5 7.3l-2 3.5L5 12l-2 1.2 2 3.5 2.3-.6 1.6.9.6 2.9h5l.6-2.9 1.6-.9 2.3.6 2-3.5z',
    chevron: 'M9 6l6 6-6 6',
    more: 'M6 12h.01M12 12h.01M18 12h.01',
    back: 'M15 6l-6 6 6 6',
    search: 'M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4'
  };
  function icon(name) { return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + icons[name] + '"/></svg>'; }
  function iconAll(scope) {
    (scope || document).querySelectorAll('[data-icon]').forEach(function (el) { el.insertAdjacentHTML('afterbegin', icon(el.getAttribute('data-icon'))); });
  }

  window.Ingest = {
    trend: trend, spark: spark, weekBars: weekBars, weightChart: weightChart,
    hypnogram: hypnogram, stageTotals: stageTotals, synthNight: synthNight,
    dayTimeline: dayTimeline, synthDay: synthDay, dots: dots, hydrate: hydrate,
    icon: icon, iconAll: iconAll, rng: rng
  };
})();
