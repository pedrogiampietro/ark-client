local CODE_TOOLTIPS = 105

local tooltipWindow = nil
local itemSprite = nil
local itemWeightLabel = nil
local labels = nil
local hoveredItem = nil
local player = nil
local protocolGame = nil
local showingVirtual = nil
local hoveredLinked = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local cachedItems = {}

local Colors = {
    Default = "#ffffff",
    ItemLevel = "#abface",
    Description = "#8080ff",
    Implicit = "#ffbb22",
    Attribute = "#2266ff",
    Mirrored = "#22ffbb"
}

local rarityColor = {
    [0] = {name = "", color = "#ffffff"},
    [1] = {name = "Common", color = "#7b7b7b"},
    [2] = {name = "Rare", color = "#25fc19"},
    [3] = {name = "Epic", color = "#bd3ffa"},
    [4] = {name = "Legendary", color = "#ff7605"},
    [5] = {name = "Mythic", color = "#FF0000"}
}

local implicits = {
    ["ca"] = "Critical Damage",
    ["cc"] = "Critical Chance",
    ["la"] = "Life Leech",
    ["lc"] = "Life Leech Chance",
    ["ma"] = "Mana Leech",
    ["mc"] = "Mana Leech Chance",
    ["speed"] = "Movement Speed",
    ["fist"] = "Fist Fighting",
    ["sword"] = "Sword Fighting",
    ["club"] = "Club Fighting",
    ["axe"] = "Axe Fighting",
    ["dist"] = "Distance Fighting",
    ["shield"] = "Shielding",
    ["fish"] = "Fishing",
    ["mag"] = "Magic Level",
    ["a_phys"] = "Physical Protection",
    ["a_ene"] = "Energy Protection",
    ["a_earth"] = "Earth Protection",
    ["a_fire"] = "Fire Protection",
    ["a_ldrain"] = "Lifedrain Protection",
    ["a_mdrain"] = "Manadrain Protection",
    ["a_heal"] = "Healing Protection",
    ["a_drown"] = "Drown Protection",
    ["a_ice"] = "Ice Protection",
    ["a_holy"] = "Holy Protection",
    ["a_death"] = "Death Protection",
    ["a_all"] = "Protection All",
    ["hpgain"] = "HP Regeneration",
    ["hpticks"] = "HP Regen Every",
    ["mpgain"] = "MP Regeneration",
    ["mpticks"] = "MP Regen Every"
}

local impPercent = {
    ["ca"] = true,
    ["cc"] = true,
    ["la"] = true,
    ["lc"] = true,
    ["ma"] = true,
    ["mc"] = true,
    ["a_phys"] = true,
    ["a_ene"] = true,
    ["a_earth"] = true,
    ["a_fire"] = true,
    ["a_ldrain"] = true,
    ["a_mdrain"] = true,
    ["a_heal"] = true,
    ["a_drown"] = true,
    ["a_ice"] = true,
    ["a_holy"] = true,
    ["a_death"] = true,
    ["a_all"] = true
}

function init()
    connect(UIItem, {onHoverChange = onHoverChange})
    connect(g_game, {onGameEnd = resetData})

    ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

    tooltipWindow = g_ui.displayUI("item_tooltip")
    _G.tooltipWindow = tooltipWindow
    tooltipWindow:hide()

    labels = tooltipWindow:getChildById("labels")
    itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
    itemSprite = tooltipWindow:getChildById("itemSprite")

    _G.buildItemTooltip = buildItemTooltip
    _G.showItemTooltip = showItemTooltip
end

function terminate()
    disconnect(UIItem, {onHoverChange = onHoverChange})
    disconnect(g_game, {onGameEnd = resetData})

    ProtocolGame.unregisterExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

    if tooltipWindow then
        cachedItems = {}
        hoveredItem = nil
        player = nil
        protocolGame = nil
        showingVirtual = nil
        hoveredLinked = nil

        itemWeightLabel = nil
        itemSprite = nil
        labels = nil

        tooltipWindow:destroy()
        tooltipWindow = nil
    end
end

function onExtendedOpcode(protocol, code, buffer)
    local json_status, json_data = pcall(function()
        return json.decode(buffer)
    end)

    if not json_status then
        g_logger.error("Tooltips JSON error: " .. json_data)
        return
    end

    local action = json_data.action
    local data = json_data.data
    if not action or not data then
        g_logger.error("Tooltip: action or data missing in JSON")
        return
    end

    if action == "new" then newTooltip(data) end
end

function newTooltip(data)
    local _itemUId = data.uid
    local _itemName = data.itemName
    local _itemDesc = data.desc
    local _itemId = data.clientId
    local _itemLevel = data.itemLevel or 0
    local _imp = data.imp
    local _unidentified = data.unidentified
    local _mirrored = data.mirrored
    local _upgradeLevel = data.uLevel or 0
    local _uniqueName = data.uniqueName
    local _itemRarity = data.rarityId or 0
    local _itemMaxAttributes = data.maxAttr or 0
    local _itemAttributes = data.attr
    local _requiredLevel = data.reqLvl or 0

    if _itemRarity ~= 0 then
        for i = _itemMaxAttributes, 1, -1 do
            _itemAttributes[i] = _itemAttributes[i]:gsub("%%%%", "%%")
        end
    end

    local _isStackable = data.stackable
    local _itemType = data.itemType
    local _firstStat = data.armor or data.attack or 0
    local _secondStat = data.hitChance or data.defense or 0
    local _thirdStat = data.shootRange or data.extraDefense or 0
    local _weight = data.weight

    cachedItems[_itemUId] = {
        last = os.time(),
        name = _itemName,
        desc = _itemDesc,
        iLvl = _itemLevel,
        imp = _imp,
        unidentified = _unidentified,
        mirrored = _mirrored,
        uLvl = _upgradeLevel,
        uniqueName = _uniqueName,
        rarity = _itemRarity,
        maxAttributes = _itemMaxAttributes,
        attributes = _itemAttributes,
        stackable = _isStackable,
        type = _itemType,
        first = _firstStat,
        second = _secondStat,
        third = _thirdStat,
        weight = _weight,
        reqLvl = _requiredLevel,
        itemId = _itemId
    }

    if hoveredLinked and _itemUId == hoveredLinked.uid then
        hoveredLinked.cached = true
        for key, value in pairs(cachedItems[_itemUId]) do
            hoveredLinked[key] = value
        end
        buildItemTooltip(hoveredLinked:getLinkedTooltip())
        return
    end

    if hoveredItem and _itemId == hoveredItem:getId() then
        hoveredItem.uid = _itemUId
        hoveredItem.name = _itemName ..
                               (_upgradeLevel > 0 and " +" .. _upgradeLevel or
                                   "")
        hoveredItem.rarity = _itemRarity
        showTooltip(_itemUId)
    end
end

function resetData()
    cachedItems = {}
    hoveredItem = nil
    player = nil
    protocolGame = nil
    showingVirtual = nil
    hoveredLinked = nil
    tooltipWindow:hide()
end

function onHoverChange(widget, hovered)
    if not protocolGame then protocolGame = g_game.getProtocolGame() end

    if widget.getLinkedTooltip then
        hoveredLinked = widget
        if not widget.cached then
            if protocolGame then
                protocolGame:sendExtendedOpcode(CODE_TOOLTIPS,
                                                json.encode({widget.uid}))
            end
        else
            if hovered then
                showingVirtual = widget:getLinkedTooltip()
                buildItemTooltip(widget:getLinkedTooltip())
                showItemTooltip()
            else
                tooltipWindow:hide()
                showingVirtual = nil
            end
        end
        return
    end

    if not hovered then
        tooltipWindow:hide()
        hoveredItem = nil
        showingVirtual = nil
        return
    end

    player = g_game.getLocalPlayer()
    if not player then return end

    local item = widget:getItem()
    if not item then return end

    hoveredItem = item

    if not protocolGame then
        return
    end

    protocolGame:sendExtendedOpcode(
        CODE_TOOLTIPS,
        json.encode({player:getId(), item:getPosition(), item:getId(), item:getCount()})
    )
end

function buildItemTooltip(data)
    -- minimal safe stub; full visual implementation can be added as needed
    if not tooltipWindow or not labels then
        return
    end

    labels:destroyChildren()

    local nameLabel = g_ui.createWidget("Label", labels)
    nameLabel:setText(data.name or "Item")
    nameLabel:setColor(Colors.Default)
end

function showTooltip(uid)
    if not cachedItems[uid] then
        return
    end
    buildItemTooltip(cachedItems[uid])
    showItemTooltip()
end

function showItemTooltip()
    if not tooltipWindow then return end
    tooltipWindow:show()
    tooltipWindow:raise()
end

