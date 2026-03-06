-- Item Forge System
-- GUI module for upgrading, tiering, and enchanting items
-- Communicates with server via ExtendedOpcode 51

FORGE_OPCODE = 51

local TIER_NAMES = {
  [0] = 'None',
  [1] = 'Common',
  [2] = 'Uncommon',
  [3] = 'Rare',
  [4] = 'Epic',
  [5] = 'Legendary'
}

local TIER_COLORS = {
  [0] = '#c0c0c0',
  [1] = '#ffffff',
  [2] = '#00cc00',
  [3] = '#3399ff',
  [4] = '#cc66ff',
  [5] = '#ffcc00'
}

local FORGE_RUNES = {
  TIER_UP = { id = 2312, name = 'Rune of Tiering' },
  UPGRADE = { id = 2284, name = 'Rune of Upgrading' },
  ENCHANT_ADD = { id = 2276, name = 'Rune of Enchanting' },
  ENCHANT_REROLL_LAST = { id = 2272, name = 'Rune of Rolling' },
  ENCHANT_REROLL_ALL = { id = 2296, name = 'Rune of Total Rolling' },
  ENCHANT_REMOVE_LAST = { id = 2270, name = 'Rune of Cleansing' },
  ENCHANT_REMOVE_ALL = { id = 2298, name = 'Rune of Total Cleansing' },
}

-- State
forgeWindow = nil
local forgeTabBar = nil
local forgeButton = nil
local forging = false
local forgeAnimEvent = nil

-- Original item positions (from inventory/container)
local classSourcePos = nil
local attrSourcePos = nil
local toolsSourcePos = nil

-- Bonus toggle state per tab
local classBonusActive = false
local toolsBonusActive = false

-- Cached cost data from server
local classCostData = nil
local toolsCostData = nil
local attrCostData = nil

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
  stopForgeAnimation()
  destroyWindow()
end

function onGameEnd()
  stopForgeAnimation()
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
    classBonusActive = false
    toolsBonusActive = false
    classCostData = nil
    toolsCostData = nil
    attrCostData = nil
    forging = false
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

  forgeTabBar:addTab(tr('Classification'), classTab)
  forgeTabBar:addTab(tr('Attributes'), attrTab)
  forgeTabBar:addTab(tr('Tools'), toolsTab)

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

-- Show/hide placeholder text when item is set/cleared
local function updatePlaceholder(tab, placeholderId, hasItem)
  local placeholder = tab:recursiveGetChildById(placeholderId)
  if placeholder then
    placeholder:setVisible(not hasItem)
  end
end

-- Setup a ForgeItemSlot with drop handler that captures source position
local function setupItemSlot(slot, tabType, tab)
  slot.onDrop = function(self, widget, mousePos, forced)
    if forging then return false end
    if not self:canAcceptDrop(widget, mousePos) and not forced then return false end
    local item = widget.currentDragThing
    if not item or not item:isItem() then return false end
    if not item:isPickupable() then return false end

    local srcPos = item:getPosition()
    self:setItem(Item.create(item:getId(), item:getCountOrSubType()))

    if tabType == 'CLASS' then
      classSourcePos = srcPos
      updatePlaceholder(tab, 'classPlaceholder', true)
      sendToServer('QUERY:CLASS:' .. posToStr(srcPos))
    elseif tabType == 'ATTR' then
      attrSourcePos = srcPos
      updatePlaceholder(tab, 'attrPlaceholder', true)
      sendToServer('QUERY:ATTR:' .. posToStr(srcPos))
    elseif tabType == 'TOOLS' then
      toolsSourcePos = srcPos
      updatePlaceholder(tab, 'toolsPlaceholder', true)
      sendToServer('QUERY:TOOLS:' .. posToStr(srcPos))
    end
    return true
  end

  -- Prevent dragging items OUT of forge slots
  slot.onDragEnter = function() return false end
end

-- ==========================================
-- FORGE ANIMATION
-- ==========================================

function stopForgeAnimation()
  if forgeAnimEvent then
    removeEvent(forgeAnimEvent)
    forgeAnimEvent = nil
  end
  forging = false
end

-- Run progress bar animation then call onComplete
local function runForgeAnimation(progressBarId, onComplete)
  if not forgeWindow then return end
  local bar = forgeWindow:recursiveGetChildById(progressBarId)
  if not bar then
    if onComplete then onComplete() end
    return
  end

  forging = true
  bar:setVisible(true)
  bar:setPercent(0)

  local step = 0
  local totalSteps = 20
  local interval = 80

  local function animStep()
    step = step + 1
    if not forgeWindow or not bar then
      stopForgeAnimation()
      return
    end

    local pct = math.floor((step / totalSteps) * 100)
    bar:setPercent(math.min(pct, 100))

    if step >= totalSteps then
      stopForgeAnimation()
      bar:setVisible(false)
      if onComplete then onComplete() end
    else
      forgeAnimEvent = scheduleEvent(animStep, interval)
    end
  end

  forgeAnimEvent = scheduleEvent(animStep, interval)
end

-- Show result message with color (green for success, red for failure)
local function showResultMessage(labelId, success)
  if not forgeWindow then return end
  local label = forgeWindow:recursiveGetChildById(labelId)
  if not label then return end

  if success then
    label:setText(tr('Success!'))
    label:setColor('#00ff00')
  else
    label:setText(tr('Failed!'))
    label:setColor('#ff3333')
  end

  -- Clear message after 3 seconds
  scheduleEvent(function()
    if forgeWindow and label then
      label:setText('')
    end
  end, 3000)
end

-- ==========================================
-- CLASSIFICATION TAB (TIER)
-- ==========================================

function setupClassificationTab(tab)
  local sourceItem = tab:recursiveGetChildById('classSourceItem')
  local forgBtn = tab:recursiveGetChildById('classForgeButton')
  local bonusBtn = tab:recursiveGetChildById('classBonusButton')

  setupItemSlot(sourceItem, 'CLASS', tab)

  if bonusBtn then
    bonusBtn.onClick = function()
      classBonusActive = not classBonusActive
      if classBonusActive then
        bonusBtn:setColor('#00ff00')
        bonusBtn:setText(tr('+20%% ON'))
      else
        bonusBtn:setColor('#3399ff')
        bonusBtn:setText(tr('+20%%'))
      end
      -- Update cost display
      if classCostData then
        updateClassCostDisplay(tab)
      end
    end
  end

  forgBtn.onClick = function()
    if classSourcePos and not forging then
      forgBtn:setEnabled(false)
      runForgeAnimation('classProgressBar', function()
        local msg = 'FORGE:TIER_UP:' .. posToStr(classSourcePos)
        if classBonusActive then msg = msg .. ':BONUS' end
        sendToServer(msg)
      end)
    end
  end
end

function updateClassCostDisplay(tab)
  if not classCostData then return end
  local costLabel = tab:recursiveGetChildById('classCostLabel')
  if costLabel then
    local totalCost = classCostData.cost
    if classBonusActive then totalCost = totalCost + classCostData.bonusCost end
    local hasEnough = classCostData.playerGold >= totalCost
    costLabel:setText(tr('Cost') .. ': ' .. totalCost .. ' crystal coins (' .. tr('You have') .. ': ' .. classCostData.playerGold .. ')')
    costLabel:setColor(hasEnough and '#ffcc00' or '#ff3333')
  end
  -- Update forge button state
  local forgBtn = tab:recursiveGetChildById('classForgeButton')
  if forgBtn then
    local totalCost = classCostData.cost
    if classBonusActive then totalCost = totalCost + classCostData.bonusCost end
    local hasEnough = classCostData.playerGold >= totalCost
    forgBtn:setEnabled(classCostData.canForge and classCostData.hasRune and hasEnough and not forging)
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
  local hasRune = data.hasRune or false

  -- Cache cost data
  classCostData = {
    cost = data.cost or 0,
    bonusCost = data.bonusCost or 0,
    playerGold = data.playerGold or 0,
    canForge = canForge,
    hasRune = hasRune
  }

  local tierLabel = tab:recursiveGetChildById('classSourceTierLabel')
  if tierLabel then
    tierLabel:setText(tr('Current') .. ': ' .. (TIER_NAMES[currentTier] or 'None'))
    tierLabel:setColor(TIER_COLORS[currentTier] or '#c0c0c0')
  end

  local resultLabel = tab:recursiveGetChildById('classResultTierLabel')
  if resultLabel then
    if nextTier > 0 then
      resultLabel:setText(tr('Next') .. ': ' .. (TIER_NAMES[nextTier] or '?'))
      resultLabel:setColor(TIER_COLORS[nextTier] or '#c0c0c0')
    else
      resultLabel:setText(tr('Maximum Tier'))
      resultLabel:setColor('#ffcc00')
    end
  end

  local chanceLabel = tab:recursiveGetChildById('classChanceLabel')
  if chanceLabel then
    chanceLabel:setText(tr('Chance') .. ': ' .. chance .. '%')
    if chance >= 60 then chanceLabel:setColor('#00ff00')
    elseif chance >= 30 then chanceLabel:setColor('#ffcc00')
    else chanceLabel:setColor('#ff3333') end
  end

  local matLabel = tab:recursiveGetChildById('classMaterialLabel')
  if matLabel then
    local rune = FORGE_RUNES.TIER_UP
    if hasRune then
      matLabel:setText(tr('Required') .. ': ' .. rune.name .. ' [OK]')
      matLabel:setColor('#00ff00')
    else
      matLabel:setText(tr('Required') .. ': ' .. rune.name .. ' [' .. tr('Missing') .. ']')
      matLabel:setColor('#ff3333')
    end
  end

  local forgBtn = tab:recursiveGetChildById('classForgeButton')
  if forgBtn then forgBtn:setEnabled(canForge and hasRune and not forging) end

  -- Display cost
  updateClassCostDisplay(tab)
end

function clearClassInfo()
  classSourcePos = nil
  classBonusActive = false
  classCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('classificationTab')
  if not tab then return end
  local slot = tab:recursiveGetChildById('classSourceItem')
  if slot then slot:setItem(nil) end
  for _, id in ipairs({'classSourceTierLabel', 'classResultTierLabel', 'classChanceLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('classForgeButton')
  if btn then btn:setEnabled(false) end
  local bonusBtn = tab:recursiveGetChildById('classBonusButton')
  if bonusBtn then bonusBtn:setColor('#3399ff'); bonusBtn:setText(tr('+20%%')) end
  updatePlaceholder(tab, 'classPlaceholder', false)
  local msg = tab:recursiveGetChildById('classResultMessage')
  if msg then msg:setText('') end
  local mat = tab:recursiveGetChildById('classMaterialLabel')
  if mat then mat:setText('') end
  local costLabel = tab:recursiveGetChildById('classCostLabel')
  if costLabel then costLabel:setText('') end
end

-- Clear slot after forge (preserves result message)
function clearClassSlot()
  classSourcePos = nil
  classBonusActive = false
  classCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('classificationTab')
  if not tab then return end
  local slot = tab:recursiveGetChildById('classSourceItem')
  if slot then slot:setItem(nil) end
  local bonusBtn = tab:recursiveGetChildById('classBonusButton')
  if bonusBtn then bonusBtn:setColor('#3399ff'); bonusBtn:setText(tr('+20%%')) end
  for _, id in ipairs({'classSourceTierLabel', 'classResultTierLabel', 'classChanceLabel', 'classMaterialLabel', 'classCostLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('classForgeButton')
  if btn then btn:setEnabled(false) end
  updatePlaceholder(tab, 'classPlaceholder', false)
end

-- ==========================================
-- ATTRIBUTES TAB (ENCHANTMENTS)
-- ==========================================

function setupAttributesTab(tab)
  local sourceItem = tab:recursiveGetChildById('attrSourceItem')
  setupItemSlot(sourceItem, 'ATTR', tab)

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
        if attrSourcePos and not forging then
          setAttrButtonsEnabled(false)
          runForgeAnimation('attrProgressBar', function()
            sendToServer('FORGE:' .. a.action .. ':' .. posToStr(attrSourcePos))
          end)
        end
      end
    end
  end
end

function setAttrButtonsEnabled(enabled)
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end
  for _, id in ipairs({'attrAddEnchant', 'attrRerollLast', 'attrRerollAll', 'attrRemoveLast', 'attrRemoveAll'}) do
    local btn = tab:recursiveGetChildById(id)
    if btn then btn:setEnabled(enabled) end
  end
end

function updateAttrInfo(data)
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local tier = data.tier or 0
  local slotsUsed = data.slotsUsed or 0
  local slotsMax = data.slotsMax or 0
  local runeFlags = data.runeFlags or {}

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then
    itemInfo:setText(tr('Tier') .. ': ' .. (TIER_NAMES[tier] or 'None') .. ' (' .. slotsUsed .. '/' .. slotsMax .. ' slots)')
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
      label:setText('[Slot ' .. i .. '] ' .. tr('empty'))
      label:setColor('#666666')
      label:setHeight(18)
    end
  end

  local hasTier = tier > 0
  local hasFreeSlots = slotsUsed < slotsMax
  local hasEnchants = slotsUsed > 0

  local btnStates = {
    { id = 'attrAddEnchant',  enabled = hasTier and hasFreeSlots, runeKey = 'hasAdd' },
    { id = 'attrRerollLast',  enabled = hasEnchants, runeKey = 'hasRerollLast' },
    { id = 'attrRerollAll',   enabled = hasEnchants, runeKey = 'hasRerollAll' },
    { id = 'attrRemoveLast',  enabled = hasEnchants, runeKey = 'hasRemoveLast' },
    { id = 'attrRemoveAll',   enabled = hasEnchants, runeKey = 'hasRemoveAll' },
  }
  for _, bs in ipairs(btnStates) do
    local btn = tab:recursiveGetChildById(bs.id)
    if btn then
      local hasRune = runeFlags[bs.runeKey] or false
      btn:setEnabled(bs.enabled and hasRune and not forging)
    end
  end

  -- Show material summary
  local matLabel = tab:recursiveGetChildById('attrMaterialLabel')
  if matLabel then
    local parts = {}
    local runeInfo = {
      { key = 'hasAdd', name = FORGE_RUNES.ENCHANT_ADD.name },
      { key = 'hasRerollLast', name = FORGE_RUNES.ENCHANT_REROLL_LAST.name },
      { key = 'hasRemoveLast', name = FORGE_RUNES.ENCHANT_REMOVE_LAST.name },
    }
    for _, ri in ipairs(runeInfo) do
      local has = runeFlags[ri.key] or false
      local status = has and '[OK]' or '[' .. tr('Missing') .. ']'
      table.insert(parts, ri.name .. ' ' .. status)
    end
    matLabel:setText(table.concat(parts, '  |  '))
    -- Color based on whether any rune is missing
    local anyMissing = false
    for _, v in pairs(runeFlags) do
      if not v then anyMissing = true break end
    end
    matLabel:setColor(anyMissing and '#ffcc00' or '#00ff00')
  end

  -- Display cost info
  attrCostData = {
    costs = data.costs or {},
    bonusCost = data.bonusCost or 0,
    playerGold = data.playerGold or 0
  }
  local costLabel = tab:recursiveGetChildById('attrCostLabel')
  if costLabel then
    local costAdd = (data.costs and data.costs.add) or 0
    costLabel:setText(tr('Cost') .. ': ' .. costAdd .. '+ crystal coins (' .. tr('You have') .. ': ' .. (data.playerGold or 0) .. ')')
    costLabel:setColor((data.playerGold or 0) >= costAdd and '#ffcc00' or '#ff3333')
  end
end

function clearAttrInfo()
  attrSourcePos = nil
  attrCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local slot = tab:recursiveGetChildById('attrSourceItem')
  if slot then slot:setItem(nil) end

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then itemInfo:setText('') end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then list:destroyChildren() end

  for _, id in ipairs({'attrAddEnchant', 'attrRerollLast', 'attrRerollAll', 'attrRemoveLast', 'attrRemoveAll'}) do
    local btn = tab:recursiveGetChildById(id)
    if btn then btn:setEnabled(false) end
  end

  updatePlaceholder(tab, 'attrPlaceholder', false)
  local msg = tab:recursiveGetChildById('attrResultMessage')
  if msg then msg:setText('') end
  local mat = tab:recursiveGetChildById('attrMaterialLabel')
  if mat then mat:setText('') end
  local costLabel = tab:recursiveGetChildById('attrCostLabel')
  if costLabel then costLabel:setText('') end
end

-- Clear slot after forge (preserves result message)
function clearAttrSlot()
  attrSourcePos = nil
  attrCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local slot = tab:recursiveGetChildById('attrSourceItem')
  if slot then slot:setItem(nil) end

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then itemInfo:setText('') end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then list:destroyChildren() end

  for _, id in ipairs({'attrAddEnchant', 'attrRerollLast', 'attrRerollAll', 'attrRemoveLast', 'attrRemoveAll'}) do
    local btn = tab:recursiveGetChildById(id)
    if btn then btn:setEnabled(false) end
  end

  updatePlaceholder(tab, 'attrPlaceholder', false)
  local mat = tab:recursiveGetChildById('attrMaterialLabel')
  if mat then mat:setText('') end
  local costLabel = tab:recursiveGetChildById('attrCostLabel')
  if costLabel then costLabel:setText('') end
end

-- ==========================================
-- TOOLS TAB (UPGRADE)
-- ==========================================

function setupToolsTab(tab)
  local sourceItem = tab:recursiveGetChildById('toolsSourceItem')
  local forgBtn = tab:recursiveGetChildById('toolsForgeButton')
  local bonusBtn = tab:recursiveGetChildById('toolsBonusButton')

  setupItemSlot(sourceItem, 'TOOLS', tab)

  if bonusBtn then
    bonusBtn.onClick = function()
      toolsBonusActive = not toolsBonusActive
      if toolsBonusActive then
        bonusBtn:setColor('#00ff00')
        bonusBtn:setText(tr('+20%% ON'))
      else
        bonusBtn:setColor('#3399ff')
        bonusBtn:setText(tr('+20%%'))
      end
      if toolsCostData then
        updateToolsCostDisplay(tab)
      end
    end
  end

  forgBtn.onClick = function()
    if toolsSourcePos and not forging then
      forgBtn:setEnabled(false)
      runForgeAnimation('toolsProgressBar', function()
        local msg = 'FORGE:UPGRADE:' .. posToStr(toolsSourcePos)
        if toolsBonusActive then msg = msg .. ':BONUS' end
        sendToServer(msg)
      end)
    end
  end
end

function updateToolsCostDisplay(tab)
  if not toolsCostData then return end
  local costLabel = tab:recursiveGetChildById('toolsCostLabel')
  if costLabel then
    local totalCost = toolsCostData.cost
    if toolsBonusActive then totalCost = totalCost + toolsCostData.bonusCost end
    local hasEnough = toolsCostData.playerGold >= totalCost
    costLabel:setText(tr('Cost') .. ': ' .. totalCost .. ' crystal coins (' .. tr('You have') .. ': ' .. toolsCostData.playerGold .. ')')
    costLabel:setColor(hasEnough and '#ffcc00' or '#ff3333')
  end
  local forgBtn = tab:recursiveGetChildById('toolsForgeButton')
  if forgBtn then
    local totalCost = toolsCostData.cost
    if toolsBonusActive then totalCost = totalCost + toolsCostData.bonusCost end
    local hasEnough = toolsCostData.playerGold >= totalCost
    forgBtn:setEnabled(toolsCostData.canForge and toolsCostData.hasRune and hasEnough and not forging)
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
  local hasRune = data.hasRune or false

  -- Cache cost data
  toolsCostData = {
    cost = data.cost or 0,
    bonusCost = data.bonusCost or 0,
    playerGold = data.playerGold or 0,
    canForge = canForge,
    hasRune = hasRune
  }

  local levelLabel = tab:recursiveGetChildById('toolsSourceLevelLabel')
  if levelLabel then
    levelLabel:setText(tr('Current') .. ': +' .. level)
  end

  local resultLabel = tab:recursiveGetChildById('toolsResultLevelLabel')
  if resultLabel then
    if level < maxLevel then
      resultLabel:setText(tr('Next') .. ': +' .. (level + 1))
      resultLabel:setColor('#00ff00')
    else
      resultLabel:setText(tr('Maximum') .. ' (+' .. maxLevel .. ')')
      resultLabel:setColor('#ffcc00')
    end
  end

  local chanceLabel = tab:recursiveGetChildById('toolsChanceLabel')
  if chanceLabel then
    chanceLabel:setText(tr('Chance') .. ': ' .. chance .. '%')
    if chance >= 60 then chanceLabel:setColor('#00ff00')
    elseif chance >= 30 then chanceLabel:setColor('#ffcc00')
    else chanceLabel:setColor('#ff3333') end
  end

  local matLabel = tab:recursiveGetChildById('toolsMaterialLabel')
  if matLabel then
    local rune = FORGE_RUNES.UPGRADE
    if hasRune then
      matLabel:setText(tr('Required') .. ': ' .. rune.name .. ' [OK]')
      matLabel:setColor('#00ff00')
    else
      matLabel:setText(tr('Required') .. ': ' .. rune.name .. ' [' .. tr('Missing') .. ']')
      matLabel:setColor('#ff3333')
    end
  end

  local forgBtn = tab:recursiveGetChildById('toolsForgeButton')
  if forgBtn then forgBtn:setEnabled(canForge and hasRune and not forging) end

  -- Display cost
  updateToolsCostDisplay(tab)
end

function clearToolsInfo()
  toolsSourcePos = nil
  toolsBonusActive = false
  toolsCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('toolsTab')
  if not tab then return end
  local slot = tab:recursiveGetChildById('toolsSourceItem')
  if slot then slot:setItem(nil) end
  for _, id in ipairs({'toolsSourceLevelLabel', 'toolsResultLevelLabel', 'toolsChanceLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('toolsForgeButton')
  if btn then btn:setEnabled(false) end
  local bonusBtn = tab:recursiveGetChildById('toolsBonusButton')
  if bonusBtn then bonusBtn:setColor('#3399ff'); bonusBtn:setText(tr('+20%%')) end
  updatePlaceholder(tab, 'toolsPlaceholder', false)
  local msg = tab:recursiveGetChildById('toolsResultMessage')
  if msg then msg:setText('') end
  local mat = tab:recursiveGetChildById('toolsMaterialLabel')
  if mat then mat:setText('') end
  local costLabel = tab:recursiveGetChildById('toolsCostLabel')
  if costLabel then costLabel:setText('') end
end

-- Clear slot after forge (preserves result message)
function clearToolsSlot()
  toolsSourcePos = nil
  toolsBonusActive = false
  toolsCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('toolsTab')
  if not tab then return end
  local slot = tab:recursiveGetChildById('toolsSourceItem')
  if slot then slot:setItem(nil) end
  local bonusBtn = tab:recursiveGetChildById('toolsBonusButton')
  if bonusBtn then bonusBtn:setColor('#3399ff'); bonusBtn:setText(tr('+20%%')) end
  for _, id in ipairs({'toolsSourceLevelLabel', 'toolsResultLevelLabel', 'toolsChanceLabel', 'toolsMaterialLabel', 'toolsCostLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('toolsForgeButton')
  if btn then btn:setEnabled(false) end
  updatePlaceholder(tab, 'toolsPlaceholder', false)
end

-- ==========================================
-- SERVER DATA HANDLER
-- ==========================================

function onForgeData(protocol, opcode, buffer)
  if not buffer or #buffer == 0 then return end

  -- CLASS_INFO:currentTier,nextTier,chance,canForge,hasRune,cost,bonusCost,playerGold
  if buffer:sub(1, 11) == 'CLASS_INFO:' then
    local parts = splitStr(buffer:sub(12), ',')
    if #parts >= 5 then
      updateClassInfo({
        currentTier = tonumber(parts[1]) or 0,
        nextTier = tonumber(parts[2]) or 0,
        chance = tonumber(parts[3]) or 0,
        canForge = parts[4] == '1',
        hasRune = parts[5] == '1',
        cost = tonumber(parts[6]) or 0,
        bonusCost = tonumber(parts[7]) or 0,
        playerGold = tonumber(parts[8]) or 0
      })
    end

  -- ATTR_INFO:tier,slotsUsed,slotsMax,hasAdd,hasRerollLast,hasRerollAll,hasRemoveLast,hasRemoveAll,costAdd,costRerollLast,costRerollAll,costRemoveLast,costRemoveAll,bonusCost,playerGold|enchName1=val1|...
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
        runeFlags = {
          hasAdd = mainParts[4] == '1',
          hasRerollLast = mainParts[5] == '1',
          hasRerollAll = mainParts[6] == '1',
          hasRemoveLast = mainParts[7] == '1',
          hasRemoveAll = mainParts[8] == '1',
        },
        costs = {
          add = tonumber(mainParts[9]) or 0,
          rerollLast = tonumber(mainParts[10]) or 0,
          rerollAll = tonumber(mainParts[11]) or 0,
          removeLast = tonumber(mainParts[12]) or 0,
          removeAll = tonumber(mainParts[13]) or 0,
        },
        bonusCost = tonumber(mainParts[14]) or 0,
        playerGold = tonumber(mainParts[15]) or 0,
        enchantments = enchantments
      })
    end

  -- TOOLS_INFO:level,maxLevel,chance,canForge,hasRune,cost,bonusCost,playerGold
  elseif buffer:sub(1, 11) == 'TOOLS_INFO:' then
    local parts = splitStr(buffer:sub(12), ',')
    if #parts >= 5 then
      updateToolsInfo({
        level = tonumber(parts[1]) or 0,
        maxLevel = tonumber(parts[2]) or 0,
        chance = tonumber(parts[3]) or 0,
        canForge = parts[4] == '1',
        hasRune = parts[5] == '1',
        cost = tonumber(parts[6]) or 0,
        bonusCost = tonumber(parts[7]) or 0,
        playerGold = tonumber(parts[8]) or 0
      })
    end

  -- FORGE_RESULT:tab,success
  elseif buffer:sub(1, 13) == 'FORGE_RESULT:' then
    local parts = splitStr(buffer:sub(14), ',')
    if #parts >= 2 then
      local tab = parts[1]
      local success = parts[2] == '1'

      -- Show result feedback, then clear slot (preserving result message)
      if tab == 'CLASS' then
        showResultMessage('classResultMessage', success)
        clearClassSlot()
      elseif tab == 'ATTR' then
        showResultMessage('attrResultMessage', success)
        clearAttrSlot()
      elseif tab == 'TOOLS' then
        showResultMessage('toolsResultMessage', success)
        clearToolsSlot()
      end
    end

  -- FORGE_ERROR:message
  elseif buffer:sub(1, 12) == 'FORGE_ERROR:' then
    stopForgeAnimation()
    local errorMsg = buffer:sub(13)
    -- Show error in the active tab's result label
    if forgeWindow then
      local labels = {'classResultMessage', 'attrResultMessage', 'toolsResultMessage'}
      for _, id in ipairs(labels) do
        local label = forgeWindow:recursiveGetChildById(id)
        if label then
          label:setText(errorMsg)
          label:setColor('#ff3333')
        end
      end
      scheduleEvent(function()
        if forgeWindow then
          for _, id in ipairs(labels) do
            local label = forgeWindow:recursiveGetChildById(id)
            if label then label:setText('') end
          end
        end
      end, 3000)
    end
  end
end
