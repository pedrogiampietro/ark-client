-- Item Rarity Frame System
-- Receives tier data from server via ExtendedOpcode and applies colored frames

RARITY_OPCODE = 50

local rarityImages = {
  [1] = '/images/ui/rarity_white',
  [2] = '/images/ui/rarity_blue',
  [3] = '/images/ui/rarity_purple',
  [4] = '/images/ui/rarity_gold',
  [5] = '/images/ui/rarity_red',
}

local containerRarities = {}
local inventoryRarities = {}
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

function applyRarityFrame(itemWidget, tier)
  if not itemWidget then return end
  if tier and tier > 0 and rarityImages[tier] then
    itemWidget:setImageSource(rarityImages[tier])
  else
    itemWidget:setImageSource('/images/ui/item')
  end
end

-- Find the container contentsPanel by searching the full UI tree
function findContainerPanel(containerId)
  local containerWindow = rootWidget:recursiveGetChildById('container' .. containerId)
  if not containerWindow then return nil end
  return containerWindow:getChildById('contentsPanel')
end

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
    applyContainerRarities(containerId)
    scheduleEvent(function()
      applyContainerRarities(containerId)
    end, 200)

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
    end, 200)
  end
end

function applyContainerRarities(containerId)
  local tiers = containerRarities[containerId]
  if not tiers then return end

  -- Find the container panel directly in the UI tree
  local contentsPanel = findContainerPanel(containerId)
  if not contentsPanel then return end

  local children = contentsPanel:getChildren()
  for slot = 0, #children - 1 do
    local itemWidget = contentsPanel:getChildById('item' .. slot)
    if itemWidget then
      local tier = tiers[slot] or 0
      applyRarityFrame(itemWidget, tier)
    end
  end
end

function applyAllContainerRarities()
  for containerId, _ in pairs(containerRarities) do
    applyContainerRarities(containerId)
  end
end

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

function applyAllRarities()
  applyInventoryRarities()
  applyAllContainerRarities()
end

function requestContainerRarity(containerId)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(RARITY_OPCODE, "C:" .. containerId)
  end
end

function requestAllRarities()
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(RARITY_OPCODE, "ALL")
  end
end

-- Event handlers

function onRarityGameStart()
  local delays = {500, 1500, 3000, 5000, 8000}
  for _, delay in ipairs(delays) do
    scheduleEvent(function()
      requestAllRarities()
    end, delay)
  end
end

function onRarityContainerOpen(container, previousContainer)
  local id = container:getId()

  scheduleEvent(function()
    requestContainerRarity(id)
  end, 500)

  if containerRarities[id] then
    scheduleEvent(function()
      applyContainerRarities(id)
    end, 300)
  end
end

function onRarityContainerClose(container)
  containerRarities[container:getId()] = nil
end

function onRarityContainerUpdate(container, slot, item, oldItem)
  local id = container:getId()

  if containerRarities[id] then
    scheduleEvent(function()
      applyContainerRarities(id)
    end, 100)
  end

  scheduleEvent(function()
    requestContainerRarity(id)
  end, 500)
end

function onRarityContainerSizeChange(container, size)
  local id = container:getId()
  scheduleEvent(function()
    requestContainerRarity(id)
  end, 500)
end

function onRarityInventoryChange(player, slot, item, oldItem)
  scheduleEvent(function()
    applyInventoryRarities()
  end, 50)

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
