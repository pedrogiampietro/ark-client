local CODE_TOOLTIPS = 105

local tooltipWindow = nil
local tooltipHeader = nil
local itemSprite = nil
local itemWeightLabel = nil
local itemNameLabel = nil
local itemTypeLabel = nil
local labels = nil
local hoveredItem = nil
local player = nil
local protocolGame = nil
local showingVirtual = nil
local hoveredLinked = nil

local HEADER_HEIGHT = 56
local BASE_WIDTH = 170
local BASE_HEIGHT = HEADER_HEIGHT

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local cachedItems = {}

local Colors = {
    Default     = "#ffffff",
    ItemLevel   = "#abface",
    Description = "#8080ff",
    Implicit    = "#ffbb22",
    Attribute   = "#2266ff",
    Mirrored    = "#22ffbb"
}

local rarityColor = {
    [0] = {name = "",          color = "#ffffff"},
    [1] = {name = "Common",    color = "#7b7b7b"},
    [2] = {name = "Rare",      color = "#25fc19"},
    [3] = {name = "Epic",      color = "#bd3ffa"},
    [4] = {name = "Legendary", color = "#ff7605"},
    [5] = {name = "Mythic",    color = "#FF0000"}
}

local rarityHeaderBg = {
    [0] = "#141414",
    [1] = "#141414",
    [2] = "#061a06",
    [3] = "#0d0619",
    [4] = "#1f0d00",
    [5] = "#190303"
}

local rarityBorderColor = {
    [0] = "#444444",
    [1] = "#555555",
    [2] = "#1a6b1a",
    [3] = "#5a1f9c",
    [4] = "#9c4c00",
    [5] = "#9c1010"
}

local implicits = {
    ["ca"]       = "Critical Damage",
    ["cc"]       = "Critical Chance",
    ["la"]       = "Life Leech",
    ["lc"]       = "Life Leech Chance",
    ["ma"]       = "Mana Leech",
    ["mc"]       = "Mana Leech Chance",
    ["speed"]    = "Movement Speed",
    ["fist"]     = "Fist Fighting",
    ["sword"]    = "Sword Fighting",
    ["club"]     = "Club Fighting",
    ["axe"]      = "Axe Fighting",
    ["dist"]     = "Distance Fighting",
    ["shield"]   = "Shielding",
    ["fish"]     = "Fishing",
    ["mag"]      = "Magic Level",
    ["a_phys"]   = "Physical Protection",
    ["a_ene"]    = "Energy Protection",
    ["a_earth"]  = "Earth Protection",
    ["a_fire"]   = "Fire Protection",
    ["a_ldrain"] = "Lifedrain Protection",
    ["a_mdrain"] = "Manadrain Protection",
    ["a_heal"]   = "Healing Protection",
    ["a_drown"]  = "Drown Protection",
    ["a_ice"]    = "Ice Protection",
    ["a_holy"]   = "Holy Protection",
    ["a_death"]  = "Death Protection",
    ["a_all"]    = "Protection All",
    ["hpgain"]   = "HP Regeneration",
    ["hpticks"]  = "HP Regen Every",
    ["mpgain"]   = "MP Regeneration",
    ["mpticks"]  = "MP Regen Every"
}

local impPercent = {
    ["ca"] = true,
    ["cc"] = true,
    ["la"] = true,
    ["lc"] = true,
    ["ma"] = true,
    ["mc"] = true,
    ["a_phys"]   = true,
    ["a_ene"]    = true,
    ["a_earth"]  = true,
    ["a_fire"]   = true,
    ["a_ldrain"] = true,
    ["a_mdrain"] = true,
    ["a_heal"]   = true,
    ["a_drown"]  = true,
    ["a_ice"]    = true,
    ["a_holy"]   = true,
    ["a_death"]  = true,
    ["a_all"]    = true
}

function init()
    connect(UIItem, {onHoverChange = onHoverChange})
    connect(g_game, {onGameEnd = resetData})

    ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

    tooltipWindow = g_ui.displayUI("item_tooltip")
    _G.tooltipWindow = tooltipWindow
    tooltipWindow:hide()

    -- All widgets are direct children of the root FlatPanel (same as chimera)
    tooltipHeader   = tooltipWindow:getChildById("tooltipHeader")
    labels          = tooltipWindow:getChildById("labels")
    itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
    itemNameLabel   = tooltipWindow:getChildById("itemNameLabel")
    itemTypeLabel   = tooltipWindow:getChildById("itemTypeLabel")
    itemSprite      = tooltipWindow:getChildById("itemSprite")

    _G.buildItemTooltip = buildItemTooltip
    _G.showItemTooltip = showItemTooltip
end

function terminate()
    disconnect(UIItem, {onHoverChange = onHoverChange})
    disconnect(g_game, {onGameEnd = resetData})

    ProtocolGame.unregisterExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

    if tooltipWindow then
        cachedItems     = {}
        hoveredItem     = nil
        player          = nil
        protocolGame    = nil
        showingVirtual  = nil
        hoveredLinked   = nil

        itemWeightLabel = nil
        itemNameLabel   = nil
        itemTypeLabel   = nil
        itemSprite      = nil
        tooltipHeader   = nil
        labels          = nil

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
        g_logger.error("Tooltip: action ou data não encontrados no JSON")
        return
    end

    g_logger.info("[TIP] opcode received action=" .. tostring(action))
    if action == "new" then newTooltip(data) end
end

function newTooltip(data)
    local _itemUId        = data.uid
    local _itemName       = data.itemName
    local _itemDesc       = data.desc
    local _itemId         = data.clientId
    local _itemLevel      = data.itemLevel or 0
    local _imp            = data.imp
    local _unidentified   = data.unidentified
    local _mirrored       = data.mirrored
    local _upgradeLevel   = data.uLevel or 0
    local _uniqueName     = data.uniqueName
    local _itemRarity     = data.rarityId or 0
    local _itemMaxAttributes = data.maxAttr or 0
    local _itemAttributes = data.attr
    local _requiredLevel  = data.reqLvl or 0

    if _itemRarity ~= 0 then
        for i = _itemMaxAttributes, 1, -1 do
            _itemAttributes[i] = _itemAttributes[i]:gsub("%%%%", "%%")
        end
    end
    local _isStackable = data.stackable
    local _itemType    = data.itemType
    local _firstStat   = data.armor or data.attack or 0
    local _secondStat  = data.hitChance or data.defense or 0
    local _thirdStat   = data.shootRange or data.extraDefense or 0
    local _weight      = data.weight

    cachedItems[_itemUId] = {
        last          = os.time(),
        name          = _itemName,
        desc          = _itemDesc,
        iLvl          = _itemLevel,
        imp           = _imp,
        unidentified  = _unidentified,
        mirrored      = _mirrored,
        uLvl          = _upgradeLevel,
        uniqueName    = _uniqueName,
        rarity        = _itemRarity,
        maxAttributes = _itemMaxAttributes,
        attributes    = _itemAttributes,
        stackable     = _isStackable,
        type          = _itemType,
        first         = _firstStat,
        second        = _secondStat,
        third         = _thirdStat,
        weight        = _weight,
        reqLvl        = _requiredLevel,
        itemId        = _itemId
    }

    if hoveredLinked and _itemUId == hoveredLinked.uid then
        hoveredLinked.cached = true
        for key, value in pairs(cachedItems[_itemUId]) do
            hoveredLinked[key] = value
        end
        buildItemTooltip(hoveredLinked:getLinkedTooltip())
        return
    end

    g_logger.info("[TIP] newTooltip _itemId=" .. tostring(_itemId) ..
        " hoveredItem=" .. tostring(hoveredItem) ..
        " hoveredItem:getId()=" .. tostring(hoveredItem and hoveredItem:getId()))

    if hoveredItem and _itemId == hoveredItem:getId() then
        hoveredItem.uid    = _itemUId
        hoveredItem.name   = _itemName ..
            (_upgradeLevel > 0 and " +" .. _upgradeLevel or "")
        hoveredItem.rarity = _itemRarity
        g_logger.info("[TIP] calling showTooltip uid=" .. tostring(_itemUId))
        showTooltip(_itemUId)
    else
        g_logger.info("[TIP] ID mismatch or hoveredItem nil — not showing")
    end
end

function resetData()
    cachedItems    = {}
    hoveredItem    = nil
    player         = nil
    protocolGame   = nil
    showingVirtual = nil
    hoveredLinked  = nil
    tooltipWindow:hide()
end

function onHoverChange(widget, hovered)
    g_logger.info("[TIP] onHoverChange hovered=" .. tostring(hovered) .. " id=" .. tostring(widget:getId()))

    if not protocolGame then protocolGame = g_game.getProtocolGame() end

    if widget.getLinkedTooltip then
        g_logger.info("[TIP] has getLinkedTooltip, returning")
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

    local item = widget:getItem()
    g_logger.info("[TIP] item=" .. tostring(item) .. " getItemTooltip=" .. tostring(widget.getItemTooltip) .. " isVirtual=" .. tostring(widget:isVirtual()))

    if item and widget.getItemTooltip then
        g_logger.info("[TIP] has getItemTooltip, building")
        if hovered then
            buildItemTooltip(widget:getItemTooltip())
            showItemTooltip()
        else
            tooltipWindow:hide()
        end
        return
    end
    if not item or widget:getId() == "containerItemWidget" or widget:isVirtual() then
        g_logger.info("[TIP] early return: no item or containerItemWidget or virtual")
        return
    end

    if player == nil then player = g_game.getLocalPlayer() end

    if hovered then
        hoveredItem = item
        if protocolGame then
            local pos = item:getPosition()
            g_logger.info("[TIP] sending opcode pos=" .. pos.x .. "," .. pos.y .. "," .. pos.z)
            protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({
                pos.x, pos.y, pos.z, item:getStackPos()
            }))
        else
            g_logger.error("Tooltip: protocolGame é nil")
        end
    else
        hoveredItem = nil
        tooltipWindow:hide()
    end
end

function showTooltip(uid)
    local cachedItem = cachedItems[uid]

    cachedItem.id    = hoveredItem:getId()
    cachedItem.count = hoveredItem:getCount()

    buildItemTooltip(cachedItem)
    showItemTooltip()
end

function buildItemTooltip(item)
    if not tooltipWindow then
        g_logger.error("tooltipWindow is nil in buildItemTooltip")
        return
    end
    if not labels then
        g_logger.error("labels is nil in buildItemTooltip")
        return
    end

    tooltipWidth     = 0
    longestString    = 0
    tooltipWidthBase = BASE_WIDTH
    tooltipHeight    = BASE_HEIGHT
    tooltipWindow:setWidth(tooltipWidth)
    tooltipWindow:setHeight(tooltipHeight)

    labels:destroyChildren()

    local id            = item.id
    local name          = item.name
    local desc          = item.desc
    local iLvl          = item.iLvl
    local reqLvl        = item.reqLvl or 0
    local unidentified  = item.unidentified
    local mirrored      = item.mirrored
    local rarity        = tonumber(item.rarity) or 0
    local maxAttributes = item.maxAttributes
    local attributes    = item.attributes
    local count         = item.count
    local type          = item.type
    local first         = item.first
    local second        = item.second
    local third         = item.third
    local weight        = item.weight

    -- Header colour from rarity
    if tooltipHeader then
        tooltipHeader:setBackgroundColor(rarityHeaderBg[rarity] or rarityHeaderBg[0])
    end
    tooltipWindow:setBorderColor(rarityBorderColor[rarity] or rarityBorderColor[0])
    tooltipWindow:setBorderWidth(1)

    -- Rarity frame image (kept from original)
    local src = nil
    if rarity == 1 then src = "/images/ui/rarity_white"
    elseif rarity == 2 then src = "/images/ui/rarity_blue"
    elseif rarity == 3 then src = "/images/ui/rarity_purple"
    elseif rarity == 4 then src = "/images/ui/rarity_gold"
    elseif rarity == 5 then src = "/images/ui/rarity_red"
    end
    tooltipWindow.currentRaritySrc = src

    itemWeightLabel:setText(formatWeight(weight))

    itemSprite:setItemId(id)
    itemSprite:setItemCount(count)

    -- Name colour
    local itemNameColor
    if unidentified then
        itemNameColor = rarityColor[1].color
    elseif item.uniqueName then
        itemNameColor = "#dca01e"
    elseif rarity > 1 and rarityColor[rarity] then
        itemNameColor = rarityColor[rarity].color
    else
        itemNameColor = "#ffffff"
    end

    name = name:gsub("(%a)(%a+)", function(a, b)
        return string.upper(a) .. string.lower(b)
    end)
    name = name:gsub("^a ", ""):gsub("^an ", "")
    if item.uLvl > 0 then name = name .. " +" .. item.uLvl end

    -- Build display name
    local displayName
    if unidentified then
        displayName = "Unidentified " .. name
    elseif item.uniqueName and item.uniqueName ~= "" then
        displayName = item.uniqueName .. " " .. name
    elseif rarity > 1 and rarityColor[rarity] then
        displayName = rarityColor[rarity].name .. " " .. name
    else
        displayName = name
    end

    -- Set name directly in header label (no addString for name)
    if itemNameLabel then
        itemNameLabel:setText(displayName)
        itemNameLabel:setColor(itemNameColor)
    end

    -- Set type label
    if itemTypeLabel then
        itemTypeLabel:setText(type or "")
    end

    -- Body content (same logic as chimera) ──────────────────────────────────

    if iLvl > 0 then addString("Item Level " .. iLvl, Colors.ItemLevel) end

    local firstText, secondText, thirdText
    if (type == "Armor" or type == "Helmet" or type == "Legs" or type == "Ring" or
        type == "Necklace" or type == "Boots") and first ~= 0 then
        firstText = "Armor: " .. first
    elseif type == "Two-Handed Sword" or type == "Two-Handed Club" or type ==
        "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or
        type == "Fist" or type == "Distance" or type == "Ammunition" then
        firstText = "Attack: " .. first
    elseif type == "Shield" then
        firstText = "Defense: " .. second
    end

    if type == "Two-Handed Sword" or type == "Two-Handed Club" or type ==
        "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or
        type == "Fist" then
        secondText = "Defense: " .. second
    elseif type == "Distance" then
        secondText = "Hit Chance: +" .. second .. "%"
    end

    if type == "Two-Handed Sword" or type == "Two-Handed Club" or type ==
        "Two-Handed Axe" or type == "Sword" or type == "Club" or type == "Axe" or
        type == "Fist" then
        thirdText = "Extra-Defense: " .. third
    elseif type == "Distance" then
        thirdText = "Shoot Range: " .. third
    end

    if reqLvl > 0 then
        addString("Required Level " .. reqLvl, Colors.ItemLevel)
    end

    if (firstText and (type == "Shield" or type == "Ring" or type == "Necklace")) or
        (first ~= 0 and second == 0 and third == 0) then
        addSeparator()
        addEmpty(5)
        addString(firstText, Colors.Default)
    elseif first ~= 0 and second ~= 0 and third == 0 then
        addSeparator()
        addEmpty(5)
        addString(firstText, Colors.Default)
        addString(secondText, Colors.Default)
    elseif first ~= 0 and second ~= 0 and third ~= 0 or type == "Distance" then
        addSeparator()
        addEmpty(5)
        addString(firstText, Colors.Default)
        addString(secondText, Colors.Default)
        addString(thirdText, Colors.Default)
    end

    if item.imp then
        if first ~= 0 or second ~= 0 or third ~= 0 or item.rarity ~= 0 then
            addSeparator()
            addEmpty(5)
        end

        for key, value in pairs(item.imp) do
            local impText
            if not implicits[key] then
                impText = value
            else
                local formattedValue = value
                local suffix = impPercent[key] and "%" or ""

                if key == "hpticks" or key == "mpticks" then
                    formattedValue = value / 1000
                    suffix = "s"
                end

                impText = implicits[key] .. " " .. (value > 0 and "+" or "") ..
                              formattedValue .. suffix
            end
            addString(impText, Colors.Implicit)
        end
    end

    if item.rarity ~= 0 then
        addSeparator()
        addEmpty(5)
        for i = 1, maxAttributes do
            addString(attributes[i], Colors.Attribute)
        end
    end

    if mirrored then
        addEmpty(5)
        addString("Mirrored", Colors.Mirrored)
    end

    if desc and desc:len() > 0 then
        addEmpty(5)
        addString(desc, Colors.Description, true)
    end

    shrinkSeparators()

    -- Set tooltip size
    tooltipWindow:setWidth(tooltipWidth)
    tooltipWindow:setHeight(tooltipHeight)

    -- Rarity frame around sprite
    if tooltipWindow.currentRaritySrc then
        if not itemSprite.rarityFrame then
            itemSprite.rarityFrame = g_ui.createWidget("UIWidget", tooltipWindow)
            local size = itemSprite:getSize()
            itemSprite.rarityFrame:setSize({width = size.width + 8, height = size.height + 8})
        end
        itemSprite.rarityFrame:setImageSource(tooltipWindow.currentRaritySrc)
    else
        if itemSprite.rarityFrame then itemSprite.rarityFrame:hide() end
    end
end

_G.buildItemTooltip = buildItemTooltip
_G.showItemTooltip = showItemTooltip

g_logger.info("Item tooltip mod loaded: buildItemTooltip and showItemTooltip set in _G")

function addString(text, color, resize, font)
    local label = g_ui.createWidget("TooltipLabel", labels)
    label:setColor(color)
    if font then label:setFont(font) end

    if resize then
        tooltipWindow:setWidth(tooltipWidth)
        label:setTextWrap(true)
        label:setTextAutoResize(true)
        label:setText(text)
        tooltipHeight = tooltipHeight + label:getTextSize().height + 4
    else
        label:setText(text)
        local textSize = label:getTextSize()
        if longestString == 0 then
            longestString = textSize.width + itemWeightLabel:getWidth()
            tooltipWidth = tooltipWidthBase + longestString
            label:addAnchor(AnchorTop, "parent", AnchorTop)
        elseif textSize.width > longestString then
            longestString = textSize.width
            tooltipWidth = tooltipWidthBase + longestString
        end
        tooltipHeight = tooltipHeight + textSize.height
    end
end

function shrinkSeparators()
    local children = labels:getChildren()
    local m = math.max(60, math.floor(tooltipWidth / 4))
    for _, child in ipairs(children) do
        if child:getStyleName() == "TooltipSeparator" then
            child:setMarginLeft(m)
            child:setMarginRight(m)
        end
    end
end

function addSeparator()
    local sep = g_ui.createWidget("TooltipSeparator", labels)
    tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() +
                        sep:getMarginBottom()
end

function addEmpty(height)
    local empty = g_ui.createWidget("TooltipEmpty", labels)
    empty:setHeight(height)
    tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
    if not tooltipWindow then
        g_logger.error("tooltipWindow is nil in showItemTooltip")
        return
    end
    local mousePos = g_window.getMousePosition()
    tooltipHeight = math.max(tooltipHeight, HEADER_HEIGHT + 10)
    tooltipWindow:setWidth(tooltipWidth)
    tooltipWindow:setHeight(tooltipHeight)

    local windowSize = g_window.getSize()
    local x = mousePos.x + 5
    if x + tooltipWidth > windowSize.width then
        x = mousePos.x - tooltipWidth - 5
    end
    x = math.max(0, math.min(windowSize.width - tooltipWidth, x))

    local y = mousePos.y - tooltipHeight - 5
    if y < 0 then y = mousePos.y + 5 end
    y = math.max(0, math.min(windowSize.height - tooltipHeight, y))

    tooltipWindow:move(x, y)
    tooltipWindow:raise()

    -- Rarity frame position
    if itemSprite.rarityFrame and tooltipWindow.currentRaritySrc then
        local pos = itemSprite:getPosition()
        itemSprite.rarityFrame:setPosition({x = pos.x - 4, y = pos.y - 4})
        itemSprite.rarityFrame:show()
        itemSprite:raise()
    end

    local success, err = pcall(function() tooltipWindow:show() end)
    if not success then
        g_logger.error("Failed to show tooltipWindow: " .. err)
    end
end

function formatWeight(weight)
    local ss

    if weight < 10 then
        ss = "0.0" .. weight
    elseif weight < 100 then
        ss = "0." .. weight
    else
        local weightString = tostring(weight)
        local len = weightString:len()
        ss = weightString:sub(1, len - 2) .. "." ..
                 weightString:sub(len - 1, len)
    end

    ss = ss .. " oz."
    return ss
end
