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
-- containerRarities[containerId] = { [slot] = tier, ... }
-- inventoryRarities[slot] = tier
local containerRarities = {}
local inventoryRarities = {}

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
    onGameEnd = onRarityGameEnd
  })

  containerRarities = {}
  inventoryRarities = {}
end

function onRarityGameEnd()
  containerRarities = {}
  inventoryRarities = {}
end

-- Get the rarity image for a tier level
function getRarityImage(tier)
  return rarityImages[tier]
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
    -- Container rarity: "C:<id>:<tier1>,<tier2>,..."
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
    applyContainerRarities(containerId)

  elseif prefix == "I:" then
    -- Inventory rarity: "I:<slot>=<tier>,<slot>=<tier>,..."
    local rest = buffer:sub(3)
    -- Clear old data
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
  end
end

-- Apply rarity frames to all items in a container
function applyContainerRarities(containerId)
  local containers = g_game.getContainers()
  local container = containers[containerId]
  if not container or not container.itemsPanel then return end

  local tiers = containerRarities[containerId]
  if not tiers then return end

  for slot = 0, container:getCapacity() - 1 do
    local itemWidget = container.itemsPanel:getChildById('item' .. slot)
    if itemWidget then
      local tier = tiers[slot] or 0
      applyRarityFrame(itemWidget, tier)
    end
  end
end

-- Apply rarity frames to inventory slots
function applyInventoryRarities()
  local inventoryPanel = nil

  -- Access the inventory panel from game_inventory module
  if modules.game_inventory and modules.game_inventory.inventoryPanel then
    inventoryPanel = modules.game_inventory.inventoryPanel
  end

  if not inventoryPanel then return end

  for slot = 1, 10 do
    local itemWidget = inventoryPanel:getChildById('slot' .. slot)
    if itemWidget then
      local tier = inventoryRarities[slot] or 0
      local item = g_game.getLocalPlayer():getInventoryItem(slot)
      if item and tier > 0 then
        applyRarityFrame(itemWidget, tier)
      else
        -- Don't override the empty slot style image
        if item then
          applyRarityFrame(itemWidget, 0)
        end
      end
    end
  end
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

function onRarityContainerOpen(container, previousContainer)
  -- Request rarity data from server when container opens
  scheduleEvent(function()
    requestContainerRarity(container:getId())
  end, 100)
end

function onRarityContainerClose(container)
  containerRarities[container:getId()] = nil
end

function onRarityContainerUpdate(container, slot, item, oldItem)
  -- Re-request rarity data when an item changes in a container
  scheduleEvent(function()
    requestContainerRarity(container:getId())
  end, 100)
end

function onRarityContainerSizeChange(container, size)
  scheduleEvent(function()
    requestContainerRarity(container:getId())
  end, 100)
end

function onRarityInventoryChange(player, slot, item, oldItem)
  -- Request inventory rarity update
  scheduleEvent(function()
    local protocol = g_game.getProtocolGame()
    if protocol then
      protocol:sendExtendedOpcode(RARITY_OPCODE, "I")
    end
  end, 100)
end
