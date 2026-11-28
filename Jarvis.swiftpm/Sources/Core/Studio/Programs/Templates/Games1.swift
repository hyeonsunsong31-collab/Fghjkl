import Foundation

/// Game templates: snake, brick breaker, paddle duel, hopper.
enum GamesOne {
    static let snake = #"""
    /* Snake — eat, grow, don't bite yourself. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var N = K.clamp(Math.round(K.num('grid', 20)), 8, 40);
      var SIZE = 480, cell = SIZE / N;
      var ctx = K.setup(SIZE, SIZE);
      var wrap = !!C.wrap;
      var dirs = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
      var s;

      function occupied(x, y) {
        for (var i = 0; i < s.body.length; i++) if (s.body[i].x === x && s.body[i].y === y) return true;
        for (var j = 0; j < s.rocks.length; j++) if (s.rocks[j].x === x && s.rocks[j].y === y) return true;
        return false;
      }
      function placeFood() {
        for (var t = 0; t < 2000; t++) {
          var x = K.randInt(0, N - 1), y = K.randInt(0, N - 1);
          if (!occupied(x, y)) { s.food = { x: x, y: y, gold: K.feature('powerups') && K.random() < 0.15 }; return; }
        }
        s.food = null;
      }
      function spawn() {
        var c = Math.floor(N / 2);
        s.body = [{ x: c, y: c }, { x: c - 1, y: c }, { x: c - 2, y: c }];
        s.dir = 'right'; s.queue = []; s.acc = 0;
      }
      function start() {
        s = { score: 0, lives: Math.max(1, K.num('lives', 1)), level: 1, eaten: 0, time: K.num('time', 0), over: false, rocks: [] };
        spawn();
        if (K.feature('enemies')) {
          var c = Math.floor(N / 2);
          for (var i = 0; i < Math.floor(N / 2); i++) {
            var r = { x: K.randInt(0, N - 1), y: K.randInt(0, N - 1) };
            if (Math.abs(r.y - c) > 1) s.rocks.push(r);
          }
        }
        placeFood();
      }
      function interval() {
        var faster = K.feature('levels', true) ? Math.pow(0.93, s.level - 1) : 1;
        return Math.max(0.035, faster / (8 * K.speed));
      }
      K.onPress = function (name) {
        if (!K.running || !dirs[name]) return;
        var last = s.queue.length ? s.queue[s.queue.length - 1] : s.dir;
        var a = dirs[last], b = dirs[name];
        if (a[0] + b[0] === 0 && a[1] + b[1] === 0) return;
        if (name !== last && s.queue.length < 3) s.queue.push(name);
      };
      function die() {
        var h = s.body[0];
        K.sfx.die();
        K.burst(h.x * cell + cell / 2, h.y * cell + cell / 2, K.color('snake', '#22c55e'), 24);
        s.lives--;
        if (s.lives > 0) { spawn(); return; }
        s.over = true;
        K.gameOver(s.score);
      }
      function move() {
        if (s.queue.length) s.dir = s.queue.shift();
        var d = dirs[s.dir], head = s.body[0];
        var nx = head.x + d[0], ny = head.y + d[1];
        if (wrap) { nx = (nx + N) % N; ny = (ny + N) % N; }
        if (nx < 0 || ny < 0 || nx >= N || ny >= N) { die(); return; }
        var eat = s.food && nx === s.food.x && ny === s.food.y;
        for (var i = 0; i < s.body.length - (eat ? 0 : 1); i++) if (s.body[i].x === nx && s.body[i].y === ny) { die(); return; }
        for (var j = 0; j < s.rocks.length; j++) if (s.rocks[j].x === nx && s.rocks[j].y === ny) { die(); return; }
        s.body.unshift({ x: nx, y: ny });
        if (eat) {
          s.score += s.food.gold ? 5 : 1;
          s.eaten++;
          K.sfx.coin();
          K.burst(nx * cell + cell / 2, ny * cell + cell / 2, K.color('food', '#ef4444'), 10);
          if (s.eaten % 5 === 0) s.level++;
          placeFood();
        } else {
          s.body.pop();
        }
      }
      function update(dt) {
        if (!K.running || s.over) return;
        if (s.time > 0) {
          s.time -= dt;
          if (s.time <= 0) { s.time = 0; s.over = true; K.gameOver(s.score, K.t('timeUp', "Time's up")); return; }
        }
        s.acc += dt;
        var step = interval();
        while (s.acc >= step && K.running && !s.over) { s.acc -= step; move(); }
      }
      function render() {
        ctx.fillStyle = K.color('background', '#0d1424');
        ctx.fillRect(0, 0, SIZE, SIZE);
        ctx.fillStyle = 'rgba(255,255,255,0.035)';
        for (var gx = 0; gx < N; gx++) for (var gy = gx % 2; gy < N; gy += 2) ctx.fillRect(gx * cell, gy * cell, cell, cell);
        if (!s) return;
        ctx.fillStyle = K.color('walls', '#64748b');
        s.rocks.forEach(function (r) { K.roundRect(ctx, r.x * cell + 2, r.y * cell + 2, cell - 4, cell - 4, 4); ctx.fill(); });
        if (s.food) {
          var fc = s.food.gold ? K.color('coins', '#fbbf24') : K.color('food', '#ef4444');
          K.glow(ctx, fc);
          ctx.fillStyle = fc;
          ctx.beginPath(); ctx.arc(s.food.x * cell + cell / 2, s.food.y * cell + cell / 2, cell * 0.36, 0, Math.PI * 2); ctx.fill();
          K.noGlow(ctx);
        }
        var sc = K.color('snake', '#22c55e');
        K.glow(ctx, sc, 8);
        for (var i = s.body.length - 1; i >= 0; i--) {
          var b = s.body[i];
          ctx.fillStyle = sc;
          ctx.globalAlpha = i === 0 ? 1 : 0.7 + 0.3 * (1 - i / s.body.length);
          K.roundRect(ctx, b.x * cell + 1, b.y * cell + 1, cell - 2, cell - 2, cell * 0.3); ctx.fill();
        }
        ctx.globalAlpha = 1;
        K.noGlow(ctx);
        var h = s.body[0], d = dirs[s.dir];
        var ex = h.x * cell + cell / 2 + d[0] * cell * 0.18, ey = h.y * cell + cell / 2 + d[1] * cell * 0.18;
        ctx.fillStyle = '#0b1020';
        ctx.beginPath();
        ctx.arc(ex - d[1] * cell * 0.18, ey - d[0] * cell * 0.18, cell * 0.08, 0, Math.PI * 2);
        ctx.arc(ex + d[1] * cell * 0.18, ey + d[0] * cell * 0.18, cell * 0.08, 0, Math.PI * 2);
        ctx.fill();
        K.drawParticles(ctx);
        var hud = K.t('score', 'Score') + ' ' + s.score;
        if (K.num('lives', 1) > 1) hud += '   ♥ ' + s.lives;
        if (K.feature('levels', true)) hud += '   ' + K.t('level', 'Level') + ' ' + s.level;
        if (K.num('time', 0) > 0) hud += '   ⏱ ' + Math.ceil(s.time);
        if (K.feature('highscore', true)) hud += '   ' + K.t('best', 'Best') + ' ' + K.best();
        K.hud(hud);
      }
      start();
      K.flow({ start: start, intro: K.t('intro', 'Arrow keys or swipe to steer.\nEat to grow — avoid the walls and your tail.') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, level: s.level, length: s.body.length, over: s.over, running: !!K.running, frame: K.frame }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(42); K.begin();
          var c = Math.floor(N / 2);
          s.rocks = []; s.food = { x: c + 3, y: c, gold: false };
          K.step(Math.ceil(interval() * 60 * 3.6));
          check(s.score === 1, 'eating food scores a point');
          check(s.body.length === 4, 'the snake grows when it eats');
          K.onPress('left');
          check(s.queue.length === 0, 'the snake cannot reverse into itself');
          s.lives = 1; s.queue = []; s.dir = 'up'; s.food = null;
          K.step(Math.ceil(interval() * 60 * (N + 3)));
          if (wrap) check(!s.over, 'the snake wraps around the edges');
          else check(s.over, 'hitting the wall ends the game');
          return { ok: ok, details: out };
        }
      });
    })();
    """#

    static let breakout = #"""
    /* Brick breaker — keep the ball up, clear every brick. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 480, H = 640, TOP = 48;
      var ctx = K.setup(W, H);
      var maxLevels = K.num('levels', 0);
      var s;
      var palette = ['#ef4444', '#f97316', '#facc15', '#22c55e', '#22d3ee', '#3b82f6', '#a855f7', '#ec4899', '#f43f5e'];

      function buildBricks(level) {
        var rows = Math.min(4 + level, 9), cols = 8, bw = (W - 32) / cols, bh = 20;
        var list = [];
        for (var r = 0; r < rows; r++) for (var c = 0; c < cols; c++) {
          list.push({ x: 16 + c * bw + 2, y: TOP + 30 + r * (bh + 6), w: bw - 4, h: bh, hp: level > 2 && r < 2 ? 2 : 1,
                      color: C.colors.bricks || palette[r % palette.length] });
        }
        return list;
      }
      function resetBall() { s.ball = { x: s.paddle.x + s.paddle.w / 2, y: s.paddle.y - 9, r: 8, vx: 0, vy: 0, stuck: true }; }
      function start() {
        s = { score: 0, lives: Math.max(1, K.num('lives', 3)), level: 1, paddle: { x: W / 2 - 45, y: H - 46, w: 90, h: 14 }, drops: [], wide: 0, over: false };
        s.bricks = buildBricks(1);
        resetBall();
      }
      function launch() {
        if (!s.ball.stuck) return;
        var speed = 360 * K.speed * (1 + 0.08 * (s.level - 1));
        var a = -Math.PI / 2 + K.rand(-0.35, 0.35);
        s.ball.vx = Math.cos(a) * speed; s.ball.vy = Math.sin(a) * speed; s.ball.stuck = false;
      }
      K.onPress = function (name) { if (K.running && (name === 'action' || name === 'up')) launch(); };
      K.onPointer = function (type, x) {
        if (!K.running) return;
        s.paddle.x = K.clamp(x - s.paddle.w / 2, 0, W - s.paddle.w);
        if (type === 'up' && !K.swiped) launch();
      };
      function loseLife() {
        s.lives--;
        K.sfx.die();
        if (s.lives <= 0) { s.over = true; K.gameOver(s.score); return; }
        resetBall();
      }
      function update(dt) {
        if (!K.running || s.over) return;
        var p = s.paddle, b = s.ball;
        if (K.keys.left) p.x -= 470 * dt;
        if (K.keys.right) p.x += 470 * dt;
        var target = s.wide > 0 ? 140 : 90;
        if (p.w !== target) { p.x += (p.w - target) / 2; p.w = target; }
        if (s.wide > 0) s.wide -= dt;
        p.x = K.clamp(p.x, 0, W - p.w);
        if (b.stuck) { b.x = p.x + p.w / 2; b.y = p.y - b.r - 1; return; }
        var steps = Math.max(1, Math.ceil(Math.max(Math.abs(b.vx), Math.abs(b.vy)) * dt / 5));
        for (var i = 0; i < steps; i++) {
          b.x += b.vx * dt / steps; b.y += b.vy * dt / steps;
          if (b.x < b.r) { b.x = b.r; b.vx = Math.abs(b.vx); K.sfx.bounce(); }
          if (b.x > W - b.r) { b.x = W - b.r; b.vx = -Math.abs(b.vx); K.sfx.bounce(); }
          if (b.y < TOP + b.r) { b.y = TOP + b.r; b.vy = Math.abs(b.vy); K.sfx.bounce(); }
          if (b.vy > 0 && b.y + b.r >= p.y && b.y + b.r <= p.y + p.h + 12 && b.x >= p.x - b.r && b.x <= p.x + p.w + b.r) {
            var hit = K.clamp((b.x - (p.x + p.w / 2)) / (p.w / 2), -1, 1);
            var speed = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
            var angle = -Math.PI / 2 + hit * 1.05;
            b.vx = Math.cos(angle) * speed; b.vy = Math.sin(angle) * speed; b.y = p.y - b.r - 1;
            K.sfx.bounce();
          }
          for (var j = 0; j < s.bricks.length; j++) {
            var k = s.bricks[j];
            if (b.x + b.r > k.x && b.x - b.r < k.x + k.w && b.y + b.r > k.y && b.y - b.r < k.y + k.h) {
              var ox = Math.min(b.x + b.r - k.x, k.x + k.w - (b.x - b.r));
              var oy = Math.min(b.y + b.r - k.y, k.y + k.h - (b.y - b.r));
              if (ox < oy) b.vx = -b.vx; else b.vy = -b.vy;
              k.hp--;
              if (k.hp <= 0) {
                s.bricks.splice(j, 1);
                s.score += 10 * s.level;
                K.sfx.hit();
                K.burst(k.x + k.w / 2, k.y + k.h / 2, k.color, 10);
                if (K.feature('powerups') && K.random() < 0.18) s.drops.push({ x: k.x + k.w / 2, y: k.y, kind: K.random() < 0.7 ? 'wide' : 'life' });
              } else {
                K.sfx.bounce();
              }
              break;
            }
          }
          if (b.y > H + 20) { loseLife(); return; }
        }
        for (var d = s.drops.length - 1; d >= 0; d--) {
          var dr = s.drops[d];
          dr.y += 150 * dt;
          if (dr.y > p.y - 6 && dr.y < p.y + p.h + 10 && dr.x > p.x && dr.x < p.x + p.w) {
            if (dr.kind === 'wide') s.wide = 12; else s.lives++;
            K.sfx.power();
            s.drops.splice(d, 1);
          } else if (dr.y > H) s.drops.splice(d, 1);
        }
        if (s.bricks.length === 0) {
          if (maxLevels > 0 && s.level >= maxLevels) { s.over = true; K.win(s.score); return; }
          s.level++;
          s.bricks = buildBricks(s.level);
          resetBall();
          K.sfx.win();
        }
      }
      function render() {
        var g = ctx.createLinearGradient(0, 0, 0, H);
        g.addColorStop(0, K.color('background', '#0f172a'));
        g.addColorStop(1, '#020617');
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, W, H);
        if (!s) return;
        ctx.fillStyle = 'rgba(255,255,255,0.06)';
        ctx.fillRect(0, TOP - 2, W, 2);
        s.bricks.forEach(function (k) {
          ctx.fillStyle = k.color;
          ctx.globalAlpha = k.hp > 1 ? 1 : 0.88;
          K.roundRect(ctx, k.x, k.y, k.w, k.h, 5); ctx.fill();
          if (k.hp > 1) { ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.stroke(); }
        });
        ctx.globalAlpha = 1;
        s.drops.forEach(function (dr) { K.text(ctx, dr.kind === 'wide' ? '⟷' : '♥', dr.x, dr.y, 18, dr.kind === 'wide' ? '#22d3ee' : '#f43f5e'); });
        var pc = K.color('paddle', '#e2e8f0');
        K.glow(ctx, pc);
        ctx.fillStyle = pc;
        K.roundRect(ctx, s.paddle.x, s.paddle.y, s.paddle.w, s.paddle.h, 7); ctx.fill();
        var bc = K.color('ball', '#fbbf24');
        ctx.fillStyle = bc;
        ctx.beginPath(); ctx.arc(s.ball.x, s.ball.y, s.ball.r, 0, Math.PI * 2); ctx.fill();
        K.noGlow(ctx);
        K.drawParticles(ctx);
        K.text(ctx, K.t('score', 'Score') + ' ' + s.score, 14, 24, 18, '#e2e8f0', 'left');
        K.text(ctx, '♥'.repeat(Math.min(s.lives, 8)), W - 14, 24, 18, '#f43f5e', 'right');
        if (s.ball.stuck && K.running) K.text(ctx, K.t('launch', 'Tap or press Space to launch'), W / 2, H / 2 + 80, 16, 'rgba(255,255,255,.7)');
        K.hud(K.t('level', 'Level') + ' ' + s.level + (K.feature('highscore', true) ? '   ' + K.t('best', 'Best') + ' ' + K.best() : ''));
      }
      start();
      K.flow({ start: start, intro: K.t('intro', 'Move with ← → or drag. Space or tap launches the ball.\nBreak every brick!') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, level: s.level, bricks: s.bricks.length, over: s.over, running: !!K.running, frame: K.frame }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(7); K.begin();
          var count = s.bricks.length, target = s.bricks[s.bricks.length - 1];
          s.ball = { x: target.x + target.w / 2, y: target.y + target.h + 30, r: 8, vx: 0, vy: -320, stuck: false };
          K.step(20);
          check(s.bricks.length === count - 1 && s.score > 0, 'the ball breaks a brick and scores');
          s.ball = { x: s.paddle.x + s.paddle.w / 2, y: s.paddle.y - 60, r: 8, vx: 0, vy: 320, stuck: false };
          K.step(18);
          check(s.ball.vy < 0, 'the paddle bounces the ball back up');
          var lives = s.lives;
          s.paddle.x = W - s.paddle.w;
          s.ball = { x: 12, y: H - 30, r: 8, vx: 0, vy: 420, stuck: false };
          K.step(20);
          check(s.lives === lives - 1 || s.over, 'missing the ball costs a life');
          K.press('right'); K.step(10); K.release('right');
          check(s.paddle.x <= W - s.paddle.w, 'the paddle stays on screen');
          return { ok: ok, details: out };
        }
      });
    })();
    """#

    static let pong = #"""
    /* Paddle duel — first to the target score wins. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 640, H = 400;
      var ctx = K.setup(W, H);
      var two = K.feature('twoplayer');
      var target = Math.max(1, K.num('target', 7));
      var raw = {};
      var s;
      window.addEventListener('keydown', function (e) { raw[e.key] = true; });
      window.addEventListener('keyup', function (e) { raw[e.key] = false; });
      var touches = {};
      document.getElementById('game').addEventListener('pointermove', function (e) {
        if (!K.running) return;
        var r = K.canvas.getBoundingClientRect();
        var x = (e.clientX - r.left) / r.width * W, y = (e.clientY - r.top) / r.height * H;
        touches[e.pointerId] = { x: x, y: y };
      });
      function serve(dir) {
        var speed = 330 * K.speed;
        var a = K.rand(-0.5, 0.5);
        s.ball = { x: W / 2, y: H / 2, r: 8, vx: Math.cos(a) * speed * dir, vy: Math.sin(a) * speed, wait: 0.8 };
      }
      function start() {
        s = { left: { x: 22, y: H / 2 - 40, w: 12, h: 80, score: 0 }, right: { x: W - 34, y: H / 2 - 40, w: 12, h: 80, score: 0 }, over: false };
        serve(K.random() < 0.5 ? 1 : -1);
      }
      function movePaddle(p, dir, dt) { p.y = K.clamp(p.y + dir * 420 * dt, 0, H - p.h); }
      function ai(p, dt) {
        var b = s.ball;
        var maxSpeed = [210, 290, 400][K.num('difficulty', 1)] * K.speed;
        var aim = b.vx > 0 ? b.y + (Math.sin(K.frame / 40) * 18) : H / 2;
        var center = p.y + p.h / 2;
        var diff = aim - center;
        p.y = K.clamp(p.y + K.clamp(diff, -maxSpeed * dt, maxSpeed * dt), 0, H - p.h);
      }
      function point(winner) {
        winner.score++;
        K.sfx.coin();
        if (winner.score >= target) {
          s.over = true;
          var you = s.left.score + ' : ' + s.right.score;
          if (two) K.win(null, (winner === s.left ? K.t('leftWins', 'Left player wins') : K.t('rightWins', 'Right player wins')) + '\n' + you);
          else if (winner === s.left) K.win(s.left.score, you);
          else K.gameOver(s.left.score, you);
          return;
        }
        serve(winner === s.left ? 1 : -1);
      }
      function update(dt) {
        if (!K.running || s.over) return;
        var l = s.left, r = s.right, b = s.ball;
        var up1 = two ? (raw.w || raw.W) : K.keys.up, down1 = two ? (raw.s || raw.S) : K.keys.down;
        if (up1) movePaddle(l, -1, dt);
        if (down1) movePaddle(l, 1, dt);
        for (var id in touches) {
          var t = touches[id];
          if (t.x < W / 2) l.y = K.clamp(t.y - l.h / 2, 0, H - l.h);
          else if (two) r.y = K.clamp(t.y - r.h / 2, 0, H - r.h);
        }
        if (two) {
          if (raw.ArrowUp) movePaddle(r, -1, dt);
          if (raw.ArrowDown) movePaddle(r, 1, dt);
        } else {
          ai(r, dt);
        }
        if (b.wait > 0) { b.wait -= dt; return; }
        var steps = Math.max(1, Math.ceil(Math.abs(b.vx) * dt / 6));
        for (var i = 0; i < steps; i++) {
          b.x += b.vx * dt / steps; b.y += b.vy * dt / steps;
          if (b.y < b.r) { b.y = b.r; b.vy = Math.abs(b.vy); K.sfx.bounce(); }
          if (b.y > H - b.r) { b.y = H - b.r; b.vy = -Math.abs(b.vy); K.sfx.bounce(); }
          var paddles = [l, r];
          for (var k = 0; k < 2; k++) {
            var p = paddles[k];
            var movingTo = k === 0 ? b.vx < 0 : b.vx > 0;
            if (movingTo && b.x + b.r > p.x && b.x - b.r < p.x + p.w && b.y + b.r > p.y && b.y - b.r < p.y + p.h) {
              var hit = (b.y - (p.y + p.h / 2)) / (p.h / 2);
              var speed = Math.min(900, Math.sqrt(b.vx * b.vx + b.vy * b.vy) * 1.06);
              var angle = hit * 0.9;
              b.vx = Math.cos(angle) * speed * (k === 0 ? 1 : -1);
              b.vy = Math.sin(angle) * speed;
              b.x = k === 0 ? p.x + p.w + b.r : p.x - b.r;
              K.sfx.hit();
              K.burst(b.x, b.y, K.color('ball', '#fbbf24'), 6, 80);
            }
          }
          if (b.x < -20) { point(r); return; }
          if (b.x > W + 20) { point(l); return; }
        }
      }
      function render() {
        ctx.fillStyle = K.color('background', '#0b1224');
        ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = 'rgba(255,255,255,0.15)';
        for (var y = 10; y < H; y += 26) ctx.fillRect(W / 2 - 2, y, 4, 14);
        if (!s) return;
        K.text(ctx, String(s.left.score), W / 2 - 60, 46, 42, 'rgba(255,255,255,.85)');
        K.text(ctx, String(s.right.score), W / 2 + 60, 46, 42, 'rgba(255,255,255,.85)');
        var pc = K.color('paddle', '#e2e8f0');
        K.glow(ctx, pc);
        ctx.fillStyle = K.color('player', pc);
        K.roundRect(ctx, s.left.x, s.left.y, s.left.w, s.left.h, 6); ctx.fill();
        ctx.fillStyle = K.color('enemy', pc);
        K.roundRect(ctx, s.right.x, s.right.y, s.right.w, s.right.h, 6); ctx.fill();
        ctx.fillStyle = K.color('ball', '#fbbf24');
        ctx.beginPath(); ctx.arc(s.ball.x, s.ball.y, s.ball.r, 0, Math.PI * 2); ctx.fill();
        K.noGlow(ctx);
        K.drawParticles(ctx);
        K.hud((two ? K.t('twoPlayers', '2 players') : K.t('vsComputer', 'You vs computer')) + '   ' + K.t('firstTo', 'First to') + ' ' + target);
      }
      start();
      var intro = two ? K.t('intro2', 'Left: W / S · Right: ↑ / ↓ (or drag on each half).') : K.t('intro', 'Move with ↑ / ↓ or drag. Beat the computer!');
      K.flow({ start: start, intro: intro + '\n' + K.t('firstTo', 'First to') + ' ' + target });
      K.loop(update, render);
      K.expose({
        state: function () { return { left: s.left.score, right: s.right.score, over: s.over, running: !!K.running, frame: K.frame, score: s.left.score }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(3); K.begin();
          s.left.y = 0;
          s.ball = { x: 120, y: H - 40, r: 8, vx: -400, vy: 0, wait: 0 };
          K.step(40);
          check(s.right.score === 1, 'a missed ball scores for the other side');
          s.left.y = H / 2 - 40;
          s.ball = { x: 120, y: H / 2, r: 8, vx: -400, vy: 0, wait: 0 };
          K.step(20);
          check(s.ball.vx > 0, 'the paddle returns the ball');
          s.ball = { x: W / 2, y: 20, r: 8, vx: 0, vy: -300, wait: 0 };
          K.step(10);
          check(s.ball.vy > 0, 'the ball bounces off the walls');
          return { ok: ok, details: out };
        }
      });
    })();
    """#

    static let hopper = #"""
    /* Hopper — tap to flap through the gaps. Made by Jarvis. */
    (function () {
      'use strict';
      var K = Kit, C = K.config;
      var W = 480, H = 640, GROUND = H - 70;
      var ctx = K.setup(W, H);
      var gap = [200, 165, 138][K.num('difficulty', 1)];
      var s;
      function start() {
        s = { bird: { x: 130, y: H / 2 - 40, vy: -380, r: 15 }, pipes: [], timer: 0.6, score: 0, lives: Math.max(1, K.num('lives', 1)), over: false, scroll: 0, coins: [] };
      }
      function flap() { if (K.running && !s.over) { s.bird.vy = -410; K.sfx.jump(); } }
      K.onPress = function (name) { if (name === 'action' || name === 'up') flap(); };
      K.onPointer = function (type) { if (type === 'down') flap(); };
      function hit() {
        K.sfx.die();
        K.burst(s.bird.x, s.bird.y, K.color('player', '#facc15'), 20);
        s.lives--;
        if (s.lives > 0) { s.bird.y = H / 2 - 40; s.bird.vy = -380; s.pipes = []; s.timer = 0.8; return; }
        s.over = true;
        K.gameOver(s.score);
      }
      function update(dt) {
        if (!K.running || s.over) return;
        var speed = 165 * K.speed * (1 + Math.min(0.6, s.score * 0.015));
        var b = s.bird;
        b.vy = Math.min(b.vy + 1350 * dt, 720);
        b.y += b.vy * dt;
        s.scroll = (s.scroll + speed * dt) % 48;
        s.timer -= dt;
        if (s.timer <= 0) {
          s.timer = 1.55 / K.speed;
          var top = K.rand(70, GROUND - gap - 70);
          s.pipes.push({ x: W + 40, top: top, passed: false });
          if (K.feature('powerups') && K.random() < 0.35) s.coins.push({ x: W + 40 + 26, y: top + gap / 2 });
        }
        for (var i = s.pipes.length - 1; i >= 0; i--) {
          var p = s.pipes[i];
          p.x -= speed * dt;
          if (!p.passed && p.x + 52 < b.x) { p.passed = true; s.score++; K.sfx.coin(); }
          if (p.x < -70) s.pipes.splice(i, 1);
          var inX = b.x + b.r > p.x && b.x - b.r < p.x + 52;
          if (inX && (b.y - b.r < p.top || b.y + b.r > p.top + gap)) { hit(); return; }
        }
        for (var j = s.coins.length - 1; j >= 0; j--) {
          var c = s.coins[j];
          c.x -= speed * dt;
          if (K.dist(c.x, c.y, b.x, b.y) < b.r + 10) { s.score += 3; K.sfx.power(); s.coins.splice(j, 1); }
          else if (c.x < -20) s.coins.splice(j, 1);
        }
        if (b.y + b.r >= GROUND) { b.y = GROUND - b.r; hit(); return; }
        if (b.y - b.r < 0) { b.y = b.r; b.vy = 0; }
      }
      function render() {
        var sky = ctx.createLinearGradient(0, 0, 0, H);
        sky.addColorStop(0, K.color('background', '#38bdf8'));
        sky.addColorStop(1, '#bae6fd');
        ctx.fillStyle = sky;
        ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = 'rgba(255,255,255,.7)';
        for (var k = 0; k < 4; k++) {
          var cx = ((k * 160 - (s ? s.scroll * 0.4 : 0) * 3) % (W + 120) + W + 120) % (W + 120) - 60;
          ctx.beginPath(); ctx.arc(cx, 90 + k * 40, 26, 0, Math.PI * 2); ctx.arc(cx + 30, 90 + k * 40, 20, 0, Math.PI * 2); ctx.fill();
        }
        if (!s) return;
        var pipeColor = K.color('enemy', '#22c55e');
        s.pipes.forEach(function (p) {
          ctx.fillStyle = pipeColor;
          ctx.fillRect(p.x, 0, 52, p.top);
          ctx.fillRect(p.x, p.top + gap, 52, GROUND - p.top - gap);
          ctx.fillStyle = 'rgba(0,0,0,.18)';
          ctx.fillRect(p.x - 4, p.top - 18, 60, 18);
          ctx.fillRect(p.x - 4, p.top + gap, 60, 18);
        });
        s.coins.forEach(function (c) { ctx.fillStyle = K.color('coins', '#fbbf24'); ctx.beginPath(); ctx.arc(c.x, c.y, 9, 0, Math.PI * 2); ctx.fill(); });
        ctx.fillStyle = '#a16207';
        ctx.fillRect(0, GROUND, W, H - GROUND);
        ctx.fillStyle = '#65a30d';
        ctx.fillRect(0, GROUND, W, 14);
        ctx.fillStyle = 'rgba(0,0,0,.12)';
        for (var x = -s.scroll; x < W; x += 48) ctx.fillRect(x, GROUND + 14, 24, H - GROUND);
        var b = s.bird;
        ctx.save();
        ctx.translate(b.x, b.y);
        ctx.rotate(K.clamp(b.vy / 600, -0.5, 1));
        ctx.fillStyle = K.color('player', '#facc15');
        ctx.beginPath(); ctx.ellipse(0, 0, b.r + 3, b.r, 0, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(6, -5, 5, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#111'; ctx.beginPath(); ctx.arc(7, -5, 2.4, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = '#f97316'; ctx.beginPath(); ctx.moveTo(13, 0); ctx.lineTo(24, 3); ctx.lineTo(13, 6); ctx.fill();
        ctx.restore();
        K.drawParticles(ctx);
        K.text(ctx, String(s.score), W / 2, 70, 52, '#fff');
        K.hud((K.num('lives', 1) > 1 ? '♥ ' + s.lives + '   ' : '') + K.t('best', 'Best') + ' ' + K.best());
      }
      start();
      K.flow({ start: start, intro: K.t('intro', 'Tap, click or press Space to flap.\nFly through the gaps!') });
      K.loop(update, render);
      K.expose({
        state: function () { return { score: s.score, lives: s.lives, over: s.over, running: !!K.running, frame: K.frame, y: s.bird.y }; },
        selfTest: function () {
          var out = [], ok = true;
          function check(c, label) { out.push((c ? '✓ ' : '✗ ') + label); if (!c) ok = false; }
          K.seed(11); K.begin();
          s.lives = 1; s.timer = 99;
          var y0 = s.bird.y;
          K.step(5);
          K.press('action'); K.release('action');
          check(s.bird.vy < 0, 'flapping makes the bird rise');
          s.pipes = [{ x: s.bird.x - 30, top: s.bird.y - gap / 2, passed: false }];
          s.bird.vy = -200;
          K.step(30);
          check(s.score >= 1, 'flying past a pipe scores');
          s.timer = 99; s.pipes = [];
          K.step(200);
          check(s.over, 'falling to the ground ends the game');
          return { ok: ok, details: out, y0: y0 };
        }
      });
    })();
    """#
}
