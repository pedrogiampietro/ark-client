-- Item Rarity Frame System
-- Receives tier data from server via ExtendedOpcode and applies colored frames

RARITY_OPCODE = 50

local rarityImages = {
  [1] = '/images/ui/rarity_white',
  [2] = '/images/ui/rarity_green',
  [3] = '/images/ui/rarity_blue',
  [4] = '/images/ui/rarity_purple',
  [5] = '/images/ui/rarity_gold',
}

-- Storage for rarity tiers
local containerRarities = {}
local inventoryRarities = {}

-- Store direct references to container panel widgets
local containerPanels = {}

-- Debounce
local inventoryRequestEvent = nil
local containerRequestEvents = {}
local containerDirty = {}
local containerRequestToken = {}
local containerLastRequestMs = {}

local RARITY_DEBUG = true
local rarityDebugSeq = 0

local function rarityDebug(msg)
  if not RARITY_DEBUG then return end
  rarityDebugSeq = rarityDebugSeq + 1
  g_logger.info(string.format('[RARITY][%05d][%d] %s', rarityDebugSeq, g_clock.millis(), msg))
end

local function safeItemInfo(item)
  if not item then return 'nil' end
  local okId, id = pcall(function() return item:getId() end)
  local okCount, count = pcall(function() return item:getCount() end)
  local idText = okId and tostring(id) or '?'
  local countText = okCount and tostring(count) or '?'
  return idText .. 'x' .. countText
end

local function rarityState(containerId)
  local dirty = containerDirty[containerId] and 1 or 0
  local hasPanel = containerPanels[containerId] and 1 or 0
  local pending = containerRequestEvents[containerId] and 1 or 0
  local token = containerRequestToken[containerId] or 0
  return string.format('cid=%d dirty=%d panel=%d pendingReq=%d token=%d', containerId, dirty, hasPanel, pending, token)
end

function init()
  rarityDebug('init module')
  ProtocolGame.registerExtendedOpcode(RARITY_OPCODE, onRarityData)

  connect(Container, {
    onOpen = onRarityContainerOpen,
    onClose = onRarityContainerClose,
    onAddItem = onRarityContainerAdd,
    onRemoveItem = onRarityContainerRemove,
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
  rarityDebug('terminate module')
  ProtocolGame.unregisterExtendedOpcode(RARITY_OPCODE)

  disconnect(Container, {
    onOpen = onRarityContainerOpen,
    onClose = onRarityContainerClose,
    onAddItem = onRarityContainerAdd,
    onRemoveItem = onRarityContainerRemove,
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

  for containerId, event in pairs(containerRequestEvents) do
    removeEvent(event)
    containerRequestEvents[containerId] = nil
  end

  containerRarities = {}
  inventoryRarities = {}
  containerPanels = {}
  containerDirty = {}
end

function onRarityGameEnd()
  rarityDebug('game end -> clearing rarity state')
  for containerId, event in pairs(containerRequestEvents) do
    removeEvent(event)
    containerRequestEvents[containerId] = nil
  end
  containerRarities = {}
  inventoryRarities = {}
  containerPanels = {}
  containerDirty = {}
end

function applyRarityFrame(itemWidget, tier)
  if not itemWidget then return end
  local imageSource = '/images/ui/item'
  if tier and tier > 0 and rarityImages[tier] then
    imageSource = rarityImages[tier]
  end

  -- Avoid forcing recache when source is unchanged.
  if itemWidget:getImageSource() ~= imageSource then
    itemWidget:setImageSource(imageSource)
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

    local now = g_clock.millis()
    local dt = -1
    if containerLastRequestMs[containerId] then
      dt = now - containerLastRequestMs[containerId]
    end
    rarityDebug(string.format('recv C response cid=%d slots=%d dt=%dms stateBefore={%s}', containerId, slot, dt, rarityState(containerId)))

    containerRarities[containerId] = tiers
    containerDirty[containerId] = false
    rarityDebug('apply from C response -> ' .. rarityState(containerId))
    applyContainerRarities(containerId)

    -- Retry only when the panel is still missing.
    if not findContainerPanel(containerId) then
      local retryDelay = 80
      scheduleEvent(function()
        rarityDebug(string.format('retry apply C (panel missing) cid=%d delay=%dms state={%s}', containerId, retryDelay, rarityState(containerId)))
        applyContainerRarities(containerId)
      end, retryDelay)
    end

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

    local count = 0
    for _ in pairs(inventoryRarities) do
      count = count + 1
    end
    rarityDebug(string.format('recv I response entries=%d', count))

    applyInventoryRarities()
  end
end

function applyContainerRarities(containerId)
  if containerDirty[containerId] then
    rarityDebug('skip apply (container dirty) -> ' .. rarityState(containerId))
    return
  end

  local tiers = containerRarities[containerId]
  if not tiers then
    rarityDebug('skip apply (no tiers) -> ' .. rarityState(containerId))
    return
  end

  local panel = findContainerPanel(containerId)
  if not panel then
    rarityDebug('skip apply (panel not found) -> ' .. rarityState(containerId))
    return
  end

  local children = panel:getChildren()
  local applied = 0
  for i = 1, #children do
    local itemWidget = children[i]
    if itemWidget then
      local slot = i - 1
      local tier = tiers[slot] or 0
      applyRarityFrame(itemWidget, tier)
      applied = applied + 1
    end
  end
  rarityDebug(string.format('applied container frames cid=%d widgets=%d state={%s}', containerId, applied, rarityState(containerId)))
end

function requestContainerRarityDebounced(containerId, delay)
  local useDelay = delay or 100
  if containerRequestEvents[containerId] then
    removeEvent(containerRequestEvents[containerId])
    containerRequestEvents[containerId] = nil
    rarityDebug(string.format('debounce replace cid=%d delay=%dms state={%s}', containerId, useDelay, rarityState(containerId)))
  else
    rarityDebug(string.format('debounce schedule cid=%d delay=%dms state={%s}', containerId, useDelay, rarityState(containerId)))
  end

  containerRequestEvents[containerId] = scheduleEvent(function()
    containerRequestEvents[containerId] = nil
    rarityDebug('debounce fire -> request C ' .. rarityState(containerId))
    requestContainerRarity(containerId)
  end, useDelay)
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
    local token = (containerRequestToken[containerId] or 0) + 1
    containerRequestToken[containerId] = token
    containerLastRequestMs[containerId] = g_clock.millis()
    rarityDebug(string.format('send C request cid=%d token=%d state={%s}', containerId, token, rarityState(containerId)))
    protocol:sendExtendedOpcode(RARITY_OPCODE, "C:" .. containerId)
  else
    rarityDebug('skip C request (no protocol) -> ' .. rarityState(containerId))
  end
end

function requestAllRarities()
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(RARITY_OPCODE, "ALL")
  end
end

function requestAndApplyAll()
  rarityDebug('requestAndApplyAll -> request ALL')
  requestAllRarities()
end

-- Event handlers

function onRarityGameStart()
  rarityDebug('game start -> scheduling initial sync')
  -- Keep startup sync lightweight to avoid visual churn.
  local delays = {80, 350}
  for _, delay in ipairs(delays) do
    scheduleEvent(requestAndApplyAll, delay)
  end
end

function onRarityContainerOpen(container, previousContainer)
  local id = container:getId()

  -- Cache panel reference
  if container.itemsPanel then
    containerPanels[id] = container.itemsPanel
  end

  rarityDebug('container open -> ' .. rarityState(id))
end

-- Called directly by containers.lua AFTER container is fully set up
-- This is the primary mechanism (like onInventoryChange for inventory)
function onContainerReady(container)
  local id = container:getId()

  -- Cache panel reference (guaranteed to be set at this point)
  if container.itemsPanel then
    containerPanels[id] = container.itemsPanel
  end

  -- Request fresh data from server
  containerDirty[id] = true
  rarityDebug('container ready -> mark dirty and request C ' .. rarityState(id))
  requestContainerRarity(id)
end

-- Called directly by containers.lua after setItem() resets frames
function onContainerItemUpdated(container, reason)
  local id = container:getId()

  -- Cache panel
  if container.itemsPanel and not containerPanels[id] then
    containerPanels[id] = container.itemsPanel
  end

  -- Container slots changed: wait for fresh server mapping to avoid frame jumps.
  containerDirty[id] = true
  rarityDebug(string.format('container ui refreshed reason=%s -> mark dirty %s', tostring(reason or 'unknown'), rarityState(id)))
  requestContainerRarityDebounced(id, 120)
end

function onRarityContainerClose(container)
  local id = container:getId()
  rarityDebug('container close -> ' .. rarityState(id))
  if containerRequestEvents[id] then
    removeEvent(containerRequestEvents[id])
    containerRequestEvents[id] = nil
  end
  containerRarities[id] = nil
  containerPanels[id] = nil
  containerDirty[id] = nil
  containerRequestToken[id] = nil
  containerLastRequestMs[id] = nil
end

function onRarityContainerAdd(container, slot, item)
  local id = container:getId()
  containerDirty[id] = true
  rarityDebug(string.format('event onAddItem cid=%d slot=%s item=%s -> mark dirty', id, tostring(slot), safeItemInfo(item)))
  requestContainerRarityDebounced(id, 120)
end

function onRarityContainerRemove(container, slot, item)
  local id = container:getId()
  containerDirty[id] = true
  rarityDebug(string.format('event onRemoveItem cid=%d slot=%s item=%s -> mark dirty', id, tostring(slot), safeItemInfo(item)))
  requestContainerRarityDebounced(id, 120)
end

function onRarityContainerUpdate(container, slot, item, oldItem)
  local id = container:getId()
  containerDirty[id] = true
  rarityDebug(string.format('event onUpdateItem cid=%d slot=%s old=%s new=%s -> mark dirty', id, tostring(slot), safeItemInfo(oldItem), safeItemInfo(item)))
  requestContainerRarityDebounced(id, 120)
end

function onRarityContainerSizeChange(container, size)
  local id = container:getId()
  containerDirty[id] = true
  rarityDebug(string.format('event onSizeChange cid=%d size=%s -> mark dirty', id, tostring(size)))
  requestContainerRarityDebounced(id, 120)
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
