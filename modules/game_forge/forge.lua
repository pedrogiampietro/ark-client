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

local TIER_RARITY_IMAGES = {
  [1] = '/images/ui/rarity_white',
  [2] = '/images/ui/rarity_green',
  [3] = '/images/ui/rarity_blue',
  [4] = '/images/ui/rarity_purple',
  [5] = '/images/ui/rarity_gold'
}

local FORGE_RUNES = {
  TIER_UP = { id = 2312, name = 'Rune of Tiering' },
  UPGRADE = { id = 2284, name = 'Rune of Upgrading' },
  ENCHANT_ADD = { id = 2276, name = 'Rune of Enchanting' },
  ENCHANT_REROLL_LAST = { id = 2272, name = 'Rune of Rolling' },
  ENCHANT_REROLL_ALL = { id = 2296, name = 'Rune of Total Rolling' },
  ENCHANT_REMOVE_LAST = { id = 2270, name = 'Rune of Cleansing' },
  ENCHANT_REMOVE_ALL = { id = 2298, name = 'Rune of Total Cleansing' },
  ENCHANT_REPLACE = { id = 2272, name = 'Rune of Rolling' },
}

local PROTECTION_RUNES = {
  TIER = { id = 2309, name = 'Tier Protection' },
  UPGRADE = { id = 2283, name = 'Upgrade Protection' },
}

local ATTR_ACTIONS = {
  { key = 'ENCHANT_ADD', label = 'Add Enchantment', runeKey = 'hasAdd', countKey = 'addCount', costKey = 'add',
    desc = 'Adds a random enchantment to the next free slot. The enchantment type depends on the item slot and the tier of the slot being filled.' },
  { key = 'ENCHANT_REROLL_LAST', label = 'Reroll Last', runeKey = 'hasRerollLast', countKey = 'rerollLastCount', costKey = 'rerollLast',
    desc = 'Rerolls the last enchantment, generating a new random type and value for that slot.' },
  { key = 'ENCHANT_REROLL_ALL', label = 'Reroll All', runeKey = 'hasRerollAll', countKey = 'rerollAllCount', costKey = 'rerollAll',
    desc = 'Rerolls all enchantments on the item, generating new random types and values for every slot.' },
  { key = 'ENCHANT_REMOVE_LAST', label = 'Remove Last', runeKey = 'hasRemoveLast', countKey = 'removeLastCount', costKey = 'removeLast',
    desc = 'Removes the last enchantment from the item, freeing up the slot for a new one.' },
  { key = 'ENCHANT_REMOVE_ALL', label = 'Remove All', runeKey = 'hasRemoveAll', countKey = 'removeAllCount', costKey = 'removeAll',
    desc = 'Removes all enchantments from the item, freeing up all slots.' },
  { key = 'ENCHANT_REPLACE', label = 'Replace Attribute', runeKey = 'hasReplace', countKey = 'replaceCount', costKey = 'replace',
    desc = 'Replaces the attribute in a chosen slot with another valid attribute for that slot. The new value is random.' },
}

-- State
forgeWindow = nil
local forgeTabBar = nil
local forgeButton = nil
local forging = false
local forgeAnimEvent = nil

local classSourcePos = nil
local attrSourcePos = nil
local toolsSourcePos = nil

local classBonusActive = false
local toolsBonusActive = false

local classCostData = nil
local toolsCostData = nil
local attrCostData = nil

local selectedAttrAction = 1
local selectedAttrReplaceSlot = nil   -- 1-based slot index for Replace
local selectedAttrReplaceEnchantId = nil -- enchantment ID for Replace
local _updatingAttrReplaceUI = false  -- guard to avoid recursion when filling replace combos

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
    selectedAttrAction = 1
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

local function updateForgeBalance(gold)
  if not forgeWindow then return end
  local balanceLabel = forgeWindow:getChildById('forgeBalanceLabel')
  if balanceLabel then
    balanceLabel:setText((gold or 0) .. ' cc')
  end
end

local function updatePlaceholder(tab, placeholderId, hasItem)
  local placeholder = tab:recursiveGetChildById(placeholderId)
  if placeholder then
    placeholder:setVisible(not hasItem)
  end
end

local function setupRuneSlot(tab, slotId, runeId, count, total)
  local slot = tab:recursiveGetChildById(slotId)
  if not slot then return end

  local runeItem = slot:recursiveGetChildById('runeItem')
  if runeItem then
    runeItem:setItemId(runeId)
  end

  local countLabel = slot:recursiveGetChildById('runeCount')
  if countLabel then
    local displayCount = count or 0
    local displayTotal = total or 1
    countLabel:setText(displayCount .. ' / ' .. displayTotal)
    if displayCount >= displayTotal then
      countLabel:setColor('#00ff00')
    else
      countLabel:setColor('#ff3333')
    end
  end
end

local function clearRuneSlot(tab, slotId)
  local slot = tab:recursiveGetChildById(slotId)
  if not slot then return end

  local runeItem = slot:recursiveGetChildById('runeItem')
  if runeItem then
    runeItem:setItemId(0)
  end

  local countLabel = slot:recursiveGetChildById('runeCount')
  if countLabel then
    countLabel:setText('')
  end
end

local function setupItemSlot(slot, tabType, tab)
  slot.onDrop = function(self, widget, mousePos, forced)
    if forging then return false end
    if not self:canAcceptDrop(widget, mousePos) and not forced then return false end
    local item = widget.currentDragThing
    if not item or not item:isItem() then return false end
    if not item:isPickupable() then return false end

    local srcPos = item:getPosition()
    local itemCopy = Item.create(item:getId(), item:getCountOrSubType())
    self:setItem(itemCopy)

    local resultItemId = ({CLASS = 'classResultItem', TOOLS = 'toolsResultItem'})[tabType]
    if resultItemId then
      local resultItem = tab:recursiveGetChildById(resultItemId)
      if resultItem then
        resultItem:setItem(Item.create(item:getId(), item:getCountOrSubType()))
      end
    end

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
      bonusBtn:setOn(classBonusActive)
      if classCostData then
        updateClassCostDisplay(tab)
      end
    end
  end

  if forgBtn then
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
end

function updateClassCostDisplay(tab)
  if not classCostData then return end
  local totalCost = classCostData.cost
  if classBonusActive then totalCost = totalCost + classCostData.bonusCost end
  local hasEnough = classCostData.playerGold >= totalCost

  local costLabel = tab:recursiveGetChildById('classCostLabel')
  if costLabel then
    costLabel:setText(totalCost .. ' cc')
    costLabel:setColor(hasEnough and '#ffcc00' or '#ff3333')
  end

  local bonusCostLabel = tab:recursiveGetChildById('classBonusCostLabel')
  if bonusCostLabel then
    if classBonusActive then
      bonusCostLabel:setText(classCostData.bonusCost .. ' cc')
    else
      bonusCostLabel:setText('0 cc')
    end
  end

  local chanceLabel = tab:recursiveGetChildById('classChanceLabel')
  if chanceLabel then
    local effectiveChance = math.min(classCostData.chance + (classBonusActive and 20 or 0), 100)
    chanceLabel:setText(tr('Chance') .. ': ' .. effectiveChance .. '%')
    if effectiveChance >= 60 then chanceLabel:setColor('#00ff00')
    elseif effectiveChance >= 30 then chanceLabel:setColor('#ffcc00')
    else chanceLabel:setColor('#ff3333') end
  end

  updateForgeBalance(classCostData.playerGold)

  local forgBtn = tab:recursiveGetChildById('classForgeButton')
  if forgBtn then
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

  classCostData = {
    cost = data.cost or 0,
    bonusCost = data.bonusCost or 0,
    playerGold = data.playerGold or 0,
    canForge = canForge,
    hasRune = hasRune,
    chance = chance
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

  local resultContainer = tab:recursiveGetChildById('classResultItemContainer')
  if resultContainer then
    local rarityImg = TIER_RARITY_IMAGES[nextTier]
    if rarityImg then
      resultContainer:setImageSource(rarityImg)
    else
      resultContainer:setImageSource('/images/ui/slot')
    end
  end

  setupRuneSlot(tab, 'classTierRuneSlot', FORGE_RUNES.TIER_UP.id, data.runeCount or (hasRune and 1 or 0), 1)
  setupRuneSlot(tab, 'classProtRuneSlot', PROTECTION_RUNES.TIER.id, data.protectionCount or 0, 1)

  local matLabel = tab:recursiveGetChildById('classMaterialLabel')
  if matLabel then
    if not hasRune then
      matLabel:setText(FORGE_RUNES.TIER_UP.name .. ' [' .. tr('Missing') .. ']')
      matLabel:setColor('#ff3333')
    else
      matLabel:setText('')
    end
  end

  local forgBtn = tab:recursiveGetChildById('classForgeButton')
  if forgBtn then forgBtn:setEnabled(canForge and hasRune and not forging) end

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
  local resultItem = tab:recursiveGetChildById('classResultItem')
  if resultItem then resultItem:setItem(nil) end
  local resultContainer = tab:recursiveGetChildById('classResultItemContainer')
  if resultContainer then resultContainer:setImageSource('/images/ui/slot') end
  for _, id in ipairs({'classSourceTierLabel', 'classResultTierLabel', 'classChanceLabel', 'classCostLabel', 'classMaterialLabel', 'classBonusCostLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('classForgeButton')
  if btn then btn:setEnabled(false) end
  local bonusBtn = tab:recursiveGetChildById('classBonusButton')
  if bonusBtn then bonusBtn:setOn(false) end
  updatePlaceholder(tab, 'classPlaceholder', false)
  local msg = tab:recursiveGetChildById('classResultMessage')
  if msg then msg:setText('') end
  clearRuneSlot(tab, 'classTierRuneSlot')
  clearRuneSlot(tab, 'classProtRuneSlot')
end

function clearClassSlot()
  classSourcePos = nil
  classBonusActive = false
  classCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('classificationTab')
  if not tab then return end
  local slot = tab:recursiveGetChildById('classSourceItem')
  if slot then slot:setItem(nil) end
  local resultItem = tab:recursiveGetChildById('classResultItem')
  if resultItem then resultItem:setItem(nil) end
  local resultContainer = tab:recursiveGetChildById('classResultItemContainer')
  if resultContainer then resultContainer:setImageSource('/images/ui/slot') end
  local bonusBtn = tab:recursiveGetChildById('classBonusButton')
  if bonusBtn then bonusBtn:setOn(false) end
  for _, id in ipairs({'classSourceTierLabel', 'classResultTierLabel', 'classChanceLabel', 'classMaterialLabel', 'classCostLabel', 'classBonusCostLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('classForgeButton')
  if btn then btn:setEnabled(false) end
  updatePlaceholder(tab, 'classPlaceholder', false)
  clearRuneSlot(tab, 'classTierRuneSlot')
  clearRuneSlot(tab, 'classProtRuneSlot')
end

-- ==========================================
-- ATTRIBUTES TAB (ENCHANTMENTS)
-- ==========================================

function setupAttributesTab(tab)
  local sourceItem = tab:recursiveGetChildById('attrSourceItem')
  setupItemSlot(sourceItem, 'ATTR', tab)

  local combo = tab:recursiveGetChildById('attrActionCombo')
  if combo then
    for i, action in ipairs(ATTR_ACTIONS) do
      combo:addOption(tr(action.label))
    end
    combo.onOptionChange = function(widget)
      selectedAttrAction = widget.currentIndex
      selectedAttrReplaceSlot = nil
      selectedAttrReplaceEnchantId = nil
      updateAttrActionDisplay(tab)
    end
  end

  local replaceSlotCombo = tab:recursiveGetChildById('attrReplaceSlotCombo')
  if replaceSlotCombo then
    replaceSlotCombo.onOptionChange = function(widget)
      if _updatingAttrReplaceUI then return end
      _updatingAttrReplaceUI = true
      -- UIComboBox uses 1-based currentIndex
      selectedAttrReplaceSlot = math.max(1, widget.currentIndex or 1)
      selectedAttrReplaceEnchantId = nil
      -- Fill attribute combo for this slot
      local avail = attrCostData and attrCostData.availableForSlot and attrCostData.availableForSlot[selectedAttrReplaceSlot]
      local attrCombo = tab:recursiveGetChildById('attrReplaceAttrCombo')
      if attrCombo and avail and avail.names then
        attrCombo:clearOptions()
        for _, name in ipairs(avail.names) do
          attrCombo:addOption(name)
        end
        attrCombo:setCurrentIndex(1, true)
        if avail.ids and avail.ids[1] then
          selectedAttrReplaceEnchantId = avail.ids[1]
        end
      end
      updateAttrActionDisplay(tab)
      scheduleEvent(function()
        _updatingAttrReplaceUI = false
      end, 50)
    end
  end

  local replaceAttrCombo = tab:recursiveGetChildById('attrReplaceAttrCombo')
  if replaceAttrCombo then
    replaceAttrCombo.onOptionChange = function(widget)
      if _updatingAttrReplaceUI then return end
      local slot = selectedAttrReplaceSlot
      local avail = attrCostData and attrCostData.availableForSlot and slot and attrCostData.availableForSlot[slot]
      -- UIComboBox uses 1-based currentIndex
      local idx = widget.currentIndex or 1
      if avail and avail.ids and avail.ids[idx] then
        selectedAttrReplaceEnchantId = avail.ids[idx]
      else
        selectedAttrReplaceEnchantId = nil
      end
      updateAttrActionDisplay(tab)
    end
  end

  local execBtn = tab:recursiveGetChildById('attrExecuteButton')
  if execBtn then
    execBtn.onClick = function()
      if attrSourcePos and not forging then
        local action = ATTR_ACTIONS[selectedAttrAction]
        if action then
          execBtn:setEnabled(false)
          local posStr = posToStr(attrSourcePos)
          local msg
          if action.key == 'ENCHANT_REPLACE' and selectedAttrReplaceSlot and selectedAttrReplaceEnchantId then
            msg = 'FORGE:ENCHANT_REPLACE:' .. posStr .. ':' .. tostring(selectedAttrReplaceSlot) .. ':' .. tostring(selectedAttrReplaceEnchantId)
          else
            msg = 'FORGE:' .. action.key .. ':' .. posStr
          end
          runForgeAnimation('attrProgressBar', function()
            sendToServer(msg)
          end)
        end
      end
    end
  end
end

function updateAttrActionDisplay(tab)
  if not tab then
    if not forgeWindow then return end
    tab = forgeWindow:recursiveGetChildById('attributesTab')
    if not tab then return end
  end

  local action = ATTR_ACTIONS[selectedAttrAction]
  if not action then return end

  local replaceSlotLabel = tab:recursiveGetChildById('attrReplaceSlotLabel')
  local replaceSlotCombo = tab:recursiveGetChildById('attrReplaceSlotCombo')
  local replaceAttrLabel = tab:recursiveGetChildById('attrReplaceAttrLabel')
  local replaceAttrCombo = tab:recursiveGetChildById('attrReplaceAttrCombo')

  local isReplace = (action.key == 'ENCHANT_REPLACE')
  if replaceSlotLabel then replaceSlotLabel:setVisible(isReplace) end
  if replaceSlotCombo then replaceSlotCombo:setVisible(isReplace) end
  if replaceAttrLabel then replaceAttrLabel:setVisible(isReplace) end
  if replaceAttrCombo then replaceAttrCombo:setVisible(isReplace) end

  -- Rune title is always anchored to attrReplacePanel.bottom in OTUI (panel has fixed height for Slot + New attribute)
  if isReplace and attrCostData then
    local slotsUsed = attrCostData.slotsUsed or 0
    if replaceSlotCombo and slotsUsed > 0 then
      _updatingAttrReplaceUI = true
      -- Only rebuild slot options when count changed, to avoid ComboBox firing onOptionChange(0) and resetting to slot 1
      local optsCount = (replaceSlotCombo.getOptionsCount and replaceSlotCombo:getOptionsCount()) or 0
      if optsCount ~= slotsUsed then
        replaceSlotCombo:clearOptions()
        for i = 1, slotsUsed do
          replaceSlotCombo:addOption(tostring(i))
        end
      end
      if not selectedAttrReplaceSlot or selectedAttrReplaceSlot > slotsUsed or selectedAttrReplaceSlot < 1 then
        selectedAttrReplaceSlot = 1
      end
      -- UIComboBox is 1-based; dontSignal to avoid onOptionChange resetting selection
      replaceSlotCombo:setCurrentIndex(selectedAttrReplaceSlot, true)
      local avail = attrCostData.availableForSlot and attrCostData.availableForSlot[selectedAttrReplaceSlot]
      if replaceAttrCombo and avail and avail.names then
        replaceAttrCombo:clearOptions()
        for _, name in ipairs(avail.names) do
          replaceAttrCombo:addOption(name)
        end
        local attrIdx = 0
        if avail.ids and selectedAttrReplaceEnchantId then
          for i, id in ipairs(avail.ids) do
            if id == selectedAttrReplaceEnchantId then attrIdx = i - 1 break end
          end
        end
        replaceAttrCombo:setCurrentIndex(attrIdx + 1, true)
        if avail.ids and avail.ids[attrIdx + 1] then
          selectedAttrReplaceEnchantId = avail.ids[attrIdx + 1]
        elseif avail.ids and avail.ids[1] then
          selectedAttrReplaceEnchantId = avail.ids[1]
        else
          selectedAttrReplaceEnchantId = nil
        end
      else
        selectedAttrReplaceEnchantId = nil
      end
      _updatingAttrReplaceUI = false
    end
  end

  local rune = FORGE_RUNES[action.key]
  if rune then
    local runeCount = 0
    if attrCostData and attrCostData.runeCounts and attrCostData.runeCounts[action.countKey] then
      runeCount = attrCostData.runeCounts[action.countKey]
    end
    setupRuneSlot(tab, 'attrRuneSlot', rune.id, runeCount, 1)
  end

  local costLabel = tab:recursiveGetChildById('attrCostLabel')
  if costLabel then
    local cost = 0
    if attrCostData and attrCostData.costs and attrCostData.costs[action.costKey] then
      cost = attrCostData.costs[action.costKey]
    end
    local playerGold = (attrCostData and attrCostData.playerGold) or 0
    costLabel:setText(cost .. ' crystal coins')
    costLabel:setColor(playerGold >= cost and '#ffcc00' or '#ff3333')
  end

  local descLabel = tab:recursiveGetChildById('attrDescLabel')
  if descLabel then
    descLabel:setText(tr(action.desc))
  end

  local execBtn = tab:recursiveGetChildById('attrExecuteButton')
  if execBtn then
    local canDo = false
    if attrCostData then
      local hasRune = not not (attrCostData.runeFlags and attrCostData.runeFlags[action.runeKey])
      local cost = attrCostData.costs and attrCostData.costs[action.costKey] or 0
      local hasEnough = (attrCostData.playerGold or 0) >= cost
      canDo = hasRune and hasEnough and not forging
      local tier = attrCostData.tier or 0
      local slotsUsed = attrCostData.slotsUsed or 0
      local slotsMax = attrCostData.slotsMax or 0

      if action.key == 'ENCHANT_ADD' then
        canDo = canDo and (tier > 0) and (slotsUsed < slotsMax)
      elseif action.key == 'ENCHANT_REROLL_LAST' or action.key == 'ENCHANT_REROLL_ALL'
          or action.key == 'ENCHANT_REMOVE_LAST' or action.key == 'ENCHANT_REMOVE_ALL' then
        canDo = canDo and (slotsUsed > 0)
      elseif action.key == 'ENCHANT_REPLACE' then
        canDo = canDo and (slotsUsed > 0) and (selectedAttrReplaceSlot and selectedAttrReplaceSlot >= 1)
            and (selectedAttrReplaceEnchantId ~= nil)
      end
    end
    execBtn:setEnabled(canDo)
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
    local tierName = TIER_NAMES[tier] or 'None'
    local tierColor = TIER_COLORS[tier] or '#c0c0c0'
    itemInfo:setText(tierName .. ' (' .. slotsUsed .. '/' .. slotsMax .. ' ' .. tr('slots') .. ')')
    itemInfo:setColor(tierColor)
  end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then
    list:destroyChildren()
    if data.enchantments then
      for i, ench in ipairs(data.enchantments) do
        local row = g_ui.createWidget('ForgeEnchantRow', list)
        local slotIdx = row:recursiveGetChildById('slotIndex')
        local enchName = row:recursiveGetChildById('enchantName')
        if slotIdx then
          slotIdx:setText('[' .. i .. ']')
          slotIdx:setColor('#888888')
        end
        if enchName then
          enchName:setText(ench.name .. ': ' .. ench.value)
          enchName:setColor('#c0ffee')
        end
      end
    end
    for i = slotsUsed + 1, slotsMax do
      local row = g_ui.createWidget('ForgeEnchantRow', list)
      local slotIdx = row:recursiveGetChildById('slotIndex')
      local enchName = row:recursiveGetChildById('enchantName')
      if slotIdx then
        slotIdx:setText('[' .. i .. ']')
        slotIdx:setColor('#666666')
      end
      if enchName then
        enchName:setText(tr('empty'))
        enchName:setColor('#666666')
      end
    end
  end

  attrCostData = {
    tier = tier,
    slotsUsed = slotsUsed,
    slotsMax = slotsMax,
    runeFlags = data.runeFlags or {},
    costs = data.costs or {},
    runeCounts = data.runeCounts or {},
    bonusCost = data.bonusCost or 0,
    playerGold = data.playerGold or 0,
    availableForSlot = data.availableForSlot or {}
  }

  updateForgeBalance(data.playerGold or 0)
  updateAttrActionDisplay(tab)
end

function clearAttrInfo()
  attrSourcePos = nil
  attrCostData = nil
  selectedAttrReplaceSlot = nil
  selectedAttrReplaceEnchantId = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local slot = tab:recursiveGetChildById('attrSourceItem')
  if slot then slot:setItem(nil) end

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then itemInfo:setText('') end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then list:destroyChildren() end

  local execBtn = tab:recursiveGetChildById('attrExecuteButton')
  if execBtn then execBtn:setEnabled(false) end

  updatePlaceholder(tab, 'attrPlaceholder', false)
  local msg = tab:recursiveGetChildById('attrResultMessage')
  if msg then msg:setText('') end
  local costLabel = tab:recursiveGetChildById('attrCostLabel')
  if costLabel then costLabel:setText('') end
  clearRuneSlot(tab, 'attrRuneSlot')
end

function clearAttrSlot()
  attrSourcePos = nil
  attrCostData = nil
  selectedAttrReplaceSlot = nil
  selectedAttrReplaceEnchantId = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('attributesTab')
  if not tab then return end

  local slot = tab:recursiveGetChildById('attrSourceItem')
  if slot then slot:setItem(nil) end

  local itemInfo = tab:recursiveGetChildById('attrItemInfo')
  if itemInfo then itemInfo:setText('') end

  local list = tab:recursiveGetChildById('attrEnchantList')
  if list then list:destroyChildren() end

  local execBtn = tab:recursiveGetChildById('attrExecuteButton')
  if execBtn then execBtn:setEnabled(false) end

  updatePlaceholder(tab, 'attrPlaceholder', false)
  local costLabel = tab:recursiveGetChildById('attrCostLabel')
  if costLabel then costLabel:setText('') end
  clearRuneSlot(tab, 'attrRuneSlot')
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
      bonusBtn:setOn(toolsBonusActive)
      if toolsCostData then
        updateToolsCostDisplay(tab)
      end
    end
  end

  if forgBtn then
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
end

function updateToolsCostDisplay(tab)
  if not toolsCostData then return end
  local totalCost = toolsCostData.cost
  if toolsBonusActive then totalCost = totalCost + toolsCostData.bonusCost end
  local hasEnough = toolsCostData.playerGold >= totalCost

  local costLabel = tab:recursiveGetChildById('toolsCostLabel')
  if costLabel then
    costLabel:setText(totalCost .. ' cc')
    costLabel:setColor(hasEnough and '#ffcc00' or '#ff3333')
  end

  local bonusCostLabel = tab:recursiveGetChildById('toolsBonusCostLabel')
  if bonusCostLabel then
    if toolsBonusActive then
      bonusCostLabel:setText(toolsCostData.bonusCost .. ' cc')
    else
      bonusCostLabel:setText('0 cc')
    end
  end

  local chanceLabel = tab:recursiveGetChildById('toolsChanceLabel')
  if chanceLabel then
    local effectiveChance = math.min(toolsCostData.chance + (toolsBonusActive and 20 or 0), 100)
    chanceLabel:setText(tr('Chance') .. ': ' .. effectiveChance .. '%')
    if effectiveChance >= 60 then chanceLabel:setColor('#00ff00')
    elseif effectiveChance >= 30 then chanceLabel:setColor('#ffcc00')
    else chanceLabel:setColor('#ff3333') end
  end

  updateForgeBalance(toolsCostData.playerGold)

  local forgBtn = tab:recursiveGetChildById('toolsForgeButton')
  if forgBtn then
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

  toolsCostData = {
    cost = data.cost or 0,
    bonusCost = data.bonusCost or 0,
    playerGold = data.playerGold or 0,
    canForge = canForge,
    hasRune = hasRune,
    chance = chance
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

  local resultContainer = tab:recursiveGetChildById('toolsResultItemContainer')
  if resultContainer then
    resultContainer:setImageSource('/images/ui/slot')
  end

  setupRuneSlot(tab, 'toolsUpgradeRuneSlot', FORGE_RUNES.UPGRADE.id, data.runeCount or (hasRune and 1 or 0), 1)
  setupRuneSlot(tab, 'toolsProtRuneSlot', PROTECTION_RUNES.UPGRADE.id, data.protectionCount or 0, 1)

  local matLabel = tab:recursiveGetChildById('toolsMaterialLabel')
  if matLabel then
    if not hasRune then
      matLabel:setText(FORGE_RUNES.UPGRADE.name .. ' [' .. tr('Missing') .. ']')
      matLabel:setColor('#ff3333')
    else
      matLabel:setText('')
    end
  end

  local forgBtn = tab:recursiveGetChildById('toolsForgeButton')
  if forgBtn then forgBtn:setEnabled(canForge and hasRune and not forging) end

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
  local resultItem = tab:recursiveGetChildById('toolsResultItem')
  if resultItem then resultItem:setItem(nil) end
  local resultContainer = tab:recursiveGetChildById('toolsResultItemContainer')
  if resultContainer then resultContainer:setImageSource('/images/ui/slot') end
  for _, id in ipairs({'toolsSourceLevelLabel', 'toolsResultLevelLabel', 'toolsChanceLabel', 'toolsCostLabel', 'toolsMaterialLabel', 'toolsBonusCostLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('toolsForgeButton')
  if btn then btn:setEnabled(false) end
  local bonusBtn = tab:recursiveGetChildById('toolsBonusButton')
  if bonusBtn then bonusBtn:setOn(false) end
  updatePlaceholder(tab, 'toolsPlaceholder', false)
  local msg = tab:recursiveGetChildById('toolsResultMessage')
  if msg then msg:setText('') end
  clearRuneSlot(tab, 'toolsUpgradeRuneSlot')
  clearRuneSlot(tab, 'toolsProtRuneSlot')
end

function clearToolsSlot()
  toolsSourcePos = nil
  toolsBonusActive = false
  toolsCostData = nil
  if not forgeWindow then return end
  local tab = forgeWindow:recursiveGetChildById('toolsTab')
  if not tab then return end
  local slot = tab:recursiveGetChildById('toolsSourceItem')
  if slot then slot:setItem(nil) end
  local resultItem = tab:recursiveGetChildById('toolsResultItem')
  if resultItem then resultItem:setItem(nil) end
  local resultContainer = tab:recursiveGetChildById('toolsResultItemContainer')
  if resultContainer then resultContainer:setImageSource('/images/ui/slot') end
  local bonusBtn = tab:recursiveGetChildById('toolsBonusButton')
  if bonusBtn then bonusBtn:setOn(false) end
  for _, id in ipairs({'toolsSourceLevelLabel', 'toolsResultLevelLabel', 'toolsChanceLabel', 'toolsMaterialLabel', 'toolsCostLabel', 'toolsBonusCostLabel'}) do
    local w = tab:recursiveGetChildById(id)
    if w then w:setText('') end
  end
  local btn = tab:recursiveGetChildById('toolsForgeButton')
  if btn then btn:setEnabled(false) end
  updatePlaceholder(tab, 'toolsPlaceholder', false)
  clearRuneSlot(tab, 'toolsUpgradeRuneSlot')
  clearRuneSlot(tab, 'toolsProtRuneSlot')
end

-- ==========================================
-- SERVER DATA HANDLER
-- ==========================================

function onForgeData(protocol, opcode, buffer)
  if not buffer or #buffer == 0 then return end

  -- CLASS_INFO:currentTier,nextTier,chance,canForge,hasRune,cost,bonusCost,playerGold,runeCount,protectionCount
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
        playerGold = tonumber(parts[8]) or 0,
        runeCount = tonumber(parts[9]) or 0,
        protectionCount = tonumber(parts[10]) or 0
      })
    end

  -- ATTR_INFO:tier,slotsUsed,slotsMax,hasAdd,hasRerollLast,hasRerollAll,hasRemoveLast,hasRemoveAll,hasReplace,
  --   costAdd,costRerollLast,costRerollAll,costRemoveLast,costRemoveAll,costReplace,bonusCost,playerGold,
  --   addCount,...,replaceCount|enchName1=val1|...|S1=id1,id2|A1=name1\tname2|...
  elseif buffer:sub(1, 10) == 'ATTR_INFO:' then
    local sections = splitStr(buffer:sub(11), '|')
    if #sections >= 1 then
      local mainParts = splitStr(sections[1], ',')
      local enchantments = {}
      local availableForSlot = {}
      for i = 2, #sections do
        local s = sections[i]
        local eqPos = s:find('=')
        if eqPos then
          local key = s:sub(1, eqPos - 1)
          local val = s:sub(eqPos + 1)
          if key:sub(1, 1) == 'S' and key:match('^S%d+$') then
            local slotNum = tonumber(key:sub(2))
            if slotNum then
              local ids = {}
              for idStr in val:gmatch('[^,]+') do
                local id = tonumber(idStr)
                if id then table.insert(ids, id) end
              end
              availableForSlot[slotNum] = availableForSlot[slotNum] or { ids = {}, names = {} }
              availableForSlot[slotNum].ids = ids
            end
          elseif key:sub(1, 1) == 'A' and key:match('^A%d+$') then
            local slotNum = tonumber(key:sub(2))
            if slotNum then
              local names = {}
              for name in val:gmatch('[^\t]+') do table.insert(names, name) end
              availableForSlot[slotNum] = availableForSlot[slotNum] or { ids = {}, names = {} }
              availableForSlot[slotNum].names = names
            end
          else
            table.insert(enchantments, { name = key, value = val })
          end
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
          hasReplace = mainParts[9] == '1',
        },
        costs = {
          add = tonumber(mainParts[10]) or 0,
          rerollLast = tonumber(mainParts[11]) or 0,
          rerollAll = tonumber(mainParts[12]) or 0,
          removeLast = tonumber(mainParts[13]) or 0,
          removeAll = tonumber(mainParts[14]) or 0,
          replace = tonumber(mainParts[15]) or 0,
        },
        bonusCost = tonumber(mainParts[16]) or 0,
        playerGold = tonumber(mainParts[17]) or 0,
        runeCounts = {
          addCount = tonumber(mainParts[18]) or 0,
          rerollLastCount = tonumber(mainParts[19]) or 0,
          rerollAllCount = tonumber(mainParts[20]) or 0,
          removeLastCount = tonumber(mainParts[21]) or 0,
          removeAllCount = tonumber(mainParts[22]) or 0,
          replaceCount = tonumber(mainParts[23]) or 0,
        },
        enchantments = enchantments,
        availableForSlot = availableForSlot,
      })
    end

  -- TOOLS_INFO:level,maxLevel,chance,canForge,hasRune,cost,bonusCost,playerGold,runeCount,protectionCount
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
        playerGold = tonumber(parts[8]) or 0,
        runeCount = tonumber(parts[9]) or 0,
        protectionCount = tonumber(parts[10]) or 0
      })
    end

  -- FORGE_RESULT:tab,success
  elseif buffer:sub(1, 13) == 'FORGE_RESULT:' then
    local parts = splitStr(buffer:sub(14), ',')
    if #parts >= 2 then
      local tab = parts[1]
      local success = parts[2] == '1'

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
