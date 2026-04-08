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

function Cyclopedia.getMonsterCache(id)
    local c = Cyclopedia.monsterCache[id]
    if c then
        return { name = c.name, outfit = { type = c.lookType or 0 } }
    end
    return { name = "Unknown #" .. id, outfit = { type = 0 } }
end

function Cyclopedia.loadBestiaryOverview(name, creatures, totalAnimus)
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
            if isCompleted then
                bar:setImageRect({ height = 12, x = 0, y = 0, width = width })
                bar:setImageSource("/game_cyclopedia/images/bestiary/fill")
            else
                bar:setWidth(width)
                bar:setImageSource("/game_cyclopedia/images/bestiary/progressbar-orange-small")
                bar:setImageRect({})
            end
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

    if table.find(storedRaceIDs, data.id) then
        UI.ListBase.CreatureInfo.LeftBase.TrackCheck:setChecked(true)
    else
        UI.ListBase.CreatureInfo.LeftBase.TrackCheck:setChecked(false)
    end

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
    for i = 1, 8 do
        local bar = resistMap[i]
        if bar then
            local val = (data.combat and data.combat[i]) or 0
            local combat = Cyclopedia.calculateCombatValues(val)
            bar.Fill:setMarginRight(combat.margin)
            bar.Fill:setBackgroundColor(combat.color)
            bar.ValueLabel:setText(combat.label)
            bar:setTooltip(resistNames[i] .. ": " .. combat.tooltip)
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
end

function Cyclopedia.ShowBestiaryCreature()
    Cyclopedia.Bestiary.Stage = STAGES.CREATURE
    Cyclopedia.onStageChange()
end

function Cyclopedia.ShowBestiaryCreatures(Category)
    UI.ListBase.CreatureList:destroyChildren()
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
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
    widget:setText(Data.name)
    local key = Data.name:lower():gsub(" ", "_")
    local iconName = RACE_ICON_MAP[Data.name:lower()] or RACE_ICON_MAP[key] or key
    widget.ClassIcon:setImageSource("/game_cyclopedia/images/bestiary/creatures/" .. iconName)
    widget.Category = Data.name
    widget:setColor("#C0C0C0")
    widget.TotalValue:setText(string.format("Total: %d", Data.amount))
    widget.KnownValue:setText(string.format("Known: %d", Data.know))

    function widget.ClassBase:onClick()
        UI.BackPageButton:setEnabled(true)
        Cyclopedia.ShowBestiaryCreatures(self:getParent().Category)
        Cyclopedia.Bestiary.Stage = STAGES.CREATURES
        Cyclopedia.onStageChange()
    end
end

function Cyclopedia.loadBestiarySearchCreatures(data)
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

function Cyclopedia.BestiarySearch()
    local text = UI.SearchEdit:getText()
    -- Search local cache
    local list = {}
    for raceId, data in pairs(Cyclopedia.monsterCache) do
        if data.name and data.name:lower():find(text:lower(), 1, true) then
            list[#list + 1] = { id = raceId, currentLevel = data.level or 0, creatureAnimusMasteryBonus = 0 }
        end
    end
    if #list > 0 then
        Cyclopedia.loadBestiarySearchCreatures(list)
    else
        -- Request from server
        g_game.requestBestiaryCreatures("Result")
    end
    UI.SearchEdit:setText("")
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

    local stageSymbols = { [0]="—", [1]="I", [2]="II", [3]="III" }
    if data.currentLevel >= 3 then
        widget.Finalized:setVisible(true)
        widget.KillsLabel:setVisible(false)
        widget.Name:setColor("#e8c050")
    elseif data.currentLevel < 1 then
        widget.KillsLabel:setText("?")
        widget.KillsLabel:setColor("#666666")
        widget.Name:setText("?")
        widget.Name:setColor("#666666")
        widget.AnimusMastery:setVisible(false)
    else
        local sym = stageSymbols[data.currentLevel] or "?"
        widget.KillsLabel:setText(sym)
        widget.KillsLabel:setColor("#c8a030")
    end

    function widget.ClassBase:onClick()
        if data.currentLevel < 1 then return end
        UI.BackPageButton:setEnabled(true)
        g_game.requestBestiaryMonsterData(widget:getId())
        -- ShowBestiaryCreature() called from loadBestiarySelectedCreature when data arrives
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

-- Called by game_cyclopedia.lua after parseMonsterData updates the cache
function Cyclopedia.refreshCreatureListItem(raceId)
    if not UI or not UI.ListBase.CreatureList:isVisible() then return end
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
end

function Cyclopedia.loadBestiaryCreature(page, search)
    local state = search and "Search" or "Creatures"
    if not Cyclopedia.Bestiary[state] or not Cyclopedia.Bestiary[state][page] then return end

    UI.ListBase.CreatureList:destroyChildren()
    for _, data in ipairs(Cyclopedia.Bestiary[state][page]) do
        Cyclopedia.CreateBestiaryCreaturesItem(data)
        -- Request data for unknown creatures so names/sprites update automatically
        if not Cyclopedia.monsterCache[data.id] and data.currentLevel >= 1 then
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

function Cyclopedia.refreshBestiaryTracker()
    local tracker = trackerMiniWindow
    if not tracker or not tracker:isVisible() then return end

    local contents = tracker:recursiveGetChildById('contentsPanel')
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

        -- Progress bars
        local kills = entry.kills or 0
        local g1 = entry.firstUnlock or 0
        local g2 = entry.secondUnlock or 0
        local g3 = entry.toUnlock or 0
        local fit = 54
        Cyclopedia.SetBestiaryProgress(fit, btn.killsBar2, btn.ProgressBack33, btn.ProgressBack55, kills, g1, g2, g3)
    end
end
