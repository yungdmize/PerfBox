-- PerfBox (vehicle side): GPS-style performance meter.
-- Everything is measured inside the physics step (onPhysicsStep, 2000 Hz) on the simulation clock, so results do not
-- depend on frame rate, UI rate or slow motion. Speed is the horizontal ground speed of the vehicle (like a GPS
-- logger), distance is that speed integrated (trapezoid) every physics step, and every threshold crossing is linearly
-- interpolated inside its 0.5 ms step.
--
-- Standing start: stand still (< 0.3 km/h) for 0.3 s; the run triggers at 0.5 km/h and its clock is wound back to the
-- moment the car started moving. Optional 1 ft rollout (US drag strip): the clock starts after the first 0.3048 m of
-- travel, distances still count from rest.
-- Rolling intervals (60-100, 80-120, 100-200, 200-300) are taken whenever the speed climbs through them without dipping
-- below the lower bound. Braking 100-0 starts when the speed falls through 100 km/h with the brake applied.
local M = {}

local KMH = 3.6
local START_KMH = 0.5
local STOP_KMH = 0.3
local STAND_TIME = 0.3
local ROLLOUT_M = 0.3048
local MAX_RUN = 300
local UI_PERIOD = 1 / 15

-- label: language-neutral (English) name for the CSV and the log; the UI app shows the translated
-- "perfbox.metric.<key>" from locales/translations/<lang>/perfbox.translation.json
local SPEEDS = {
  {key = "s60", kmh = 60, label = "0-60 km/h"},
  {key = "s96", kmh = 96.56064, label = "0-60 mph"},
  {key = "s100", kmh = 100, label = "0-100 km/h"},
  {key = "s150", kmh = 150, label = "0-150 km/h"},
  {key = "s200", kmh = 200, label = "0-200 km/h"},
  {key = "s250", kmh = 250, label = "0-250 km/h"},
  {key = "s300", kmh = 300, label = "0-300 km/h"},
}
local DISTS = {
  {key = "d60ft", m = 18.288, label = "60 ft (18 m)"},
  {key = "d201", m = 201.168, label = "1/8 mile (201 m)"},
  {key = "d402", m = 402.336, label = "1/4 mile (402 m)"},
  {key = "d805", m = 804.672, label = "1/2 mile (805 m)"},
  {key = "d1000", m = 1000, label = "1 km"},
  {key = "d1609", m = 1609.344, label = "1 mile (1609 m)"},
}
local INTERVALS = {
  {key = "i60_100", lo = 60, hi = 100, label = "60-100 km/h"},
  {key = "i80_120", lo = 80, hi = 120, label = "80-120 km/h"},
  {key = "i100_200", lo = 100, hi = 200, label = "100-200 km/h"},
  {key = "i200_300", lo = 200, hi = 300, label = "200-300 km/h"},
}
local BRAKES = {
  {key = "b100", from = 100, label = "100-0 km/h"},
}

-- state
local simT = 0            -- simulation clock, s
local vPrev = 0           -- horizontal speed at the previous step, m/s
local odo = 0             -- integrated distance, m
local mode = "moving"     -- "moving" | "standing" | "run"
local standT = 0
local run = nil           -- current standing-start run
local lastRun = nil       -- summary of the last run {time, dist, maxKmh}
local rolling = {}        -- interval key -> {t, d} when the lower bound was crossed
local braking = {}        -- brake key -> {t, d}
local rollout = false
local last = {}           -- metric key -> {t, x, fresh}
local best = {}           -- metric key -> {t, x}
local dirty = true
local uiTimer = 0
local pendingLog = {}
local auto = nil          -- auto run state (see autoRun)
local blockStart = false  -- no standing start while the auto run is settling

local function lerp(a, b, f)
  return a + (b - a) * f
end

local function frac(a, b, target)
  if b == a then
    return 1
  end
  local f = (target - a) / (b - a)
  if f < 0 then return 0 end
  if f > 1 then return 1 end
  return f
end

local function record(key, label, t, x, unit)
  last[key] = {t = t, x = x, fresh = true}
  local b = best[key]
  if not b or t < b.t then
    best[key] = {t = t, x = x}
  end
  table.insert(pendingLog, {label = label, t = t, x = x, unit = unit})
  dirty = true
end

local function startRun(tStart, odoStart)
  for _, r in pairs(last) do
    r.fresh = false
  end
  run = {tStart = tStart, odo0 = odoStart, t0 = (not rollout) and tStart or nil, hit = {}, maxKmh = 0}
  mode = "run"
  dirty = true
end

local function finishRun(tEnd)
  if run then
    lastRun = {time = tEnd - (run.t0 or run.tStart), dist = odo - run.odo0, maxKmh = run.maxKmh}
  end
  run = nil
  mode = "moving"
  standT = 0
  dirty = true
end

local function onPhysicsStep(dt)
  local vel = obj:getVelocity()
  local spd = math.sqrt(vel.x * vel.x + vel.y * vel.y)
  local dir = obj:getDirectionVector()
  local forward = (vel.x * dir.x + vel.y * dir.y) >= 0
  local k0, k1 = vPrev * KMH, spd * KMH
  local dStep = (vPrev + spd) * 0.5 * dt
  local odo1 = odo + dStep

  -- standstill detection and standing start
  if mode ~= "run" then
    if k1 < STOP_KMH then
      standT = standT + dt
      if standT >= STAND_TIME and mode ~= "standing" then
        mode = "standing"
        dirty = true
      end
    elseif k1 >= START_KMH then
      if mode == "standing" and not blockStart and forward then
        -- the trigger fires at 0.5 km/h; the clock is wound back to the moment the car started moving, using the
        -- acceleration of this step (true standstill timing, as the published 0-100 figures)
        local f = frac(k0, k1, START_KMH)
        local accel = (spd - vPrev) / dt
        local vTrig = START_KMH / KMH
        local back = accel > 0.5 and vTrig / accel or 0
        local backDist = accel > 0.5 and vTrig * vTrig / (2 * accel) or 0
        startRun(simT + f * dt - back, odo + dStep * f - backDist)
      else
        -- rolling backwards, or creeping while the auto run is still settling: not a standing start
        standT = 0
        if mode == "standing" then
          mode = "moving"
          dirty = true
        end
      end
    end
  end

  -- standing-start run: speed and distance milestones
  if mode == "run" and run then
    local d0, d1 = odo - run.odo0, odo1 - run.odo0
    if not run.t0 and d1 >= ROLLOUT_M then
      run.t0 = simT + frac(d0, d1, ROLLOUT_M) * dt
    end
    if run.t0 then
      for i = 1, #SPEEDS do
        local s = SPEEDS[i]
        if not run.hit[s.key] and k0 < s.kmh and k1 >= s.kmh then
          local f = frac(k0, k1, s.kmh)
          run.hit[s.key] = true
          record(s.key, s.label, simT + f * dt - run.t0, lerp(d0, d1, f), "m")
        end
      end
      for i = 1, #DISTS do
        local D = DISTS[i]
        if not run.hit[D.key] and d0 < D.m and d1 >= D.m then
          local f = frac(d0, d1, D.m)
          run.hit[D.key] = true
          record(D.key, D.label, simT + f * dt - run.t0, lerp(k0, k1, f), "km/h")
        end
      end
    end
    if k1 > run.maxKmh then
      run.maxKmh = k1
    end
    if k1 < STOP_KMH or (simT + dt - run.tStart) > MAX_RUN then
      finishRun(simT + dt)
    end
  end

  -- rolling intervals (any time the speed climbs through them)
  for i = 1, #INTERVALS do
    local I = INTERVALS[i]
    local st = rolling[I.key]
    if k0 < I.lo and k1 >= I.lo then
      local f = frac(k0, k1, I.lo)
      st = {t = simT + f * dt, d = odo + dStep * f}
      rolling[I.key] = st
    elseif st and k1 < I.lo then
      rolling[I.key] = nil
      st = nil
    end
    if st and k0 < I.hi and k1 >= I.hi then
      local f = frac(k0, k1, I.hi)
      record(I.key, I.label, simT + f * dt - st.t, odo + dStep * f - st.d, "m")
      rolling[I.key] = nil
    end
  end

  -- braking from speed to standstill
  for i = 1, #BRAKES do
    local B = BRAKES[i]
    local st = braking[B.key]
    if k0 > B.from and k1 <= B.from and (electrics.values.brake or 0) > 0.05 then
      local f = frac(k0, k1, B.from)
      braking[B.key] = {t = simT + f * dt, d = odo + dStep * f}
    elseif st then
      if k1 > B.from + 2 then
        braking[B.key] = nil
      elseif k1 < STOP_KMH then
        -- stop detected at 0.3 km/h: extend to the full stop with this step's deceleration
        local f = frac(k0, k1, STOP_KMH)
        local decel = (vPrev - spd) / dt
        local vStop = STOP_KMH / KMH
        local extraT = decel > 0.5 and vStop / decel or 0
        local extraD = decel > 0.5 and vStop * vStop / (2 * decel) or 0
        record(B.key, B.label, simT + f * dt + extraT - st.t, odo + dStep * f + extraD - st.d, "m")
        braking[B.key] = nil
      end
    end
  end

  simT = simT + dt
  odo = odo1
  vPrev = spd
end

local function rowsFor(group, list)
  local rows = {}
  for i = 1, #list do
    local m = list[i]
    local l, b = last[m.key], best[m.key]
    rows[#rows + 1] = {
      key = m.key, label = m.label, group = group,
      t = l and l.t or nil, x = l and l.x or nil, fresh = l and l.fresh or false,
      bt = b and b.t or nil, bx = b and b.x or nil,
    }
  end
  return rows
end

local function sendUI()
  local runTime, runDist
  if mode == "run" and run then
    runTime = simT - (run.t0 or run.tStart)
    runDist = odo - run.odo0
  elseif lastRun then
    runTime, runDist = lastRun.time, lastRun.dist
  end
  guihooks.trigger("PerfBoxUpdate", {
    kmh = vPrev * KMH,
    mode = mode,
    auto = auto and auto.phase or nil,
    rollout = rollout,
    runTime = runTime,
    runDist = runDist,
    maxKmh = (run and run.maxKmh) or (lastRun and lastRun.maxKmh) or nil,
    -- id: the UI shows the translated "perfbox.group.<id>" and "perfbox.groupUnit.<id>"
    groups = {
      {id = "speed", rows = rowsFor("speed", SPEEDS)},
      {id = "dist", rows = rowsFor("dist", DISTS)},
      {id = "interval", rows = rowsFor("interval", INTERVALS)},
      {id = "brake", rows = rowsFor("brake", BRAKES)},
    },
  })
end

local function flushLog()
  if #pendingLog == 0 then
    return
  end
  local cfg = (v.config and v.config.partConfigFilename) or ""
  for i = 1, #pendingLog do
    local e = pendingLog[i]
    obj:queueGameEngineLua(string.format("if perfbox then perfbox.onResult(%q, %q, %.4f, %.3f, %q, %s) end",
      cfg, e.label, e.t, e.x or 0, e.unit or "", tostring(rollout)))
  end
  pendingLog = {}
end

local function clearRun()
  run = nil
  mode = "moving"
  standT = 0
  vPrev = 0
  rolling = {}
  braking = {}
  dirty = true
end

-- ---------------------------------------------------------------- auto run (factory-style standing start)
-- Holds the car on the parking brake until it has settled, then releases it and applies full throttle at the same
-- moment (no brake torquing, no launch control), drives straight until 200 km/h (sweep: 100 km/h) and 1/4 mile are both
-- done (or 60 s), then brakes to a stop. Player input is blocked meanwhile and the gearbox runs in arcade mode (the
-- previous mode is restored afterwards). With sweep = true the game engine side is told when it is done.
local AUTO_INPUTS = {"throttle", "brake", "parkingbrake", "steering", "clutch"}

local function autoInputs(enabled)
  for i = 1, #AUTO_INPUTS do
    if enabled then
      input.setAllowedInputSource(AUTO_INPUTS[i], "perfbox", true)
    else
      input.setAllowedInputSource(AUTO_INPUTS[i], nil)
    end
  end
end

-- note: in arcade gearbox mode a brake input at standstill engages reverse, so the car is held with the parking brake
local function drive(throttle, brake, parkingbrake)
  input.event("throttle", throttle, FILTER_DIRECT, nil, nil, nil, "perfbox")
  input.event("brake", brake, FILTER_DIRECT, nil, nil, nil, "perfbox")
  input.event("parkingbrake", parkingbrake or 0, FILTER_DIRECT, nil, nil, nil, "perfbox")
  input.event("steering", 0, FILTER_DIRECT, nil, nil, nil, "perfbox")
  input.event("clutch", 0, FILTER_DIRECT, nil, nil, nil, "perfbox")
end

local function vehicleMass()
  local ok, stats = pcall(function() return obj:calcBeamStats() end)
  return (ok and stats and stats.total_weight) or 0
end

local function configName()
  return (v.config and v.config.partConfigFilename) or ""
end

local function alog(msg)
  log("I", "perfbox", string.format("%s  auto: %s  (%.1f km/h, gear %s)", configName(), msg, vPrev * KMH,
    tostring(electrics.values.gear)))
end

local function setBehavior(b)
  local mc = controller.mainController
  if b and mc and mc.setGearboxMode then
    mc.setGearboxMode(b)
  end
end

local doneToken = nil     -- last sweep token this vehicle has finished

local function autoRun(sweep, token)
  local mc = controller.mainController
  auto = {phase = "settle", t = 0, sweep = sweep and true or false, token = token,
    behavior = mc and mc.gearboxBehavior or nil}
  clearRun()
  blockStart = true
  autoInputs(true)
  if auto.behavior ~= "arcade" then
    setBehavior("arcade")
  end
  obj:queueGameEngineLua(string.format("if perfbox then perfbox.onAutoStart(%q, %.1f, %s) end", configName(), vehicleMass(),
    tostring(token)))
  alog("settle on the parking brake")
  dirty = true
end

local function autoStop(notify)
  if auto then
    local sweep, behavior, token = auto.sweep, auto.behavior, auto.token
    auto = nil
    blockStart = false
    drive(0, 0, 0)
    autoInputs(false)
    if behavior and behavior ~= "arcade" then
      setBehavior(behavior)
    end
    if notify and sweep then
      doneToken = token
      obj:queueGameEngineLua("if perfbox then perfbox.onAutoDone(" .. tostring(token) .. ") end")
    end
    dirty = true
  end
end

local function autoUpdate(dt)
  local a = auto
  if not a then
    return
  end
  a.t = a.t + dt
  if a.phase == "settle" then
    drive(0, 0, 1)
    if a.t > 2.5 and mode == "standing" then
      -- release the parking brake and floor it in the same frame; the run starts at first forward movement
      a.phase, a.t = "launch", 0
      blockStart = false
      drive(1, 0, 0)
      alog("launch")
    elseif a.t > 20 then
      alog("the car did not settle in 20 s, skipped")
      autoStop(true)
    end
  elseif a.phase == "launch" then
    drive(1, 0, 0)
    if mode == "run" then
      a.started = true
    end
    local hit = run and run.hit or {}
    -- single test: 200 km/h and 1/4 mile; config sweep: 100 km/h and 1/4 mile (shorter, less track needed)
    local need = a.sweep and "s100" or "s200"
    local reason
    if hit[need] and hit.d402 then
      reason = "done"
    elseif a.t > 60 then
      reason = "time limit 60 s"
    elseif a.started and mode ~= "run" then
      reason = "the run ended (car stopped)"
    elseif not a.started and a.t > 8 then
      reason = "the car did not move forward in 8 s"
    end
    if reason then
      a.phase, a.t = "stop", 0
      alog("stop: " .. reason)
    end
  elseif a.phase == "stop" then
    -- service brake while rolling; near standstill the parking brake (the brake would select reverse in arcade mode)
    if vPrev * KMH > 8 then
      drive(0, 1, 0)
    else
      drive(0, 0, 1)
    end
    if (vPrev * KMH < STOP_KMH and a.t > 1) or a.t > 30 then
      alog("finished")
      autoStop(true)
    end
  end
end

local function updateGFX(dt)
  autoUpdate(dt)
  flushLog()
  if not playerInfo.firstPlayerSeated then
    return
  end
  uiTimer = uiTimer + dt
  if uiTimer >= UI_PERIOD or dirty then
    uiTimer = 0
    dirty = false
    sendUI()
  end
end

-- public: called from the UI app
local function reset()
  autoStop(false)
  clearRun()
  last, best, lastRun = {}, {}, nil
  dirty = true
end

local function setRollout(enabled)
  rollout = enabled and true or false
  clearRun()
  dirty = true
end

local function toggleRollout()
  setRollout(not rollout)
end

local function requestUI()
  dirty = true
end

local function onReset()
  clearRun()
end

-- config sweep: the GE side pings once per second while a configuration is being tested; start its run once
local function sweepPing(token)
  if auto or token == doneToken then
    return
  end
  autoRun(true, token)
end

local function onExtensionLoaded()
  enablePhysicsStepHook()
  simT, odo, vPrev = 0, 0, 0
  clearRun()
end

M.onExtensionLoaded = onExtensionLoaded
M.onPhysicsStep = onPhysicsStep
M.updateGFX = updateGFX
M.onReset = onReset
M.reset = reset
M.setRollout = setRollout
M.toggleRollout = toggleRollout
M.requestUI = requestUI
M.autoRun = autoRun
M.sweepPing = sweepPing
M.autoStop = function() autoStop(false) end

return M
