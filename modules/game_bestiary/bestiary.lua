-- game_bestiary/bestiary.lua
-- Bestiary & Charms client module

local bestiaryWindow = nil
local bestiaryButton = nil  -- sidebutton ref (set from sidebuttons module)

-- State
local races = {}           -- { [raceName] = { total=N, unlocked=N } }
local raceOrder = {}       -- ordered list of race names
local creatures = {}       -- { [raceId] = { name=str, progress=N, occurrence=N } } (per current race)
local currentRace = nil    -- selected race name
local currentCreatureId = nil -- selected creature raceId

local charms = {}          -- indexed by charmId (0-based): { id, tier, unlocked, raceId, removeCost }
local charmPoints = 0
local charmSlots = 0
local charmResetCost = 0
local finishedMonsters = {} -- list of raceIds with bestiary complete (eligible for charm assign)
local trackedMonsters = {}  -- { [raceId] = { kills, first, second, toUnlock, progress } }
local monsterData = {}     -- cached full data: { [raceId] = { ... } }

local ELEMENT_NAMES = {
  [0] = "Physical",
  [1] = "Fire",
  [2] = "Earth",
  [3] = "Energy",
  [4] = "Life Drain",
  [5] = "Mana Drain"
}

local OCCURRENCE_NAMES = {
  [0] = "Common",
  [1] = "Uncommon",
  [2] = "Rare",
  [3] = "Very Rare"
}

local CHARM_NAMES = {
  [0]  = "Wound",        [1]  = "Enflame",     [2]  = "Poison",
  [3]  = "Freeze",       [4]  = "Zap",         [5]  = "Curse",
  [6]  = "Cripple",      [7]  = "Parry",       [8]  = "Dodge",
  [9]  = "Adrenaline",   [10] = "Numb",        [11] = "Cleanse",
  [12] = "Bless",        [13] = "Scavenge",    [14] = "Gut",
  [15] = "Low Blow",     [16] = "Vampiric",    [17] = "Void",
  [18] = "Vengeance",    [19] = "Rune",        [20] = "Overpower",
  [21] = "Absorb",       [22] = "Divine",      [23] = "Spin",
  [24] = "Overflux"
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Init / Terminate
-- ─────────────────────────────────────────────────────────────────────────────

function init()
  bestiaryWindow = g_ui.loadUI('bestiary', rootWidget)
  if not bestiaryWindow then
    g_logger.error('[game_bestiary] failed to load bestiary.otui')
    return
  end
  bestiaryWindow:hide()
  bestiaryWindow:centerIn(rootWidget)

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd   = onGameEnd
  })

  g_keyboard.bindKeyDown('Alt+L', toggle)

  -- Start on bestiary tab
  showBestiaryTab()

  -- wire tab buttons
  local win = bestiaryWindow
  win:recursiveGetChildById('tabBestiary').onClick = function() showBestiaryTab() end
  win:recursiveGetChildById('tabCharms').onClick   = function() showCharmsTab() end

  -- Get sidebutton reference
  if modules.game_sidebuttons then
    bestiaryButton = modules.game_sidebuttons.bestiaryButton
  end

  -- Register protocol opcodes directly (bypasses GameTibia12Protocol guard)
  ProtocolGame.registerOpcode(0xD5, parseRaces)
  ProtocolGame.registerOpcode(0xD6, parseOverview)
  ProtocolGame.registerOpcode(0xD7, parseMonsterData)
  ProtocolGame.registerOpcode(0xD8, parseCharms)
  ProtocolGame.registerOpcode(0xD9, parseEntryChanged)
  ProtocolGame.registerOpcode(0xB9, parseTracker)
  ProtocolGame.registerOpcode(0x4B, parseResourceBalance)

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd   = onGameEnd
  })

  g_keyboard.unbindKeyDown('Alt+L')

  ProtocolGame.unregisterOpcode(0xD5)
  ProtocolGame.unregisterOpcode(0xD6)
  ProtocolGame.unregisterOpcode(0xD7)
  ProtocolGame.unregisterOpcode(0xD8)
  ProtocolGame.unregisterOpcode(0xD9)
  ProtocolGame.unregisterOpcode(0xB9)
  ProtocolGame.unregisterOpcode(0x4B)

  if bestiaryWindow then
    bestiaryWindow:destroy()
    bestiaryWindow = nil
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Protocol parsers (registered directly, no GameTibia12Protocol guard)
-- ─────────────────────────────────────────────────────────────────────────────

function parseRaces(protocol, msg)
  local count = msg:getU16()
  local raceData = {}
  for i = 1, count do
    local name     = msg:getString()
    local total    = msg:getU16()
    local unlocked = msg:getU16()
    table.insert(raceData, { name = name, total = total, unlocked = unlocked })
  end
  onBestiaryData(raceData)
end

function parseOverview(protocol, msg)
  local raceName = msg:getString()
  local count    = msg:getU16()
  local list = {}
  for i = 1, count do
    local raceId     = msg:getU16()
    local progress   = msg:getU8()
    local occurrence = 0
    if progress > 0 then
      occurrence = msg:getU8()
    end
    local animusBonus = msg:getU16()
    table.insert(list, { raceId = raceId, progress = progress,
                         occurrence = occurrence, animusBonus = animusBonus })
  end
  local totalAnimus = msg:getU16()
  onBestiaryOverview(raceName, list, totalAnimus)
end

function parseMonsterData(protocol, msg)
  local raceId    = msg:getU16()
  local className = msg:getString()
  local level     = msg:getU8()
  msg:getU16() -- animusMasteryBonus
  msg:getU16() -- animusMasteryPoints
  local kills        = msg:getU32()
  local firstUnlock  = msg:getU16()
  local secondUnlock = msg:getU16()
  local toUnlock     = msg:getU16()
  local stars        = msg:getU8()
  local occurrence   = msg:getU8()

  local lootCount = msg:getU8()
  local lootItems = {}
  for i = 1, lootCount do
    local itemId     = msg:getU16()
    local difficulty = msg:getU8()
    local special    = msg:getU8()
    local name = ""
    local maxCount = 0
    if itemId ~= 0 then
      name     = msg:getString()
      maxCount = msg:getU8()
    end
    table.insert(lootItems, { itemId = itemId, difficulty = difficulty,
                               name = name, maxCount = maxCount })
  end

  local charmPts = 0
  local attackMode = 0
  local healthMax = 0
  local experience = 0
  local baseSpeed = 0
  local armor = 0
  if level > 1 then
    charmPts   = msg:getU16()
    attackMode = msg:getU8()
    msg:getU8() -- unknown
    healthMax  = msg:getU32()
    experience = msg:getU32()
    baseSpeed  = msg:getU16()
    armor      = msg:getU16()
    msg:getU64() -- mitigation double
  end

  local elements = {}
  local locations = ""
  if level > 2 then
    local elemCount = msg:getU8()
    for i = 1, elemCount do
      local eId  = msg:getU8()
      local eVal = msg:getU16()
      table.insert(elements, { id = eId, value = eVal })
    end
    msg:getU16() -- unknown
    locations = msg:getString()
  end

  onBestiaryMonsterData({
    raceId = raceId, className = className, level = level,
    kills = kills, firstUnlock = firstUnlock, secondUnlock = secondUnlock,
    toUnlock = toUnlock, stars = stars, occurrence = occurrence,
    lootItems = lootItems, charmPoints = charmPts, attackMode = attackMode,
    healthMax = healthMax, experience = experience, baseSpeed = baseSpeed,
    armor = armor, elements = elements, locations = locations
  })
end

function parseCharms(protocol, msg)
  local resetCost  = msg:getU64()
  local charmCount = msg:getU8()
  local charmList  = {}
  for i = 1, charmCount do
    local id         = msg:getU8()
    local tier       = msg:getU8()
    local unlocked   = msg:getU8() > 0
    local raceId     = 0
    local removeCost = 0
    if unlocked then
      raceId     = msg:getU16()
      removeCost = msg:getU32()
    end
    table.insert(charmList, { id = id, tier = tier, unlocked = unlocked,
                               raceId = raceId, removeCost = removeCost })
  end
  local slots         = msg:getU8()
  local finishedCount = msg:getU16()
  local finished = {}
  for i = 1, finishedCount do
    table.insert(finished, msg:getU16())
  end
  onBestiaryCharms({ resetCost = resetCost, charms = charmList,
                     slots = slots, finished = finished })
end

function parseEntryChanged(protocol, msg)
  local raceId = msg:getU16()
  onBestiaryEntryChanged(raceId)
end

function parseTracker(protocol, msg)
  local trackerType = msg:getU8()
  local count = msg:getU8()
  local entries = {}
  for i = 1, count do
    local raceId   = msg:getU16()
    local kills    = msg:getU32()
    local first    = msg:getU16()
    local second   = msg:getU16()
    local toUnlock = msg:getU16()
    local progress = msg:getU8()
    table.insert(entries, { raceId = raceId, kills = kills,
                             firstUnlock = first, secondUnlock = second,
                             toUnlock = toUnlock, progress = progress })
  end
  onBestiaryTracker(entries)
end

function parseResourceBalance(protocol, msg)
  local resourceType = msg:getU8()
  local amount = msg:getU64()
  if resourceType == 1 then
    charmPoints = amount
    if bestiaryWindow and bestiaryWindow:isVisible() then
      local label = bestiaryWindow:recursiveGetChildById('charmPointsLabel')
      if label then
        label:setText(tr('Charm Points: ') .. charmPoints)
      end
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Game events
-- ─────────────────────────────────────────────────────────────────────────────

function onGameStart()
  -- nothing to pre-load; data arrives when window is opened
end

function onGameEnd()
  races = {}
  raceOrder = {}
  creatures = {}
  currentRace = nil
  currentCreatureId = nil
  charms = {}
  charmPoints = 0
  finishedMonsters = {}
  trackedMonsters = {}
  monsterData = {}
  if bestiaryWindow then
    bestiaryWindow:hide()
  end
  if bestiaryButton then
    bestiaryButton:setOn(false)
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Toggle
-- ─────────────────────────────────────────────────────────────────────────────

function toggle()
  if not g_game.isOnline() then return end

  if bestiaryWindow:isVisible() then
    bestiaryWindow:hide()
    if bestiaryButton then bestiaryButton:setOn(false) end
  else
    bestiaryWindow:show()
    bestiaryWindow:raise()
    bestiaryWindow:focus()
    if bestiaryButton then bestiaryButton:setOn(true) end
    -- Request data from server
    g_game.requestBestiaryRaces()
  end
end

function onMiniWindowClose()
  if bestiaryButton then bestiaryButton:setOn(false) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tab management
-- ─────────────────────────────────────────────────────────────────────────────

function showBestiaryTab()
  local win = bestiaryWindow
  win:recursiveGetChildById('bestiaryPanel'):show()
  win:recursiveGetChildById('charmsPanel'):hide()
  win:recursiveGetChildById('tabBestiary'):setOn(true)
  win:recursiveGetChildById('tabCharms'):setOn(false)
end

function showCharmsTab()
  local win = bestiaryWindow
  win:recursiveGetChildById('bestiaryPanel'):hide()
  win:recursiveGetChildById('charmsPanel'):show()
  win:recursiveGetChildById('tabBestiary'):setOn(false)
  win:recursiveGetChildById('tabCharms'):setOn(true)
  refreshCharmsUI()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Protocol handlers (called from game_protocol/protocol.lua)
-- ─────────────────────────────────────────────────────────────────────────────

-- 0xD5 — Race list
function onBestiaryData(raceData)
  -- raceData: list of { name, total, unlocked }
  races = {}
  raceOrder = {}
  for _, r in ipairs(raceData) do
    races[r.name] = { total = r.total, unlocked = r.unlocked }
    if r.total > 0 then
      table.insert(raceOrder, r.name)
    end
  end
  refreshRaceList()
end

-- 0xD6 — Creature overview for a race
function onBestiaryOverview(raceName, creatureList, totalAnimus)
  -- creatureList: list of { raceId, progress, occurrence, animusBonus }
  creatures = {}
  for _, c in ipairs(creatureList) do
    creatures[c.raceId] = c
  end
  currentRace = raceName
  refreshCreatureList()
end

-- 0xD7 — Full monster data
function onBestiaryMonsterData(data)
  -- data: { raceId, className, level, kills, firstUnlock, secondUnlock, toUnlock,
  --         stars, occurrence, lootItems, charmPoints, attackMode, healthMax,
  --         experience, baseSpeed, armor, elements, locations }
  monsterData[data.raceId] = data
  if currentCreatureId == data.raceId then
    refreshCreatureDetail(data.raceId)
  end
end

-- 0xD8 — Charms data
function onBestiaryCharms(data)
  -- data: { resetCost, charms=[{id,tier,unlocked,raceId,removeCost}], slots, finished=[raceIds] }
  charmResetCost = data.resetCost
  charms = {}
  for _, c in ipairs(data.charms) do
    charms[c.id] = c
  end
  charmSlots = data.slots
  finishedMonsters = data.finished

  -- If charms tab is showing, refresh it
  if bestiaryWindow:isVisible() then
    local charmsPanel = bestiaryWindow:recursiveGetChildById('charmsPanel')
    if charmsPanel:isVisible() then
      refreshCharmsUI()
    end
  end
end

-- 0xD9 — Entry changed notification (a kill count updated)
function onBestiaryEntryChanged(raceId)
  -- Invalidate cached data and refresh if this creature is selected
  monsterData[raceId] = nil
  if currentCreatureId == raceId then
    g_game.requestBestiaryMonsterData(raceId)
  end
  -- Refresh overview if this race is showing
  if currentRace then
    g_game.requestBestiaryCreatures(currentRace)
  end
  -- Refresh race list
  g_game.requestBestiaryRaces()
end

-- 0xB9 — Tracker update
function onBestiaryTracker(entries)
  -- entries: list of { raceId, kills, firstUnlock, secondUnlock, toUnlock, progress }
  trackedMonsters = {}
  for _, e in ipairs(entries) do
    trackedMonsters[e.raceId] = e
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UI refresh helpers
-- ─────────────────────────────────────────────────────────────────────────────

function refreshRaceList()
  local list = bestiaryWindow:recursiveGetChildById('raceList')
  list:destroyChildren()

  for _, name in ipairs(raceOrder) do
    local r = races[name]
    local btn = g_ui.createWidget('BestiaryRaceButton', list)
    local label = name .. ' (' .. r.unlocked .. '/' .. r.total .. ')'
    btn:setText(label)
    btn.raceName = name
    btn.onClick = function()
      currentRace = name
      currentCreatureId = nil
      clearCreatureDetail()
      g_game.requestBestiaryCreatures(name)
    end
  end
end

function refreshCreatureList()
  local list = bestiaryWindow:recursiveGetChildById('creatureList')
  list:destroyChildren()

  -- Sort by raceId
  local sorted = {}
  for raceId, c in pairs(creatures) do
    table.insert(sorted, { raceId = raceId, data = c })
  end
  table.sort(sorted, function(a, b) return a.raceId < b.raceId end)

  for _, entry in ipairs(sorted) do
    local raceId = entry.raceId
    local c = entry.data
    local btn = g_ui.createWidget('BestiaryCreatureButton', list)

    local progressStr = ""
    if c.progress == 0 then
      progressStr = " [?]"
    elseif c.progress == 1 then
      progressStr = " [I]"
    elseif c.progress == 2 then
      progressStr = " [II]"
    elseif c.progress == 3 then
      progressStr = " [III]"
    end

    -- Try to get name from cached data
    local name = "Monster " .. raceId
    if monsterData[raceId] then
      name = monsterData[raceId].name or name
    end

    btn:setText(name .. progressStr)
    btn.raceId = raceId
    btn.onClick = function()
      currentCreatureId = raceId
      if monsterData[raceId] then
        refreshCreatureDetail(raceId)
      else
        g_game.requestBestiaryMonsterData(raceId)
      end
    end
  end
end

function clearCreatureDetail()
  local detail = bestiaryWindow:recursiveGetChildById('creatureDetail')
  detail:recursiveGetChildById('detailName'):setText('')
  detail:recursiveGetChildById('detailClass'):setText('')
  detail:recursiveGetChildById('detailProgress'):setText('')
  detail:recursiveGetChildById('detailKills'):setText('')
  detail:recursiveGetChildById('detailHealth'):setText('')
  detail:recursiveGetChildById('detailExp'):setText('')
  detail:recursiveGetChildById('detailArmor'):setText('')
  detail:recursiveGetChildById('detailSpeed'):setText('')
  detail:recursiveGetChildById('detailCharmPts'):setText('')
  detail:recursiveGetChildById('detailLoot'):setText('')
  detail:recursiveGetChildById('detailElements'):setText('')
  detail:recursiveGetChildById('detailLocations'):setText('')
end

function refreshCreatureDetail(raceId)
  local data = monsterData[raceId]
  if not data then return end

  local detail = bestiaryWindow:recursiveGetChildById('creatureDetail')

  detail:recursiveGetChildById('detailName'):setText(data.name or "Unknown")
  detail:recursiveGetChildById('detailClass'):setText(data.className or "")

  -- Progress label
  local progressLabels = { [0]="No info", [1]="Stage I", [2]="Stage II", [3]="Complete" }
  local progressStr = (progressLabels[data.level] or "Stage " .. data.level)
  detail:recursiveGetChildById('detailProgress'):setText("Progress: " .. progressStr)

  -- Kill counts
  local kills = data.kills or 0
  local toUnlock = data.toUnlock or 0
  local firstUnlock = data.firstUnlock or 0
  local secondUnlock = data.secondUnlock or 0
  detail:recursiveGetChildById('detailKills'):setText(
    "Kills: " .. kills .. " / " .. toUnlock ..
    " (I:" .. firstUnlock .. " II:" .. secondUnlock .. ")")

  -- Stats (available at level > 1)
  if data.level and data.level > 1 then
    detail:recursiveGetChildById('detailHealth'):setText("HP: " .. (data.healthMax or "?"))
    detail:recursiveGetChildById('detailExp'):setText("Exp: " .. (data.experience or "?"))
    detail:recursiveGetChildById('detailArmor'):setText("Armor: " .. (data.armor or "?"))
    detail:recursiveGetChildById('detailSpeed'):setText("Speed: " .. (data.baseSpeed or "?"))
    detail:recursiveGetChildById('detailCharmPts'):setText("Charm pts: " .. (data.charmPoints or 0))
  else
    detail:recursiveGetChildById('detailHealth'):setText("HP: ???")
    detail:recursiveGetChildById('detailExp'):setText("Exp: ???")
    detail:recursiveGetChildById('detailArmor'):setText("Armor: ???")
    detail:recursiveGetChildById('detailSpeed'):setText("Speed: ???")
    detail:recursiveGetChildById('detailCharmPts'):setText("")
  end

  -- Loot
  local lootStr = "Loot:\n"
  if data.lootItems and #data.lootItems > 0 then
    local diffNames = { [0]="Always", [1]="Common", [2]="Uncommon", [3]="Rare", [4]="Very Rare" }
    for _, loot in ipairs(data.lootItems) do
      local diff = diffNames[loot.difficulty] or "?"
      lootStr = lootStr .. " " .. (loot.name or loot.itemId) .. " (" .. diff .. ")\n"
    end
  else
    lootStr = lootStr .. " (kill more to discover)"
  end
  detail:recursiveGetChildById('detailLoot'):setText(lootStr)

  -- Elements (available at level > 2)
  if data.level and data.level > 2 and data.elements then
    local elemStr = "Weaknesses:\n"
    for _, elem in ipairs(data.elements) do
      local eName = ELEMENT_NAMES[elem.id] or ("Element " .. elem.id)
      elemStr = elemStr .. " " .. eName .. ": " .. elem.value .. "%\n"
    end
    detail:recursiveGetChildById('detailElements'):setText(elemStr)
    detail:recursiveGetChildById('detailLocations'):setText("Location: " .. (data.locations or "Unknown"))
  else
    detail:recursiveGetChildById('detailElements'):setText("")
    detail:recursiveGetChildById('detailLocations'):setText("")
  end

  -- Tracker button
  local btn = detail:recursiveGetChildById('trackerBtn')
  if trackedMonsters[raceId] then
    btn:setText(tr('Untrack'))
  else
    btn:setText(tr('Track'))
  end
end

function refreshCharmsUI()
  local win = bestiaryWindow

  -- Points
  win:recursiveGetChildById('charmPointsLabel'):setText(
    tr('Charm Points: ') .. charmPoints)
  win:recursiveGetChildById('charmInfoLabel'):setText(
    tr('Slots: ') .. charmSlots .. "  |  " ..
    tr('Reset Cost: ') .. charmResetCost)

  -- Build charm list
  local list = win:recursiveGetChildById('charmList')
  list:destroyChildren()

  -- 25 charms, 0-indexed
  for i = 0, 24 do
    local c = charms[i]
    if c then
      local btn = g_ui.createWidget('BestiaryCharmButton', list)
      local name = CHARM_NAMES[i] or ("Charm " .. i)
      local status
      if c.unlocked then
        if c.raceId and c.raceId > 0 then
          status = " [Active: race " .. c.raceId .. "]"
        else
          status = " [Unlocked]"
        end
      else
        status = " [Locked]"
      end
      btn:setText(name .. " (Tier " .. c.tier .. ")" .. status)
      btn.charmId = i
      btn.charmData = c
      btn.onClick = function()
        onCharmClick(i, c)
      end
    end
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Button handlers
-- ─────────────────────────────────────────────────────────────────────────────

function onTrackerClick()
  if not currentCreatureId then return end
  local raceId = currentCreatureId

  if trackedMonsters[raceId] then
    -- Remove from tracker
    g_game.requestBestiaryTrackerStatus(raceId, false)
    trackedMonsters[raceId] = nil
  else
    -- Add to tracker
    g_game.requestBestiaryTrackerStatus(raceId, true)
    trackedMonsters[raceId] = {}
  end

  -- Refresh tracker button
  local detail = bestiaryWindow:recursiveGetChildById('creatureDetail')
  local btn = detail:recursiveGetChildById('trackerBtn')
  if trackedMonsters[raceId] then
    btn:setText(tr('Untrack'))
  else
    btn:setText(tr('Track'))
  end
end

function onCharmClick(charmId, c)
  if not c then return end

  if c.unlocked and c.raceId and c.raceId > 0 then
    -- Ask to remove (action=1)
    local dialog = displayGeneralBox(
      tr('Remove Charm'),
      tr('Remove this charm assignment? Cost: ') .. (c.removeCost or 0),
      {
        { text = tr('Remove'), callback = function()
            g_game.requestBestiaryBuyCharmRune(charmId, 1, c.raceId)
          end },
        { text = tr('Cancel') }
      },
      nil, nil, true)
  elseif c.unlocked then
    -- Assign: ask which monster
    -- For simplicity, show a text input dialog
    local dialog = displayInputBox(
      tr('Assign Charm'),
      tr('Enter race ID to assign charm to:'),
      function(raceId)
        local rid = tonumber(raceId)
        if rid then
          g_game.requestBestiaryBuyCharmRune(charmId, 0, rid)
        end
      end)
  else
    -- Buy/unlock charm
    displayGeneralBox(
      tr('Unlock Charm'),
      tr('Unlock this charm?'),
      {
        { text = tr('Unlock'), callback = function()
            g_game.requestBestiaryBuyCharmRune(charmId, 2, 0)
          end },
        { text = tr('Cancel') }
      },
      nil, nil, true)
  end
end
