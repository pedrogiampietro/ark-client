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

-- Storage for rarity tiers
local containerRarities = {}
local inventoryRarities = {}

-- Store direct references to container panel widgets
local containerPanels = {}

-- Debounce
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
  containerPanels = {}
end

function onRarityGameEnd()
  containerRarities = {}
  inventoryRarities = {}
  containerPanels = {}
end

function applyRarityFrame(itemWidget, tier)
  if not itemWidget then return end
  if tier and tier > 0 and rarityImages[tier] then
    itemWidget:setImageSource(rarityImages[tier])
  else
    itemWidget:setImageSource('/images/ui/item')
  end
end

-- Find container items panel using multiple strategies
function findContainerPanel(containerId)
  -- Strategy 1: cached reference from onOpen
  local cached = containerPanels[containerId]
  if cached then return cached end

  -- Strategy 2: from g_game.getContainers() property
  local containers = g_game.getContainers()
  if containers then
    local container = containers[containerId]
    if container and container.itemsPanel then
      containerPanels[containerId] = container.itemsPanel
      return container.itemsPanel
    end
  end

  -- Strategy 3: search UI tree
  local root = g_ui.getRootWidget()
  if root then
    local containerWindow = root:recursiveGetChildById('container' .. containerId)
    if containerWindow then
      local panel = containerWindow:getChildById('contentsPanel')
      if panel then
        containerPanels[containerId] = panel
        return panel
      end
    end
  end

  return nil
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
    -- Retry in case panel wasn't ready
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
  end
end

function applyContainerRarities(containerId)
  local tiers = containerRarities[containerId]
  if not tiers then return end

  local panel = findContainerPanel(containerId)
  if not panel then return end

  local children = panel:getChildren()
  for i = 1, #children do
    local itemWidget = children[i]
    if itemWidget then
      local slot = i - 1
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

function requestAndApplyAll()
  requestAllRarities()
  -- Also re-apply cached data (covers the case where data already arrived)
  scheduleEvent(function()
    applyAllRarities()
  end, 100)
end

-- Event handlers

function onRarityGameStart()
  -- Aggressive sync on login: request + reapply at multiple intervals
  local delays = {1, 50, 150, 300}
  for _, delay in ipairs(delays) do
    scheduleEvent(requestAndApplyAll, delay)
  end
end

function onRarityContainerOpen(container, previousContainer)
  local id = container:getId()

  -- Store the panel reference directly from the container object
  -- containers.lua onContainerOpen runs before us (loaded first) so itemsPanel is set
  if container.itemsPanel then
    containerPanels[id] = container.itemsPanel
  end

  -- Request fresh data
  scheduleEvent(function()
    -- Try to cache panel if we didn't get it before
    if not containerPanels[id] and container.itemsPanel then
      containerPanels[id] = container.itemsPanel
    end
    requestContainerRarity(id)
  end, 200)

  -- Apply cached data if available
  if containerRarities[id] then
    scheduleEvent(function()
      applyContainerRarities(id)
    end, 100)
  end
end

function onRarityContainerClose(container)
  local id = container:getId()
  containerRarities[id] = nil
  containerPanels[id] = nil
end

function onRarityContainerUpdate(container, slot, item, oldItem)
  local id = container:getId()

  -- Update panel reference
  if container.itemsPanel and not containerPanels[id] then
    containerPanels[id] = container.itemsPanel
  end

  -- Re-apply cached + request fresh
  if containerRarities[id] then
    scheduleEvent(function()
      applyContainerRarities(id)
    end, 50)
  end
  scheduleEvent(function()
    requestContainerRarity(id)
  end, 300)
end

function onRarityContainerSizeChange(container, size)
  local id = container:getId()
  if container.itemsPanel and not containerPanels[id] then
    containerPanels[id] = container.itemsPanel
  end
  scheduleEvent(function()
    requestContainerRarity(id)
  end, 300)
end

function onRarityInventoryChange(player, slot, item, oldItem)
  -- Re-apply cached rarity after inventory module resets the style
  scheduleEvent(function()
    applyInventoryRarities()
  end, 50)

  -- Request fresh data (debounced)
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
