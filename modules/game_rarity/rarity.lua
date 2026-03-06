-- Item Rarity Frame System
-- Receives tier data from server via ExtendedOpcode and applies colored frames

RARITY_OPCODE = 50

-- Tier -> image source mapping
local rarityImages = {
  [1] = '/images/ui/rarity_white',   -- common
  [2] = '/images/ui/rarity_blue',    -- rare
  [3] = '/images/ui/rarity_purple',  -- epic
  [4] = '/images/ui/rarity_gold',    -- legendary
  [5] = '/images/ui/rarity_red',     -- mythical
}

-- Storage for current rarity data
local containerRarities = {}
local inventoryRarities = {}

-- Debounce event IDs
local inventoryRequestEvent = nil

function init()
  ProtocolGame.registerExtendedOpcode(RARITY_OPCODE, onRarityData)

  connect(Container, {
    onOpen = onRarityContainerOpen,
    onClose = onRarityContainerClose,
    onUpdateItem = onRarityContainerUpdate,
    onSizeChange = onRarityContainerSizeChange
  })

  connect(LocalPlayer, {
    onInventoryChange = onRarityInventoryChange
  })

  connect(g_game, {
    onGameStart = onRarityGameStart,
    onGameEnd = onRarityGameEnd
  })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(RARITY_OPCODE)

  disconnect(Container, {
    onOpen = onRarityContainerOpen,
    onClose = onRarityContainerClose,
    onUpdateItem = onRarityContainerUpdate,
    onSizeChange = onRarityContainerSizeChange
  })

  disconnect(LocalPlayer, {
    onInventoryChange = onRarityInventoryChange
  })

  disconnect(g_game, {
    onGameStart = onRarityGameStart,
    onGameEnd = onRarityGameEnd
  })

  if inventoryRequestEvent then
    removeEvent(inventoryRequestEvent)
    inventoryRequestEvent = nil
  end

  containerRarities = {}
  inventoryRarities = {}
end

function onRarityGameEnd()
  containerRarities = {}
  inventoryRarities = {}
end

-- Apply rarity frame to a single item widget
function applyRarityFrame(itemWidget, tier)
  if not itemWidget then return end
  if tier and tier > 0 and rarityImages[tier] then
    itemWidget:setImageSource(rarityImages[tier])
  else
    itemWidget:setImageSource('/images/ui/item')
  end
end

-- Parse and handle rarity data from server
function onRarityData(protocol, opcode, buffer)
  if not buffer or #buffer == 0 then return end

  local prefix = buffer:sub(1, 2)

  if prefix == "C:" then
    local rest = buffer:sub(3)
    local colonPos = rest:find(":")
    if not colonPos then return end

    local containerId = tonumber(rest:sub(1, colonPos - 1))
    if not containerId then return end

    local tierStr = rest:sub(colonPos + 1)
    local tiers = {}
    local slot = 0
    for t in tierStr:gmatch("([^,]+)") do
      tiers[slot] = tonumber(t) or 0
      slot = slot + 1
    end

    containerRarities[containerId] = tiers

    -- Apply immediately and also with a small delay (in case widgets arent fully ready)
    applyContainerRarities(containerId)
    scheduleEvent(function()
      applyContainerRarities(containerId)
    end, 100)

  elseif prefix == "I:" then
    local rest = buffer:sub(3)
    inventoryRarities = {}

    if #rest > 0 then
      for pair in rest:gmatch("([^,]+)") do
        local eqPos = pair:find("=")
        if eqPos then
          local slot = tonumber(pair:sub(1, eqPos - 1))
          local tier = tonumber(pair:sub(eqPos + 1))
          if slot and tier then
            inventoryRarities[slot] = tier
          end
        end
      end
    end

    applyInventoryRarities()
    scheduleEvent(function()
      applyInventoryRarities()
    end, 100)
  end
end

-- Find the items panel for a container, trying multiple approaches
function getContainerItemsPanel(containerId, container)
  -- Method 1: direct property (set by containers.lua)
  if container.itemsPanel then
    return container.itemsPanel
  end

  -- Method 2: find the container window by ID in the game UI
  local containerPanel = modules.game_interface.getContainerPanel()
  if containerPanel then
    local containerWindow = containerPanel:getChildById('container' .. containerId)
    if containerWindow then
      local panel = containerWindow:getChildById('contentsPanel')
      if panel then
        return panel
      end
    end
  end

  return nil
end

-- Apply rarity frames to all items in a container
function applyContainerRarities(containerId)
  local container = g_game.getContainers()[containerId]
  if not container then return end

  local containerPanel = getContainerItemsPanel(containerId, container)
  if not containerPanel then return end

  local tiers = containerRarities[containerId]
  if not tiers then return end

  for slot = 0, container:getCapacity() - 1 do
    local itemWidget = containerPanel:getChildById('item' .. slot)
    if itemWidget then
      local tier = tiers[slot] or 0
      applyRarityFrame(itemWidget, tier)
    end
  end
end

-- Apply rarity to all open containers using cached data
function applyAllContainerRarities()
  for containerId, _ in pairs(containerRarities) do
    applyContainerRarities(containerId)
  end
end

-- Apply rarity frames to inventory slots using cached data
function applyInventoryRarities()
  local inventoryPanel = nil

  if modules.game_inventory and modules.game_inventory.inventoryPanel then
    inventoryPanel = modules.game_inventory.inventoryPanel
  end

  if not inventoryPanel then return end

  local player = g_game.getLocalPlayer()
  if not player then return end

  for slot = 1, 10 do
    local itemWidget = inventoryPanel:getChildById('slot' .. slot)
    if itemWidget then
      local tier = inventoryRarities[slot] or 0
      local item = player:getInventoryItem(slot)
      if item and tier > 0 then
        applyRarityFrame(itemWidget, tier)
      elseif item then
        applyRarityFrame(itemWidget, 0)
      end
    end
  end
end

-- Apply all cached rarity data (inventory + containers)
function applyAllRarities()
  applyInventoryRarities()
  applyAllContainerRarities()
end

-- Request rarity data from server for a container
function requestContainerRarity(containerId)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(RARITY_OPCODE, "C:" .. containerId)
  end
end

-- Request all rarity data from server
function requestAllRarities()
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(RARITY_OPCODE, "ALL")
  end
end

-- Event handlers

function onRarityGameStart()
  -- Multiple requests at staggered delays
  -- Ensures we sync even after inventory.lua refresh() resets styles
  -- Server also pushes at T+2s and T+5s from login.lua
  local delays = {1000, 2000, 4000, 7000}
  for _, delay in ipairs(delays) do
    scheduleEvent(function()
      requestAllRarities()
    end, delay)
  end
end

function onRarityContainerOpen(container, previousContainer)
  local id = container:getId()

  -- Request from server
  scheduleEvent(function()
    requestContainerRarity(id)
  end, 300)

  -- If we already have cached data, re-apply it after widgets are created
  if containerRarities[id] then
    scheduleEvent(function()
      applyContainerRarities(id)
    end, 150)
  end
end

function onRarityContainerClose(container)
  containerRarities[container:getId()] = nil
end

function onRarityContainerUpdate(container, slot, item, oldItem)
  local id = container:getId()

  -- Re-apply cached data after the widget update
  if containerRarities[id] then
    scheduleEvent(function()
      applyContainerRarities(id)
    end, 50)
  end

  -- Request fresh data from server
  scheduleEvent(function()
    requestContainerRarity(id)
  end, 300)
end

function onRarityContainerSizeChange(container, size)
  local id = container:getId()
  scheduleEvent(function()
    requestContainerRarity(id)
  end, 300)
end

function onRarityInventoryChange(player, slot, item, oldItem)
  -- Re-apply cached rarity after inventory module resets the style
  scheduleEvent(function()
    applyInventoryRarities()
  end, 50)

  -- Request fresh data from server (debounced)
  if inventoryRequestEvent then
    removeEvent(inventoryRequestEvent)
  end
  inventoryRequestEvent = scheduleEvent(function()
    inventoryRequestEvent = nil
    local protocol = g_game.getProtocolGame()
    if protocol then
      protocol:sendExtendedOpcode(RARITY_OPCODE, "I")
    end
  end, 300)
end
