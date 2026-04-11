-- private variables
local SHOP_EXTENTED_OPCODE = 201

shop = nil
transferWindow = nil
local otcv8shop = false
local shopButton = nil
local msgWindow = nil
local browsingHistory = false
local transferValue = 0

-- for classic store
local storeUrl = ""
local coinsPacketSize = 0

local CATEGORIES = {}
local HISTORY = {}
local STATUS = {}
local AD = {}

local selectedOffer = {}
local currentCategoryId = nil

local SORT_RECOMMENDED = "Recommended"
local SORT_PRICE_ASC = "Price: Low to High"
local SORT_PRICE_DESC = "Price: High to Low"
local SORT_NAME_ASC = "Name: A-Z"

local function sendAction(action, data)
  if not g_game.getFeature(GameExtendedOpcode) then
    return
  end
  
  local protocolGame = g_game.getProtocolGame()
  if data == nil then
    data = {}
  end
  if protocolGame then
    protocolGame:sendExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, {action = action, data = data})
  end  
end

local function normalizeText(text)
  if not text then
    return ""
  end
  return text:lower()
end

local function getSortMode()
  if not shop or not shop.sortCombo then
    return SORT_RECOMMENDED
  end
  return shop.sortCombo:getCurrentOption() or SORT_RECOMMENDED
end

local function compareOffers(a, b, sortMode)
  local aCost = tonumber(a.offer.cost) or 0
  local bCost = tonumber(b.offer.cost) or 0
  if sortMode == SORT_PRICE_ASC then
    if aCost == bCost then
      return a.offer.title:lower() < b.offer.title:lower()
    end
    return aCost < bCost
  elseif sortMode == SORT_PRICE_DESC then
    if aCost == bCost then
      return a.offer.title:lower() < b.offer.title:lower()
    end
    return aCost > bCost
  elseif sortMode == SORT_NAME_ASC then
    return a.offer.title:lower() < b.offer.title:lower()
  end

  return a.index < b.index
end

local function buildOfferEntries(sourceOffers)
  local entries = {}
  local searchText = normalizeText(shop.searchEdit:getText())
  for index, offer in ipairs(sourceOffers) do
    local title = normalizeText(offer.title)
    local desc = normalizeText(offer.description)
    if searchText == "" or title:find(searchText, 1, true) or desc:find(searchText, 1, true) then
      table.insert(entries, {index = index, offer = offer})
    end
  end

  table.sort(entries, function(a, b)
    return compareOffers(a, b, getSortMode())
  end)

  return entries
end

local function renderOffers(categoryId, sourceOffers)
  clearOffers()
  local entries = buildOfferEntries(sourceOffers)
  for _, entry in ipairs(entries) do
    addOffer(categoryId, entry.offer, entry.index)
  end
end

local function refreshCurrentView()
  if not shop then
    return
  end

  if browsingHistory then
    renderOffers(0, HISTORY)
    return
  end

  if not currentCategoryId or not CATEGORIES[currentCategoryId] then
    return
  end

  renderOffers(currentCategoryId, CATEGORIES[currentCategoryId].offers)
end

-- public functions
function init()
  connect(g_game, {
    onGameStart = check, 
    onGameEnd = hide,
    onStoreInit = onStoreInit,
    onStoreCategories = onStoreCategories,
    onStoreOffers = onStoreOffers,
    onStoreTransactionHistory = onStoreTransactionHistory,    
    onStorePurchase = onStorePurchase,
    onStoreError = onStoreError,
    onCoinBalance = onCoinBalance    
  })

  ProtocolGame.registerExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)
  
  if g_game.isOnline() then
    check()
  end
  createShop()
  createTransferWindow()
end

function terminate()
  disconnect(g_game, {
    onGameStart = check, 
    onGameEnd = hide,
    onStoreInit = onStoreInit,
    onStoreCategories = onStoreCategories,
    onStoreOffers = onStoreOffers,
    onStoreTransactionHistory = onStoreTransactionHistory,    
    onStorePurchase = onStorePurchase,
    onStoreError = onStoreError,
    onCoinBalance = onCoinBalance    
  })

  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)
  
  if shopButton then
    shopButton:destroy()
    shopButton = nil
  end
  if shop then
    disconnect(shop.categories, { onChildFocusChange = changeCategory })
    shop:destroy()
    shop = nil
  end
  if msgWindow then
    msgWindow:destroy()
  end
end

function check()
  otcv8shop = false
  sendAction("init")
end

function hide()
  if not shop then
    return
  end
  shop:hide()
end

function show()
  if not shop or not shopButton then
    return
  end
  if g_game.getFeature(GameIngameStore) then
    g_game.openStore(0)
  end
  
  shop:show()
  shop:raise()
  shop:focus()
end

function softHide()
  if not transferWindow then return end

  transferWindow:hide()
  shop:show()
end

function showTransfer()
  if not shop or not transferWindow then return end

  hide()
  transferWindow:show()
  transferWindow:raise()
  transferWindow:focus()
end

function hideTransfer()
  if not shop or not transferWindow then return end

  transferWindow:hide()
  show()
end

function toggle()
  if not shop then
    return
  end
  if shop:isVisible() then
    return hide()
  end
  show()
  check()
end

function createShop()
  if shop then return end
  shop = g_ui.displayUI('shop')
  shop:hide()
  shopButton = modules.client_topmenu.addRightGameToggleButton('shopButton', tr('Shop'), '/images/topbuttons/shop', toggle, false, 8)
  connect(shop.categories, { onChildFocusChange = changeCategory })

  shop.sortCombo:clearOptions()
  shop.sortCombo:addOption(SORT_RECOMMENDED)
  shop.sortCombo:addOption(SORT_PRICE_ASC)
  shop.sortCombo:addOption(SORT_PRICE_DESC)
  shop.sortCombo:addOption(SORT_NAME_ASC)
  shop.sortCombo:setCurrentOption(SORT_RECOMMENDED, true)

  shop.searchEdit.onTextChange = function()
    refreshCurrentView()
  end
  shop.sortCombo.onOptionChange = function()
    refreshCurrentView()
  end
end

function createTransferWindow()
  if transferWindow then return end
  transferWindow = g_ui.displayUI('transfer')
  transferWindow:hide()
end

function onStoreInit(url, coins)
  if otcv8shop then return end
  storeUrl = url
  if storeUrl:len() > 0 then
    if storeUrl:sub(storeUrl:len(), storeUrl:len()) ~= "/" then
      storeUrl = storeUrl .. "/"
    end
    storeUrl = storeUrl .. "64/"
    if storeUrl:sub(1, 4):lower() ~= "http" then
      storeUrl = "http://" .. storeUrl
    end
  end
  coinsPacketSize = coins
  createShop()
  createTransferWindow()
end

function onStoreCategories(categories)
  if not shop or otcv8shop then return end
  local correctCategories = {}
  for i, category in ipairs(categories) do
    local image = ""
    if category.icon:len() > 0 then
      image = storeUrl .. category.icon
    end
    table.insert(correctCategories, {
      type = "image",
      image = image,
      name = category.name,
      offers = {}
    })
  end
  processCategories(correctCategories)
end

function onStoreOffers(categoryName, offers)
  if not shop or otcv8shop then return end
  local updated = false
    
  for i, category in ipairs(CATEGORIES) do
    if category.name == categoryName then
      if #category.offers ~= #offers then
        updated = true
      end
      for i = 1, math.min(#category.offers, #offers) do
        if category.offers[i].title ~= offers[i].name or category.offers[i].id ~= offers[i].id or category.offers[i].cost ~= offers[i].price then
          updated = true
        end
      end
      if updated then    
        for offer in pairs(category.offers) do
          category.offers[offer] = nil
        end
        for i, offer in ipairs(offers) do
          local image = ""
          if offer.icon:len() > 0 then
            image = storeUrl .. offer.icon
          end
          table.insert(category.offers, {
            id=offer.id,
            type="image",
            image=image,
            cost=offer.price,
            title=offer.name,
            description=offer.description        
          })
        end
      end
    end
  end
  if not updated then
    return
  end

  refreshCurrentView()
end

function onStoreTransactionHistory(currentPage, hasNextPage, offers)
  if not shop or otcv8shop then return end
  HISTORY = {}
  for i, offer in ipairs(offers) do
    table.insert(HISTORY, {
      id=offer.id,
      type="image",
      image=storeUrl .. offer.icon,
      cost=offer.price,
      title=offer.name,
      description=offer.description        
    })
  end
  
  if not browsingHistory then return end
  shop.categories:focusChild(nil)
  renderOffers(0, HISTORY)
end

function onStorePurchase(message)
  if not shop or otcv8shop then return end
  if not transferWindow:isVisible() then
    processMessage({title="Successful shop purchase", msg=message})
  else
    processMessage({title="Successfuly gifted coins", msg=message})
    softHide()
  end
end

function onStoreError(errorType, message)
  if not shop or otcv8shop then return end
  if not transferWindow:isVisible() then
    processMessage({title="Shop Error", msg=message})
  else
    processMessage({title="Gift coins error", msg=message})
  end
end

function onCoinBalance(coins, transferableCoins)
  if not shop or otcv8shop then return end
  shop.infoPanel.points:setText(tr("Points:") .. " " .. coins)
  transferWindow.coinsBalance:setText(tr('Transferable Tibia Coins: ') .. coins)
  transferWindow.coinsAmount:setMaximum(coins)
  shop.infoPanel.buy:hide()
end

function transferCoins()
  if not transferWindow then return end
  local amount = 0
  amount = transferWindow.coinsAmount:getValue()
  local recipient = transferWindow.recipient:getText()

  g_game.transferCoins(recipient, amount)
  transferWindow.recipient:setText('')
  transferWindow.coinsAmount:setValue(0)
end

function onExtendedJSONOpcode(protocol, code, json_data)
  createShop()
  createTransferWindow()

  local action = json_data['action']
  local data = json_data['data']
  local status = json_data['status']
  if not action or not data then
    return false
  end
  
  otcv8shop = true
  if action == 'categories' then
    processCategories(data)
  elseif action == 'history' then
    processHistory(data)
  elseif action == 'message' then
    processMessage(data)
  end

  if status then
    processStatus(status)
  end
end

function clearOffers()
  if not shop or not shop.offers then
    return
  end
  shop.offers:destroyChildren()
end

function clearCategories()
  CATEGORIES = {}
  currentCategoryId = nil
  clearOffers()
  shop.categories:destroyChildren()
end

function clearHistory()
  HISTORY = {}
  if browsingHistory then
    clearOffers()
  end
end

function processCategories(data)
  if table.equal(CATEGORIES,data) then
    return
  end
  clearCategories()
  CATEGORIES = data
  browsingHistory = false
  for i, category in ipairs(data) do
    addCategory(category)
  end
  if not browsingHistory then
    local firstCategory = shop.categories:getChildByIndex(1)
    if firstCategory then
      firstCategory:focus()
    end
  end
end

function processHistory(data)
  if table.equal(HISTORY,data) then
    return
  end
  HISTORY = data
  if browsingHistory then
    showHistory(true)
  end
end

function processMessage(data)
  if msgWindow then
    msgWindow:destroy()
  end
    
  local title = tr(data["title"])
  local msg = data["msg"]
  msgWindow = displayInfoBox(title, msg)
  msgWindow.onDestroy = function(widget)
    if widget == msgWindow then
      msgWindow = nil
    end
  end
  msgWindow:show()
  msgWindow:raise()
  msgWindow:focus()
end

function processStatus(data)
  if table.equal(STATUS,data) then
    return
  end
  STATUS = data

  if data['ad'] then 
    processAd(data['ad'])
  end
  if data['points'] then
    shop.infoPanel.points:setText(tr("Points:") .. " " .. data['points'])
  end
  if data['buyUrl'] and data['buyUrl']:sub(1, 4):lower() == "http" then
    shop.infoPanel.buy:show()
    shop.infoPanel.buy.onMouseRelease = function() 
      scheduleEvent(function() g_platform.openUrl(data['buyUrl']) end, 50)
    end
  else
    shop.infoPanel.buy:hide()
  end
end

function processAd(data)
  if table.equal(AD,data) then
    return
  end
  AD = data
  
  if data['image'] and data['image']:sub(1, 4):lower() == "http" then
    HTTP.downloadImage(data['image'], function(path, err) 
      if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
      shop.adPanel.ad:setText("")
      shop.adPanel.ad:setImageSource(path)
      shop.adPanel.ad:setImageFixedRatio(true)
      shop.adPanel.ad:setImageAutoResize(true)
    end)
  elseif data['text'] and data['text']:len() > 0 then
      shop.adPanel.ad:setText(data['text'])
  else
      shop.adPanel.ad:setText("")
      shop.adPanel.ad:setImageSource("")
  end
  if data['url'] and data['url']:sub(1, 4):lower() == "http" then
    shop.adPanel.ad.onMouseRelease = function() 
      scheduleEvent(function() g_platform.openUrl(data['url']) end, 50)
    end
  else
    shop.adPanel.ad.onMouseRelease = nil
  end
end

function addCategory(data)
  local category
  if data["type"] == "item" then
    category = g_ui.createWidget('ShopCategoryItem', shop.categories)  
    category.item:setItemId(data["item"])
    category.item:setItemCount(data["count"])
    category.item:setShowCount(false)
  elseif data["type"] == "outfit" then
    category = g_ui.createWidget('ShopCategoryCreature', shop.categories)
    category.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      category.creature:setAutoRotating(true)
    end
  elseif data["type"] == "image" then
    category = g_ui.createWidget('ShopCategoryImage', shop.categories)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
       HTTP.downloadImage(data['image'], function(path, err) 
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data["image"]) return end
        category.image:setImageSource(path)
      end)
    else
      category.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop category type: " .. tostring(data["type"]))
    return
  end
  category:setId("category_" .. shop.categories:getChildCount())
  category.name:setText(data["name"])
end

function showHistory(force)
  if browsingHistory and not force then
    return
  end

  if g_game.getFeature(GameIngameStore) and not otcv8shop then
    g_game.openTransactionHistory(100)
  end
  sendAction("history")

  browsingHistory = true
  currentCategoryId = nil
  clearOffers()
  shop.categories:focusChild(nil)
  renderOffers(0, HISTORY)
end

function addOffer(category, data, sourceIndex)
  local offer
  if data["type"] == "item" then
    offer = g_ui.createWidget('ShopOfferItem', shop.offers)  
    offer.item:setItemId(data["item"])
    offer.item:setItemCount(data["count"])
    offer.item:setShowCount(false)
  elseif data["type"] == "outfit" then
    offer = g_ui.createWidget('ShopOfferCreature', shop.offers)
    offer.creature:setOutfit(data["outfit"])
    if data["outfit"]["rotating"] then
      offer.creature:setAutoRotating(true)
    end
  elseif data["type"] == "image" then
    offer = g_ui.createWidget('ShopOfferImage', shop.offers)
    if data["image"] and data["image"]:sub(1, 4):lower() == "http" then
      HTTP.downloadImage(data['image'], function(path, err) 
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
        if not offer.image then return end
        offer.image:setImageSource(path)
      end)
    elseif data["image"] and data["image"]:len() > 1 then
      offer.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop offer type: " .. tostring(data["type"]))
    return
  end
  offer:setId("offer_" .. category .. "_" .. shop.offers:getChildCount())
  offer.title:setText(data["title"])
  offer.description:setText(data["description"] or "")
  offer.price:setText(data["cost"] .. " points")
  offer:setTooltip(data["description"] or "")
  offer.categoryId = category
  offer.offerIndex = sourceIndex
  offer.offerData = data
  offer.offerId = data["id"]
  if category ~= 0 then
    offer.onDoubleClick = buyOffer
    offer.buyButton.onClick = function() buyOffer(offer) end
  else
    offer.buyButton:hide()
  end
end


function changeCategory(widget, newCategory)
  if not newCategory then
    return
  end
  
  if g_game.getFeature(GameIngameStore) and widget ~= newCategory and not otcv8shop then
    local serviceType = 0
    if g_game.getFeature(GameTibia12Protocol) then
      serviceType = 2
    end
    g_game.requestStoreOffers(newCategory.name:getText(), serviceType)
  end
  
  browsingHistory = false
  local id = tonumber(newCategory:getId():split("_")[2])
  if not id or not CATEGORIES[id] then
    return
  end
  currentCategoryId = id
  renderOffers(id, CATEGORIES[id]["offers"])
end

function buyOffer(widget)
  if not widget then
    return
  end
  local category = widget.categoryId
  local offer = widget.offerIndex
  local item = widget.offerData
  if not item and category and category ~= 0 and CATEGORIES[category] then
    item = CATEGORIES[category]["offers"][offer]
  end
  if not item then
    return
  end
  
  selectedOffer = {category=category, offer=offer, title=item.title, cost=item.cost, id=widget.offerId}
  
  scheduleEvent(function()
      if msgWindow then
        msgWindow:destroy()
      end
      
      local title = tr("Buying from shop")
      local msg = "Do you want to buy " ..  item.title .. " for " .. item.cost .. " premium points?"
      msgWindow = displayGeneralBox(title, msg, {
          { text=tr('Yes'), callback=buyConfirmed },
          { text=tr('No'), callback=buyCanceled },
          anchor=AnchorHorizontalCenter}, buyConfirmed, buyCanceled)
      msgWindow:show()
      msgWindow:raise()
      msgWindow:focus()
      msgWindow:raise()
    end, 50)
end

function buyConfirmed()
  msgWindow:destroy()
  msgWindow = nil
  sendAction("buy", selectedOffer)
  if g_game.getFeature(GameIngameStore) and selectedOffer.id and not otcv8shop then
    local offerName = selectedOffer.title:lower()
    if string.find(offerName, "name") and string.find(offerName, "change") and modules.client_textedit then
      modules.client_textedit.singlelineEditor("", function(newName)
        if newName:len() == 0 then
          return
        end
        g_game.buyStoreOffer(selectedOffer.id, 1, newName)        
      end)
    else
      g_game.buyStoreOffer(selectedOffer.id, 0, "")
    end
  end
end

function buyCanceled()
  msgWindow:destroy()
  msgWindow = nil
  selectedOffer = {}
end