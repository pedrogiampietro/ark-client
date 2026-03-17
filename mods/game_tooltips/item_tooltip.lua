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
local BODY_MARGIN = 10  -- top + bottom padding inside body
local MIN_WIDTH = 200

local tooltipWidth = MIN_WIDTH
local bodyHeight = 0

local cachedItems = {}

local Colors = {
    Default     = "#cccccc",
    ItemLevel   = "#abface",
    Description = "#8888cc",
    Implicit    = "#ffbb22",
    Attribute   = "#6699ff",
    Mirrored    = "#22ffbb"
}

local rarityColor = {
    [0] = {name = "",          color = "#ffffff"},
    [1] = {name = "Common",    color = "#9d9d9d"},
    [2] = {name = "Rare",      color = "#25fc19"},
    [3] = {name = "Epic",      color = "#bd3ffa"},
    [4] = {name = "Legendary", color = "#ff7605"},
    [5] = {name = "Mythic",    color = "#ff4444"}
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
    ["ca"] = true, ["cc"] = true, ["la"] = true, ["lc"] = true,
    ["ma"] = true, ["mc"] = true,
    ["a_phys"] = true, ["a_ene"] = true, ["a_earth"] = true,
    ["a_fire"] = true, ["a_ldrain"] = true, ["a_mdrain"] = true,
    ["a_heal"] = true, ["a_drown"] = true, ["a_ice"] = true,
    ["a_holy"] = true, ["a_death"] = true, ["a_all"] = true
}

function init()
    connect(UIItem, {onHoverChange = onHoverChange})
    connect(g_game, {onGameEnd = resetData})

    ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

    tooltipWindow = g_ui.displayUI("item_tooltip")
    _G.tooltipWindow = tooltipWindow
    tooltipWindow:hide()

    tooltipHeader   = tooltipWindow:getChildById("tooltipHeader")
    local tooltipBody = tooltipWindow:getChildById("tooltipBody")

    -- getChildById may be non-recursive — access nested widgets through their direct parent
    if tooltipHeader then
        itemSprite      = tooltipHeader:getChildById("itemSprite")
        itemNameLabel   = tooltipHeader:getChildById("itemNameLabel")
        itemTypeLabel   = tooltipHeader:getChildById("itemTypeLabel")
        itemWeightLabel = tooltipHeader:getChildById("itemWeightLabel")
    end
    if tooltipBody then
        labels = tooltipBody:getChildById("labels")
    end

    if not labels or not itemSprite or not itemNameLabel or not itemWeightLabel then
        g_logger.error("item_tooltip: failed to find required child widgets — check item_tooltip.otui IDs")
        return
    end

    _G.buildItemTooltip = buildItemTooltip
    _G.showItemTooltip  = showItemTooltip
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
    local data   = json_data.data
    if not action or not data then
        g_logger.error("Tooltip: action ou data não encontrados no JSON")
        return
    end

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
    local _itemMaxAttr    = data.maxAttr or 0
    local _itemAttributes = data.attr
    local _requiredLevel  = data.reqLvl or 0

    if _itemRarity ~= 0 and _itemAttributes then
        for i = _itemMaxAttr, 1, -1 do
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
        maxAttributes = _itemMaxAttr,
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

    if hoveredItem and _itemId == hoveredItem:getId() then
        hoveredItem.uid    = _itemUId
        hoveredItem.name   = _itemName ..
            (_upgradeLevel > 0 and " +" .. _upgradeLevel or "")
        hoveredItem.rarity = _itemRarity
        showTooltip(_itemUId)
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

    local item = widget:getItem()
    if item and widget.getItemTooltip then
        if hovered then
            buildItemTooltip(widget:getItemTooltip())
            showItemTooltip()
        else
            tooltipWindow:hide()
        end
        return
    end

    if not item or widget:getId() == "containerItemWidget" or widget:isVirtual() then
        return
    end

    if player == nil then player = g_game.getLocalPlayer() end

    if hovered then
        hoveredItem = item
        if protocolGame then
            local pos = item:getPosition()
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

-- ─────────────────────────────────────────────────────────────────────────────
-- buildItemTooltip
-- ─────────────────────────────────────────────────────────────────────────────
function buildItemTooltip(item)
    if not tooltipWindow then return end
    if not labels       then return end

    -- Reset
    tooltipWidth = MIN_WIDTH
    bodyHeight   = 0
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
    local itemType      = item.type
    local first         = item.first
    local second        = item.second
    local third         = item.third
    local weight        = item.weight

    -- ── Header colours ────────────────────────────────────────────────────────
    local headerBg  = rarityHeaderBg[rarity]    or rarityHeaderBg[0]
    local borderCol = rarityBorderColor[rarity] or rarityBorderColor[0]
    if tooltipHeader then tooltipHeader:setBackgroundColor(headerBg) end
    tooltipWindow:setBorderColor(borderCol)

    -- ── Item sprite ───────────────────────────────────────────────────────────
    if id    then itemSprite:setItemId(id)       end
    if count then itemSprite:setItemCount(count) end

    -- ── Weight ────────────────────────────────────────────────────────────────
    itemWeightLabel:setText(formatWeight(weight))

    -- ── Name (with rarity prefix / unique name) ───────────────────────────────
    local nameColor
    if unidentified then
        nameColor = rarityColor[1].color
    elseif item.uniqueName and item.uniqueName ~= "" then
        nameColor = "#dca01e"
    elseif rarity > 1 and rarityColor[rarity] then
        nameColor = rarityColor[rarity].color
    else
        nameColor = "#ffffff"
    end

    name = name:gsub("(%a)(%a+)", function(a, b)
        return string.upper(a) .. string.lower(b)
    end)
    name = name:gsub("^a ", ""):gsub("^an ", "")
    if item.uLvl and item.uLvl > 0 then name = name .. " +" .. item.uLvl end

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

    itemNameLabel:setText(displayName)
    itemNameLabel:setColor(nameColor)

    -- ── Type label ────────────────────────────────────────────────────────────
    if itemTypeLabel then
        itemTypeLabel:setText(itemType or "")
    end

    -- ── Body: level lines ─────────────────────────────────────────────────────
    if iLvl > 0 then
        addString("Item Level " .. iLvl, Colors.ItemLevel)
    end
    if reqLvl > 0 then
        addString("Required Level " .. reqLvl, Colors.ItemLevel)
    end

    -- ── Body: base stats ──────────────────────────────────────────────────────
    local firstText, secondText, thirdText

    if (itemType == "Armor" or itemType == "Helmet" or itemType == "Legs" or
        itemType == "Ring" or itemType == "Necklace" or itemType == "Boots") and
        first ~= 0 then
        firstText = "Armor: " .. first
    elseif itemType == "Two-Handed Sword" or itemType == "Two-Handed Club" or
           itemType == "Two-Handed Axe"   or itemType == "Sword" or
           itemType == "Club"             or itemType == "Axe"  or
           itemType == "Fist"             or itemType == "Distance" or
           itemType == "Ammunition" then
        firstText = "Attack: " .. first
    elseif itemType == "Shield" then
        firstText = "Defense: " .. second
    end

    if itemType == "Two-Handed Sword" or itemType == "Two-Handed Club" or
       itemType == "Two-Handed Axe"   or itemType == "Sword" or
       itemType == "Club"             or itemType == "Axe"  or
       itemType == "Fist" then
        secondText = "Defense: " .. second
    elseif itemType == "Distance" then
        secondText = "Hit Chance: +" .. second .. "%"
    end

    if itemType == "Two-Handed Sword" or itemType == "Two-Handed Club" or
       itemType == "Two-Handed Axe"   or itemType == "Sword" or
       itemType == "Club"             or itemType == "Axe"  or
       itemType == "Fist" then
        thirdText = "Extra-Defense: " .. third
    elseif itemType == "Distance" then
        thirdText = "Shoot Range: " .. third
    end

    local hasStats = firstText or secondText or thirdText
    if hasStats then
        addSeparator()
        addEmpty(3)
        if firstText  then addString(firstText,  Colors.Default) end
        if secondText then addString(secondText, Colors.Default) end
        if thirdText  then addString(thirdText,  Colors.Default) end
    end

    -- ── Body: implicits ───────────────────────────────────────────────────────
    if item.imp then
        if hasStats or iLvl > 0 or reqLvl > 0 then
            addSeparator()
            addEmpty(3)
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
                impText = implicits[key] .. " " ..
                    (value > 0 and "+" or "") .. formattedValue .. suffix
            end
            addString(impText, Colors.Implicit)
        end
    end

    -- ── Body: rarity attributes ───────────────────────────────────────────────
    if rarity ~= 0 and attributes then
        addSeparator()
        addEmpty(3)
        for i = 1, maxAttributes do
            if attributes[i] then
                addString(attributes[i], Colors.Attribute)
            end
        end
    end

    -- ── Body: mirrored ────────────────────────────────────────────────────────
    if mirrored then
        addEmpty(3)
        addString("Mirrored", Colors.Mirrored)
    end

    -- ── Body: description ─────────────────────────────────────────────────────
    if desc and desc:len() > 0 then
        addSeparator()
        addEmpty(3)
        addString(desc, Colors.Description, true)
    end

    shrinkSeparators()

    -- ── Final size ────────────────────────────────────────────────────────────
    local totalHeight = HEADER_HEIGHT + bodyHeight + BODY_MARGIN
    totalHeight = math.max(totalHeight, HEADER_HEIGHT + 16)

    tooltipWindow:setWidth(tooltipWidth)
    tooltipWindow:setHeight(totalHeight)
end

_G.buildItemTooltip = buildItemTooltip
_G.showItemTooltip  = showItemTooltip

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────
function addString(text, color, resize, font)
    local label = g_ui.createWidget("TooltipLabel", labels)
    label:setColor(color)
    if font then label:setFont(font) end

    if resize then
        -- wrap to current width first
        tooltipWindow:setWidth(tooltipWidth)
        label:setTextWrap(true)
        label:setTextAutoResize(true)
        label:setText(text)
        bodyHeight = bodyHeight + label:getTextSize().height + 4
    else
        label:setText(text)
        local textSize = label:getTextSize()
        local needed   = textSize.width + 24  -- left + right margins
        if needed > tooltipWidth then
            tooltipWidth = needed
        end
        bodyHeight = bodyHeight + textSize.height
    end
end

function shrinkSeparators()
    local children = labels:getChildren()
    local m = math.max(20, math.floor(tooltipWidth / 6))
    for _, child in ipairs(children) do
        if child:getStyleName() == "TooltipSeparator" then
            child:setMarginLeft(m)
            child:setMarginRight(m)
        end
    end
end

function addSeparator()
    local sep = g_ui.createWidget("TooltipSeparator", labels)
    bodyHeight = bodyHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
    local empty = g_ui.createWidget("TooltipEmpty", labels)
    empty:setHeight(height)
    bodyHeight = bodyHeight + height
end

function showItemTooltip()
    if not tooltipWindow then return end

    local mousePos  = g_window.getMousePosition()
    local w         = tooltipWindow:getWidth()
    local h         = tooltipWindow:getHeight()
    local winSize   = g_window.getSize()

    local x = mousePos.x + 15
    if x + w > winSize.width then x = mousePos.x - w - 10 end
    x = math.max(0, math.min(winSize.width - w, x))

    local y = mousePos.y - h - 10
    if y < 0 then y = mousePos.y + 15 end
    y = math.max(0, math.min(winSize.height - h, y))

    tooltipWindow:move(x, y)
    tooltipWindow:raise()
    tooltipWindow:show()
end

function formatWeight(weight)
    local ss
    if weight < 10 then
        ss = "0.0" .. weight
    elseif weight < 100 then
        ss = "0." .. weight
    else
        local s   = tostring(weight)
        local len = s:len()
        ss = s:sub(1, len - 2) .. "." .. s:sub(len - 1, len)
    end
    return ss .. " oz."
end

g_logger.info("Item tooltip mod loaded")
