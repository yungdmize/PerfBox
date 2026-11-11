-- PerfBox (game engine side): keeps the vehicle-side timer (extensions/perfboxVeh) loaded in the player's vehicle,
-- writes every measured result to settings/perfbox_results.csv in the user folder, and runs automatic tests:
--   autoTest()  - one factory-style standing start of the current vehicle
--   autoSweep() - the same for every configuration of the current model, each one respawned at the start point
local M = {}

local VEH_EXT = "perfboxVeh"
local CSV = "settings/perfbox_results.csv"
local CSV_HEADER = "date;config;metric;time_s;value;unit;rollout\n"

local sweep = nil   -- {model, list, i, pos, rot, token, wait, cfgTime}

-- After core_vehicles.replaceVehicle the vehicle Lua is restarted, and a command queued from onVehicleSpawned can be lost
-- in that restart. So the sweep does not rely on spawn hooks: while a configuration is being tested the GE side pings the
-- vehicle once per second with the run token, and the vehicle starts the auto run for a token it has not run yet.
local PING_DELAY = 1.5     -- s after the replace before the first ping
local PING_PERIOD = 1.0
local CONFIG_TIMEOUT = 150 -- s per configuration, then it is skipped

local function appendCsv(line)
  local old = readFile(CSV)
  if not old or old == "" then
    old = CSV_HEADER
  end
  writeFile(CSV, old .. line)
end

local function inject(vid)
  if not vid or vid < 0 then
    return
  end
  local veh = be:getObjectByID(vid)
  if veh then
    veh:queueLuaCommand('extensions.load("' .. VEH_EXT .. '")')
  end
end

local function ensure()
  inject(be:getPlayerVehicleID(0))
end

local function startAuto(veh)
  veh:queueLuaCommand('extensions.load("' .. VEH_EXT .. '"); if extensions.' .. VEH_EXT .. ' then extensions.' .. VEH_EXT .. '.autoRun(false) end')
end

local function pingSweep(veh, token)
  veh:queueLuaCommand('extensions.load("' .. VEH_EXT .. '"); if extensions.' .. VEH_EXT .. ' then extensions.' .. VEH_EXT .. '.sweepPing(' .. token .. ') end')
end

local function nextConfig()
  if not sweep then
    return
  end
  sweep.i = sweep.i + 1
  if sweep.i > #sweep.list then
    log("I", "perfbox", "sweep finished: " .. sweep.model)
    guihooks.trigger("PerfBoxSweep", {done = true})
    sweep = nil
    return
  end
  local veh = be:getPlayerVehicle(0)
  if veh and sweep.pos then
    spawn.safeTeleport(veh, sweep.pos, sweep.rot)
  end
  sweep.token = sweep.token + 1
  sweep.wait = PING_DELAY
  sweep.cfgTime = 0
  sweep.started = false
  log("I", "perfbox", string.format("sweep %d/%d: %s", sweep.i, #sweep.list, sweep.list[sweep.i]))
  guihooks.trigger("PerfBoxSweep", {i = sweep.i, n = #sweep.list, config = sweep.list[sweep.i]})
  core_vehicles.replaceVehicle(sweep.model, {config = sweep.list[sweep.i]})
end

local function sweepBusy()
  if not sweep then
    return false
  end
  log("I", "perfbox", string.format("sweep already running (%d/%d: %s), press Stop to cancel it", sweep.i, #sweep.list,
    tostring(sweep.list[sweep.i])))
  guihooks.trigger("PerfBoxSweep", {i = sweep.i, n = #sweep.list, config = sweep.list[sweep.i], busy = true})
  return true
end

local function autoTest()
  if sweepBusy() then
    return
  end
  local veh = be:getPlayerVehicle(0)
  if veh then
    startAuto(veh)
  end
end

local function autoSweep()
  if sweepBusy() then
    return
  end
  local veh = be:getPlayerVehicle(0)
  if not veh then
    return
  end
  local model = veh:getJBeamFilename()
  local m = core_vehicles.getModel(model)
  local list = {}
  for key, _ in pairs((m and m.configs) or {}) do
    table.insert(list, key)
  end
  table.sort(list)
  if #list == 0 then
    log("W", "perfbox", "no configurations found for " .. tostring(model))
    return
  end
  sweep = {model = model, list = list, i = 0, token = math.floor(os.clock() * 1000) % 1000000,
    pos = veh:getPosition(), rot = quatFromDir(veh:getDirectionVector(), veh:getDirectionVectorUp())}
  log("I", "perfbox", string.format("sweep started: %s, %d configurations", model, #list))
  nextConfig()
end

local function stopAuto()
  sweep = nil
  local veh = be:getPlayerVehicle(0)
  if veh then
    veh:queueLuaCommand('if extensions.' .. VEH_EXT .. ' then extensions.' .. VEH_EXT .. '.autoStop() end')
  end
  guihooks.trigger("PerfBoxSweep", {done = true})
end

local function onVehicleSpawned(vid)
  if vid ~= be:getPlayerVehicleID(0) then
    return
  end
  inject(vid)
end

local function onVehicleReplaced(vid)
  if vid ~= be:getPlayerVehicleID(0) then
    return
  end
  inject(vid)
end

local function onUpdate(dtReal)
  if not sweep or sweep.i < 1 then
    return
  end
  dtReal = dtReal or 0
  sweep.cfgTime = sweep.cfgTime + dtReal
  if sweep.cfgTime > CONFIG_TIMEOUT then
    log("W", "perfbox", string.format("sweep %d/%d: %s timed out after %d s, skipped", sweep.i, #sweep.list,
      tostring(sweep.list[sweep.i]), CONFIG_TIMEOUT))
    nextConfig()
    return
  end
  sweep.wait = sweep.wait - dtReal
  if sweep.wait <= 0 then
    sweep.wait = PING_PERIOD
    local veh = be:getPlayerVehicle(0)
    if veh then
      pingSweep(veh, sweep.token)
    end
  end
end

local function onVehicleSwitched(oldId, newId)
  if oldId and oldId >= 0 then
    local old = be:getObjectByID(oldId)
    if old then
      old:queueLuaCommand('extensions.unload("' .. VEH_EXT .. '")')
    end
  end
  inject(newId)
end

-- called from the vehicle side
local function onResult(config, label, t, x, unit, rollout)
  appendCsv(string.format("%s;%s;%s;%.3f;%.2f;%s;%s\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(config), tostring(label),
    t or 0, x or 0, tostring(unit), rollout and "1ft" or "no"))
  log("I", "perfbox", string.format("%s  %s  %.3f s  %.2f %s%s", tostring(config), tostring(label), t or 0, x or 0, tostring(unit), rollout and "  (1 ft rollout)" or ""))
end

local function onAutoStart(config, mass, token)
  appendCsv(string.format("%s;%s;auto run start (mass kg);0;%.1f;kg;no\n", os.date("%Y-%m-%d %H:%M:%S"), tostring(config), mass or 0))
  log("I", "perfbox", string.format("%s  auto run, mass %.1f kg", tostring(config), mass or 0))
  if sweep and token and token == sweep.token then
    sweep.started = true
  end
end

local function onAutoDone(token)
  if sweep and token and token == sweep.token then
    nextConfig()
  end
end

local function onExtensionLoaded()
  ensure()
end

M.onExtensionLoaded = onExtensionLoaded
M.onVehicleSpawned = onVehicleSpawned
M.onVehicleReplaced = onVehicleReplaced
M.onUpdate = onUpdate
M.onVehicleSwitched = onVehicleSwitched
M.ensure = ensure
M.onResult = onResult
M.onAutoStart = onAutoStart
M.onAutoDone = onAutoDone
M.autoTest = autoTest
M.autoSweep = autoSweep
M.stopAuto = stopAuto

return M
