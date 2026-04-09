Cyclopedia = {}
cyclopediaWindow = nil
local cyclopediaButton = nil
contentContainer = nil

local currentTab = nil

-- Tracker
trackerMiniWindow = nil
local trackerButton = nil

-- ─────────────────────────────────────────────────────────────────────────────
-- Throttled monster-data request queue
-- Sends requests in small batches to avoid flooding the server on first open.
-- ─────────────────────────────────────────────────────────────────────────────
local monsterDataQueue  = {}
local monsterQueueTimer = nil
local QUEUE_BATCH       = 2    -- requests per tick (keep concurrent load low)
local QUEUE_INTERVAL    = 150  -- ms between batches

local function flushMonsterDataQueue()
    monsterQueueTimer = nil
    if #monsterDataQueue == 0 then
        -- Queue fully drained: if a search is waiting for data, run it now
        if Cyclopedia.onSearchDataReady then
            Cyclopedia.onSearchDataReady()
        end
        return
    end

    for i = 1, math.min(QUEUE_BATCH, #monsterDataQueue) do
        g_game.requestBestiaryMonsterData(table.remove(monsterDataQueue, 1))
    end

    if #monsterDataQueue > 0 then
        if scheduleEvent then
            monsterQueueTimer = scheduleEvent(flushMonsterDataQueue, QUEUE_INTERVAL)
        else
            flushMonsterDataQueue()
        end
    end
end

-- Returns true when the monster-data queue is fully idle (nothing in-flight).
function Cyclopedia.isMonsterDataQueueEmpty()
    return #monsterDataQueue == 0 and monsterQueueTimer == nil
end

local function queueMonsterDataRequest(id)
    if Cyclopedia.monsterCache[id] then return end   -- already cached
    for _, qid in ipairs(monsterDataQueue) do        -- no duplicates
        if qid == id then return end
    end
    table.insert(monsterDataQueue, id)
    if not monsterQueueTimer then
        if scheduleEvent then
            monsterQueueTimer = scheduleEvent(flushMonsterDataQueue, QUEUE_INTERVAL)
        else
            flushMonsterDataQueue()
        end
    end
end

-- Exposed so bestiary.lua can queue IDs for search without importing internals.
function Cyclopedia.queueMonsterDataRequest(id) queueMonsterDataRequest(id) end

local function clearMonsterDataQueue()
    monsterDataQueue = {}
    if monsterQueueTimer and type(monsterQueueTimer) ~= "boolean" then
        monsterQueueTimer:cancel()
    end
    monsterQueueTimer = nil
end

-- Detect creature kills from loot messages and request fresh bestiary data.
-- The server (Eldera) does not push opcode 0xD9 on kill, so we poll on loot events.
local raceRefreshTimer = nil

local function onTextMessage(mode, text)
    -- Match "Loot of a rat:", "Loot of an ant:", "Loot of the demon:", etc.
    local name = text:match("[Ll]oot of %a+ (.-)%s*:")
    if not name or name == "" then return end

    local lower = name:lower()
    local foundId = nil
    for raceId, data in pairs(Cyclopedia.monsterCache) do
        if data.name and data.name:lower() == lower then
            foundId = raceId
            break
        end
    end

    -- Remember every creature name we've seen from loot, for better search hints
    Cyclopedia.seenCreatureNames = Cyclopedia.seenCreatureNames or {}
    Cyclopedia.seenCreatureNames[lower] = true

    if foundId then
        g_game.requestBestiaryMonsterData(foundId)
    else
        -- Creature not in cache yet (hasn't reached stage 1) — debounced race refresh
        -- to detect when a new category becomes unlocked (unlockedCount 0→1).
        if raceRefreshTimer then return end
        local function doRefresh()
            raceRefreshTimer = nil
            g_game.requestBestiaryRaces()
        end
        if scheduleEvent then
            raceRefreshTimer = scheduleEvent(doRefresh, 4000)
        else
            -- scheduleEvent unavailable: fire immediately but still gate on the timer flag
            raceRefreshTimer = true
            doRefresh()
        end
    end
end

function init()
    cyclopediaWindow = g_ui.loadUI('game_cyclopedia', rootWidget)
    if not cyclopediaWindow then
        g_logger.error('[game_cyclopedia] failed to load game_cyclopedia.otui')
        return
    end
    cyclopediaWindow:hide()
    cyclopediaWindow:centerIn(rootWidget)

    g_ui.importStyle('cyclopedia_widgets')
    g_ui.importStyle('cyclopedia_pages')

    contentContainer = cyclopediaWindow:recursiveGetChildById('contentContainer')

    connect(g_game, {
        onGameStart   = onGameStart,
        onGameEnd     = onGameEnd,
        onTextMessage = onTextMessage,
    })

    g_keyboard.bindKeyDown('Alt+B', toggle)

    -- Unregister first in case another module claimed these opcodes, then re-register
    local opcodes = {0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xB9, 0x4B}
    for _, op in ipairs(opcodes) do ProtocolGame.unregisterOpcode(op) end
    ProtocolGame.registerOpcode(0xD5, parseRaces)
    ProtocolGame.registerOpcode(0xD6, parseOverview)
    ProtocolGame.registerOpcode(0xD7, parseMonsterData)
    ProtocolGame.registerOpcode(0xD8, parseCharms)
    ProtocolGame.registerOpcode(0xD9, parseEntryChanged)
    ProtocolGame.registerOpcode(0xB9, parseTracker)
    ProtocolGame.registerOpcode(0x4B, parseResourceBalance)

    -- Connect sidebutton
    if modules.game_sidebuttons then
        cyclopediaButton = modules.game_sidebuttons.bestiaryButton
        if cyclopediaButton then
            cyclopediaButton.onClick = function() toggle() end
        end
    end

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart   = onGameStart,
        onGameEnd     = onGameEnd,
        onTextMessage = onTextMessage,
    })

    g_keyboard.unbindKeyDown('Alt+B')

    ProtocolGame.unregisterOpcode(0xD5)
    ProtocolGame.unregisterOpcode(0xD6)
    ProtocolGame.unregisterOpcode(0xD7)
    ProtocolGame.unregisterOpcode(0xD8)
    ProtocolGame.unregisterOpcode(0xD9)
    ProtocolGame.unregisterOpcode(0xB9)
    ProtocolGame.unregisterOpcode(0x4B)

    if trackerMiniWindow then
        trackerMiniWindow:destroy()
        trackerMiniWindow = nil
    end

    if cyclopediaWindow then
        cyclopediaWindow:destroy()
        cyclopediaWindow = nil
    end
end

function onGameStart()
    Cyclopedia.monsterCache     = {}
    Cyclopedia.knownCategories  = {}
    Cyclopedia.storedRaceCounts = {}
    -- Setup tracker miniwindow
    if not trackerMiniWindow then
        trackerMiniWindow = g_ui.createWidget('BestiaryTracker', modules.game_interface.getMiniWindowContainer and modules.game_interface.getMiniWindowContainer() or modules.game_interface.getRightPanel())
        if trackerMiniWindow then
            trackerMiniWindow:setup()
            trackerMiniWindow:hide()
        end
    end
end

function onGameEnd()
    Cyclopedia.monsterCache = {}
    Cyclopedia.knownCategories = {}
    Cyclopedia.seenCreatureNames = {}
    Cyclopedia.pendingSearchText = nil
    Cyclopedia.pendingSearchOriginal = nil
    Cyclopedia.pendingSearchOverviews = 0
    Cyclopedia.searchRequestedCategories = {}
    Cyclopedia.categoryCreatures = {}
    Cyclopedia.storedRaceCounts  = {}
    Cyclopedia.storedTrackerData = nil
    clearMonsterDataQueue()
    if raceRefreshTimer and type(raceRefreshTimer) ~= "boolean" then
        raceRefreshTimer:cancel()
    end
    raceRefreshTimer = nil
    if cyclopediaWindow then cyclopediaWindow:hide() end
    if cyclopediaButton then cyclopediaButton:setOn(false) end
    if trackerMiniWindow then trackerMiniWindow:hide() end
end

function toggle()
    if not g_game.isOnline() then return end
    if cyclopediaWindow:isVisible() then
        cyclopediaWindow:hide()
        if cyclopediaButton then cyclopediaButton:setOn(false) end
    else
        cyclopediaWindow:show()
        cyclopediaWindow:raise()
        cyclopediaWindow:focus()
        if cyclopediaButton then cyclopediaButton:setOn(true) end
        showTab('bestiary')
    end
end

function showTab(tabName)
    -- Unload current tab UI
    if contentContainer then
        contentContainer:destroyChildren()
    end

    -- Reset tab button states
    local tabBar = cyclopediaWindow:recursiveGetChildById('tabBar')
    if tabBar then
        for _, btn in ipairs(tabBar:getChildren()) do
            btn:setOn(false)
        end
        local btn = tabBar:recursiveGetChildById('tab' .. tabName:sub(1,1):upper() .. tabName:sub(2))
        if btn then btn:setOn(true) end
    end

    currentTab = tabName

    if tabName == 'bestiary' then
        showBestiary()
    elseif tabName == 'charms' then
        showCharms()
    end
end

function toggleTracker()
    if not trackerMiniWindow then return end
    if trackerMiniWindow:isVisible() then
        trackerMiniWindow:close()
    else
        trackerMiniWindow:open()
        Cyclopedia.refreshBestiaryTracker()
    end
end

function onTrackerClose()
    -- no-op, handled by miniwindow
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Protocol parsers
-- ─────────────────────────────────────────────────────────────────────────────

function parseRaces(protocol, msg)
    local count = msg:getU16()
    local raceData = {}
    for i = 1, count do
        local name     = msg:getString()
        local total    = msg:getU16()
        local unlocked = msg:getU16()
        table.insert(raceData, {
            bestClass       = name,
            count           = total,
            unlockedCount   = unlocked,
            AnimusMasteryBonus = 0,
        })
    end
    Cyclopedia.loadBestiaryCategories(raceData)

    Cyclopedia.knownCategories  = Cyclopedia.knownCategories or {}
    Cyclopedia.storedRaceCounts = Cyclopedia.storedRaceCounts or {}

    local windowOpen = cyclopediaWindow and cyclopediaWindow:isVisible()
    -- First-ever parseRaces for this session: storedRaceCounts is empty.
    -- In that case countRose would fire for EVERY category (all go from 0 → N),
    -- which would bulk-load all overviews on login. Suppress that by only using
    -- countRose logic once we have a previous snapshot to compare against.
    local hasPrevSnapshot = next(Cyclopedia.storedRaceCounts) ~= nil

    for _, r in ipairs(raceData) do
        local prevCount = Cyclopedia.storedRaceCounts[r.bestClass] or 0
        local countRose = hasPrevSnapshot and (r.unlockedCount > prevCount)
        local isNew     = not Cyclopedia.knownCategories[r.bestClass]
        Cyclopedia.storedRaceCounts[r.bestClass] = r.unlockedCount

        -- Fetch overview only when:
        --   a) bestiary window is open and category is unlocked+new (user just opened it)
        --   b) unlock count increased vs last snapshot (kill just happened — window may be closed)
        -- Never bulk-fetch on the first server-pushed parseRaces at login (window closed).
        if (windowOpen and r.unlockedCount > 0 and isNew) or countRose then
            g_game.requestBestiaryCreatures(r.bestClass)
        end
    end
end

function parseOverview(protocol, msg)
    local raceName = msg:getString()
    local count    = msg:getU16()
    Cyclopedia.knownCategories = Cyclopedia.knownCategories or {}
    Cyclopedia.knownCategories[raceName] = true
    Cyclopedia.categoryCreatures = Cyclopedia.categoryCreatures or {}
    local list = {}
    for i = 1, count do
        local raceId     = msg:getU16()
        local progress   = msg:getU8()
        local occurrence = 0
        if progress > 0 then occurrence = msg:getU8() end
        local animusBonus = msg:getU16()
        table.insert(list, {
            id                        = raceId,
            currentLevel              = progress,
            creatureAnimusMasteryBonus = animusBonus,
        })
    end
    local totalAnimus = msg:getU16()

    -- Record which raceIds belong to this category so search can check cache completeness.
    local ids = {}
    for _, entry in ipairs(list) do ids[#ids + 1] = entry.id end
    Cyclopedia.categoryCreatures[raceName] = ids

    -- If a search is waiting on this category, queue ALL its monster data now.
    -- Track how many search-requested overviews are still pending so we know when to run the search.
    if Cyclopedia.searchRequestedCategories and Cyclopedia.searchRequestedCategories[raceName] then
        Cyclopedia.searchRequestedCategories[raceName] = nil
        Cyclopedia.pendingSearchOverviews = (Cyclopedia.pendingSearchOverviews or 1) - 1
        for _, entry in ipairs(list) do
            queueMonsterDataRequest(entry.id)
        end
        -- If all overviews are in AND the queue is already empty (categories had 0 creatures),
        -- fire the search check immediately.
        if Cyclopedia.pendingSearchOverviews == 0 and Cyclopedia.isMonsterDataQueueEmpty() then
            if Cyclopedia.onSearchDataReady then Cyclopedia.onSearchDataReady() end
        end
    end

    -- Only update the creature list UI when this is the category the user navigated to.
    -- Monster data is fetched lazily per-page in loadBestiaryCreature, not here.
    if raceName == Cyclopedia.currentCategory then
        Cyclopedia.loadBestiaryOverview(raceName, list, totalAnimus)
    end
end

function parseMonsterData(protocol, msg)
    local raceId    = msg:getU16()
    local lookType  = msg:getU16()
    local name      = msg:getString()
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
        local itemName   = ""
        local maxCount   = 0
        if itemId ~= 0 then
            itemName = msg:getString()
            maxCount = msg:getU8()
        end
        table.insert(lootItems, {
            itemId   = itemId,
            diffculty = difficulty,  -- note: typo kept for cyclopedia compat
            name     = itemName,
            maxCount = maxCount,
            stackable = maxCount > 1 and 1 or 0,
            id       = itemId,
            type     = 0,
        })
    end

    local charmPts  = 0
    local attackMode = 0
    local healthMax  = 0
    local experience = 0
    local baseSpeed  = 0
    local armor      = 0
    if level > 1 then
        charmPts   = msg:getU16()
        attackMode = msg:getU8()
        msg:getU8()
        healthMax  = msg:getU32()
        experience = msg:getU32()
        baseSpeed  = msg:getU16()
        armor      = msg:getU16()
        msg:getU64()
    end

    -- Element resistances
    local elementsRaw = {}
    local locations = ""
    if level > 2 then
        local elemCount = msg:getU8()
        for i = 1, elemCount do
            local eId  = msg:getU8()
            local eVal = msg:getU16()
            elementsRaw[eId] = eVal
        end
        msg:getU16()
        locations = msg:getString()
    end

    -- Map our element IDs to cyclopedia's combat[1..8]:
    -- 1=Physical, 2=Fire, 3=Earth, 4=Energy, 5=Ice, 6=Holy, 7=Death, 8=Healing
    local ourToCyclopedia = { [0]=1, [1]=2, [2]=3, [3]=4 }
    local combat = {}
    for i = 1, 8 do combat[i] = 0 end
    for ourId, val in pairs(elementsRaw) do
        local idx = ourToCyclopedia[ourId]
        if idx then combat[idx] = val end
    end

    -- Update monster cache and remove from queue (prevents duplicate sends)
    Cyclopedia.monsterCache[raceId] = {
        name     = name,
        lookType = lookType,
        level    = level,
    }
    for i = #monsterDataQueue, 1, -1 do
        if monsterDataQueue[i] == raceId then
            table.remove(monsterDataQueue, i)
        end
    end

    -- Build cyclopedia-format data
    local data = {
        id                  = raceId,
        ocorrence           = occurrence,
        difficulty          = stars,
        killCounter         = kills,
        thirdDifficulty     = firstUnlock,   -- stage 1 target
        secondUnlock        = secondUnlock,  -- stage 2 target
        lastProgressKillCount = toUnlock,    -- stage 3 target (final)
        maxHealth           = healthMax,
        experience          = experience,
        speed               = baseSpeed,
        armor               = armor,
        mitigation          = 0,
        attackMode          = attackMode,
        currentLevel        = level,
        charmValue          = charmPts,
        combat              = combat,
        loot                = lootItems,
        location            = locations,
        AnimusMasteryPoints = 0,
        AnimusMasteryBonus  = 0,
    }

    -- If a search is pending and all overviews are in, check whether the queue just drained.
    if Cyclopedia.pendingSearchText and (Cyclopedia.pendingSearchOverviews or 1) == 0
            and Cyclopedia.isMonsterDataQueueEmpty() then
        if Cyclopedia.onSearchDataReady then Cyclopedia.onSearchDataReady() end
    end

    -- Route to UI: show creature view if user-requested, otherwise just cache + list refresh
    if Cyclopedia.onMonsterDataReceived then
        Cyclopedia.onMonsterDataReceived(data)
    end
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
        table.insert(charmList, {
            id           = id,
            tier         = tier,
            unlocked     = unlocked,
            raceId       = raceId,
            removeCost   = removeCost,
            removeRuneCost = removeCost,
            asignedStatus = unlocked and raceId > 0,
            unlockPrice   = 0, -- calculated from charm table
            name          = "",
            description   = "",
        })
    end
    local slots         = msg:getU8()
    local finishedCount = msg:getU16()
    local finished = {}
    for i = 1, finishedCount do
        table.insert(finished, msg:getU16())
    end

    Cyclopedia.loadCharms({
        points           = 0,  -- updated via parseResourceBalance
        resetAllCharmsCost = resetCost,
        charms           = charmList,
        finishedMonsters = finished,
        slots            = slots,
    })
end

function parseEntryChanged(protocol, msg)
    local raceId = msg:getU16()

    -- Invalidate cache
    Cyclopedia.monsterCache[raceId] = nil

    -- Refresh category counts
    g_game.requestBestiaryRaces()

    -- Refresh creature list if a category is open
    if Cyclopedia.currentCategory then
        g_game.requestBestiaryCreatures(Cyclopedia.currentCategory)
    end

    -- Refresh monster data
    g_game.requestBestiaryMonsterData(raceId)
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
        table.insert(entries, {
            raceId      = raceId,
            kills       = kills,
            firstUnlock  = first,
            secondUnlock = second,
            toUnlock    = toUnlock,
            progress    = progress,
        })
    end
    Cyclopedia.onParseCyclopediaTracker(trackerType, entries)
end

function parseResourceBalance(protocol, msg)
    local resourceType = msg:getU8()
    local amount = msg:getU64()
    if resourceType == 1 then
        -- charm points
        if cyclopediaWindow and cyclopediaWindow:isVisible() then
            local v = cyclopediaWindow:recursiveGetChildById('CharmsBase')
            if v then
                local lbl = v:recursiveGetChildById('Value')
                if lbl then lbl:setText(tostring(amount)) end
            end
        end
        if currentTab == 'charms' and contentContainer then
            local ui = contentContainer:getChildById('Cat3')
            if ui then
                ui.CharmsPoints = amount
            end
        end
    end
end

function Cyclopedia.onResourcesBalanceChange(resourceType, amount)
    -- handled by parseResourceBalance
end

function Cyclopedia.formatGold(value)
    return tostring(value)
end

function comma_value(n)
    return tostring(n)
end
