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
    if modules.game_rarity then
      modules.game_rarity.applyRarityFrame(slot, 2)  -- tier 2 = green
    end
  else
    slot:setStyle('RelicSlot')
    slot:setItem(nil)
    if modules.game_rarity then
      modules.game_rarity.applyRarityFrame(slot, 0)  -- remove frame
    end
  end
end

local OPCODE_RELICS = 52

local function sendRelicOpcode(msg)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE_RELICS, msg)
  end
end

local function onRelicOpcode(protocol, opcode, buffer)
  if buffer:sub(1, 5) ~= "SYNC:" then return end
  -- Format: SYNC:slot:id:slot:id...
  local parts = {}
  for p in buffer:sub(6):gmatch("[^:]+") do parts[#parts + 1] = tonumber(p) end
  for i = 1, NUM_SLOTS do
    equippedRelics[i] = nil
    updateSlotVisual(i)
  end
  local i = 1
  while i < #parts do
    local slot = parts[i]
    local id   = parts[i + 1]
    if slot and id and slot >= 1 and slot <= NUM_SLOTS then
      equippedRelics[slot] = Item.create(id)
      updateSlotVisual(slot)
    end
    i = i + 2
  end
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
    local item = equippedRelics[slotIndex]
    if item then
      local ok, id = pcall(function() return item:getId() end)
      if ok then
        sendRelicOpcode('REMOVE:' .. slotIndex .. ':' .. id)
      end
      equippedRelics[slotIndex] = nil
      updateSlotVisual(slotIndex)
    end
    return true
  end

  return false
end

local function onSlotDrop(self, dragWidget, mousePos, forced)
  if not self:canAcceptDrop(dragWidget, mousePos) and not forced then return false end

  local item = dragWidget.currentDragThing
  if not item or not item:isItem() then return false end

  if not isRelic(item) then
    modules.game_textmessage.displayMessage('Only relics can be placed in the relic box.', MessageInfo)
    return false
  end

  -- Only allow items from inventory/containers (x == 65535), not ground tiles
  local pos = item:getPosition()
  if pos.x ~= 65535 then
    modules.game_textmessage.displayMessage('Pick up the relic before equipping it.', MessageInfo)
    return false
  end

  local ok, itemId = pcall(function() return item:getId() end)
  if not ok then return false end

  -- Prevent duplicate relics across slots
  for i = 1, NUM_SLOTS do
    local equipped = equippedRelics[i]
    if equipped then
      local ok2, equippedId = pcall(function() return equipped:getId() end)
      if ok2 and equippedId == itemId then
        modules.game_textmessage.displayMessage('You cannot equip the same relic twice.', MessageInfo)
        return false
      end
    end
  end

  -- Always use the first available slot (ordered 1→4), ignoring the drop target
  local slotIndex = nil
  for i = 1, NUM_SLOTS do
    if not equippedRelics[i] then
      slotIndex = i
      break
    end
  end

  if not slotIndex then
    modules.game_textmessage.displayMessage('All relic slots are full.', MessageInfo)
    return false
  end

  sendRelicOpcode('EQUIP:' .. slotIndex .. ':' .. itemId .. ':' .. pos.y .. ':' .. pos.z)

  equippedRelics[slotIndex] = item
  updateSlotVisual(slotIndex)
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
  relicBoxWindow:setHeight(82)

  -- Lock window size: hide the resize border and prevent it from showing on maximize
  local resizeBorder = relicBoxWindow:getChildById('bottomResizeBorder')
  if resizeBorder then
    resizeBorder:hide()
    local origMaximize = relicBoxWindow.maximize
    relicBoxWindow.maximize = function(self, ...)
      origMaximize(self, ...)
      local b = self:getChildById('bottomResizeBorder')
      if b then b:hide() end
      self:setHeight(82)
    end
  end

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

  ProtocolGame.registerExtendedOpcode(OPCODE_RELICS, onRelicOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE_RELICS)
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
