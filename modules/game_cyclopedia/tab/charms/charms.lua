local UI = nil
Cyclopedia.Charms = {}

local charms = {
    [0]  = { name="Wound",           category=1, type=1, points={240,360,1200} },
    [1]  = { name="Enflame",         category=1, type=1, points={400,600,2000} },
    [2]  = { name="Poison",          category=1, type=1, points={240,360,1200} },
    [3]  = { name="Freeze",          category=1, type=1, points={320,480,1600} },
    [4]  = { name="Zap",             category=1, type=1, points={320,480,1600} },
    [5]  = { name="Curse",           category=1, type=1, points={360,540,1800} },
    [6]  = { name="Cripple",         category=2, type=1, points={100,150,225}  },
    [7]  = { name="Parry",           category=1, type=2, points={400,600,2000} },
    [8]  = { name="Dodge",           category=1, type=2, points={240,360,1200} },
    [9]  = { name="Adrenaline Burst",category=2, type=2, points={100,150,225}  },
    [10] = { name="Numb",            category=2, type=2, points={100,150,225}  },
    [11] = { name="Cleanse",         category=2, type=2, points={100,150,225}  },
    [12] = { name="Bless",           category=2, type=3, points={100,150,225}  },
    [13] = { name="Scavenge",        category=2, type=3, points={100,150,225}  },
    [14] = { name="Gut",             category=2, type=3, points={100,150,225}  },
    [15] = { name="Low Blow",        category=1, type=3, points={800,1200,4000}},
    [16] = { name="Divine Wrath",    category=1, type=1, points={600,900,3000} },
    [17] = { name="Vampiric Embrace",category=2, type=3, points={100,150,225}  },
    [18] = { name="Void",            category=1, type=3, points={500,750,2500} },
    [19] = { name="Rune",            category=1, type=1, points={500,750,2500} },
    [20] = { name="Overpower",       category=1, type=1, points={600,900,3000} },
    [21] = { name="Absorb",          category=1, type=2, points={600,900,3000} },
    [22] = { name="Divine Caldera",  category=1, type=1, points={600,900,3000} },
    [23] = { name="Spin",            category=1, type=1, points={600,900,3000} },
    [24] = { name="Overflux",        category=1, type=1, points={600,900,3000} },
}

function showCharms()
    UI = g_ui.loadUI("charms", contentContainer)
    UI:show()
    cyclopediaWindow.bottomBar.CharmsBase:setVisible(true)
    cyclopediaWindow.bottomBar.GoldBase:setVisible(false)
    cyclopediaWindow.bottomBar.BestiaryTrackerButton:setVisible(false)
end

function Cyclopedia.loadCharms(charmsData)
    if not UI then return end

    local CharmList = UI.CharmList
    if not CharmList then return end

    -- Update charm points display
    cyclopediaWindow.bottomBar.CharmsBase.Value:setText(tostring(charmsData.points or 0))

    UI.CharmsPoints = charmsData.points or 0

    -- Build finished monsters list
    Cyclopedia.Charms.Monsters = {}
    for _, raceId in ipairs(charmsData.finishedMonsters or {}) do
        table.insert(Cyclopedia.Charms.Monsters, raceId)
    end

    CharmList:destroyChildren()

    -- Sort charms: unlocked first, then by name
    local formattedData = {}
    for _, charmData in pairs(charmsData.charms or {}) do
        local id = charmData.id
        if id ~= nil and charms[id] then
            local c = charms[id]
            charmData.name = c.name
            charmData.internalId = id
            charmData.typePriority = c.type
            charmData.category = c.category
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

function Cyclopedia.CreateCharmItem(data)
    if not UI then return end

    local widget = g_ui.createWidget("CharmItem", UI.CharmList)
    widget:setId(data.id)

    widget.charmBase.image:setImageSource("/game_cyclopedia/images/charms/monster-bonus-effects")
    widget.charmBase.image:setImageClip(string.format("%d 0 32 32", (data.id or 0) * 32))

    local charmData = charms[data.id]
    widget:setText(charmData and charmData.name or ("Charm " .. (data.id or "?")))
    widget.data = data

    -- If assigned, show creature sprite
    if data.asignedStatus and data.raceId and data.raceId > 0 then
        local raceData = Cyclopedia.getMonsterCache(data.raceId)
        if raceData.outfit.type > 0 then
            widget.InfoBase.Sprite:setOutfit(raceData.outfit)
            local sc = widget.InfoBase.Sprite:getCreature()
            if sc and sc.setStaticWalking then sc:setStaticWalking(1000) end
        end
    end

    local isUnlocked = (data.tier and data.tier > 0) or data.unlocked
    widget.charmBase.lockedMask:setVisible(not isUnlocked)

    -- Price display
    widget.PriceBase.Charm:setVisible(not isUnlocked)
    widget.PriceBase.Gold:setVisible(isUnlocked)

    if isUnlocked then
        widget.PriceBase.Value:setText(tostring(data.removeCost or 0))
    else
        local pts = charmData and charmData.points and charmData.points[1] or 0
        widget.PriceBase.Value:setText(tostring(pts))
        local canAfford = (UI.CharmsPoints or 0) >= pts
        widget.PriceBase.Value:setColor(canAfford and "#C0C0C0" or "#D33C3C")
    end
end

function Cyclopedia.selectCharm(widget, checked)
    if not UI then return end

    -- Uncheck all others
    local CharmList = UI.CharmList
    if CharmList then
        for _, child in ipairs(CharmList:getChildren()) do
            if child ~= widget then
                child:setChecked(false)
            end
        end
    end

    if not checked then
        -- Clear info panel
        Cyclopedia.clearCharmInfo()
        return
    end

    local data = widget.data
    if not data then return end

    local charmData = charms[data.id]
    Cyclopedia.showCharmInfo(data, charmData)
end

function Cyclopedia.showCharmInfo(data, charmData)
    if not UI or not UI.InformationBase then return end

    UI.InformationBase.TextBase:setText(charmData and charmData.description or "No description.")

    local isUnlocked = (data.tier and data.tier > 0) or data.unlocked
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
    if not UI or not UI.InformationBase then return end
    UI.InformationBase.TextBase:setText("")
    UI.InformationBase.UnlockButton:setEnabled(false)
    UI.InformationBase.UnlockButton:setText(tr("Select"))
end

function Cyclopedia.actionCharmButton(btn)
    local data = btn.data
    if not data then return end

    local isUnlocked = (data.tier and data.tier > 0) or data.unlocked

    if isUnlocked and data.asignedStatus and data.raceId and data.raceId > 0 then
        -- Remove charm from creature
        g_game.requestBestiaryBuyCharmRune(data.id, 1, data.raceId)
    elseif isUnlocked then
        -- Assign: show creature picker
        Cyclopedia.showCreatureCharmPicker(data)
    else
        -- Unlock charm
        g_game.requestBestiaryBuyCharmRune(data.id, 2, 0)
    end
end

function Cyclopedia.showCreatureCharmPicker(charmData)
    if not UI then return end
    local creatureList = UI.InformationBase.CreaturesBase.CreatureList
    if not creatureList then return end

    creatureList:destroyChildren()

    for _, raceId in ipairs(Cyclopedia.Charms.Monsters or {}) do
        local raceInfo = Cyclopedia.getMonsterCache(raceId)
        local btn = g_ui.createWidget('CharmCreatureName', creatureList)
        btn:setText(raceInfo.name)
        btn.raceId = raceId
        btn.charmId = charmData.id
    end
end

function Cyclopedia.selectCreatureCharm(widget, checked)
    if not checked then return end
    local raceId = widget.raceId
    local charmId = widget.charmId
    if raceId and charmId then
        g_game.requestBestiaryBuyCharmRune(charmId, 0, raceId)
    end
end
