import Foundation

/// Shared pieces of every generated game: page shell, stylesheet and the JavaScript kit.
enum JarvisGameKit {
    static func html(title: String, korean: Bool, controls: String, pad: [String]) -> String {
        let labels: [String: String] = ["left": "◀", "right": "▶", "up": "▲", "down": "▼", "action": korean ? "●" : "●"]
        let buttons = pad.map { "<button class=\"padbtn pad-\($0)\" data-key=\"\($0)\" aria-label=\"\($0)\">\(labels[$0] ?? $0)</button>" }.joined(separator: "\n      ")
        let t = MarkdownFormat.escape(title)
        return """
        <!DOCTYPE html>
        <html lang="\(korean ? "ko" : "en")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <title>\(t)</title>
        <link rel="stylesheet" href="style.css">
        </head>
        <body>
        <header id="bar">
          <h1 id="title">\(t)</h1>
          <div id="hud" aria-live="polite"></div>
          <div class="tools">
            <button id="btn-sound" title="\(korean ? "소리" : "Sound")">♪</button>
            <button id="btn-pause" title="\(korean ? "일시정지" : "Pause")">II</button>
            <button id="btn-full" title="\(korean ? "전체 화면" : "Full screen")">⤢</button>
          </div>
        </header>
        <main id="stage">
          <canvas id="game" width="480" height="640"></canvas>
          <div id="overlay" class="overlay">
            <h2 id="ov-title"></h2>
            <p id="ov-text"></p>
            <button id="ov-button"></button>
          </div>
        </main>
        <div id="pad" class="pad">
              \(buttons)
        </div>
        <footer id="help">\(MarkdownFormat.escape(controls))</footer>
        <script src="config.js"></script>
        <script src="kit.js"></script>
        <script src="game.js"></script>
        </body>
        </html>

        """
    }

    static let css = #"""
    :root { --bg: #0b1020; --panel: #141b33; --fg: #e8ecff; --muted: #8f9bc7; --accent: #36d6ff; --accent2: #ff4f8b; }
    * { box-sizing: border-box; }
    html, body { margin: 0; height: 100%; background: var(--bg); color: var(--fg);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif; }
    body { display: flex; flex-direction: column; overflow: hidden; -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
    #bar { display: flex; align-items: center; gap: 12px; padding: 8px 14px; background: var(--panel); box-shadow: 0 1px 0 rgba(255,255,255,.06); }
    #bar h1 { font-size: 17px; margin: 0; letter-spacing: .02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    #hud { flex: 1; text-align: center; font-variant-numeric: tabular-nums; font-weight: 600; font-size: 15px; color: var(--accent); }
    .tools { display: flex; gap: 6px; }
    .tools button, .overlay button { background: transparent; color: var(--fg); border: 1px solid rgba(255,255,255,.18); border-radius: 8px;
      min-width: 38px; height: 34px; font-size: 15px; cursor: pointer; }
    .tools button.off { opacity: .4; }
    #stage { flex: 1; position: relative; display: flex; align-items: center; justify-content: center; min-height: 0; padding: 8px; }
    canvas { display: block; touch-action: none; border-radius: 10px; box-shadow: 0 10px 40px rgba(0,0,0,.45); background: #000; }
    .overlay { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;
      text-align: center; background: rgba(5, 8, 20, .62); backdrop-filter: blur(3px); -webkit-backdrop-filter: blur(3px); padding: 24px; }
    .overlay.hidden { display: none; }
    .overlay h2 { margin: 0; font-size: clamp(26px, 6vw, 44px); color: var(--accent); text-shadow: 0 0 18px var(--accent); }
    .overlay p { margin: 0; color: var(--fg); white-space: pre-line; font-size: 16px; max-width: 34em; line-height: 1.5; }
    .overlay button { margin-top: 8px; padding: 0 22px; height: 46px; font-size: 18px; font-weight: 700; color: #04121a; background: var(--accent);
      border: none; box-shadow: 0 6px 20px rgba(0,0,0,.35); }
    .pad { display: none; justify-content: center; gap: 10px; padding: 8px 10px calc(10px + env(safe-area-inset-bottom)); }
    .padbtn { width: 64px; height: 56px; border-radius: 14px; border: 1px solid rgba(255,255,255,.2); background: var(--panel); color: var(--fg);
      font-size: 22px; touch-action: none; }
    .padbtn.down { background: var(--accent); color: #04121a; }
    .pad-action { width: 84px; }
    #help { text-align: center; color: var(--muted); font-size: 12px; padding: 4px 10px 8px; }
    @media (pointer: coarse) { .pad { display: flex; } #help { display: none; } }
    body.touch .pad { display: flex; }
    body.theme-light { --bg: #eef1f8; --panel: #ffffff; --fg: #1a2033; --muted: #66708f; }
    body.theme-neon { --bg: #05010f; --panel: #120526; --accent: #39ff14; --accent2: #ff2bd6; }
    body.theme-retro { --bg: #1d1a12; --panel: #2b2619; --fg: #f3e7c3; --accent: #ffb000; --accent2: #ff5a36; font-family: "Courier New", monospace; }
    body.theme-pastel { --bg: #fff5f8; --panel: #ffffff; --fg: #4b3f56; --muted: #9b8fa6; --accent: #8fb8ff; --accent2: #ff9ec7; }
    body.theme-retro canvas, body.pixel canvas { image-rendering: pixelated; }
    """#

    /// The game kit (kit.js). Games use `Kit` for canvas, input, loop, sound, storage, screens and test hooks.
    static let js = #"""
    /* Jarvis game kit — canvas, input, fixed-step loop, sound, storage, screens, particles, test hooks. */
    (function () {
      'use strict';
      var C = window.CONFIG || {};
      C.features = C.features || {};
      C.colors = C.colors || {};
      C.strings = C.strings || {};
      var K = { config: C, frame: 0, paused: false, keys: {}, pressed: {}, particles: [], W: 480, H: 640, scale: 1 };

      K.t = function (key, fallback) { return C.strings[key] || fallback || key; };
      K.color = function (role, fallback) { return C.colors[role] || fallback; };
      K.feature = function (name, fallback) { return C.features[name] === undefined ? !!fallback : !!C.features[name]; };
      K.num = function (name, fallback) { return typeof C[name] === 'number' ? C[name] : fallback; };

      /* Seeded randomness so tests replay exactly (mulberry32). */
      var seed = (Date.now() ^ 0x5f3759df) >>> 0;
      K.seed = function (s) { seed = s >>> 0; };
      K.random = function () {
        seed = (seed + 0x6D2B79F5) >>> 0;
        var t = seed;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
      };
      K.rand = function (a, b) { return a + (b - a) * K.random(); };
      K.randInt = function (a, b) { return Math.floor(K.rand(a, b + 1)); };
      K.pick = function (list) { return list[Math.floor(K.random() * list.length)]; };
      K.clamp = function (v, a, b) { return Math.max(a, Math.min(b, v)); };
      K.overlap = function (a, b) { return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y; };
      K.dist = function (ax, ay, bx, by) { var dx = ax - bx, dy = ay - by; return Math.sqrt(dx * dx + dy * dy); };

      /* Theme and page tools. */
      var theme = C.theme || 'dark';
      document.body.classList.add('theme-' + theme);
      if (C.pixel) document.body.classList.add('pixel');
      if (C.colors.accent || C.colors.main) document.documentElement.style.setProperty('--accent', C.colors.accent || C.colors.main);
      if (C.colors.background) document.documentElement.style.setProperty('--bg', C.colors.background);
      if (C.features.touch) document.body.classList.add('touch');

      /* Canvas with a fixed logical size, scaled sharply to fit the screen. */
      K.setup = function (width, height) {
        var canvas = document.getElementById('game');
        var ctx = canvas.getContext('2d');
        K.canvas = canvas; K.ctx = ctx; K.W = width; K.H = height;
        function fit() {
          var stage = document.getElementById('stage');
          var availW = Math.max(100, stage.clientWidth - 16), availH = Math.max(100, stage.clientHeight - 16);
          var scale = Math.min(availW / width, availH / height);
          var dpr = Math.min(window.devicePixelRatio || 1, 2);
          canvas.style.width = Math.floor(width * scale) + 'px';
          canvas.style.height = Math.floor(height * scale) + 'px';
          canvas.width = Math.floor(width * scale * dpr);
          canvas.height = Math.floor(height * scale * dpr);
          ctx.setTransform(scale * dpr, 0, 0, scale * dpr, 0, 0);
          ctx.imageSmoothingEnabled = !(C.pixel || theme === 'retro');
          K.scale = scale;
          if (K.render) K.render();
        }
        window.addEventListener('resize', fit);
        window.addEventListener('orientationchange', function () { setTimeout(fit, 200); });
        fit();
        return ctx;
      };

      /* Input: held keys, keys pressed this frame, pointer, swipes and on-screen buttons. */
      var keyMap = { ArrowLeft: 'left', a: 'left', A: 'left', ArrowRight: 'right', d: 'right', D: 'right', ArrowUp: 'up', w: 'up', W: 'up',
        ArrowDown: 'down', s: 'down', S: 'down', ' ': 'action', Enter: 'action', p: 'pause', P: 'pause', Escape: 'pause',
        z: 'action', Z: 'action', x: 'action2', X: 'action2', k: 'left2', l: 'right2', i: 'up2', o: 'down2' };
      K.press = function (name) {
        if (name === 'pause') { K.togglePause(); return; }
        if (!K.keys[name]) K.pressed[name] = true;
        K.keys[name] = true;
        if (K.onPress) K.onPress(name);
      };
      K.release = function (name) { K.keys[name] = false; };
      K.tap = function (name) { K.press(name); setTimeout(function () { K.release(name); }, 60); };
      window.addEventListener('keydown', function (e) {
        var k = keyMap[e.key];
        if (k) { if (!e.repeat) K.press(k); e.preventDefault(); }
        K.audio.unlock();
      });
      window.addEventListener('keyup', function (e) { var k = keyMap[e.key]; if (k) K.release(k); });

      K.pointer = { x: 0, y: 0, down: false, clicked: false };
      var start = null;
      function toLogical(e) {
        var r = K.canvas.getBoundingClientRect();
        return { x: (e.clientX - r.left) / r.width * K.W, y: (e.clientY - r.top) / r.height * K.H };
      }
      document.addEventListener('DOMContentLoaded', function () {});
      setTimeout(function () {
        var canvas = document.getElementById('game');
        canvas.addEventListener('pointerdown', function (e) {
          K.audio.unlock();
          var p = toLogical(e);
          K.pointer.x = p.x; K.pointer.y = p.y; K.pointer.down = true; K.pointer.clicked = true;
          start = { x: e.clientX, y: e.clientY, t: Date.now() };
          if (K.onPointer) K.onPointer('down', p.x, p.y);
          e.preventDefault();
        });
        canvas.addEventListener('pointermove', function (e) {
          var p = toLogical(e);
          K.pointer.x = p.x; K.pointer.y = p.y;
          if (K.onPointer) K.onPointer('move', p.x, p.y);
        });
        function up(e) {
          K.pointer.down = false;
          if (start) {
            var dx = e.clientX - start.x, dy = e.clientY - start.y;
            if (Math.max(Math.abs(dx), Math.abs(dy)) > 28 && Date.now() - start.t < 600) {
              K.tap(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 'right' : 'left') : (dy > 0 ? 'down' : 'up'));
              K.swiped = true;
            }
          }
          start = null;
          var p = toLogical(e);
          if (K.onPointer) K.onPointer('up', p.x, p.y);
        }
        canvas.addEventListener('pointerup', up);
        canvas.addEventListener('pointercancel', up);
        var pads = document.querySelectorAll('[data-key]');
        for (var i = 0; i < pads.length; i++) {
          (function (btn) {
            var key = btn.getAttribute('data-key');
            btn.addEventListener('pointerdown', function (e) { K.audio.unlock(); K.press(key); btn.classList.add('down'); e.preventDefault(); });
            var off = function () { K.release(key); btn.classList.remove('down'); };
            btn.addEventListener('pointerup', off); btn.addEventListener('pointerleave', off); btn.addEventListener('pointercancel', off);
          })(pads[i]);
        }
        var b = function (id) { return document.getElementById(id); };
        b('btn-pause').addEventListener('click', function () { K.togglePause(); });
        b('btn-sound').addEventListener('click', function () {
          K.audio.enabled = !K.audio.enabled; K.audio.unlock();
          b('btn-sound').classList.toggle('off', !K.audio.enabled);
          if (!K.audio.enabled) K.music.stop(); else if (K.feature('music') && K.running) K.music.start();
        });
        b('btn-full').addEventListener('click', function () {
          var el = document.documentElement;
          if (document.fullscreenElement || document.webkitFullscreenElement) { (document.exitFullscreen || document.webkitExitFullscreen).call(document); }
          else if (el.requestFullscreen) el.requestFullscreen(); else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
        });
        b('ov-button').addEventListener('click', function () { K.audio.unlock(); if (K.onOverlayButton) K.onOverlayButton(); });
        if (!K.feature('pause', true)) b('btn-pause').style.display = 'none';
      }, 0);

      K.endFrame = function () { K.pressed = {}; K.pointer.clicked = false; K.swiped = false; };

      /* Fixed-step loop (60 updates per second, renders every frame). */
      K.loop = function (update, render) {
        K.update = update; K.render = render;
        var last = (window.performance || Date).now(), acc = 0, dt = 1 / 60;
        function frame(now) {
          acc += Math.min(0.25, (now - last) / 1000);
          last = now;
          while (acc >= dt) {
            if (!K.paused) { update(dt); K.frame++; K.updateParticles(dt); }
            K.endFrame();
            acc -= dt;
          }
          render();
          window.requestAnimationFrame(frame);
        }
        window.requestAnimationFrame(frame);
      };
      /* Deterministic stepping for automated checks. */
      K.step = function (n) {
        for (var i = 0; i < n; i++) { if (!K.paused) { K.update(1 / 60); K.frame++; K.updateParticles(1 / 60); } K.endFrame(); }
        if (K.render) K.render();
      };

      K.togglePause = function () {
        if (!K.running) return;
        K.paused = !K.paused;
        if (K.paused) { K.overlay(K.t('paused', 'Paused'), K.t('pausedHint', 'Press P or tap to continue'), K.t('resume', 'Resume')); K.music.stop(); }
        else { K.hideOverlay(); if (K.feature('music')) K.music.start(); }
        var prev = K.onOverlayButton;
        if (K.paused) K.onOverlayButton = function () { K.onOverlayButton = prev; K.togglePause(); };
      };

      /* Sound: synthesised effects (no files), optional procedural music. */
      K.audio = {
        ctx: null, enabled: C.features.sound !== false,
        unlock: function () {
          var AC = window.AudioContext || window.webkitAudioContext;
          if (!this.ctx && AC) { try { this.ctx = new AC(); } catch (e) { this.ctx = null; } }
          if (this.ctx && this.ctx.state === 'suspended') { try { this.ctx.resume(); } catch (e) {} }
        },
        tone: function (freq, dur, type, vol, slide) {
          if (!this.enabled || !this.ctx) return;
          try {
            var t = this.ctx.currentTime, o = this.ctx.createOscillator(), g = this.ctx.createGain();
            o.type = type || 'square';
            o.frequency.setValueAtTime(freq, t);
            if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq * slide), t + dur);
            g.gain.setValueAtTime(vol || 0.06, t);
            g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
            o.connect(g); g.connect(this.ctx.destination);
            o.start(t); o.stop(t + dur + 0.02);
          } catch (e) {}
        }
      };
      K.sfx = {
        coin: function () { K.audio.tone(880, 0.08, 'square', 0.05); setTimeout(function () { K.audio.tone(1320, 0.1, 'square', 0.05); }, 60); },
        hit: function () { K.audio.tone(220, 0.08, 'square', 0.06); },
        bounce: function () { K.audio.tone(520, 0.05, 'triangle', 0.07); },
        jump: function () { K.audio.tone(330, 0.14, 'square', 0.05, 2); },
        shoot: function () { K.audio.tone(900, 0.07, 'sawtooth', 0.03, 0.4); },
        boom: function () { K.audio.tone(120, 0.35, 'sawtooth', 0.08, 0.3); },
        die: function () { K.audio.tone(440, 0.5, 'triangle', 0.08, 0.25); },
        power: function () { [523, 659, 784, 1046].forEach(function (f, i) { setTimeout(function () { K.audio.tone(f, 0.09, 'square', 0.05); }, i * 70); }); },
        click: function () { K.audio.tone(660, 0.03, 'square', 0.04); },
        win: function () { [523, 659, 784, 1046, 1318].forEach(function (f, i) { setTimeout(function () { K.audio.tone(f, 0.14, 'triangle', 0.07); }, i * 110); }); }
      };
      K.music = {
        timer: null, step: 0,
        start: function () {
          if (this.timer || !K.feature('music') || !K.audio.enabled) return;
          var notes = [262, 330, 392, 330, 294, 349, 440, 349, 262, 330, 392, 523, 494, 392, 330, 294];
          var bass = [131, 131, 175, 175, 147, 147, 196, 196];
          var self = this;
          this.timer = setInterval(function () {
            var i = self.step++;
            K.audio.tone(notes[i % notes.length], 0.18, 'triangle', 0.025);
            if (i % 2 === 0) K.audio.tone(bass[(i / 2) % bass.length | 0], 0.3, 'sine', 0.03);
          }, 200);
        },
        stop: function () { if (this.timer) { clearInterval(this.timer); this.timer = null; } }
      };

      /* Storage (high scores, settings). */
      var prefix = 'jarvis:' + (C.id || document.title) + ':';
      K.store = {
        get: function (k, d) { try { var v = window.localStorage.getItem(prefix + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
        set: function (k, v) { try { window.localStorage.setItem(prefix + k, JSON.stringify(v)); } catch (e) {} }
      };
      K.best = function () { return K.store.get('best', 0); };
      K.submit = function (score) { if (score > K.best()) { K.store.set('best', score); return true; } return false; };

      /* Overlay screens and HUD. */
      K.overlay = function (title, text, button) {
        var o = document.getElementById('overlay');
        document.getElementById('ov-title').textContent = title || '';
        document.getElementById('ov-text').textContent = text || '';
        var b = document.getElementById('ov-button');
        b.textContent = button || '';
        b.style.display = button ? '' : 'none';
        o.classList.remove('hidden');
      };
      K.hideOverlay = function () { document.getElementById('overlay').classList.add('hidden'); };
      K.hud = function (text) { var h = document.getElementById('hud'); if (h && h.textContent !== text) h.textContent = text; };

      /* Game flow: title screen → playing → game over, shared by all games. */
      K.flow = function (opts) {
        K.running = false;
        function begin() {
          K.audio.unlock();
          K.hideOverlay();
          K.paused = false;
          K.running = true;
          opts.start();
          if (K.feature('music')) K.music.start();
        }
        K.begin = begin;
        K.gameOver = function (score, extra) {
          K.running = false;
          K.music.stop();
          var record = typeof score === 'number' && K.submit(score);
          var lines = [];
          if (typeof score === 'number') lines.push(K.t('score', 'Score') + ': ' + score);
          if (typeof score === 'number' && K.feature('highscore', true)) lines.push(K.t('best', 'Best') + ': ' + K.best() + (record ? '  ★ ' + K.t('newRecord', 'New record!') : ''));
          if (extra) lines.push(extra);
          K.overlay(opts.overTitle || K.t('gameOver', 'Game over'), lines.join('\n'), K.t('again', 'Play again'));
          K.onOverlayButton = begin;
        };
        K.win = function (score, extra) {
          K.running = false;
          K.music.stop();
          if (typeof score === 'number') K.submit(score);
          K.sfx.win();
          K.overlay(K.t('youWin', 'You win!'), (typeof score === 'number' ? K.t('score', 'Score') + ': ' + score + '\n' : '') + (extra || ''), K.t('again', 'Play again'));
          K.onOverlayButton = begin;
        };
        K.overlay(C.title || document.title, (opts.intro || '') + (K.feature('highscore', true) && K.best() > 0 ? '\n' + K.t('best', 'Best') + ': ' + K.best() : ''), K.t('start', 'Start'));
        K.onOverlayButton = begin;
        var previous = K.onPress;
        K.onPress = function (name) {
          if (!K.running && (name === 'action') && document.getElementById('overlay').classList.contains('hidden') === false) { begin(); return; }
          if (previous) previous(name);
        };
      };

      /* Particles. */
      K.burst = function (x, y, color, n, speed) {
        if (C.features.particles === false) return;
        for (var i = 0; i < (n || 12); i++) {
          var a = K.random() * Math.PI * 2, s = (speed || 120) * (0.4 + K.random());
          K.particles.push({ x: x, y: y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.6 + K.random() * 0.4, color: color || '#fff' });
        }
      };
      K.updateParticles = function (dt) {
        for (var i = K.particles.length - 1; i >= 0; i--) {
          var p = K.particles[i];
          p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 200 * dt; p.life -= dt;
          if (p.life <= 0) K.particles.splice(i, 1);
        }
      };
      K.drawParticles = function (ctx) {
        for (var i = 0; i < K.particles.length; i++) {
          var p = K.particles[i];
          ctx.globalAlpha = Math.max(0, Math.min(1, p.life));
          ctx.fillStyle = p.color;
          ctx.fillRect(p.x - 2, p.y - 2, 4, 4);
        }
        ctx.globalAlpha = 1;
      };

      /* Drawing helpers. */
      K.roundRect = function (ctx, x, y, w, h, r) {
        r = Math.min(r, w / 2, h / 2);
        ctx.beginPath();
        ctx.moveTo(x + r, y);
        ctx.arcTo(x + w, y, x + w, y + h, r);
        ctx.arcTo(x + w, y + h, x, y + h, r);
        ctx.arcTo(x, y + h, x, y, r);
        ctx.arcTo(x, y, x + w, y, r);
        ctx.closePath();
      };
      K.text = function (ctx, s, x, y, size, color, align) {
        ctx.fillStyle = color || '#fff';
        ctx.font = '700 ' + (size || 20) + 'px -apple-system, "Segoe UI", sans-serif';
        ctx.textAlign = align || 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(s, x, y);
      };
      K.glow = function (ctx, color, blur) { if (theme === 'neon' || C.glow) { ctx.shadowColor = color; ctx.shadowBlur = blur || 12; } };
      K.noGlow = function (ctx) { ctx.shadowBlur = 0; };

      /* Speed multiplier from the request (1 = normal) and difficulty (0 easy, 1 normal, 2 hard). */
      K.speed = K.num('speed', 1) * [0.8, 1, 1.25][K.num('difficulty', 1)];

      /* Automated checks call window.__game (each game adds its own selfTest). */
      K.expose = function (api) {
        api.step = K.step; api.press = K.press; api.release = K.release; api.tap = K.tap;
        api.begin = function () { K.begin(); };
        window.__game = api;
      };

      window.Kit = K;
    })();
    """#
}
