-- Relic IDs allowed in the relic box
local RELIC_IDS = {
  [5130] = true, -- artifact of combat
  [5131] = true, -- artifact of mana leech
  [5132] = true, -- artifact of gold
  [5133] = true, -- artifact of protection
  [5134] = true, -- artifact of bounty
  [5135] = true, -- artifact of swiftness
  [5136] = true, -- artifact of sorcery
  [5137] = true, -- artifact of precision
  [5138] = true, -- artifact of arcane power
}

local NUM_SLOTS = 4

local relicBoxWindow = nil
local relicBoxButton = nil
local relicSlots = {}      -- UIItem widgets (the 4 slots)
local equippedRelics = {}  -- item stored in each slot index (1..4)

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function isRelic(item)
  if not item then return false end
  local ok, id = pcall(function() return item:getId() end)
  return ok and RELIC_IDS[id] == true
end

local function updateSlotVisual(slotIndex)
  local slot = relicSlots[slotIndex]
  local item = equippedRelics[slotIndex]
  if not slot then return end
  if item then
    slot:setStyle('InventoryItem')
    slot:setItem(item)
  else
    slot:setStyle('RelicSlot')
    slot:setItem(nil)
  end
end

local function notifyServerRelics()
  -- TODO (parte 2): send relic state to server via extended opcode
  local ids = {}
  for i = 1, NUM_SLOTS do
    local item = equippedRelics[i]
    ids[i] = item and item:getId() or 0
  end
  -- g_game.sendExtendedOpcode(OPCODE_RELICS, table.tostring(ids))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Slot interaction
-- ─────────────────────────────────────────────────────────────────────────────

local function slotIndexFromWidget(widget)
  return tonumber(widget:getId():match('relicSlot(%d+)'))
end

local function onSlotMousePress(widget, mousePos, mouseButton)
  local slotIndex = slotIndexFromWidget(widget)
  if not slotIndex then return false end

  if mouseButton == MouseRightButton then
    if equippedRelics[slotIndex] then
      equippedRelics[slotIndex] = nil
      updateSlotVisual(slotIndex)
      notifyServerRelics()
    end
    return true
  end

  return false
end

local function onSlotDrop(self, dragWidget, mousePos, forced)
  print('[RelicBox] onSlotDrop called. forced=' .. tostring(forced))

  if not self:canAcceptDrop(dragWidget, mousePos) and not forced then
    print('[RelicBox] canAcceptDrop=false, aborting')
    return false
  end

  local item = dragWidget.currentDragThing
  print('[RelicBox] currentDragThing=' .. tostring(item))

  if not item or not item:isItem() then
    print('[RelicBox] item is nil or not an item, aborting')
    return false
  end

  local ok, itemId = pcall(function() return item:getId() end)
  local pos = item:getPosition()
  print('[RelicBox] item:getId()=' .. tostring(ok and itemId or 'ERROR') ..
        ' pos={x=' .. tostring(pos and pos.x) ..
        ', y=' .. tostring(pos and pos.y) ..
        ', z=' .. tostring(pos and pos.z) .. '}')
  print('[RelicBox] dragWidget.position=' .. tostring(dragWidget.position))
  print('[RelicBox] self.position=' .. tostring(self.position))

  local slotIndex = slotIndexFromWidget(self)
  print('[RelicBox] slotIndex=' .. tostring(slotIndex))
  if not slotIndex then return false end

  if not isRelic(item) then
    print('[RelicBox] not a relic id, rejecting')
    modules.game_textmessage.displayMessage('Only relics can be placed in the relic box.', MessageInfo)
    return false
  end

  print('[RelicBox] equipping relic id=' .. tostring(itemId) .. ' in slot ' .. slotIndex)
  equippedRelics[slotIndex] = item
  updateSlotVisual(slotIndex)
  notifyServerRelics()
  print('[RelicBox] done, returning true')
  return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Window management
-- ─────────────────────────────────────────────────────────────────────────────

function toggle()
  if not relicBoxWindow then return end
  if relicBoxWindow:isVisible() then
    relicBoxWindow:hide()
    if relicBoxButton then relicBoxButton:setOn(false) end
  else
    relicBoxWindow:show()
    relicBoxWindow:raise()
    relicBoxWindow:focus()
    if relicBoxButton then relicBoxButton:setOn(true) end
  end
end

function onWindowClose()
  if relicBoxButton then relicBoxButton:setOn(false) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function init()
  -- Create the relic box window (style defined in data/styles/40-relicbox.otui)
  relicBoxWindow = g_ui.createWidget('RelicBoxWindow', modules.game_interface.getRightPanel())
  relicBoxWindow:setup()
  relicBoxWindow:hide()

  -- Wire up the 4 slot widgets
  for i = 1, NUM_SLOTS do
    local slot = relicBoxWindow:recursiveGetChildById('relicSlot' .. i)
    if slot then
      slot.onMousePress = onSlotMousePress
      slot.onDrop       = onSlotDrop
      relicSlots[i] = slot
    end
    equippedRelics[i] = nil
  end

  -- Connect to the RelicBoxButton defined in inventory.otui
  addEvent(function()
    local sbWindow = modules.game_sidebuttons and
                     modules.game_sidebuttons.buttonsWindow
    if not sbWindow then return end
    relicBoxButton = sbWindow:recursiveGetChildById('relicBoxButton')
    if relicBoxButton then
      relicBoxButton.onClick = toggle
    end
  end)

  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })

  if relicBoxWindow then
    relicBoxWindow:destroy()
    relicBoxWindow = nil
  end

  relicBoxButton = nil
  relicSlots = {}
  equippedRelics = {}
end

function onGameEnd()
  for i = 1, NUM_SLOTS do
    equippedRelics[i] = nil
    updateSlotVisual(i)
  end
end
