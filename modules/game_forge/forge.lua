-- Item Forge System
-- GUI module for upgrading, tiering, and enchanting items
-- Communicates with server via ExtendedOpcode 51

FORGE_OPCODE = 51

local TIER_NAMES = {
  [0] = 'None',
  [1] = 'Common',
  [2] = 'Rare',
  [3] = 'Epic',
  [4] = 'Legendary',
  [5] = 'Mythical'
}

local TIER_COLORS = {
  [0] = '#c0c0c0',
  [1] = '#ffffff',
  [2] = '#3399ff',
  [3] = '#cc66ff',
  [4] = '#ffcc00',
  [5] = '#ff3333'
}

-- State
forgeWindow = nil
local forgeTabBar = nil
local forgeButton = nil

-- Original item positions (from inventory/container)
local classSourcePos = nil
local attrSourcePos = nil
local toolsSourcePos = nil

function init()
  ProtocolGame.registerExtendedOpcode(FORGE_OPCODE, onForgeData)
  connect(g_game, { onGameEnd = onGameEnd })

  forgeButton = modules.client_topmenu.addLeftGameButton('forgeButton', tr('Forge Item') .. ' (Ctrl+F)', '/images/topbuttons/cooldowns', toggle, false, 10)
  g_keyboard.bindKeyDown('Ctrl+F', toggle)
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(FORGE_OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown('Ctrl+F', toggle)
  if forgeButton then
    forgeButton:destroy()
    forgeButton = nil
  end
  destroyWindow()
end

function onGameEnd()
  destroyWindow()
end

function destroyWindow()
  if forgeWindow then
    forgeWindow:destroy()
    forgeWindow = nil
    forgeTabBar = nil
    classSourcePos = nil
    attrSourcePos = nil
    toolsSourcePos = nil
  end
end

function toggle()
  if forgeWindow then
    if forgeWindow:isVisible() then
      forgeWindow:hide()
    else
      forgeWindow:show()
      forgeWindow:raise()
      forgeWindow:focus()
    end
  else
    createWindow()
  end
end

function show()
  if not forgeWindow then
    createWindow()
  else
    forgeWindow:show()
    forgeWindow:raise()
    forgeWindow:focus()
  end
end

function createWindow()
  forgeWindow = g_ui.displayUI('forge')
  forgeWindow:hide()

  forgeTabBar = forgeWindow:getChildById('forgeTabBar')
  local contentPanel = forgeWindow:getChildById('forgeContent')
  forgeTabBar:setContentWidget(contentPanel)

  local classTab = g_ui.createWidget('ForgeClassificationTab')
  local attrTab = g_ui.createWidget('ForgeAttributesTab')
  local toolsTab = g_ui.createWidget('ForgeToolsTab')

  forgeTabBar:addTab(tr('Classification'), classTab, '/images/topbuttons/cooldowns')
  forgeTabBar:addTab(tr('Attributes'), attrTab, '/images/topbuttons/skills')
  forgeTabBar:addTab(tr('Tools'), toolsTab, '/images/topbuttons/inventory')

  setupClassificationTab(classTab)
  setupAttributesTab(attrTab)
  setupToolsTab(toolsTab)

  forgeWindow:show()
  forgeWindow:raise()
  forgeWindow:focus()
end

-- ==========================================
-- HELPERS
-- ==========================================

local function posToStr(pos)
  return pos.x .. ',' .. pos.y .. ',' .. pos.z
end

local function sendToServer(msg)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(FORGE_OPCODE, msg)
  end
end

local function splitStr(str, sep)
  local result = {}
  for part in str:gmatch('[^' .. sep .. ']+') do
    table.insert(result, part)
  end
  return result
end

-- Setup a ForgeItemSlot with drop handler that captures source position
local function setupItemSlot(slot, tabType)
  slot.onDrop = function(self, widget, mousePos, forced)
    if not self:canAcceptDrop(widget, mousePos) and not forced then return false end
    local item = widget.currentDragThing
    if not item or not item:isItem() then return false end
    if not item:isPickupable() then return false end

    local srcPos = item:getPosition()
    self:setItem(Item.create(item:getId(), item:getCountOrSubType()))

    if tabType == 'CLASS' then
      classSourcePos = srcPos
      sendToServer('QUERY:CLASS:' .. posToStr(srcPos))
    elseif tabType == 'ATTR' then
      attrSourcePos = srcPos
      sendToServer('QUERY:ATTR:' .. posToStr(srcPos))
    elseif tabType == 'TOOLS' then
      toolsSourcePos = srcPos
      sendToServer('QUERY:TOOLS:' .. posToStr(srcPos))
    end
    return true
  end

  -- Prevent dragging items OUT of forge slots
  slot.onDragEnter = function() return false end
end

-- ==========================================
-- CLASSIFICATION TAB (TIER)
-- ==========================================

function setupClassificationTab(tab)
  local sourceItem = tab:recursiveGetChildById('classSourceItem')
  local forgeButton = tab:recursiveGetChildById('classForgeButton')

  setupItemSlot(sourceItem, 'CLASS')

  forgeButton.onClick = function()
    if classSourcePos then
      sendToServer('FORGE:TIER_UP:' .. posToStr(classSourcePos))
    end
  end
end

function updateClassInfo(data)
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('classificationTab')
  if not tab then return end

  local currentTier = data.currentTier or 0
  local nextTier = data.nextTier or 0
  local chance = data.chance or 0
  local canForge = data.canForge or false

  local tierLabel = tab:recursiveGetChildById('classSourceTierLabel')
  if tierLabel then
    tierLabel:setText('Current: ' .. (TIER_NAMES[currentTier] or 'None'))
    tierLabel:setColor(TIER_COLORS[currentTier] or '#c0c0c0')
  end

  local resultLabel = tab:recursiveGetChildById('classResultTierLabel')
  if resultLabel then
    if nextTier > 0 then
      resultLabel:setText('Next: ' .. (TIER_NAMES[nextTier] or '?'))
      resultLabel:setColor(TIER_COLORS[nextTier] or '#c0c0c0')
    else
      resultLabel:setText('Maximum Tier')
      resultLabel:setColor('#ffcc00')
    end
  end

  local chanceLabel = tab:recursiveGetChildById('classChanceLabel')
  if chanceLabel then
    chanceLabel:setText('Chance: ' .. chance .. '%')
    if chance >= 60 then chanceLabel:setColor('#00ff00')
    elseif chance >= 30 then chanceLabel:setColor('#ffcc00')
    else chanceLabel:setColor('#ff3333') end
  end

  local forgeButton = tab:recursiveGetChildById('classForgeButton')
  if forgeButton then forgeButton:setEnabled(canForge) end
end

function clearClassInfo()
  classSourcePos = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('classificationTab')
  if not tab then return end
  for _, id in ipairs({'classSourceTierLabel', 'classResultTierLabel', 'classChanceLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('classForgeButton')
  if btn then btn:setEnabled(false) end
end

-- ==========================================
-- ATTRIBUTES TAB (ENCHANTMENTS)
-- ==========================================

function setupAttributesTab(tab)
  local sourceItem = tab:recursiveGetChildById('attrSourceItem')
  setupItemSlot(sourceItem, 'ATTR')

  local actions = {
    { id = 'attrAddEnchant',  action = 'ENCHANT_ADD' },
    { id = 'attrRerollLast',  action = 'ENCHANT_REROLL_LAST' },
    { id = 'attrRerollAll',   action = 'ENCHANT_REROLL_ALL' },
    { id = 'attrRemoveLast',  action = 'ENCHANT_REMOVE_LAST' },
    { id = 'attrRemoveAll',   action = 'ENCHANT_REMOVE_ALL' },
  }
  for _, a in ipairs(actions) do
    local btn = tab:recursiveGetChildById(a.id)
    if btn then
      btn.onClick = function()
        if attrSourcePos then
          sendToServer('FORGE:' .. a.action .. ':' .. posToStr(attrSourcePos))
        end
      end
    end
  end
end

function updateAttrInfo(data)
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local tier = data.tier or 0
  local slotsUsed = data.slotsUsed or 0
  local slotsMax = data.slotsMax or 0

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then
    itemInfo:setText('Tier: ' .. (TIER_NAMES[tier] or 'None') .. ' (' .. slotsUsed .. '/' .. slotsMax .. ' slots)')
  end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then
    list:destroyChildren()
    if data.enchantments then
      for i, ench in ipairs(data.enchantments) do
        local label = g_ui.createWidget('Label', list)
        label:setText('[Slot ' .. i .. '] ' .. ench.name .. ': ' .. ench.value)
        label:setColor('#c0ffee')
        label:setHeight(18)
      end
    end
    for i = slotsUsed + 1, slotsMax do
      local label = g_ui.createWidget('Label', list)
      label:setText('[Slot ' .. i .. '] empty')
      label:setColor('#666666')
      label:setHeight(18)
    end
  end

  local hasTier = tier > 0
  local hasFreeSlots = slotsUsed < slotsMax
  local hasEnchants = slotsUsed > 0

  local btnStates = {
    { id = 'attrAddEnchant',  enabled = hasTier and hasFreeSlots },
    { id = 'attrRerollLast',  enabled = hasEnchants },
    { id = 'attrRerollAll',   enabled = hasEnchants },
    { id = 'attrRemoveLast',  enabled = hasEnchants },
    { id = 'attrRemoveAll',   enabled = hasEnchants },
  }
  for _, bs in ipairs(btnStates) do
    local btn = tab:recursiveGetChildById(bs.id)
    if btn then btn:setEnabled(bs.enabled) end
  end
end

function clearAttrInfo()
  attrSourcePos = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then itemInfo:setText('') end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then list:destroyChildren() end

  for _, id in ipairs({'attrAddEnchant', 'attrRerollLast', 'attrRerollAll', 'attrRemoveLast', 'attrRemoveAll'}) do
    local btn = tab:recursiveGetChildById(id)
    if btn then btn:setEnabled(false) end
  end
end

-- ==========================================
-- TOOLS TAB (UPGRADE)
-- ==========================================

function setupToolsTab(tab)
  local sourceItem = tab:recursiveGetChildById('toolsSourceItem')
  local forgeButton = tab:recursiveGetChildById('toolsForgeButton')

  setupItemSlot(sourceItem, 'TOOLS')

  forgeButton.onClick = function()
    if toolsSourcePos then
      sendToServer('FORGE:UPGRADE:' .. posToStr(toolsSourcePos))
    end
  end
end

function updateToolsInfo(data)
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('toolsTab')
  if not tab then return end

  local level = data.level or 0
  local maxLevel = data.maxLevel or 9
  local chance = data.chance or 0
  local canForge = data.canForge or false

  local levelLabel = tab:recursiveGetChildById('toolsSourceLevelLabel')
  if levelLabel then
    levelLabel:setText('Current: +' .. level)
  end

  local resultLabel = tab:recursiveGetChildById('toolsResultLevelLabel')
  if resultLabel then
    if level < maxLevel then
      resultLabel:setText('Next: +' .. (level + 1))
      resultLabel:setColor('#00ff00')
    else
      resultLabel:setText('Maximum (+' .. maxLevel .. ')')
      resultLabel:setColor('#ffcc00')
    end
  end

  local chanceLabel = tab:recursiveGetChildById('toolsChanceLabel')
  if chanceLabel then
    chanceLabel:setText('Chance: ' .. chance .. '%')
    if chance >= 60 then chanceLabel:setColor('#00ff00')
    elseif chance >= 30 then chanceLabel:setColor('#ffcc00')
    else chanceLabel:setColor('#ff3333') end
  end

  local forgeButton = tab:recursiveGetChildById('toolsForgeButton')
  if forgeButton then forgeButton:setEnabled(canForge) end
end

function clearToolsInfo()
  toolsSourcePos = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('toolsTab')
  if not tab then return end
  for _, id in ipairs({'toolsSourceLevelLabel', 'toolsResultLevelLabel', 'toolsChanceLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('toolsForgeButton')
  if btn then btn:setEnabled(false) end
end

-- ==========================================
-- SERVER DATA HANDLER
-- ==========================================

function onForgeData(protocol, opcode, buffer)
  if not buffer or #buffer == 0 then return end

  -- CLASS_INFO:currentTier,nextTier,chance,canForge
  if buffer:sub(1, 11) == 'CLASS_INFO:' then
    local parts = splitStr(buffer:sub(12), ',')
    if #parts >= 4 then
      updateClassInfo({
        currentTier = tonumber(parts[1]) or 0,
        nextTier = tonumber(parts[2]) or 0,
        chance = tonumber(parts[3]) or 0,
        canForge = parts[4] == '1'
      })
    end

  -- ATTR_INFO:tier,slotsUsed,slotsMax|enchName1=val1|enchName2=val2...
  elseif buffer:sub(1, 10) == 'ATTR_INFO:' then
    local sections = splitStr(buffer:sub(11), '|')
    if #sections >= 1 then
      local mainParts = splitStr(sections[1], ',')
      local enchantments = {}
      for i = 2, #sections do
        local eqPos = sections[i]:find('=')
        if eqPos then
          table.insert(enchantments, {
            name = sections[i]:sub(1, eqPos - 1),
            value = sections[i]:sub(eqPos + 1)
          })
        end
      end
      updateAttrInfo({
        tier = tonumber(mainParts[1]) or 0,
        slotsUsed = tonumber(mainParts[2]) or 0,
        slotsMax = tonumber(mainParts[3]) or 0,
        enchantments = enchantments
      })
    end

  -- TOOLS_INFO:level,maxLevel,chance,canForge
  elseif buffer:sub(1, 11) == 'TOOLS_INFO:' then
    local parts = splitStr(buffer:sub(12), ',')
    if #parts >= 4 then
      updateToolsInfo({
        level = tonumber(parts[1]) or 0,
        maxLevel = tonumber(parts[2]) or 0,
        chance = tonumber(parts[3]) or 0,
        canForge = parts[4] == '1'
      })
    end

  -- FORGE_RESULT:tab,success,message
  elseif buffer:sub(1, 13) == 'FORGE_RESULT:' then
    local parts = splitStr(buffer:sub(14), ',')
    if #parts >= 2 then
      local tab = parts[1]
      -- Re-query to refresh display after forge
      if tab == 'CLASS' and classSourcePos then
        sendToServer('QUERY:CLASS:' .. posToStr(classSourcePos))
      elseif tab == 'ATTR' and attrSourcePos then
        sendToServer('QUERY:ATTR:' .. posToStr(attrSourcePos))
      elseif tab == 'TOOLS' and toolsSourcePos then
        sendToServer('QUERY:TOOLS:' .. posToStr(toolsSourcePos))
      end
    end

  -- FORGE_ERROR:message
  elseif buffer:sub(1, 12) == 'FORGE_ERROR:' then
    -- Error messages are sent in-game via sendTextMessage
  end
end
