Cyclopedia = {}
cyclopediaWindow = nil
local cyclopediaButton = nil
contentContainer = nil

local currentTab = nil

-- Tracker
trackerMiniWindow = nil
local trackerButton = nil

-- Detect creature kills from loot messages and request fresh bestiary data.
-- The server (Eldera) does not push opcode 0xD9 on kill, so we poll on loot events.
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

    if foundId then
        print("[Bestiary] kill detected '" .. name .. "' raceId=" .. foundId .. " -> requesting update")
        g_game.requestBestiaryMonsterData(foundId)
    else
        -- Creature not in cache yet (first kill) — refresh races to pick up new unlocks
        print("[Bestiary] kill detected '" .. name .. "' (not in cache) -> refreshing races")
        g_game.requestBestiaryRaces()
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
    Cyclopedia.storedTrackerData = nil
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
    print("[Bestiary] parseRaces: " .. count .. " races")
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

    -- Pre-populate search cache: request creatures for all categories that have
    -- unlocked entries, so search works without having to open each category first
    for _, r in ipairs(raceData) do
        if r.unlockedCount > 0 then
            g_game.requestBestiaryCreatures(r.bestClass)
        end
    end
end

function parseOverview(protocol, msg)
    local raceName = msg:getString()
    local count    = msg:getU16()
    print("[Bestiary] parseOverview: race='" .. raceName .. "' count=" .. count)
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

    -- Background cache population: request monster data for unlocked creatures
    -- not yet in cache (drives search functionality)
    for _, entry in ipairs(list) do
        if (entry.currentLevel or 0) >= 1 and not Cyclopedia.monsterCache[entry.id] then
            g_game.requestBestiaryMonsterData(entry.id)
        end
    end

    Cyclopedia.loadBestiaryOverview(raceName, list, totalAnimus)
end

function parseMonsterData(protocol, msg)
    local raceId    = msg:getU16()
    local lookType  = msg:getU16()
    local name      = msg:getString()
    print("[Bestiary] parseMonsterData: raceId=" .. raceId .. " name='" .. name .. "'")
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

    -- Update monster cache
    Cyclopedia.monsterCache[raceId] = {
        name     = name,
        lookType = lookType,
        level    = level,
    }

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
    print("[Bestiary] parseEntryChanged fired! raceId=" .. tostring(raceId))

    -- Invalidate cache
    Cyclopedia.monsterCache[raceId] = nil
    print("[Bestiary] cache cleared for raceId=" .. tostring(raceId))

    -- Refresh category counts
    print("[Bestiary] requesting races...")
    g_game.requestBestiaryRaces()

    -- Refresh creature list if a category is open
    if Cyclopedia.currentCategory then
        print("[Bestiary] currentCategory=" .. tostring(Cyclopedia.currentCategory) .. ", refreshing creature list")
        g_game.requestBestiaryCreatures(Cyclopedia.currentCategory)
    else
        print("[Bestiary] currentCategory is nil, no creature list refresh")
    end

    -- Refresh monster data
    print("[Bestiary] requesting monster data for raceId=" .. tostring(raceId))
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
