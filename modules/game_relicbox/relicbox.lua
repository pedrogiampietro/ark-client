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
    local item = equippedRelics[slotIndex]
    if item then
      -- Return item to player backpack
      local player = g_game.getLocalPlayer()
      if player then
        local backpack = player:getInventoryItem(InventorySlotBack)
        if backpack then
          g_game.move(item, {x=65535, y=InventorySlotBack, z=0}, 1)
        end
      end
      equippedRelics[slotIndex] = nil
      updateSlotVisual(slotIndex)
      notifyServerRelics()
    end
    return true
  end

  return false
end

local function onSlotDrop(widget, mousePos, item)
  local slotIndex = slotIndexFromWidget(widget)
  if not slotIndex then return false end

  if not isRelic(item) then
    modules.game_textmessage.displayMessage('Only relics can be placed in the relic box.', MessageInfo)
    return false
  end

  -- Swap if slot already occupied
  local oldItem = equippedRelics[slotIndex]
  if oldItem then
    local player = g_game.getLocalPlayer()
    if player then
      local backpack = player:getInventoryItem(InventorySlotBack)
      if backpack then
        g_game.move(oldItem, {x=65535, y=InventorySlotBack, z=0}, 1)
      end
    end
  end

  equippedRelics[slotIndex] = item
  updateSlotVisual(slotIndex)
  notifyServerRelics()
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

  -- Dynamically insert Relics button below Tracker in the inventory window
  addEvent(function()
    local invWindow = modules.game_inventory and
                      modules.game_inventory.inventoryWindow
    if not invWindow then return end

    local tracker = invWindow:recursiveGetChildById('tracker')
    if not tracker then return end

    local parent = tracker:getParent()
    if not parent then return end

    relicBoxButton = g_ui.createWidget('RelicBoxButton', parent)
    relicBoxButton.onClick = toggle
    relicBoxButton:addAnchor(AnchorTop, tracker:getId(), AnchorBottom)
    relicBoxButton:addAnchor(AnchorLeft, tracker:getId(), AnchorLeft)
    relicBoxButton:addAnchor(AnchorRight, tracker:getId(), AnchorRight)
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
