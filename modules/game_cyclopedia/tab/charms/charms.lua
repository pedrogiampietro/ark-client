local UI = nil
local selectedCharmId = nil  -- tracks which charm is currently selected
Cyclopedia.Charms = {}

local charms = {
    [0]  = { name="Wound",            category=1, type=1, points={240,360,1200},
             description="Adds a chance to inflict a wound on the target, dealing physical damage over time." },
    [1]  = { name="Enflame",          category=1, type=1, points={400,600,2000},
             description="Adds a chance to set the target ablaze, dealing fire damage over time." },
    [2]  = { name="Poison",           category=1, type=1, points={240,360,1200},
             description="Adds a chance to poison the target, dealing earth damage over time." },
    [3]  = { name="Freeze",           category=1, type=1, points={320,480,1600},
             description="Adds a chance to freeze the target, dealing ice damage." },
    [4]  = { name="Zap",              category=1, type=1, points={320,480,1600},
             description="Adds a chance to zap the target with energy, dealing energy damage." },
    [5]  = { name="Curse",            category=1, type=1, points={360,540,1800},
             description="Adds a chance to curse the target, dealing death damage over time." },
    [6]  = { name="Cripple",          category=2, type=1, points={100,150,225},
             description="Adds a chance to cripple the target, reducing its movement speed." },
    [7]  = { name="Parry",            category=1, type=2, points={400,600,2000},
             description="Any damage taken is reflected to the aggressor with a certain chance." },
    [8]  = { name="Dodge",            category=1, type=2, points={240,360,1200},
             description="Adds a chance to dodge an incoming attack completely." },
    [9]  = { name="Adrenaline Burst", category=2, type=2, points={100,150,225},
             description="Adds a chance to gain a speed boost when taking damage from this creature." },
    [10] = { name="Numb",             category=2, type=2, points={100,150,225},
             description="Adds a chance to numb the target, reducing its attack speed." },
    [11] = { name="Cleanse",          category=2, type=2, points={100,150,225},
             description="Adds a chance to remove a negative condition when taking damage." },
    [12] = { name="Bless",            category=2, type=3, points={100,150,225},
             description="Reduces skill and experience loss upon death caused by this creature." },
    [13] = { name="Scavenge",         category=2, type=3, points={100,150,225},
             description="Increases the chance of obtaining loot from this creature." },
    [14] = { name="Gut",              category=2, type=3, points={100,150,225},
             description="Adds a chance to obtain extra loot when killing this creature." },
    [15] = { name="Low Blow",         category=1, type=3, points={800,1200,4000},
             description="Adds a chance for physical attacks to deal critical damage to this creature." },
    [16] = { name="Divine Wrath",     category=1, type=1, points={600,900,3000},
             description="Adds a chance to smite the target with holy energy." },
    [17] = { name="Vampiric Embrace", category=2, type=3, points={100,150,225},
             description="Adds a chance to drain life from the target when dealing damage." },
    [18] = { name="Void",             category=1, type=3, points={500,750,2500},
             description="Reduces mana consumption for spells cast against this creature." },
    [19] = { name="Rune",             category=1, type=1, points={500,750,2500},
             description="Increases the power of rune spells cast against this creature." },
    [20] = { name="Overpower",        category=1, type=1, points={600,900,3000},
             description="Increases physical attack damage dealt to this creature." },
    [21] = { name="Absorb",           category=1, type=2, points={600,900,3000},
             description="Adds a chance to absorb a portion of incoming damage from this creature." },
    [22] = { name="Divine Caldera",   category=1, type=1, points={600,900,3000},
             description="Deals holy area damage around the target when striking this creature." },
    [23] = { name="Spin",             category=1, type=1, points={600,900,3000},
             description="Performs a spinning attack hitting all nearby creatures on strike." },
    [24] = { name="Overflux",         category=1, type=1, points={600,900,3000},
             description="Enhances magical spell damage dealt to this creature." },
}

function showCharms()
    UI = g_ui.loadUI("charms", contentContainer)
    UI:show()
    cyclopediaWindow.bottomBar.CharmsBase:setVisible(true)
    cyclopediaWindow.bottomBar.GoldBase:setVisible(false)
    cyclopediaWindow.bottomBar.BestiaryTrackerButton:setVisible(false)

    -- Show cached data immediately if available (e.g. user already visited Bestiary)
    if Cyclopedia.storedCharmsData then
        Cyclopedia.loadCharms(Cyclopedia.storedCharmsData)
    end
    -- Always request fresh data; server responds to races request with charm data (0xD8)
    g_game.requestBestiaryRaces()
end

function Cyclopedia.loadCharms(charmsData)
    if not UI then return end

    local CharmList = UI.CharmList
    if not CharmList then return end

    -- Update charm points display
    cyclopediaWindow.bottomBar.CharmsBase.Value:setText(tostring(charmsData.points or 0))
    UI.CharmsPoints = charmsData.points or 0

    -- Build finished monsters list and pre-fetch uncached names
    Cyclopedia.Charms.Monsters = {}
    for _, raceId in ipairs(charmsData.finishedMonsters or {}) do
        table.insert(Cyclopedia.Charms.Monsters, raceId)
        if not Cyclopedia.monsterCache[raceId] then
            Cyclopedia.queueMonsterDataRequest(raceId)
        end
    end

    selectedCharmId = nil
    CharmList:destroyChildren()

    -- Sort: unlocked first, then alphabetically
    local formattedData = {}
    for _, charmData in pairs(charmsData.charms or {}) do
        local id = charmData.id
        if id ~= nil and charms[id] then
            local c = charms[id]
            charmData.name         = c.name
            charmData.internalId   = id
            charmData.typePriority = c.type
            charmData.category     = c.category
            table.insert(formattedData, charmData)
        end
    end

    table.sort(formattedData, function(a, b)
        if a.unlocked ~= b.unlocked then
            return a.unlocked and not b.unlocked
        end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    for _, value in ipairs(formattedData) do
        local ok, err = pcall(Cyclopedia.CreateCharmItem, value)
        if not ok then
            g_logger.error("Cyclopedia: error creating charm " .. tostring(value.id) .. ": " .. tostring(err))
        end
    end
end

local function deselectAllCharms()
    if not UI or not UI.CharmList then return end
    for _, child in ipairs(UI.CharmList:getChildren()) do
        child:setBorderWidth(0)
    end
end

function Cyclopedia.CreateCharmItem(data)
    if not UI then return end

    local widget = g_ui.createWidget("CharmItem", UI.CharmList)
    widget:setId(data.id)

    local charmData = charms[data.id]
    widget:setText(charmData and charmData.name or ("Charm " .. (data.id or "?")))

    -- Charm icon from sprite sheet (800x32, 25 charms × 32px)
    widget.charmBase.image:setImageSource("/game_cyclopedia/images/charms/monster-bonus-effects")
    widget.charmBase.image:setImageClip(string.format("%d 0 32 32", (data.id or 0) * 32))

    local isUnlocked = (data.tier and data.tier > 0) or data.unlocked
    widget.charmBase.lockedMask:setVisible(not isUnlocked)

    -- Price: show charm-points cost when locked, gold removal cost when unlocked
    widget.PriceBase.Charm:setVisible(not isUnlocked)
    widget.PriceBase.Gold:setVisible(isUnlocked)

    if isUnlocked then
        widget.PriceBase.Value:setText(tostring(data.removeCost or 0))
        widget.PriceBase.Value:setColor("#C0C0C0")
    else
        local pts = charmData and charmData.points and charmData.points[1] or 0
        widget.PriceBase.Value:setText(tostring(pts))
        local canAfford = (UI.CharmsPoints or 0) >= pts
        widget.PriceBase.Value:setColor(canAfford and "#C0C0C0" or "#D33C3C")
    end

    -- Click handler via closure — avoids UICheckBox state issues and widget.data lookup
    function widget:onClick()
        if not UI then return end
        if selectedCharmId == data.id then
            -- Clicking again deselects
            selectedCharmId = nil
            self:setBorderWidth(0)
            Cyclopedia.clearCharmInfo()
        else
            -- Select this charm
            deselectAllCharms()
            selectedCharmId = data.id
            self:setBorderWidth(2)
            self:setBorderColor("white")
            Cyclopedia.showCharmInfo(data, charmData)
        end
    end
end

local function clearPickerMode(btn)
    btn.pickerMode      = nil
    btn.pendingCharmId  = nil
    btn.getSelectedRace = nil
    Cyclopedia.onCharmPickerMonsterUpdate = nil
end

function Cyclopedia.showCharmInfo(data, charmData)
    if not UI or not UI.InformationBase then return end

    -- Reset picker mode when switching charm selection
    clearPickerMode(UI.InformationBase.UnlockButton)
    if UI.InformationBase.CreaturesBase and UI.InformationBase.CreaturesBase.CreatureList then
        UI.InformationBase.CreaturesBase.CreatureList:destroyChildren()
    end

    -- Description
    UI.InformationBase.TextBase:setText(charmData and charmData.description or "")

    -- Charm icon in the left panel's ItemBase
    local itemBase = UI.InformationBase.ItemBase
    if itemBase then
        itemBase.image:setImageSource("/game_cyclopedia/images/charms/monster-bonus-effects")
        itemBase.image:setImageClip(string.format("%d 0 32 32", (data.id or 0) * 32))
    end

    -- Assigned creature sprite in the left panel's InfoBase
    local infoBase = UI.InformationBase.InfoBase
    if infoBase then
        local isUnlocked = (data.tier and data.tier > 0) or data.unlocked
        if isUnlocked and data.asignedStatus and data.raceId and data.raceId > 0 then
            local raceData = Cyclopedia.getMonsterCache(data.raceId)
            infoBase.sprite:setOutfit(raceData.outfit)
            local sc = infoBase.sprite:getCreature()
            if sc and sc.setStaticWalking then sc:setStaticWalking(1000) end
        else
            infoBase.sprite:setOutfit({ type = 0 })
        end
    end

    -- Price display in info panel
    local isUnlocked = (data.tier and data.tier > 0) or data.unlocked
    local infoPrice = UI.InformationBase.PriceBase
    if infoPrice then
        if isUnlocked then
            infoPrice.Value:setText(tostring(data.removeCost or 0))
            infoPrice.Charm:setVisible(false)
            infoPrice.Gold:setVisible(true)
        else
            local pts = charmData and charmData.points and charmData.points[1] or 0
            infoPrice.Value:setText(tostring(pts))
            infoPrice.Charm:setVisible(true)
            infoPrice.Gold:setVisible(false)
        end
    end

    -- Unlock/Assign/Remove button
    UI.InformationBase.UnlockButton:setEnabled(true)
    if isUnlocked and data.asignedStatus then
        UI.InformationBase.UnlockButton:setText(tr("Remove"))
    elseif isUnlocked then
        UI.InformationBase.UnlockButton:setText(tr("Assign"))
    else
        UI.InformationBase.UnlockButton:setText(tr("Unlock"))
    end
    UI.InformationBase.UnlockButton.data = data
end

function Cyclopedia.clearCharmInfo()
    selectedCharmId = nil
    deselectAllCharms()
    if not UI or not UI.InformationBase then return end
    UI.InformationBase.TextBase:setText("")
    if UI.InformationBase.ItemBase then
        UI.InformationBase.ItemBase.image:setImageSource("")
    end
    if UI.InformationBase.InfoBase then
        UI.InformationBase.InfoBase.sprite:setOutfit({ type = 0 })
    end
    if UI.InformationBase.CreaturesBase and UI.InformationBase.CreaturesBase.CreatureList then
        UI.InformationBase.CreaturesBase.CreatureList:destroyChildren()
    end
    local btn = UI.InformationBase.UnlockButton
    clearPickerMode(btn)
    btn:setEnabled(false)
    btn:setText(tr("Select"))
    btn.data = nil
end

function Cyclopedia.actionCharmButton(btn)
    -- Phase 2: confirm assignment after creature has been selected in picker
    if btn.pickerMode then
        local raceId = btn.getSelectedRace and btn.getSelectedRace()
        if raceId then
            g_game.requestBestiaryBuyCharmRune(btn.pendingCharmId, 1, raceId)
        end
        clearPickerMode(btn)
        return
    end

    local data = btn.data
    if not data then return end

    local isUnlocked = (data.tier and data.tier > 0) or data.unlocked

    if isUnlocked and data.asignedStatus and data.raceId and data.raceId > 0 then
        g_game.requestBestiaryBuyCharmRune(data.id, 2, data.raceId)  -- action=2: remove from creature
    elseif isUnlocked then
        Cyclopedia.showCreatureCharmPicker(data)  -- phase 1: open picker, button becomes "Confirm"
    else
        g_game.requestBestiaryBuyCharmRune(data.id, 0, 0)  -- action=0: unlock/upgrade tier
    end
end

function Cyclopedia.showCreatureCharmPicker(charmData)
    if not UI then return end
    local creatureList = UI.InformationBase.CreaturesBase.CreatureList
    if not creatureList then return end

    local capturedCharmId = charmData.id
    local selectedRaceId  = nil
    local selectedWidget  = nil

    local function buildCreatureList()
        creatureList:destroyChildren()
        selectedWidget = nil

        local bg = true
        for _, raceId in ipairs(Cyclopedia.Charms.Monsters or {}) do
            local raceInfo = Cyclopedia.getMonsterCache(raceId)
            -- Skip still-unknown entries; they'll be added when the name arrives
            if raceInfo.name:sub(1, 7) ~= "Unknown" then
                local btn = g_ui.createWidget('CharmCreatureName', creatureList)
                btn:setText(raceInfo.name)
                btn:setBackgroundColor(bg and "#484848" or "#414141")
                bg = not bg

                -- Restore selection highlight if this was previously selected
                if raceId == selectedRaceId then
                    btn:setBackgroundColor("#585858")
                    selectedWidget = btn
                end

                local capturedRaceId = raceId
                function btn:onClick()
                    if selectedWidget then
                        selectedWidget:setBackgroundColor(
                            selectedWidget == btn and "#585858" or "#484848")
                    end
                    selectedRaceId = capturedRaceId
                    selectedWidget = self
                    self:setBackgroundColor("#585858")
                end
            end
        end
    end

    buildCreatureList()

    -- Live-rebuild as monster names arrive from the server
    Cyclopedia.onCharmPickerMonsterUpdate = function(updatedRaceId)
        if not UI then
            Cyclopedia.onCharmPickerMonsterUpdate = nil
            return
        end
        for _, id in ipairs(Cyclopedia.Charms.Monsters or {}) do
            if id == updatedRaceId then
                buildCreatureList()
                return
            end
        end
    end

    -- Switch button to "Confirm" mode — action is sent only when Confirm is clicked
    local btn = UI.InformationBase.UnlockButton
    btn.pickerMode      = true
    btn.pendingCharmId  = capturedCharmId
    btn.getSelectedRace = function() return selectedRaceId end
    btn:setText(tr("Confirm"))
    btn:setEnabled(true)
end

-- Called by parseResourceBalance when charm points arrive (after cards are already created)
function Cyclopedia.refreshCharmPrices(points)
    if not UI or not UI.CharmList then return end
    for _, widget in ipairs(UI.CharmList:getChildren()) do
        local data = widget.data
        if data then
            local isUnlocked = (data.tier and data.tier > 0) or data.unlocked
            if not isUnlocked then
                local charmData = charms[data.id]
                local pts = charmData and charmData.points and charmData.points[1] or 0
                widget.PriceBase.Value:setColor(points >= pts and "#C0C0C0" or "#D33C3C")
            end
        end
    end
end

function Cyclopedia.searchCharmMonster(text)
    if not UI or not UI.InformationBase then return end
    local creatureList = UI.InformationBase.CreaturesBase.CreatureList
    if not creatureList then return end

    local lower = text:lower()
    for _, child in ipairs(creatureList:getChildren()) do
        if text == "" then
            child:setVisible(true)
        else
            local name = child:getText():lower()
            child:setVisible(name:find(lower, 1, true) ~= nil)
        end
    end
end
