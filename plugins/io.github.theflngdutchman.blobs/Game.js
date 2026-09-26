// Blobs — pure game logic. No QML, no I/O: the overlay owns the clock,
// the canvas and the input, and hands them in here.
//
// All positions are in world units. A cell's radius derives from its mass so
// the only mutable per-cell numbers are x, y, mass and an impulse velocity.

var WORLD = 3200
var FOOD_COUNT = 380
var FOOD_MASS = 1
var FOOD_RADIUS = 5
var VIRUS_COUNT = 9
var VIRUS_MASS = 100
var START_MASS = 12
var MIN_SPLIT_MASS = 36
var MIN_EJECT_MASS = 35
var EJECT_COST = 16
var EJECT_MASS = 13
var MAX_CELLS = 16
var EAT_RATIO = 1.25
var BOT_NAMES = ["Pip", "Wobble", "Gloop", "Nib", "Bubbles", "Squish", "Mote", "Dot",
  "Blip", "Plop", "Ooze", "Puddle", "Dab", "Smudge", "Splat", "Goo", "Fizz", "Dollop",
  "Nubbin", "Glob", "Bloop", "Speck", "Jelly", "Wisp"]

function radius(mass) { return 6 * Math.sqrt(Math.max(mass, 0.01)) }
function speed(mass) { return 300 * Math.pow(Math.max(mass, 1), -0.25) }
function rand(min, max) { return min + Math.random() * (max - min) }
function clamp(v, a, b) { return v < a ? a : (v > b ? b : v) }
function dist(ax, ay, bx, by) { var dx = ax - bx, dy = ay - by; return Math.sqrt(dx * dx + dy * dy) }

// ------------------------------------------------------------------ setup

function create(opts) {
  var g = {
    time: 0,
    botCount: clamp(Math.round(opts.bots || 10), 2, 24),
    colors: opts.colors || ["#888888"],
    playerColor: opts.playerColor || "#ffffff",
    food: [],
    viruses: [],
    ejected: [],
    entities: [],
    player: null,
    score: 0,
    over: false,
    killedBy: "",
    nextBotId: 1
  }
  for (var i = 0; i < FOOD_COUNT; i++) g.food.push(newFood())
  for (var v = 0; v < VIRUS_COUNT; v++) g.viruses.push(newVirus(g))
  g.player = {
    id: 0, name: "You", color: g.playerColor, isPlayer: true,
    cells: [], target: null, respawnAt: -1, decideAt: 0
  }
  var cx = rand(WORLD * 0.3, WORLD * 0.7), cy = rand(WORLD * 0.3, WORLD * 0.7)
  g.player.cells.push(newCell(g, g.player, cx, cy, START_MASS))
  g.player.target = { x: cx, y: cy }
  g.entities.push(g.player)
  for (var b = 0; b < g.botCount; b++) g.entities.push(newBot(g, true))
  return g
}

function newFood() {
  return { x: rand(10, WORLD - 10), y: rand(10, WORLD - 10), hue: Math.floor(Math.random() * 1000) }
}

function newVirus(g) {
  var p = safeSpawn(g, 250)
  return { x: p.x, y: p.y, mass: VIRUS_MASS }
}

function newCell(g, owner, x, y, mass) {
  return { owner: owner, x: x, y: y, mass: mass, vx: 0, vy: 0, mergeAt: g.time }
}

function newBot(g, initial) {
  var bot = {
    id: g.nextBotId++, isPlayer: false,
    name: BOT_NAMES[Math.floor(Math.random() * BOT_NAMES.length)],
    color: g.colors[Math.floor(Math.random() * g.colors.length)],
    cells: [], target: null, respawnAt: -1, decideAt: g.time + Math.random() * 0.3
  }
  spawnBot(g, bot, initial ? rand(6, 60) : START_MASS)
  return bot
}

function spawnBot(g, bot, mass) {
  var p = safeSpawn(g, 700)
  bot.cells = [newCell(g, bot, p.x, p.y, mass)]
  bot.target = { x: p.x, y: p.y }
  bot.respawnAt = -1
}

// A point at least `minDist` away from every player cell so respawns never
// land inside the player.
function safeSpawn(g, minDist) {
  for (var tries = 0; tries < 30; tries++) {
    var x = rand(200, WORLD - 200), y = rand(200, WORLD - 200)
    var ok = true
    if (g.player) {
      for (var i = 0; i < g.player.cells.length; i++) {
        var c = g.player.cells[i]
        if (dist(x, y, c.x, c.y) < minDist + radius(c.mass)) { ok = false; break }
      }
    }
    if (ok) return { x: x, y: y }
  }
  return { x: rand(200, WORLD - 200), y: rand(200, WORLD - 200) }
}

// ------------------------------------------------------------------ queries

function totalMass(entity) {
  var m = 0
  for (var i = 0; i < entity.cells.length; i++) m += entity.cells[i].mass
  return m
}

function centroid(entity) {
  var m = 0, x = 0, y = 0
  for (var i = 0; i < entity.cells.length; i++) {
    var c = entity.cells[i]
    m += c.mass; x += c.x * c.mass; y += c.y * c.mass
  }
  if (m <= 0) return null
  return { x: x / m, y: y / m, mass: m }
}

function leaderboard(g, limit) {
  var rows = []
  for (var i = 0; i < g.entities.length; i++) {
    var e = g.entities[i]
    if (e.cells.length === 0) continue
    rows.push({ name: e.name, mass: Math.round(totalMass(e)), isPlayer: e.isPlayer, color: e.color })
  }
  rows.sort(function(a, b) { return b.mass - a.mass })
  return rows.slice(0, limit || 6)
}

function playerRank(g) {
  var rows = leaderboard(g, 999)
  for (var i = 0; i < rows.length; i++) if (rows[i].isPlayer) return i + 1
  return 0
}

// ------------------------------------------------------------------ actions

function setPlayerTarget(g, x, y) {
  if (!g.player.target) g.player.target = { x: x, y: y }
  g.player.target.x = x
  g.player.target.y = y
}

function splitPlayer(g) { splitEntity(g, g.player) }

function splitEntity(g, e) {
  var count = e.cells.length
  var sorted = e.cells.slice().sort(function(a, b) { return b.mass - a.mass })
  for (var i = 0; i < sorted.length && count < MAX_CELLS; i++) {
    var c = sorted[i]
    if (c.mass < MIN_SPLIT_MASS) continue
    var dx = e.target.x - c.x, dy = e.target.y - c.y
    var d = Math.sqrt(dx * dx + dy * dy)
    if (d < 1) { dx = 1; dy = 0; d = 1 }
    dx /= d; dy /= d
    c.mass /= 2
    var r = radius(c.mass)
    var child = newCell(g, e, c.x + dx * r, c.y + dy * r, c.mass)
    child.vx = dx * 780; child.vy = dy * 780
    var delay = 30 + 0.0233 * c.mass
    c.mergeAt = g.time + delay
    child.mergeAt = g.time + delay
    e.cells.push(child)
    count++
  }
}

function ejectPlayer(g) {
  var e = g.player
  for (var i = 0; i < e.cells.length; i++) {
    var c = e.cells[i]
    if (c.mass < MIN_EJECT_MASS) continue
    var dx = e.target.x - c.x, dy = e.target.y - c.y
    var d = Math.sqrt(dx * dx + dy * dy)
    if (d < 1) { dx = 1; dy = 0; d = 1 }
    dx /= d; dy /= d
    c.mass -= EJECT_COST
    var r = radius(c.mass)
    g.ejected.push({
      x: c.x + dx * (r + 4), y: c.y + dy * (r + 4),
      vx: dx * 820 + rand(-40, 40), vy: dy * 820 + rand(-40, 40),
      mass: EJECT_MASS, color: e.color, owner: e, bornAt: g.time
    })
  }
}

// ------------------------------------------------------------------ tick

function tick(g, dt) {
  if (g.over) return
  dt = clamp(dt, 0.001, 0.05)
  g.time += dt

  var i, j, e, c

  // Bot brains.
  for (i = 0; i < g.entities.length; i++) {
    e = g.entities[i]
    if (e.isPlayer) continue
    if (e.cells.length === 0) {
      if (e.respawnAt >= 0 && g.time >= e.respawnAt) spawnBot(g, e, START_MASS)
      continue
    }
    if (g.time >= e.decideAt) {
      decide(g, e)
      e.decideAt = g.time + 0.25 + Math.random() * 0.1
    }
  }

  // Movement + impulses + decay.
  for (i = 0; i < g.entities.length; i++) {
    e = g.entities[i]
    for (j = 0; j < e.cells.length; j++) {
      c = e.cells[j]
      var r = radius(c.mass)
      if (e.target) {
        var dx = e.target.x - c.x, dy = e.target.y - c.y
        var d = Math.sqrt(dx * dx + dy * dy)
        if (d > 0.5) {
          var s = speed(c.mass) * Math.min(1, d / Math.max(r * 0.5, 8))
          c.x += dx / d * s * dt
          c.y += dy / d * s * dt
        }
      }
      c.x += c.vx * dt; c.y += c.vy * dt
      var damp = Math.pow(0.02, dt)
      c.vx *= damp; c.vy *= damp
      if (c.mass > 100) c.mass -= c.mass * 0.003 * dt
      c.x = clamp(c.x, r * 0.3, WORLD - r * 0.3)
      c.y = clamp(c.y, r * 0.3, WORLD - r * 0.3)
    }
    resolveOwnCells(g, e)
  }

  // Ejected pellets drift.
  for (i = 0; i < g.ejected.length; i++) {
    var p = g.ejected[i]
    p.x += p.vx * dt; p.y += p.vy * dt
    var pd = Math.pow(0.03, dt)
    p.vx *= pd; p.vy *= pd
    p.x = clamp(p.x, 4, WORLD - 4); p.y = clamp(p.y, 4, WORLD - 4)
  }

  eatThings(g)

  // Player state.
  if (g.player.cells.length === 0) {
    g.over = true
    return
  }
  var pm = totalMass(g.player)
  if (pm > g.score) g.score = Math.round(pm)
}

// Same-owner cells: push apart until they may merge, then merge.
function resolveOwnCells(g, e) {
  var cells = e.cells
  for (var a = 0; a < cells.length; a++) {
    for (var b = a + 1; b < cells.length; b++) {
      var ca = cells[a], cb = cells[b]
      var ra = radius(ca.mass), rb = radius(cb.mass)
      var dx = cb.x - ca.x, dy = cb.y - ca.y
      var d = Math.sqrt(dx * dx + dy * dy)
      var canMerge = g.time >= ca.mergeAt && g.time >= cb.mergeAt
      if (canMerge) {
        if (d < Math.max(ra, rb) * 0.7) {
          var big = ca.mass >= cb.mass ? ca : cb
          var small = big === ca ? cb : ca
          big.mass += small.mass
          cells.splice(cells.indexOf(small), 1)
          return resolveOwnCells(g, e)
        }
        continue
      }
      if (d < ra + rb && d > 0.001) {
        var overlap = (ra + rb - d)
        var total = ca.mass + cb.mass
        var nx = dx / d, ny = dy / d
        ca.x -= nx * overlap * (cb.mass / total)
        ca.y -= ny * overlap * (cb.mass / total)
        cb.x += nx * overlap * (ca.mass / total)
        cb.y += ny * overlap * (ca.mass / total)
      } else if (d <= 0.001) {
        cb.x += 1
      }
    }
  }
}

function eatThings(g) {
  var i, j, k, e, c, r

  // Collect every live cell once.
  var all = []
  for (i = 0; i < g.entities.length; i++) {
    e = g.entities[i]
    for (j = 0; j < e.cells.length; j++) all.push(e.cells[j])
  }

  for (i = 0; i < all.length; i++) {
    c = all[i]
    if (c.mass <= 0) continue
    r = radius(c.mass)

    // Food.
    for (j = g.food.length - 1; j >= 0; j--) {
      var f = g.food[j]
      if (Math.abs(f.x - c.x) > r || Math.abs(f.y - c.y) > r) continue
      if (dist(f.x, f.y, c.x, c.y) < r) {
        c.mass += FOOD_MASS
        g.food[j] = newFood()
      }
    }

    // Ejected mass (not your own for a moment after ejecting).
    for (j = g.ejected.length - 1; j >= 0; j--) {
      var p = g.ejected[j]
      if (p.owner === c.owner && g.time - p.bornAt < 0.6) continue
      if (Math.abs(p.x - c.x) > r || Math.abs(p.y - c.y) > r) continue
      if (dist(p.x, p.y, c.x, c.y) < r - 3) {
        c.mass += p.mass
        g.ejected.splice(j, 1)
      }
    }

    // Viruses pop anything big enough to swallow them.
    if (c.mass > VIRUS_MASS * 1.33) {
      for (j = 0; j < g.viruses.length; j++) {
        var v = g.viruses[j]
        var vr = radius(v.mass)
        if (dist(v.x, v.y, c.x, c.y) < r - vr * 0.4) {
          c.mass += v.mass
          g.viruses[j] = newVirus(g)
          explode(g, c)
          break
        }
      }
    }

    // Other entities' cells.
    for (k = 0; k < all.length; k++) {
      var o = all[k]
      if (o === c || o.owner === c.owner || o.mass <= 0) continue
      if (c.mass < o.mass * EAT_RATIO) continue
      var orad = radius(o.mass)
      if (Math.abs(o.x - c.x) > r || Math.abs(o.y - c.y) > r) continue
      if (dist(o.x, o.y, c.x, c.y) < r - orad * 0.4) {
        c.mass += o.mass
        o.mass = 0
        var victim = o.owner
        victim.cells.splice(victim.cells.indexOf(o), 1)
        if (victim.cells.length === 0) {
          if (victim.isPlayer) g.killedBy = c.owner.name
          else victim.respawnAt = g.time + 2.5
        }
      }
    }
  }
}

function explode(g, c) {
  var e = c.owner
  var room = MAX_CELLS - e.cells.length
  if (room <= 0) return
  var pieces = Math.min(room, 7)
  var pieceMass = c.mass / (pieces + 1)
  c.mass = pieceMass
  var delay = 30 + 0.0233 * pieceMass
  c.mergeAt = g.time + delay
  for (var i = 0; i < pieces; i++) {
    var ang = (i / pieces) * Math.PI * 2 + rand(-0.2, 0.2)
    var child = newCell(g, e, c.x + Math.cos(ang) * 4, c.y + Math.sin(ang) * 4, pieceMass)
    child.vx = Math.cos(ang) * 560
    child.vy = Math.sin(ang) * 560
    child.mergeAt = g.time + delay
    e.cells.push(child)
  }
}

// ------------------------------------------------------------------ bot AI

function decide(g, bot) {
  var me = bot.cells[0]
  for (var q = 1; q < bot.cells.length; q++) if (bot.cells[q].mass > me.mass) me = bot.cells[q]
  var myMass = totalMass(bot)
  var r = radius(me.mass)
  var fleeX = 0, fleeY = 0, threatened = false
  var preyX = 0, preyY = 0, preyD = Infinity, hasPrey = false
  var i, j

  for (i = 0; i < g.entities.length; i++) {
    var e = g.entities[i]
    if (e === bot) continue
    for (j = 0; j < e.cells.length; j++) {
      var c = e.cells[j]
      var d = dist(c.x, c.y, me.x, me.y)
      var cr = radius(c.mass)
      if (c.mass > me.mass * EAT_RATIO && d < r + cr + 320) {
        threatened = true
        var w = 1 / Math.max(d - cr, 20)
        fleeX += (me.x - c.x) / d * w
        fleeY += (me.y - c.y) / d * w
      } else if (me.mass > c.mass * EAT_RATIO && d < 560 && d < preyD) {
        preyD = d; preyX = c.x; preyY = c.y; hasPrey = true
      }
    }
  }

  // Big bots steer around viruses.
  if (me.mass > VIRUS_MASS * 1.33) {
    for (i = 0; i < g.viruses.length; i++) {
      var v = g.viruses[i]
      var vd = dist(v.x, v.y, me.x, me.y)
      if (vd < r + 140) {
        threatened = true
        var vw = 1.5 / Math.max(vd, 20)
        fleeX += (me.x - v.x) / vd * vw
        fleeY += (me.y - v.y) / vd * vw
      }
    }
  }

  var tx, ty
  if (threatened) {
    var fl = Math.sqrt(fleeX * fleeX + fleeY * fleeY) || 1
    tx = me.x + fleeX / fl * 500
    ty = me.y + fleeY / fl * 500
    // Walls: bend the escape away from the edge.
    if (tx < 150) tx = 150 + Math.abs(fleeY / fl) * 200
    if (ty < 150) ty = 150 + Math.abs(fleeX / fl) * 200
    if (tx > WORLD - 150) tx = WORLD - 150 - Math.abs(fleeY / fl) * 200
    if (ty > WORLD - 150) ty = WORLD - 150 - Math.abs(fleeX / fl) * 200
  } else if (hasPrey) {
    tx = preyX; ty = preyY
  } else {
    var best = null, bestD = Infinity
    for (i = 0; i < g.ejected.length; i++) {
      var p = g.ejected[i]
      var pd = dist(p.x, p.y, me.x, me.y)
      if (pd < bestD) { bestD = pd - 200; best = p }
    }
    for (i = 0; i < g.food.length; i++) {
      var f = g.food[i]
      var fd = Math.abs(f.x - me.x) + Math.abs(f.y - me.y)
      if (fd < bestD) { bestD = fd; best = f }
    }
    if (best) { tx = best.x; ty = best.y }
    else { tx = me.x + rand(-200, 200); ty = me.y + rand(-200, 200) }
  }
  bot.target = { x: clamp(tx, r, WORLD - r), y: clamp(ty, r, WORLD - r) }
}

// ------------------------------------------------------------------ render

// view: { width, height, camX, camY, zoom, fontFamily, background, grid,
//         border, rim, text, virus, virusRim }
function render(ctx, g, view) {
  var w = view.width, h = view.height
  ctx.save()
  ctx.fillStyle = view.background
  ctx.fillRect(0, 0, w, h)

  ctx.translate(w / 2, h / 2)
  ctx.scale(view.zoom, view.zoom)
  ctx.translate(-view.camX, -view.camY)

  var left = view.camX - w / 2 / view.zoom, right = view.camX + w / 2 / view.zoom
  var top = view.camY - h / 2 / view.zoom, bottom = view.camY + h / 2 / view.zoom

  // Grid.
  var step = 60
  ctx.strokeStyle = view.grid
  ctx.lineWidth = 1 / view.zoom
  ctx.beginPath()
  var gx0 = Math.max(0, Math.floor(left / step) * step), gx1 = Math.min(WORLD, right)
  var gy0 = Math.max(0, Math.floor(top / step) * step), gy1 = Math.min(WORLD, bottom)
  for (var gx = gx0; gx <= gx1; gx += step) { ctx.moveTo(gx, Math.max(0, top)); ctx.lineTo(gx, Math.min(WORLD, bottom)) }
  for (var gy = gy0; gy <= gy1; gy += step) { ctx.moveTo(Math.max(0, left), gy); ctx.lineTo(Math.min(WORLD, right), gy) }
  ctx.stroke()

  // Arena border.
  ctx.strokeStyle = view.border
  ctx.lineWidth = 4 / view.zoom
  ctx.strokeRect(0, 0, WORLD, WORLD)

  var i, c

  // Food.
  var cols = view.foodColors
  for (i = 0; i < g.food.length; i++) {
    var f = g.food[i]
    if (f.x < left - 10 || f.x > right + 10 || f.y < top - 10 || f.y > bottom + 10) continue
    ctx.fillStyle = cols[f.hue % cols.length]
    ctx.beginPath()
    ctx.arc(f.x, f.y, FOOD_RADIUS, 0, Math.PI * 2)
    ctx.fill()
  }

  // Ejected mass.
  for (i = 0; i < g.ejected.length; i++) {
    var p = g.ejected[i]
    ctx.fillStyle = p.color
    ctx.beginPath()
    ctx.arc(p.x, p.y, radius(p.mass) * 0.75, 0, Math.PI * 2)
    ctx.fill()
  }

  // Cells, smallest first so big ones paint on top.
  var all = []
  for (i = 0; i < g.entities.length; i++) {
    var e = g.entities[i]
    for (var j = 0; j < e.cells.length; j++) all.push(e.cells[j])
  }
  all.sort(function(a, b) { return a.mass - b.mass })

  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  for (i = 0; i < all.length; i++) {
    c = all[i]
    var r = radius(c.mass)
    if (c.x + r < left || c.x - r > right || c.y + r < top || c.y - r > bottom) continue
    ctx.fillStyle = c.owner.color
    ctx.strokeStyle = view.rim
    ctx.lineWidth = Math.max(2, r * 0.08)
    ctx.beginPath()
    ctx.arc(c.x, c.y, r, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()

    var px = clamp(r * 0.5, 11 / view.zoom, r * 0.9)
    if (r * view.zoom > 14) {
      ctx.fillStyle = view.text
      ctx.font = "bold " + Math.round(px) + "px " + view.fontFamily
      ctx.fillText(c.owner.name, c.x, c.y - (r > 40 ? px * 0.35 : 0))
      if (r > 40) {
        ctx.font = Math.round(px * 0.6) + "px " + view.fontFamily
        ctx.fillText(String(Math.round(c.mass)), c.x, c.y + px * 0.55)
      }
    }
  }

  // Viruses: spiky rings.
  for (i = 0; i < g.viruses.length; i++) {
    var v = g.viruses[i]
    var vr = radius(v.mass)
    if (v.x + vr < left || v.x - vr > right || v.y + vr < top || v.y - vr > bottom) continue
    ctx.fillStyle = view.virus
    ctx.strokeStyle = view.virusRim
    ctx.lineWidth = 3
    ctx.beginPath()
    var spikes = 22
    for (var s = 0; s < spikes * 2; s++) {
      var ang = (s / (spikes * 2)) * Math.PI * 2
      var rr = s % 2 === 0 ? vr : vr * 0.86
      var xx = v.x + Math.cos(ang) * rr, yy = v.y + Math.sin(ang) * rr
      if (s === 0) ctx.moveTo(xx, yy); else ctx.lineTo(xx, yy)
    }
    ctx.closePath()
    ctx.fill()
    ctx.stroke()
  }

  ctx.restore()
}
