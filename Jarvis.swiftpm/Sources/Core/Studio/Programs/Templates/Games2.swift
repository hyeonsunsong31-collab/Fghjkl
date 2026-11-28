import Foundation

/// Game templates: space shooter, endless runner, dodge & collect, platformer.
enum GamesTwo {
    static let shooter = #"""
    /* Space shooter — clear the waves, dodge the fire. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 480, H = 640;
      var ctx = K.setup(W, H);
      var maxWaves = K.num('levels', 0);
      var stars = [];
      for (var i = 0; i < 70; i++) stars.push({ x: Math.random() * W, y: Math.random() * H, s: Math.random() * 1.6 + 0.4 });
      var s;
      function wave(n) {
        s.enemies = []; s.boss = null;
        if (K.feature('boss') && n % 3 === 0) {
          s.boss = { x: W / 2 - 60, y: 70, w: 120, h: 60, hp: 30 + n * 6, max: 30 + n * 6, dir: 1, cool: 1 };
          return;
        }
        var rows = Math.min(2 + n, 6), cols = 7;
        for (var r = 0; r < rows; r++) for (var c = 0; c < cols; c++) {
          s.enemies.push({ x: 40 + c * 56, y: 70 + r * 44, w: 34, h: 24, row: r });
        }
        s.dir = 1; s.drop = 0;
      }
      function start() {
        s = { ship: { x: W / 2 - 18, y: H - 70, w: 36, h: 30 }, bullets: [], shots: [], drops: [], score: 0, lives: Math.max(1, K.num('lives', 3)),
              wave: 1, cool: 0, double: 0, shield: false, over: false, hurt: 0 };
        wave(1);
      }
      function fire() {
        if (s.cool > 0) return;
        s.cool = 0.24;
        var cx = s.ship.x + s.ship.w / 2;
        if (s.double > 0) { s.bullets.push({ x: cx - 10, y: s.ship.y }, { x: cx + 10, y: s.ship.y }); }
        else s.bullets.push({ x: cx, y: s.ship.y });
        K.sfx.shoot();
      }
      K.onPointer = function (type, x) { if (K.running) s.ship.x = K.clamp(x - s.ship.w / 2, 0, W - s.ship.w); };
      function hurt() {
        if (s.hurt > 0) return;
        if (s.shield) { s.shield = false; s.hurt = 1; K.sfx.hit(); return; }
        s.lives--;
        s.hurt = 1.5;
        K.sfx.boom();
        K.burst(s.ship.x + s.ship.w / 2, s.ship.y + 15, K.color('player', '#38bdf8'), 30, 200);
        if (s.lives <= 0) { s.over = true; K.gameOver(s.score, K.t('wave', 'Wave') + ' ' + s.wave); }
      }
      function kill(x, y, color, points) {
        s.score += points;
        K.sfx.hit();
        K.burst(x, y, color, 14, 160);
        if (K.feature('powerups') && K.random() < 0.12) s.drops.push({ x: x, y: y, kind: K.pick(['double', 'shield', 'life']) });
      }
      function update(dt) {
        if (!K.running || s.over) return;
        var ship = s.ship;
        if (K.keys.left) ship.x -= 300 * dt;
        if (K.keys.right) ship.x += 300 * dt;
        ship.x = K.clamp(ship.x, 0, W - ship.w);
        s.cool -= dt; s.double -= dt; s.hurt -= dt;
        if (K.keys.action || K.keys.up || K.pointer.down) fire();
        for (var i = s.bullets.length - 1; i >= 0; i--) { s.bullets[i].y -= 620 * dt; if (s.bullets[i].y < -10) s.bullets.splice(i, 1); }
        var speed = (40 + 260 / Math.max(1, s.enemies.length)) * K.speed * (1 + s.wave * 0.08);
        var edge = false;
        s.enemies.forEach(function (e) { e.x += s.dir * speed * dt; if (e.x < 8 || e.x + e.w > W - 8) edge = true; });
        if (edge) { s.dir = -s.dir; s.enemies.forEach(function (e) { e.y += 16; e.x += s.dir * 4; }); }
        var fireRate = [0.5, 0.9, 1.5][K.num('difficulty', 1)] * (1 + s.wave * 0.12);
        if (s.enemies.length && K.random() < fireRate * dt) {
          var shooter = K.pick(s.enemies);
          s.shots.push({ x: shooter.x + shooter.w / 2, y: shooter.y + shooter.h, vx: 0, vy: 240 * K.speed });
        }
        if (s.boss) {
          var b = s.boss;
          b.x += b.dir * 120 * dt * K.speed;
          if (b.x < 10 || b.x + b.w > W - 10) b.dir = -b.dir;
          b.cool -= dt;
          if (b.cool <= 0) {
            b.cool = 1.1 / K.speed;
            for (var a = -2; a <= 2; a++) s.shots.push({ x: b.x + b.w / 2, y: b.y + b.h, vx: a * 60, vy: 220 * K.speed });
          }
        }
        for (var j = s.shots.length - 1; j >= 0; j--) {
          var sh = s.shots[j];
          sh.x += sh.vx * dt; sh.y += sh.vy * dt;
          if (sh.y > H + 10) { s.shots.splice(j, 1); continue; }
          if (sh.x > ship.x && sh.x < ship.x + ship.w && sh.y > ship.y && sh.y < ship.y + ship.h) { s.shots.splice(j, 1); hurt(); if (s.over) return; }
        }
        for (var bi = s.bullets.length - 1; bi >= 0; bi--) {
          var bu = s.bullets[bi], used = false;
          for (var ei = s.enemies.length - 1; ei >= 0; ei--) {
            var e = s.enemies[ei];
            if (bu.x > e.x && bu.x < e.x + e.w && bu.y > e.y && bu.y < e.y + e.h) {
              s.enemies.splice(ei, 1);
              kill(e.x + e.w / 2, e.y + e.h / 2, K.color('enemy', '#a855f7'), 10 * (6 - Math.min(5, e.row)));
              used = true;
              break;
            }
          }
          if (!used && s.boss && bu.x > s.boss.x && bu.x < s.boss.x + s.boss.w && bu.y > s.boss.y && bu.y < s.boss.y + s.boss.h) {
            used = true;
            s.boss.hp--;
            K.sfx.bounce();
            if (s.boss.hp <= 0) { kill(s.boss.x + s.boss.w / 2, s.boss.y + s.boss.h / 2, '#f97316', 500); s.boss = null; }
          }
          if (used) s.bullets.splice(bi, 1);
        }
        s.enemies.forEach(function (e) { if (e.y + e.h >= ship.y) { s.lives = 1; s.hurt = 0; s.shield = false; hurt(); } });
        if (s.over) return;
        for (var d = s.drops.length - 1; d >= 0; d--) {
          var dr = s.drops[d];
          dr.y += 120 * dt;
          if (dr.x > ship.x - 8 && dr.x < ship.x + ship.w + 8 && dr.y > ship.y && dr.y < ship.y + ship.h) {
            if (dr.kind === 'double') s.double = 10; else if (dr.kind === 'shield') s.shield = true; else s.lives++;
            K.sfx.power();
            s.drops.splice(d, 1);
          } else if (dr.y > H) s.drops.splice(d, 1);
        }
        if (!s.enemies.length && !s.boss) {
          if (maxWaves > 0 && s.wave >= maxWaves) { s.over = true; K.win(s.score); return; }
          s.wave++;
          wave(s.wave);
          K.sfx.win();
        }
        stars.forEach(function (st) { st.y += st.s * 40 * dt; if (st.y > H) { st.y = 0; st.x = K.random() * W; } });
      }
      function drawShip(x, y, w, h, color) {
        ctx.fillStyle = color;
        ctx.beginPath(); ctx.moveTo(x + w / 2, y); ctx.lineTo(x + w, y + h); ctx.lineTo(x + w / 2, y + h * 0.72); ctx.lineTo(x, y + h); ctx.closePath(); ctx.fill();
      }
      function render() {
        ctx.fillStyle = K.color('background', '#020617');
        ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = '#fff';
        stars.forEach(function (st) { ctx.globalAlpha = 0.3 + st.s / 3; ctx.fillRect(st.x, st.y, st.s, st.s); });
        ctx.globalAlpha = 1;
        if (!s) return;
        var ec = K.color('enemy', '#a855f7');
        K.glow(ctx, ec);
        s.enemies.forEach(function (e) {
          ctx.fillStyle = ec;
          K.roundRect(ctx, e.x, e.y, e.w, e.h, 6); ctx.fill();
          ctx.fillStyle = '#020617';
          ctx.fillRect(e.x + 8, e.y + 8, 5, 5); ctx.fillRect(e.x + e.w - 13, e.y + 8, 5, 5);
        });
        if (s.boss) {
          ctx.fillStyle = '#f97316';
          K.roundRect(ctx, s.boss.x, s.boss.y, s.boss.w, s.boss.h, 14); ctx.fill();
          ctx.fillStyle = '#334155'; ctx.fillRect(s.boss.x, s.boss.y - 12, s.boss.w, 6);
          ctx.fillStyle = '#ef4444'; ctx.fillRect(s.boss.x, s.boss.y - 12, s.boss.w * s.boss.hp / s.boss.max, 6);
        }
        K.noGlow(ctx);
        ctx.fillStyle = K.color('bullets', '#fde047');
        s.bullets.forEach(function (b) { ctx.fillRect(b.x - 2, b.y - 10, 4, 12); });
        ctx.fillStyle = '#fb7185';
        s.shots.forEach(function (b) { ctx.beginPath(); ctx.arc(b.x, b.y, 4, 0, Math.PI * 2); ctx.fill(); });
        s.drops.forEach(function (d) { K.text(ctx, d.kind === 'double' ? '⇈' : (d.kind === 'shield' ? '◈' : '♥'), d.x, d.y, 20, '#22d3ee'); });
        if (s.hurt <= 0 || Math.floor(K.frame / 5) % 2 === 0) {
          var pc = K.color('player', '#38bdf8');
          K.glow(ctx, pc);
          drawShip(s.ship.x, s.ship.y, s.ship.w, s.ship.h, pc);
          K.noGlow(ctx);
          if (s.shield) { ctx.strokeStyle = '#22d3ee'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(s.ship.x + 18, s.ship.y + 16, 28, 0, Math.PI * 2); ctx.stroke(); }
        }
        K.drawParticles(ctx);
        K.hud(K.t('score', 'Score') + ' ' + s.score + '   ♥ ' + s.lives + '   ' + K.t('wave', 'Wave') + ' ' + s.wave + (K.feature('highscore', true) ? '   ' + K.t('best', 'Best') + ' ' + K.best() : ''));
      }
      start();
      K.flow({ start: start, intro: K.t('intro', '← → or drag to move · hold Space or touch to fire.\nClear every wave!') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, wave: s.wave, enemies: s.enemies.length, over: s.over, running: !!K.running, frame: K.frame }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(5); K.begin();
          s.enemies = [{ x: s.ship.x, y: s.ship.y - 200, w: 34, h: 24, row: 0 }, { x: 10, y: 60, w: 34, h: 24, row: 0 }];
          s.shots = [];
          s.dir = 0;   // hold the formation still: the target stays above the ship
          K.press('action'); K.step(30); K.release('action');
          s.dir = 1;
          check(s.enemies.length === 1 && s.score > 0, 'shooting an enemy destroys it and scores');
          var lives = s.lives;
          s.hurt = 0; s.shield = false;
          s.shots = [{ x: s.ship.x + 18, y: s.ship.y - 5, vx: 0, vy: 200 }];
          K.step(10);
          check(s.lives === lives - 1, 'enemy fire costs a life');
          s.enemies = []; s.boss = null;
          var w = s.wave;
          K.step(2);
          check(s.wave === w + 1 || s.over, 'clearing a wave brings the next one');
          return { ok: ok, details: out };
        }
      });
    })();
    """#

    static let runner = #"""
    /* Endless runner — jump the obstacles, run as far as you can. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 640, H = 360, GROUND = 300;
      var ctx = K.setup(W, H);
      var s;
      function start() {
        s = { p: { x: 80, y: GROUND - 44, w: 34, h: 44, vy: 0, ground: true, duck: false }, obstacles: [], coins: [], timer: 1.2,
              speed: 300 * K.speed, distance: 0, score: 0, lives: Math.max(1, K.num('lives', 1)), over: false, hurt: 0 };
      }
      function jump() { if (K.running && s.p.ground) { s.p.vy = -640; s.p.ground = false; K.sfx.jump(); } }
      K.onPress = function (name) { if (name === 'action' || name === 'up') jump(); };
      K.onPointer = function (type) { if (type === 'down') jump(); };
      function hit() {
        if (s.hurt > 0) return;
        K.sfx.die();
        K.burst(s.p.x + 17, s.p.y + 22, K.color('player', '#f97316'), 20);
        s.lives--;
        if (s.lives > 0) { s.hurt = 1.5; s.obstacles = []; return; }
        s.over = true;
        K.gameOver(s.score);
      }
      function update(dt) {
        if (!K.running || s.over) return;
        var p = s.p;
        s.speed += 9 * dt * K.speed;
        s.distance += s.speed * dt;
        s.score = Math.floor(s.distance / 10);
        s.hurt -= dt;
        p.duck = !!K.keys.down && p.ground;
        p.h = p.duck ? 26 : 44;
        if (p.ground) p.y = GROUND - p.h;
        p.vy += (K.keys.down ? 3600 : 1900) * dt;
        p.y += p.vy * dt;
        if (p.y + p.h >= GROUND) { p.y = GROUND - p.h; p.vy = 0; p.ground = true; }
        s.timer -= dt;
        if (s.timer <= 0) {
          s.timer = K.rand(0.75, 1.6) * 300 / s.speed * 1.6;
          var flying = s.score > 250 && K.random() < 0.3;
          var tall = K.random() < 0.4;
          s.obstacles.push(flying ? { x: W + 20, y: GROUND - 70, w: 38, h: 22, fly: true }
                                  : { x: W + 20, y: GROUND - (tall ? 54 : 36), w: tall ? 22 : 30, h: tall ? 54 : 36, fly: false });
          if (K.feature('powerups') && K.random() < 0.3) s.coins.push({ x: W + 120, y: GROUND - 110 });
        }
        for (var i = s.obstacles.length - 1; i >= 0; i--) {
          var o = s.obstacles[i];
          o.x -= s.speed * dt;
          if (o.x + o.w < -10) { s.obstacles.splice(i, 1); continue; }
          if (K.overlap({ x: p.x + 4, y: p.y + 4, w: p.w - 8, h: p.h - 6 }, o)) { hit(); if (s.over) return; }
        }
        for (var j = s.coins.length - 1; j >= 0; j--) {
          var c = s.coins[j];
          c.x -= s.speed * dt;
          if (K.dist(c.x, c.y, p.x + 17, p.y + 20) < 30) { s.distance += 500; K.sfx.coin(); s.coins.splice(j, 1); }
          else if (c.x < -20) s.coins.splice(j, 1);
        }
      }
      function render() {
        var sky = ctx.createLinearGradient(0, 0, 0, H);
        sky.addColorStop(0, K.color('background', '#1e293b'));
        sky.addColorStop(1, '#0f172a');
        ctx.fillStyle = sky;
        ctx.fillRect(0, 0, W, H);
        var off = s ? s.distance : 0;
        ctx.fillStyle = 'rgba(255,255,255,.08)';
        for (var m = 0; m < 5; m++) {
          var mx = ((m * 220 - off * 0.2) % (W + 220) + W + 220) % (W + 220) - 110;
          ctx.beginPath(); ctx.moveTo(mx - 120, GROUND); ctx.lineTo(mx, GROUND - 120); ctx.lineTo(mx + 120, GROUND); ctx.fill();
        }
        ctx.fillStyle = '#475569';
        ctx.fillRect(0, GROUND, W, H - GROUND);
        ctx.fillStyle = '#64748b';
        for (var x = -(off % 40); x < W; x += 40) ctx.fillRect(x, GROUND + 10, 18, 3);
        if (!s) return;
        var ec = K.color('enemy', '#22c55e');
        s.obstacles.forEach(function (o) {
          ctx.fillStyle = o.fly ? '#f43f5e' : ec;
          K.roundRect(ctx, o.x, o.y, o.w, o.h, o.fly ? 10 : 5); ctx.fill();
        });
        ctx.fillStyle = K.color('coins', '#fbbf24');
        s.coins.forEach(function (c) { ctx.beginPath(); ctx.arc(c.x, c.y, 9, 0, Math.PI * 2); ctx.fill(); });
        if (s.hurt <= 0 || Math.floor(K.frame / 5) % 2 === 0) {
          var p = s.p, pc = K.color('player', '#f97316');
          ctx.fillStyle = pc;
          K.roundRect(ctx, p.x, p.y, p.w, p.h, 8); ctx.fill();
          ctx.fillStyle = '#fff'; ctx.fillRect(p.x + p.w - 12, p.y + 8, 6, 6);
          var leg = p.ground ? Math.sin(s.distance / 18) * 6 : 0;
          ctx.fillStyle = pc;
          ctx.fillRect(p.x + 6, p.y + p.h, 7, 6 + leg); ctx.fillRect(p.x + p.w - 13, p.y + p.h, 7, 6 - leg);
        }
        K.drawParticles(ctx);
        K.text(ctx, String(s.score).padStart(5, '0'), W - 16, 26, 22, '#e2e8f0', 'right');
        K.hud((K.num('lives', 1) > 1 ? '♥ ' + s.lives + '   ' : '') + K.t('best', 'Best') + ' ' + K.best());
      }
      start();
      K.flow({ start: start, intro: K.t('intro', 'Space, ↑ or tap to jump · ↓ to duck.\nRun as far as you can!') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, over: s.over, running: !!K.running, frame: K.frame }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(9); K.begin();
          s.timer = 99; s.lives = 1;
          K.press('action'); K.release('action');
          check(s.p.vy < 0, 'jumping lifts the runner');
          K.step(60);
          check(s.p.ground, 'the runner lands again');
          var before = s.score;
          K.step(60);
          check(s.score > before, 'running scores distance');
          s.obstacles = [{ x: s.p.x + 220, y: GROUND - 36, w: 30, h: 36, fly: false }];
          var jumped = false;
          for (var i = 0; i < 120 && !s.over; i++) {
            if (!jumped && s.obstacles.length && s.obstacles[0].x - (s.p.x + s.p.w) < 45) { K.press('action'); K.release('action'); jumped = true; }
            K.step(1);
          }
          check(!s.over, 'jumping clears an obstacle');
          s.obstacles = [{ x: s.p.x + 40, y: GROUND - 36, w: 30, h: 36, fly: false }];
          K.step(30);
          check(s.over, 'hitting an obstacle ends the run');
          return { ok: ok, details: out };
        }
      });
    })();
    """#

    static let dodge = #"""
    /* Dodge — avoid what falls, catch the stars. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 480, H = 640;
      var ctx = K.setup(W, H);
      var s;
      function start() {
        s = { p: { x: W / 2 - 22, y: H - 70, w: 44, h: 44 }, items: [], timer: 0.5, score: 0, time: 0, lives: Math.max(1, K.num('lives', 3)),
              limit: K.num('time', 0), over: false, hurt: 0 };
      }
      K.onPointer = function (type, x) { if (K.running) s.p.x = K.clamp(x - s.p.w / 2, 0, W - s.p.w); };
      function update(dt) {
        if (!K.running || s.over) return;
        var p = s.p;
        if (K.keys.left) p.x -= 380 * dt;
        if (K.keys.right) p.x += 380 * dt;
        p.x = K.clamp(p.x, 0, W - p.w);
        s.time += dt;
        s.hurt -= dt;
        if (s.limit > 0 && s.time >= s.limit) { s.over = true; K.win(s.score, K.t('survived', 'You made it!')); return; }
        var rate = (0.75 - Math.min(0.5, s.time / 90)) / K.speed;
        s.timer -= dt;
        if (s.timer <= 0) {
          s.timer = rate;
          var good = K.random() < 0.28;
          s.items.push({ x: K.rand(10, W - 34), y: -30, r: good ? 13 : K.rand(12, 22), good: good, vy: K.rand(170, 260) * K.speed * (1 + s.time / 60) });
        }
        for (var i = s.items.length - 1; i >= 0; i--) {
          var it = s.items[i];
          it.y += it.vy * dt;
          if (it.y > H + 30) { s.items.splice(i, 1); if (!it.good) s.score += 1; continue; }
          var cx = K.clamp(it.x, p.x, p.x + p.w), cy = K.clamp(it.y, p.y, p.y + p.h);
          if (K.dist(cx, cy, it.x, it.y) < it.r) {
            s.items.splice(i, 1);
            if (it.good) { s.score += 10; K.sfx.coin(); K.burst(it.x, it.y, K.color('coins', '#fbbf24'), 10); }
            else if (s.hurt <= 0) {
              s.lives--; s.hurt = 1.2; K.sfx.hit(); K.burst(it.x, it.y, K.color('enemy', '#ef4444'), 16);
              if (s.lives <= 0) { s.over = true; K.gameOver(s.score); return; }
            }
          }
        }
      }
      function render() {
        ctx.fillStyle = K.color('background', '#111827');
        ctx.fillRect(0, 0, W, H);
        if (!s) return;
        s.items.forEach(function (it) {
          if (it.good) {
            ctx.fillStyle = K.color('coins', '#fbbf24');
            ctx.beginPath();
            for (var k = 0; k < 10; k++) {
              var a = -Math.PI / 2 + k * Math.PI / 5, r = k % 2 ? it.r * 0.45 : it.r;
              ctx.lineTo(it.x + Math.cos(a) * r, it.y + Math.sin(a) * r);
            }
            ctx.fill();
          } else {
            ctx.fillStyle = K.color('enemy', '#ef4444');
            ctx.beginPath(); ctx.arc(it.x, it.y, it.r, 0, Math.PI * 2); ctx.fill();
          }
        });
        if (s.hurt <= 0 || Math.floor(K.frame / 5) % 2 === 0) {
          ctx.fillStyle = K.color('player', '#22d3ee');
          K.roundRect(ctx, s.p.x, s.p.y, s.p.w, s.p.h, 12); ctx.fill();
          ctx.fillStyle = '#0b1020';
          ctx.fillRect(s.p.x + 12, s.p.y + 14, 6, 6); ctx.fillRect(s.p.x + s.p.w - 18, s.p.y + 14, 6, 6);
        }
        K.drawParticles(ctx);
        var hud = K.t('score', 'Score') + ' ' + s.score + '   ♥ ' + s.lives;
        if (s.limit > 0) hud += '   ⏱ ' + Math.max(0, Math.ceil(s.limit - s.time));
        K.hud(hud + '   ' + K.t('best', 'Best') + ' ' + K.best());
      }
      start();
      K.flow({ start: start, intro: K.t('intro', '← → or drag to move.\nAvoid the red, catch the stars!') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, over: s.over, running: !!K.running, frame: K.frame }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(13); K.begin();
          s.timer = 99;
          s.items = [{ x: s.p.x + 22, y: s.p.y - 20, r: 13, good: true, vy: 200 }];
          K.step(12);
          check(s.score >= 10, 'catching a star scores');
          var lives = s.lives;
          s.items = [{ x: s.p.x + 22, y: s.p.y - 20, r: 15, good: false, vy: 200 }];
          K.step(12);
          check(s.lives === lives - 1, 'getting hit costs a life');
          var x = s.p.x;
          K.press('left'); K.step(10); K.release('left');
          check(s.p.x < x, 'the player moves');
          return { ok: ok, details: out };
        }
      });
    })();
    """#

    static let platformer = #"""
    /* Platformer — run, jump, stomp, collect and reach the flag. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 640, H = 360, T = 32;
      var ctx = K.setup(W, H);
      var levels = Math.max(1, K.num('levels', 3));
      var s;
      function makeLevel(n) {
        K.seed(1000 + n * 77);
        var length = 60 + n * 20, ground = [], plats = [], coins = [], enemies = [];
        var x = 0;
        while (x < length) {
          var run = x === 0 ? 12 : K.randInt(5, 12);
          for (var i = 0; i < run && x < length; i++, x++) ground.push(x);
          if (x > length - 8) { while (x < length) { ground.push(x); x++; } break; }
          var gapSize = K.randInt(2, n > 1 ? 3 : 2);
          if (K.random() < 0.55) {
            var py = K.randInt(5, 7);
            var pl = { x: (x - 2) * T, y: H - py * T, w: K.randInt(3, 5) * T, h: 14 };
            plats.push(pl);
            coins.push({ x: pl.x + pl.w / 2, y: pl.y - 26, got: false });
          }
          x += gapSize;
        }
        for (var g = 14; g < length - 6; g += K.randInt(6, 11)) {
          if (ground.indexOf(g) >= 0 && ground.indexOf(g + 1) >= 0 && ground.indexOf(g + 2) >= 0) enemies.push({ x: g * T, y: H - T - 26, w: 26, h: 26, vx: -50 * K.speed, alive: true, min: g * T - 2 * T, max: g * T + 2 * T });
          if (K.random() < 0.6) coins.push({ x: g * T + 16, y: H - T - 70, got: false });
        }
        K.seed((Date.now() ^ n) >>> 0);
        return { ground: ground, plats: plats, coins: coins, enemies: enemies, flag: (length - 3) * T, length: length };
      }
      function spawnPlayer() { s.p = { x: 2 * T, y: H - T - 30, w: 22, h: 30, vx: 0, vy: 0, ground: false, coyote: 0, buffer: 0, face: 1 }; s.cam = 0; }
      function start() {
        s = { level: 1, score: 0, lives: Math.max(1, K.num('lives', 3)), over: false, hurt: 0 };
        s.map = makeLevel(1);
        spawnPlayer();
      }
      function solidAt(px, py) {
        var tx = Math.floor(px / T);
        if (py >= H - T && py < H && s.map.ground.indexOf(tx) >= 0) return true;
        return false;
      }
      K.onPress = function (name) { if (name === 'action' || name === 'up') s.p.buffer = 0.12; };
      function lose() {
        K.sfx.die();
        s.lives--;
        if (s.lives <= 0) { s.over = true; K.gameOver(s.score, K.t('level', 'Level') + ' ' + s.level); return; }
        s.hurt = 1;
        spawnPlayer();
      }
      function update(dt) {
        if (!K.running || s.over) return;
        var p = s.p;
        var dir = (K.keys.right ? 1 : 0) - (K.keys.left ? 1 : 0);
        if (K.pointer.down) dir = K.pointer.x > W / 2 ? 1 : -1;
        var max = 220 * K.speed;
        p.vx += dir * 1400 * dt;
        if (!dir) p.vx *= p.ground ? 0.78 : 0.95;
        p.vx = K.clamp(p.vx, -max, max);
        if (dir) p.face = dir;
        p.buffer -= dt; p.coyote -= dt; s.hurt -= dt;
        if (p.buffer > 0 && (p.ground || p.coyote > 0)) { p.vy = -560; p.ground = false; p.coyote = 0; p.buffer = 0; K.sfx.jump(); }
        if (!K.keys.action && !K.keys.up && p.vy < -200) p.vy += 1200 * dt;
        p.vy = Math.min(p.vy + 1600 * dt, 900);
        p.x = Math.max(0, p.x + p.vx * dt);
        var wasGround = p.ground;
        p.ground = false;
        var ny = p.y + p.vy * dt;
        if (p.vy >= 0) {
          var feet = ny + p.h;
          if (solidAt(p.x + 3, feet) || solidAt(p.x + p.w - 3, feet)) { ny = H - T - p.h; p.vy = 0; p.ground = true; }
          s.map.plats.forEach(function (pl) {
            if (p.x + p.w > pl.x && p.x < pl.x + pl.w && p.y + p.h <= pl.y + 2 && feet >= pl.y) { ny = pl.y - p.h; p.vy = 0; p.ground = true; }
          });
        }
        p.y = ny;
        if (wasGround && !p.ground) p.coyote = 0.1;
        if (p.y > H + 60) { lose(); return; }
        s.map.coins.forEach(function (c) {
          if (!c.got && Math.abs(c.x - (p.x + p.w / 2)) < 18 && Math.abs(c.y - (p.y + p.h / 2)) < 22) { c.got = true; s.score += 10; K.sfx.coin(); }
        });
        for (var i = 0; i < s.map.enemies.length; i++) {
          var e = s.map.enemies[i];
          if (!e.alive) continue;
          e.x += e.vx * dt;
          if (e.x < e.min || e.x > e.max) e.vx = -e.vx;
          if (K.overlap(p, e)) {
            if (p.vy > 50 && p.y + p.h - e.y < 16) { e.alive = false; p.vy = -380; s.score += 50; K.sfx.hit(); K.burst(e.x + 13, e.y + 13, K.color('enemy', '#ef4444'), 12); }
            else if (s.hurt <= 0) { lose(); return; }
          }
        }
        if (p.x > s.map.flag) {
          s.score += 100 * s.level;
          if (s.level >= levels) { s.over = true; K.win(s.score); return; }
          s.level++;
          s.map = makeLevel(s.level);
          spawnPlayer();
          K.sfx.win();
        }
        s.cam = K.clamp(p.x - W * 0.35, 0, s.map.length * T - W);
      }
      function render() {
        var sky = ctx.createLinearGradient(0, 0, 0, H);
        sky.addColorStop(0, K.color('background', '#7dd3fc'));
        sky.addColorStop(1, '#e0f2fe');
        ctx.fillStyle = sky;
        ctx.fillRect(0, 0, W, H);
        if (!s) return;
        ctx.save();
        ctx.translate(-Math.round(s.cam), 0);
        ctx.fillStyle = 'rgba(255,255,255,.75)';
        for (var c = 0; c < s.map.length; c += 9) { ctx.beginPath(); ctx.arc(c * T + 40, 70 + (c % 3) * 20, 22, 0, Math.PI * 2); ctx.arc(c * T + 68, 70 + (c % 3) * 20, 16, 0, Math.PI * 2); ctx.fill(); }
        var gc = K.color('walls', '#65a30d');
        s.map.ground.forEach(function (tx) {
          ctx.fillStyle = '#92400e'; ctx.fillRect(tx * T, H - T, T, T);
          ctx.fillStyle = gc; ctx.fillRect(tx * T, H - T, T, 8);
        });
        s.map.plats.forEach(function (pl) { ctx.fillStyle = '#a16207'; K.roundRect(ctx, pl.x, pl.y, pl.w, pl.h, 5); ctx.fill(); ctx.fillStyle = gc; ctx.fillRect(pl.x, pl.y, pl.w, 5); });
        ctx.fillStyle = K.color('coins', '#fbbf24');
        s.map.coins.forEach(function (cn) { if (!cn.got) { ctx.beginPath(); ctx.ellipse(cn.x, cn.y, 7, 9, 0, 0, Math.PI * 2); ctx.fill(); } });
        s.map.enemies.forEach(function (e) {
          if (!e.alive) return;
          ctx.fillStyle = K.color('enemy', '#ef4444');
          K.roundRect(ctx, e.x, e.y, e.w, e.h, 9); ctx.fill();
          ctx.fillStyle = '#fff'; ctx.fillRect(e.x + 5, e.y + 7, 5, 5); ctx.fillRect(e.x + 16, e.y + 7, 5, 5);
        });
        ctx.fillStyle = '#e2e8f0'; ctx.fillRect(s.map.flag, H - T - 120, 4, 120);
        ctx.fillStyle = K.color('accent', '#22c55e');
        ctx.beginPath(); ctx.moveTo(s.map.flag + 4, H - T - 120); ctx.lineTo(s.map.flag + 44, H - T - 105); ctx.lineTo(s.map.flag + 4, H - T - 90); ctx.fill();
        var p = s.p;
        if (s.hurt <= 0 || Math.floor(K.frame / 5) % 2 === 0) {
          ctx.fillStyle = K.color('player', '#3b82f6');
          K.roundRect(ctx, p.x, p.y, p.w, p.h, 6); ctx.fill();
          ctx.fillStyle = '#fff'; ctx.fillRect(p.x + (p.face > 0 ? 13 : 4), p.y + 7, 5, 5);
        }
        K.drawParticles(ctx);
        ctx.restore();
        K.hud(K.t('score', 'Score') + ' ' + s.score + '   ♥ ' + s.lives + '   ' + K.t('level', 'Level') + ' ' + s.level + '/' + levels);
      }
      start();
      K.flow({ start: start, intro: K.t('intro', '← → to run · Space / ↑ to jump (hold for higher).\nStomp enemies, grab coins, reach the flag!') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, level: s.level, over: s.over, running: !!K.running, frame: K.frame }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.begin();
          s.map.enemies = [];
          K.step(30);
          check(s.p.ground, 'the player stands on the ground');
          K.press('action'); K.step(2); K.release('action');
          check(s.p.vy < 0, 'jumping lifts the player');
          K.step(60);
          s.map.coins.push({ x: s.p.x + 11, y: s.p.y + 15, got: false });
          K.step(2);
          check(s.score >= 10, 'touching a coin collects it');
          var lives = s.lives;
          s.hurt = 0;
          s.map.enemies = [{ x: s.p.x, y: s.p.y, w: 26, h: 26, vx: 0, alive: true, min: 0, max: 99999 }];
          s.p.vy = 0;
          K.step(2);
          check(s.lives === lives - 1, 'running into an enemy costs a life');
          s.map.enemies = [];
          s.p.x = s.map.flag + 4; s.p.y = H - T - 30;
          K.step(2);
          check(s.level === 2 || s.over, 'reaching the flag finishes the level');
          return { ok: ok, details: out };
        }
      });
    })();
    """#
}
