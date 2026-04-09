local UI = nil

local STAGES = {
    CREATURES = 2,
    SEARCH = 4,
    CATEGORY = 1,
    CREATURE = 3
}

local storedRaceIDs = {}
Cyclopedia.storedTrackerData = Cyclopedia.storedTrackerData or nil
local animusMasteryPoints = 0

-- Monster data cache: raceId -> {name, lookType, level}
Cyclopedia.monsterCache = Cyclopedia.monsterCache or {}

-- Which raceId the user explicitly clicked to view (nil = background request)
Cyclopedia.pendingViewRaceId = nil
-- Which raceId is currently shown in the creature detail view
Cyclopedia.currentViewingRaceId = nil

function Cyclopedia.getMonsterCache(id)
    local c = Cyclopedia.monsterCache[id]
    if c then
        return { name = c.name, outfit = { type = c.lookType or 0 } }
    end
    return { name = "Unknown #" .. id, outfit = { type = 0 } }
end

function Cyclopedia.loadBestiaryOverview(name, creatures, totalAnimus)
    if not UI then return end
    if (name == "Result" or name == "") and #creatures > 0 then
        if #creatures == 1 then
            g_game.requestBestiaryMonsterData(creatures[1].id)
            Cyclopedia.ShowBestiaryCreature()
        else
            Cyclopedia.loadBestiarySearchCreatures(creatures)
        end
    else
        Cyclopedia.loadBestiaryCreatures(creatures)
    end
end

function showBestiary()
    UI = g_ui.loadUI("bestiary", contentContainer)
    UI:show()

    UI.ListBase.CategoryList:setVisible(true)
    UI.ListBase.CreatureList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)

    Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
    cyclopediaWindow.bottomBar.CharmsBase:setVisible(true)
    cyclopediaWindow.bottomBar.GoldBase:setVisible(true)
    cyclopediaWindow.bottomBar.BestiaryTrackerButton:setVisible(true)

    g_keyboard.bindKeyDown('Enter', function()
        if UI and UI:isVisible() and UI.SearchEdit:getText() ~= "" then
            Cyclopedia.BestiarySearch()
        end
    end, UI.SearchEdit)

    -- Clear pending state from any previous open so stale in-flight responses
    -- don't unexpectedly switch views after the window is closed and reopened.
    Cyclopedia.pendingViewRaceId    = nil
    Cyclopedia.currentViewingRaceId = nil
    Cyclopedia.currentCategory      = nil

    g_game.requestBestiaryRaces()
end

Cyclopedia.Bestiary = {}
Cyclopedia.Bestiary.Stage = STAGES.CATEGORY

function Cyclopedia.SetBestiaryProgress(fit, firstBar, secondBar, thirdBar, killCount, firstGoal, secondGoal, thirdGoal)
    local function calculateWidth(value, max)
        return math.min(math.floor((value / max) * fit), fit)
    end

    local function setBarVisibility(bar, isVisible, width, isCompleted)
        isVisible = isVisible and width > 0
        bar:setVisible(isVisible)
        if isVisible then
            bar:setImageSource("")
            bar:setImageRect({})
            bar:setWidth(width)
            bar:setBackgroundColor(isCompleted and "#4a8c3a" or "#2d6b2d")
        end
    end

    local isCompleted = killCount >= thirdGoal
    local firstWidth = calculateWidth(math.min(killCount, firstGoal), firstGoal)
    setBarVisibility(firstBar, killCount > 0, firstWidth, isCompleted)

    local secondWidth = 0
    if killCount > firstGoal then
        secondWidth = calculateWidth(math.min(killCount - firstGoal, secondGoal - firstGoal), secondGoal - firstGoal)
    end
    setBarVisibility(secondBar, killCount > firstGoal, secondWidth, isCompleted)

    local thirdWidth = 0
    if killCount > secondGoal then
        thirdWidth = calculateWidth(math.min(killCount - secondGoal, thirdGoal - secondGoal), thirdGoal - secondGoal)
    end
    setBarVisibility(thirdBar, killCount > secondGoal, thirdWidth, isCompleted)
end

function Cyclopedia.SetBestiaryStars(value)
    local row = UI.ListBase.CreatureInfo.StarsRow
    row:destroyChildren()
    for i = 1, 5 do
        local star = g_ui.createWidget('UIWidget', row)
        star:setSize("9 10")
        local src = (i <= value)
            and "/game_cyclopedia/images/boss/icon_star_active"
            or  "/game_cyclopedia/images/boss/icon_star_inactive"
        star:setImageSource(src)
    end
end

function Cyclopedia.SetBestiaryDiamonds(value)
    local row = UI.ListBase.CreatureInfo.DiamondsRow
    row:destroyChildren()
    for i = 1, 4 do
        local diamond = g_ui.createWidget('UIWidget', row)
        diamond:setSize("9 10")
        local src = (i <= value)
            and "/game_cyclopedia/images/bestiary/icons/monster-icon-diamond-active"
            or  "/game_cyclopedia/images/bestiary/icons/monster-icon-diamond-inactive"
        diamond:setImageSource(src)
    end
end

function Cyclopedia.CreateCreatureItems(data)
    UI.ListBase.CreatureInfo.ItemsBase.Itemlist:destroyChildren()

    for index, _ in pairs(data) do
        local widget = g_ui.createWidget("BestiaryItemGroup", UI.ListBase.CreatureInfo.ItemsBase.Itemlist)
        widget:setId(index)

        local labels = { [0]="Common", [1]="Uncommon", [2]="Semi-Rare", [3]="Rare", [4]="Very Rare" }
        widget.Title:setText(tr(labels[index] or "?") .. ":")

        for i = 1, 15 do
            local item = g_ui.createWidget("BestiaryItem", widget.Items)
            item:setId(i)
        end

        for itemIndex, itemData in ipairs(data[index]) do
            local itemWidget = UI.ListBase.CreatureInfo.ItemsBase.Itemlist[index].Items[itemIndex]
            if itemWidget then
                itemWidget:setItemId(itemData.id)
                itemWidget.id = itemData.id
                if itemData.id == 0 then
                    itemWidget.undefinedItem:setVisible(true)
                end
                if itemData.stackable then
                    itemWidget.Stackable:setText("1+")
                else
                    itemWidget.Stackable:setText("1")
                end
            end
        end
    end
end

function Cyclopedia.loadBestiarySelectedCreature(data)
    if not UI then return end

    -- Switch to creature view if not already there
    if Cyclopedia.Bestiary.Stage ~= STAGES.CREATURE then
        Cyclopedia.ShowBestiaryCreature()
    end

    Cyclopedia.currentViewingRaceId = data.id

    local occurence = { [0] = 1, 2, 3, 4 }
    local raceData = Cyclopedia.getMonsterCache(data.id)

    UI.ListBase.CreatureInfo:setText(raceData.name)
    Cyclopedia.SetBestiaryDiamonds(occurence[data.ocorrence] or 1)
    Cyclopedia.SetBestiaryStars(data.difficulty or 0)
    UI.ListBase.CreatureInfo.LeftBase.Sprite:setOutfit(raceData.outfit)
    local creatureInfo = UI.ListBase.CreatureInfo.LeftBase.Sprite:getCreature()
    if creatureInfo and creatureInfo.setStaticWalking then creatureInfo:setStaticWalking(1000) end

    Cyclopedia.SetBestiaryProgress(60,
        UI.ListBase.CreatureInfo.ProgressBack,
        UI.ListBase.CreatureInfo.ProgressBack33,
        UI.ListBase.CreatureInfo.ProgressBack55,
        data.killCounter, data.thirdDifficulty, data.secondUnlock, data.lastProgressKillCount)

    UI.ListBase.CreatureInfo.ProgressValue:setText(data.killCounter)

    local fullText = data.killCounter >= data.lastProgressKillCount and "(fully unlocked)" or ""
    UI.ListBase.CreatureInfo.ProgressBorder1:setTooltip(string.format(" %d / %d %s", data.killCounter, data.thirdDifficulty, fullText))
    UI.ListBase.CreatureInfo.ProgressBorder2:setTooltip(string.format(" %d / %d %s", data.killCounter, data.secondUnlock, fullText))
    UI.ListBase.CreatureInfo.ProgressBorder3:setTooltip(string.format(" %d / %d %s", data.killCounter, data.lastProgressKillCount, fullText))

    UI.ListBase.CreatureInfo.LeftBase.TrackCheck.raceId = data.id

    -- Suppress the onCheckChange callback while we set the initial state,
    -- otherwise it would fire and send a spurious tracker request to the server.
    Cyclopedia._trackCheckSuppressed = true
    UI.ListBase.CreatureInfo.LeftBase.TrackCheck:setChecked(table.find(storedRaceIDs, data.id) ~= nil)
    Cyclopedia._trackCheckSuppressed = false

    if data.currentLevel > 1 then
        UI.ListBase.CreatureInfo.Value1:setText(data.maxHealth)
        UI.ListBase.CreatureInfo.Value2:setText(data.experience)
        UI.ListBase.CreatureInfo.Value3:setText(data.speed)
        UI.ListBase.CreatureInfo.Value4:setText(data.armor)
        UI.ListBase.CreatureInfo.Value5:setText((data.mitigation or 0) .. "%")
        UI.ListBase.CreatureInfo.BonusValue:setText(data.charmValue)
    else
        UI.ListBase.CreatureInfo.Value1:setText("?")
        UI.ListBase.CreatureInfo.Value2:setText("?")
        UI.ListBase.CreatureInfo.Value3:setText("?")
        UI.ListBase.CreatureInfo.Value4:setText("?")
        UI.ListBase.CreatureInfo.Value5:setText("?")
        UI.ListBase.CreatureInfo.BonusValue:setText("?")
    end

    -- Attack mode label (icon sprite sheet not available)
    local attackLabels = { [1]="Melee", [2]="Distance", [3]="Magic" }
    local modeText = attackLabels[data.attackMode] or ""
    UI.ListBase.CreatureInfo.SubTextLabel:setText(modeText)
    UI.ListBase.CreatureInfo.SubTextLabel:setImageSource("")

    -- Resistances: combat[1..8] = Physical, Fire, Earth, Energy, Ice, Holy, Death, Healing
    -- ColA: Physical(1), Fire(2), Earth(3), Energy(4)
    -- ColB: Ice(5), Holy(6), Death(7), Healing(8)
    local colA = UI.ListBase.CreatureInfo.ResistColA
    local colB = UI.ListBase.CreatureInfo.ResistColB
    local resistMap = {
        colA.PhysicalProgress, colA.FireProgress, colA.EarthProgress, colA.EnergyProgress,
        colB.IceProgress,      colB.HolyProgress, colB.DeathProgress, colB.HealingProgress,
    }
    local resistNames = {"Physical","Fire","Earth","Energy","Ice","Holy","Death","Healing"}
    local hasElements = data.currentLevel >= 3 and data.combat and not table.empty(data.combat)
    for i = 1, 8 do
        local bar = resistMap[i]
        if bar then
            if hasElements then
                local val = data.combat[i] or 0
                local combat = Cyclopedia.calculateCombatValues(val)
                bar.Fill:setMarginRight(combat.margin)
                bar.Fill:setBackgroundColor(combat.color)
                bar.ValueLabel:setText(combat.label)
                bar:setTooltip(resistNames[i] .. ": " .. combat.tooltip)
            else
                bar.Fill:setMarginRight(88)
                bar.Fill:setBackgroundColor("#333333")
                bar.ValueLabel:setText("?")
                bar:setTooltip(resistNames[i] .. ": " .. tr("Not yet unlocked"))
            end
        end
    end

    -- Loot
    local lootData = {}
    for _, loot in ipairs(data.loot) do
        local d = loot.diffculty or 0
        if not lootData[d] then lootData[d] = {} end
        table.insert(lootData[d], loot)
    end
    Cyclopedia.CreateCreatureItems(lootData)

    UI.ListBase.CreatureInfo.LocationField.Textlist.Text:setText(data.location or "")

    if data.AnimusMasteryPoints and data.AnimusMasteryPoints > 1 then
        UI.ListBase.CreatureInfo.AnimusMastery:setTooltip("Animus Mastery unlocked.")
        UI.ListBase.CreatureInfo.AnimusMastery:setVisible(true)
    else
        UI.ListBase.CreatureInfo.AnimusMastery:removeTooltip()
        UI.ListBase.CreatureInfo.AnimusMastery:setVisible(false)
    end

    Cyclopedia.updateBestiaryCharmSelection(data.id)
end

local charmNames = {
    [0]="Wound",[1]="Enflame",[2]="Poison",[3]="Freeze",[4]="Zap",
    [5]="Curse",[6]="Cripple",[7]="Parry",[8]="Dodge",[9]="Adrenaline",
    [10]="Numb",[11]="Cleanse",[12]="Bless",[13]="Scavenge",[14]="Gut",
    [15]="Low Blow",[16]="Divine Wrath",[17]="Vampiric",[18]="Void",
    [19]="Rune",[20]="Overpower",[21]="Absorb",[22]="Divine Caldera",
    [23]="Spin",[24]="Overflux",
}

-- ── Bestiary Charm Selection ──────────────────────────────────────────────────
-- Populates CharmSelector, CharmBase icon, SelectButton, and GoldBalance
-- for the creature currently shown in the bestiary detail view.
function Cyclopedia.updateBestiaryCharmSelection(raceId)
    if not UI then return end
    local info = UI.ListBase.CreatureInfo
    if not info then return end

    local charmSelector = info.CharmSelector
    local selectButton  = info.SelectButton
    local charmBase     = info.CharmBase
    local goldBalance   = info.BalanceBase and info.BalanceBase.GoldBalance

    if not charmSelector or not selectButton or not charmBase then return end

    local charmsData = Cyclopedia.storedCharmsData
    if not charmsData then
        -- No charm data yet — disable UI
        charmSelector:clearOptions()
        charmSelector:addOption("?")
        charmSelector:setEnabled(false)
        selectButton:setEnabled(false)
        charmBase:setImageSource("/images/ui/panel_flat")
        if goldBalance then goldBalance:setText("?") end
        return
    end

    -- Find which charm (if any) is assigned to this raceId
    local assignedCharm = nil
    for _, charm in ipairs(charmsData.charms or {}) do
        if charm.unlocked and charm.asignedStatus and charm.raceId == raceId then
            assignedCharm = charm
            break
        end
    end

    -- Build list of unlocked charms available to assign:
    -- unlocked charms that are either not assigned or assigned to THIS monster
    local available = {}
    for _, charm in ipairs(charmsData.charms or {}) do
        if charm.unlocked then
            -- Skip charms assigned to a different monster
            if not charm.asignedStatus or charm.raceId == raceId then
                table.insert(available, charm)
            end
        end
    end

    -- Populate ComboBox
    charmSelector:clearOptions()
    if #available == 0 then
        charmSelector:addOption("No unlocked charms")
        charmSelector:setEnabled(false)
    else
        charmSelector:addOption("-- Select charm --")
        for _, charm in ipairs(available) do
            local name = charmNames[charm.id] or ("Charm " .. charm.id)
            charmSelector:addOption(name, charm.id)
        end
        charmSelector:setEnabled(assignedCharm == nil) -- disable picker if one is already assigned
    end

    -- Update CharmBase icon via the static CharmIcon child (defined in otui)
    local charmIcon = charmBase:getChildById("CharmIcon")

    if assignedCharm then
        if charmIcon then
            charmIcon:setImageSource("/game_cyclopedia/images/charms/monster-bonus-effects")
            charmIcon:setImageClip(string.format("%d 0 32 32", assignedCharm.id * 32))
            charmIcon:setVisible(true)
        end
        charmBase:setTooltip(charmNames[assignedCharm.id] or ("Charm " .. assignedCharm.id))

        -- Show Remove button; label shows removal cost
        selectButton:setText(tr("Remove"))
        selectButton:setEnabled(true)
        selectButton:setColor("#D33C3C")
        if goldBalance then goldBalance:setText(tostring(assignedCharm.removeCost or 0)) end

        -- Wire Remove action
        function selectButton:onClick()
            local cd = Cyclopedia.storedCharmsData
            if not cd then return end
            for _, c in ipairs(cd.charms or {}) do
                if c.unlocked and c.asignedStatus and c.raceId == raceId then
                    g_game.requestBestiaryBuyCharmRune(c.id, 2, raceId)
                    return
                end
            end
        end
    else
        if charmIcon then charmIcon:setVisible(false) end
        charmBase:removeTooltip()

        -- Show Select button
        selectButton:setText(tr("Select"))
        selectButton:setColor("#C0C0C0")
        selectButton:setEnabled(#available > 0)
        if goldBalance then goldBalance:setText("0") end

        -- Wire Select action
        function selectButton:onClick()
            if not charmSelector then return end
            local opt = charmSelector:getCurrentOption()
            if not opt or type(opt.data) ~= "number" then return end
            g_game.requestBestiaryBuyCharmRune(opt.data, 1, raceId)
        end
    end
end

function Cyclopedia.ShowBestiaryCreature()
    if not UI then return end
    Cyclopedia.Bestiary.Stage = STAGES.CREATURE
    Cyclopedia.onStageChange()
end

function Cyclopedia.ShowBestiaryCreatures(Category)
    if not UI then return end
    UI.ListBase.CreatureList:destroyChildren()
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
    Cyclopedia.currentCategory = Category
    g_game.requestBestiaryCreatures(Category)
end

local RACE_ICON_MAP = {
    ["amphibians"]       = "amphibic",
    ["aquatics"]         = "aquatic",
    ["birds"]            = "bird",
    ["constructs"]       = "construct",
    ["demons"]           = "demon",
    ["dragons"]          = "dragon",
    ["elementals"]       = "elemental",
    ["extra dimensionals"] = "extra_dimensional",
    ["extra_dimensionals"] = "extra_dimensional",
    ["feys"]             = "fey",
    ["giants"]           = "giant",
    ["humans"]           = "human",
    ["humanoids"]        = "humanoid",
    ["lycanthropes"]     = "lycanthrope",
    ["magicals"]         = "magical",
    ["mammals"]          = "mammal",
    ["plants"]           = "plant",
    ["reptiles"]         = "reptile",
    ["slimes"]           = "slime",
    ["undeads"]          = "undead",
    ["vermins"]          = "vermin",
}

function Cyclopedia.CreateBestiaryCategoryItem(Data)
    UI.BackPageButton:setEnabled(false)

    local widget = g_ui.createWidget("BestiaryCategory", UI.ListBase.CategoryList)
    widget.NameLabel:setText(Data.name)
    local key = Data.name:lower():gsub(" ", "_")
    local iconName = RACE_ICON_MAP[Data.name:lower()] or RACE_ICON_MAP[key] or key
    widget.ClassIcon:setImageSource("/game_cyclopedia/images/bestiary/creatures/" .. iconName)
    widget.Category = Data.name
    widget.TotalValue:setText("Total: " .. Data.amount)
    widget.KnownValue:setText("Known: " .. Data.know)
    if Data.know > 0 then
        widget.KnownValue:setColor("#b8d090")
    end

    function widget.ClassBase:onClick()
        UI.BackPageButton:setEnabled(true)
        Cyclopedia.ShowBestiaryCreatures(self:getParent().Category)
        Cyclopedia.Bestiary.Stage = STAGES.CREATURES
        Cyclopedia.onStageChange()
    end
end

function Cyclopedia.loadBestiarySearchCreatures(data)
    if not UI then return end
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
    UI.BackPageButton:setEnabled(true)

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    Cyclopedia.onStageChange()
    Cyclopedia.Bestiary.Search = {}
    Cyclopedia.Bestiary.Page = 1

    local maxPerPage = 15
    Cyclopedia.Bestiary.TotalSearchPages = math.ceil(#data / maxPerPage)
    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalSearchPages))

    local page = 1
    Cyclopedia.Bestiary.Search[page] = {}

    for i = 1, #data do
        if (i - 1) % maxPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Search[page] = {}
        end
        table.insert(Cyclopedia.Bestiary.Search[page], {
            id = data[i].id,
            currentLevel = data[i].currentLevel,
            AnimusMasteryBonus = data[i].creatureAnimusMasteryBonus or 0,
        })
    end

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, true)
    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.loadBestiaryCreatures(data)
    if not UI then return end
    Cyclopedia.Bestiary.Creatures = {}
    Cyclopedia.Bestiary.Page = 1

    local maxPerPage = 15
    Cyclopedia.Bestiary.TotalCreaturesPages = math.ceil(#data / maxPerPage)
    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalCreaturesPages))

    local page = 1
    Cyclopedia.Bestiary.Creatures[page] = {}

    for i = 1, #data do
        if (i - 1) % maxPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Creatures[page] = {}
        end
        table.insert(Cyclopedia.Bestiary.Creatures[page], {
            id = data[i].id,
            currentLevel = data[i].currentLevel,
            AnimusMasteryBonus = data[i].creatureAnimusMasteryBonus or 0,
        })
    end

    Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, false)
    Cyclopedia.verifyBestiaryButtons()
end

local function searchCache(lower)
    local list = {}
    for raceId, data in pairs(Cyclopedia.monsterCache) do
        if data.name and data.name:lower():find(lower, 1, true) then
            list[#list + 1] = { id = raceId, currentLevel = data.level or 0, creatureAnimusMasteryBonus = 0 }
        end
    end
    return list
end

local function showSearchNotFound(original, lower)
    local msg = tr("No creatures found matching: ") .. original
    if Cyclopedia.seenCreatureNames and Cyclopedia.seenCreatureNames[lower] then
        msg = msg .. "\n\n" .. tr("You have killed this creature but it has not yet reached Bestiary Stage I.")
    else
        msg = msg .. "\n\n" .. tr("Creature not found in the bestiary.")
    end
    displayInfoBox(tr("Search"), msg)
end

-- Called by game_cyclopedia.lua once all pending search data has loaded.
function Cyclopedia.onSearchDataReady()
    if not Cyclopedia.pendingSearchText then return end
    if (Cyclopedia.pendingSearchOverviews or 0) > 0 then return end  -- still waiting for overviews

    local lower    = Cyclopedia.pendingSearchText
    local original = Cyclopedia.pendingSearchOriginal or lower
    Cyclopedia.pendingSearchText     = nil
    Cyclopedia.pendingSearchOriginal = nil

    if not UI then return end  -- bestiary was closed while loading

    local list = searchCache(lower)
    if #list > 0 then
        table.sort(list, function(a, b) return a.id < b.id end)
        Cyclopedia.loadBestiarySearchCreatures(list)
    else
        showSearchNotFound(original, lower)
    end
end

function Cyclopedia.BestiarySearch()
    local text = UI.SearchEdit:getText()
    if text == "" then return end
    UI.SearchEdit:setText("")

    local lower = text:lower()
    local list  = searchCache(lower)

    if #list > 0 then
        table.sort(list, function(a, b) return a.id < b.id end)
        Cyclopedia.loadBestiarySearchCreatures(list)
        return
    end

    -- Collect uncached creature IDs from categories whose overviews we already have.
    -- Do NOT re-request overviews — that would bulk-load all creatures and cause lag.
    local uncachedIds = {}
    for _, ids in pairs(Cyclopedia.categoryCreatures or {}) do
        for _, raceId in ipairs(ids) do
            if not Cyclopedia.monsterCache[raceId] then
                uncachedIds[#uncachedIds + 1] = raceId
            end
        end
    end

    if #uncachedIds == 0 then
        -- Everything known is cached and still nothing matches
        showSearchNotFound(text, lower)
        return
    end

    -- Queue only those specific IDs through the throttled queue. No new overview requests.
    Cyclopedia.pendingSearchText      = lower
    Cyclopedia.pendingSearchOriginal  = text
    Cyclopedia.pendingSearchOverviews = 0   -- no overviews pending
    Cyclopedia.searchRequestedCategories = {}
    for _, raceId in ipairs(uncachedIds) do
        Cyclopedia.queueMonsterDataRequest(raceId)
    end

    if UI and UI.PageValue then
        UI.PageValue:setText(tr("Searching..."))
    end
end

function Cyclopedia.BestiarySearchText(text)
    if text ~= "" then
        UI.SearchButton:enable(true)
    else
        UI.SearchButton:disable(false)
    end
end

function Cyclopedia.CreateBestiaryCreaturesItem(data)
    local raceData = Cyclopedia.getMonsterCache(data.id)

    local function truncate(name)
        if #name > 18 then return name:sub(1, 15) .. "..." end
        return name
    end

    local widget = g_ui.createWidget("BestiaryCreature", UI.ListBase.CreatureList)
    widget:setId(data.id)

    widget.Name:setText(truncate(raceData.name))
    widget.Sprite:setOutfit(raceData.outfit)
    local wCreature = widget.Sprite:getCreature()
    if wCreature and wCreature.setStaticWalking then wCreature:setStaticWalking(1000) end

    if data.AnimusMasteryBonus and data.AnimusMasteryBonus > 0 then
        widget.AnimusMastery:setTooltip("Animus Mastery unlocked.")
        widget.AnimusMastery:setVisible(true)
    else
        widget.AnimusMastery:removeTooltip()
        widget.AnimusMastery:setVisible(false)
    end

    if data.currentLevel >= 3 then
        widget.Finalized:setVisible(true)
        widget.KillsLabel:setVisible(false)
        widget.Name:setColor("#b8d090")
    elseif data.currentLevel < 1 then
        widget.KillsLabel:setText("0 / 3")
        widget.KillsLabel:setColor("#555555")
        widget.Name:setText("?")
        widget.Name:setColor("#555555")
        widget.AnimusMastery:setVisible(false)
    else
        widget.KillsLabel:setText(data.currentLevel .. " / 3")
        widget.KillsLabel:setColor("#b8d090")
    end

    function widget.ClassBase:onClick()
        -- Use data.id (number) — widget:getId() returns a string in OTClient,
        -- which would fail the equality check in onMonsterDataReceived.
        local id = data.id
        local cached = Cyclopedia.monsterCache[id]
        local level = cached and (cached.level or 0) or data.currentLevel
        if level < 1 then return end
        UI.BackPageButton:setEnabled(true)
        Cyclopedia.pendingViewRaceId = id
        g_game.requestBestiaryMonsterData(id)
    end
end

function Cyclopedia.loadBestiaryCategories(data)
    Cyclopedia.Bestiary.Categories = {}
    Cyclopedia.Bestiary.Page = 1

    local maxPerPage = 15
    Cyclopedia.Bestiary.TotalCategoriesPages = math.ceil(#data / maxPerPage)

    if UI == nil or UI.PageValue == nil then return end

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalCategoriesPages))

    local page = 1
    Cyclopedia.Bestiary.Categories[page] = {}

    for i = 1, #data do
        if (i - 1) % maxPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Categories[page] = {}
        end
        table.insert(Cyclopedia.Bestiary.Categories[page], {
            name = data[i].bestClass,
            amount = data[i].count,
            know = data[i].unlockedCount,
            AnimusMasteryBonus = data[i].AnimusMasteryBonus or 0,
        })
    end

    Cyclopedia.loadBestiaryCategory(Cyclopedia.Bestiary.Page)
    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.loadBestiaryCategory(page)
    if not Cyclopedia.Bestiary.Categories[page] then return end
    UI.ListBase.CategoryList:destroyChildren()
    for _, data in ipairs(Cyclopedia.Bestiary.Categories[page]) do
        Cyclopedia.CreateBestiaryCategoryItem(data)
    end
end

function Cyclopedia.onStageChange()
    Cyclopedia.Bestiary.Page = 1

    if Cyclopedia.Bestiary.Stage == STAGES.CATEGORY then
        UI.BackPageButton:setEnabled(false)
        UI.ListBase.CategoryList:setVisible(true)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(false)
    end

    if Cyclopedia.Bestiary.Stage == STAGES.CREATURES then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(true)
        UI.ListBase.CreatureInfo:setVisible(false)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
            Cyclopedia.onStageChange()
            g_game.requestBestiaryRaces()
        end
    end

    if Cyclopedia.Bestiary.Stage == STAGES.CREATURE then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(true)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CREATURES
            Cyclopedia.onStageChange()
        end
    end

    if Cyclopedia.Bestiary.Stage == STAGES.SEARCH then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(true)
        UI.ListBase.CreatureInfo:setVisible(false)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
            Cyclopedia.onStageChange()
            g_game.requestBestiaryRaces()
        end
    end
end

function Cyclopedia.verifyBestiaryButtons()
    if UI == nil then return end
    local stage = Cyclopedia.Bestiary.Stage
    local totalPages = 0
    if stage == STAGES.CATEGORY then
        totalPages = Cyclopedia.Bestiary.TotalCategoriesPages or 1
    elseif stage == STAGES.CREATURES then
        totalPages = Cyclopedia.Bestiary.TotalCreaturesPages or 1
    elseif stage == STAGES.SEARCH then
        totalPages = Cyclopedia.Bestiary.TotalSearchPages or 1
    end

    UI.NextPageButton:setEnabled(Cyclopedia.Bestiary.Page < totalPages)
    UI.PrevPageButton:setEnabled(Cyclopedia.Bestiary.Page > 1)
end

function Cyclopedia.changeBestiaryPage(prev, next)
    local stage = Cyclopedia.Bestiary.Stage
    local totalPages = 0
    if stage == STAGES.CATEGORY then
        totalPages = Cyclopedia.Bestiary.TotalCategoriesPages or 1
    elseif stage == STAGES.CREATURES then
        totalPages = Cyclopedia.Bestiary.TotalCreaturesPages or 1
    elseif stage == STAGES.SEARCH then
        totalPages = Cyclopedia.Bestiary.TotalSearchPages or 1
    end

    if prev and Cyclopedia.Bestiary.Page > 1 then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page - 1
    elseif next and Cyclopedia.Bestiary.Page < totalPages then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page + 1
    end

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, totalPages))

    if stage == STAGES.CATEGORY then
        Cyclopedia.loadBestiaryCategory(Cyclopedia.Bestiary.Page)
    elseif stage == STAGES.CREATURES then
        Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, false)
    elseif stage == STAGES.SEARCH then
        Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, true)
    end

    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.destroyBestiaryUI()
    UI = nil
end

-- Called by game_cyclopedia.lua after parseMonsterData updates the cache
function Cyclopedia.refreshCreatureListItem(raceId)
    if not UI or not UI.ListBase or not UI.ListBase.CreatureList then return end
    if not UI.ListBase.CreatureList:isVisible() then return end
    local widget = UI.ListBase.CreatureList:getChildById(raceId)
    if not widget then return end
    local raceData = Cyclopedia.getMonsterCache(raceId)
    local function truncate(name)
        if #name > 18 then return name:sub(1, 15) .. "..." end
        return name
    end
    widget.Name:setText(truncate(raceData.name))
    local outfit = raceData.outfit
    if outfit and outfit.type and outfit.type > 0 then
        widget.Sprite:setOutfit(outfit)
    end
    -- Refresh level indicators so the widget looks correct after a kill
    local cached = Cyclopedia.monsterCache[raceId]
    local level = cached and (cached.level or 0) or 0
    if level >= 3 then
        widget.Finalized:setVisible(true)
        widget.KillsLabel:setVisible(false)
        widget.Name:setColor("#b8d090")
    elseif level < 1 then
        widget.KillsLabel:setText("0 / 3")
        widget.KillsLabel:setColor("#555555")
        widget.Name:setColor("#555555")
    else
        widget.Finalized:setVisible(false)
        widget.KillsLabel:setVisible(true)
        widget.KillsLabel:setText(level .. " / 3")
        widget.KillsLabel:setColor("#b8d090")
        widget.Name:setColor("#d0d0d0")
    end
end

-- Called by game_cyclopedia.lua for every parseMonsterData response.
-- Only updates the creature view when it was user-requested (pendingViewRaceId)
-- or when the detail view is already showing this creature (live refresh after a kill).
function Cyclopedia.onMonsterDataReceived(data)
    local id = data.id

    if id == Cyclopedia.pendingViewRaceId then
        -- User clicked this creature: show the detail view
        Cyclopedia.pendingViewRaceId = nil
        Cyclopedia.loadBestiarySelectedCreature(data)
    elseif Cyclopedia.Bestiary.Stage == STAGES.CREATURE and Cyclopedia.currentViewingRaceId == id then
        -- Creature detail is already open for this id: refresh in-place (live update after kill)
        Cyclopedia.loadBestiarySelectedCreature(data)
    else
        -- Background cache fill: only refresh the creature list row if visible
        if Cyclopedia.refreshCreatureListItem then
            Cyclopedia.refreshCreatureListItem(id)
        end
    end
end

function Cyclopedia.loadBestiaryCreature(page, search)
    local state = search and "Search" or "Creatures"
    if not Cyclopedia.Bestiary[state] or not Cyclopedia.Bestiary[state][page] then return end

    UI.ListBase.CreatureList:destroyChildren()
    for _, data in ipairs(Cyclopedia.Bestiary[state][page]) do
        Cyclopedia.CreateBestiaryCreaturesItem(data)
        -- Request data for unknown creatures so names/sprites load automatically
        if not Cyclopedia.monsterCache[data.id] then
            g_game.requestBestiaryMonsterData(data.id)
        end
    end
end

function Cyclopedia.calculateCombatValues(value)
    -- inner bar width = 90 - 2 margins = 88px
    local fillWidth = math.max(2, math.floor((value / 100) * 88))
    local marginRight = 88 - fillWidth
    local color, label
    if value >= 100 then
        color = "#5555dd"  -- immune (blue)
        label = "Immune"
    elseif value >= 75 then
        color = "#44bb44"  -- resistant (green)
        label = tostring(value) .. "%"
    elseif value >= 25 then
        color = "#bbaa22"  -- neutral (yellow)
        label = tostring(value) .. "%"
    elseif value > 0 then
        color = "#cc4444"  -- weak (red)
        label = tostring(value) .. "%"
    else
        color = "#882222"  -- very weak/0 (dark red)
        label = "0%"
    end
    return {
        margin  = marginRight,
        color   = color,
        label   = label,
        tooltip = string.format("%d%%", value)
    }
end

-- Tracker functions

-- Called by the TrackCheck checkbox. Uses a suppression flag so programmatic
-- setChecked() calls (from loadBestiarySelectedCreature) don't send requests.
-- Also does an optimistic local update so subsequent UI refreshes read the new state.
function Cyclopedia.onTrackCheckChange(widget, checked)
    if Cyclopedia._trackCheckSuppressed then return end
    local raceId = widget.raceId
    if not raceId then return end

    if checked then
        -- Optimistic add to storedRaceIDs
        if not table.find(storedRaceIDs, raceId) then
            table.insert(storedRaceIDs, raceId)
        end
        -- Optimistic add to storedTrackerData (server will overwrite with real kill goals)
        if Cyclopedia.storedTrackerData then
            local found = false
            for _, entry in ipairs(Cyclopedia.storedTrackerData) do
                if entry.raceId == raceId then found = true; break end
            end
            if not found then
                table.insert(Cyclopedia.storedTrackerData, {
                    raceId = raceId, kills = 0,
                    firstUnlock = 0, secondUnlock = 0, toUnlock = 0
                })
            end
        end
    else
        -- Optimistic remove from storedRaceIDs
        for i = #storedRaceIDs, 1, -1 do
            if storedRaceIDs[i] == raceId then table.remove(storedRaceIDs, i) end
        end
        -- Optimistic remove from storedTrackerData
        if Cyclopedia.storedTrackerData then
            for i = #Cyclopedia.storedTrackerData, 1, -1 do
                if Cyclopedia.storedTrackerData[i].raceId == raceId then
                    table.remove(Cyclopedia.storedTrackerData, i)
                end
            end
        end
    end

    g_game.requestBestiaryTrackerStatus(raceId, checked)
    Cyclopedia.refreshBestiaryTracker()
end

function Cyclopedia.initializeTrackerData()
    storedRaceIDs = {}
    if Cyclopedia.storedTrackerData then
        for _, entry in ipairs(Cyclopedia.storedTrackerData) do
            table.insert(storedRaceIDs, entry.raceId)
        end
    end
end

function Cyclopedia.ensureStoredRaceIDsPopulated()
    if #storedRaceIDs == 0 and Cyclopedia.storedTrackerData then
        Cyclopedia.initializeTrackerData()
    end
end

function Cyclopedia.onParseCyclopediaTracker(trackerType, entries)
    Cyclopedia.storedTrackerData = entries
    Cyclopedia.initializeTrackerData()
    Cyclopedia.refreshBestiaryTracker()
end

-- Active tab: 'bestiary' or 'charms'
local trackerActiveTab = 'bestiary'

function Cyclopedia.showTrackerTab(tab)
    trackerActiveTab = tab
    local tracker = trackerMiniWindow
    if not tracker then return end

    local tabBestiary = tracker:recursiveGetChildById('tabBestiary')
    local tabCharms   = tracker:recursiveGetChildById('tabCharms')
    local contents    = tracker:recursiveGetChildById('contentsPanel')
    local analyzer    = tracker:recursiveGetChildById('charmAnalyzerPanel')

    if tabBestiary then tabBestiary:setOn(tab == 'bestiary') end
    if tabCharms   then tabCharms:setOn(tab == 'charms') end
    if contents    then contents:setVisible(tab == 'bestiary') end
    if analyzer    then analyzer:setVisible(tab == 'charms') end

    if tab == 'bestiary' then
        if analyzerTimer then analyzerTimer:cancel() analyzerTimer = nil end
        Cyclopedia.refreshBestiaryTracker()
    else
        Cyclopedia.refreshCharmAnalyzer()
    end
end

function Cyclopedia.refreshBestiaryTracker()
    local tracker = trackerMiniWindow
    if not tracker or not tracker:isVisible() then return end
    if trackerActiveTab ~= 'bestiary' then return end

    -- Activate bestiary tab visually
    local tabBestiary = tracker:recursiveGetChildById('tabBestiary')
    local tabCharms   = tracker:recursiveGetChildById('tabCharms')
    local contents    = tracker:recursiveGetChildById('contentsPanel')
    local analyzer    = tracker:recursiveGetChildById('charmAnalyzerPanel')
    if tabBestiary then tabBestiary:setOn(true) end
    if tabCharms   then tabCharms:setOn(false) end
    if contents    then contents:setVisible(true) end
    if analyzer    then analyzer:setVisible(false) end

    if not contents then return end
    contents:destroyChildren()

    if not Cyclopedia.storedTrackerData then return end

    for _, entry in ipairs(Cyclopedia.storedTrackerData) do
        local btn = g_ui.createWidget('TrackerButton', contents)
        local raceData = Cyclopedia.getMonsterCache(entry.raceId)
        btn.creature:setOutfit(raceData.outfit)
        local tc = btn.creature:getCreature()
        if tc and tc.setStaticWalking then tc:setStaticWalking(1000) end
        btn.label:setText(raceData.name)
        btn.kills:setText(tostring(entry.kills))

        local kills = entry.kills or 0
        local g1 = entry.firstUnlock or 0
        local g2 = entry.secondUnlock or 0
        local g3 = entry.toUnlock or 0
        Cyclopedia.SetBestiaryProgress(54, btn.killsBar2, btn.ProgressBack33, btn.ProgressBack55, kills, g1, g2, g3)
    end
end

local analyzerTimer = nil

local function formatTime(secs)
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%02d:%02d", m, s)
end

function Cyclopedia.refreshCharmAnalyzer()
    local tracker = trackerMiniWindow
    if not tracker or not tracker:isVisible() then return end

    local analyzer    = tracker:recursiveGetChildById('charmAnalyzerPanel')
    local sessionLbl  = tracker:recursiveGetChildById('sessionLabel')
    local analyzerList = tracker:recursiveGetChildById('analyzerList')
    if not analyzer then return end

    -- Session time
    local elapsed = Cyclopedia.charmAnalyzerStart and (os.time() - Cyclopedia.charmAnalyzerStart) or 0
    if sessionLbl then
        sessionLbl:setText('Session: ' .. formatTime(elapsed))
    end

    if not analyzerList then return end
    analyzerList:destroyChildren()

    local hasData = false
    for charmId, data in pairs(Cyclopedia.charmProcData) do
        hasData = true
        local row = g_ui.createWidget('CharmProcRow', analyzerList)
        -- Charm icon
        row.icon:setImageSource('/game_cyclopedia/images/charms/monster-bonus-effects')
        row.icon:setImageClip(string.format('%d 0 20 20', charmId * 32))
        row.charmName:setText(charmNames[charmId] or ('Charm ' .. charmId))
        row.procCount:setText('x' .. data.procs)
        row.totalDmg:setText(tostring(data.totalDamage) .. ' dmg')
    end

    if not hasData then
        local lbl = g_ui.createWidget('Label', analyzerList)
        lbl:setText('No procs recorded yet.')
        lbl:setColor('#808080')
    end

    -- Schedule next tick while visible and on charms tab
    if analyzerTimer then analyzerTimer:cancel() analyzerTimer = nil end
    if tracker:isVisible() and trackerActiveTab == 'charms' and Cyclopedia.charmAnalyzerStart then
        analyzerTimer = scheduleEvent(Cyclopedia.refreshCharmAnalyzer, 1000)
    end
end
