local EditShopWindow, SelectItemWindow
MainWindow = {}

Config = Config or {}
Config.opcode = 220
Config.money = Config.money or {2148, 2152, 2160} -- gold, platinum, crystal coins

local function onGameStart()
    if not MainWindow then return end
    hide()
end

local function onGameEnd()
    if not MainWindow then return end
    hide()
end

function onShopClose() -- Player requested shop close
    local shopClose = function(recoverItems)
        local payload = {e = 'SHOP_CLOSE', d = recoverItems}

        g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                    json.encode(payload))
        hide()
    end

    if isOwnShop() then
        if MainWindow.currentShop.offers < 1 then
            hide()
            return
        end

        local confirmBox
        confirmBox = displayGeneralBox(tr("Close Shop"), tr(
                                           "Do you wish to retrieve your items?"),
                                       {
            {
                text = tr("Yes"),
                callback = function()
                    shopClose(true)
                    if confirmBox then confirmBox:destroy() end
                end
            }, {
                text = tr("Not yet"),
                callback = function()
                    shopClose(false)
                    if confirmBox then confirmBox:destroy() end
                end
            }
        }, function()
            shopClose(true)
            if confirmBox then confirmBox:destroy() end
        end, -- Enter
        function()
            shopClose(false)
            if confirmBox then confirmBox:destroy() end
        end -- Escape
        )
    else
        shopClose()
    end
end

function openShop(sellerId)
    local payload = {e = 'SHOP_OPEN', d = sellerId}
    g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                json.encode(payload))
end

local function requestRemoveOffer(offerId)
    if not MainWindow.currentShop or MainWindow.currentShop.seller ~=
        g_game.getLocalPlayer():getId() then return false end

    for i = 1, 6 do
        local panel = MainWindow:getChildById('offer' .. i)

        local offer = panel.offerData
        if offer and offer.id == offerId then
            local payload = {e = 'SHOP_REMOVE_OFFER', d = offerId}

            g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                        json.encode(payload))
            break
        end
    end

    return true
end

local function requestModifyOffer(offerId, newitem)
    if MainWindow.currentShop.open then
        scheduleEvent(function()
            MainWindow.pauseButton:setBorderWidth(1)
            scheduleEvent(function()
                MainWindow.pauseButton:setBorderWidth(0)
            end, 350)
        end, 150)

        return false
    end

    local panel
    for i = 1, 6 do
        local p = MainWindow:getChildById('offer' .. i)
        if p.offerData and p.offerData.id == offerId then panel = p end
    end

    if not panel then return end
    local offer = panel.offerData

    SelectItemWindow:setText("Edit Offer")

    SelectItemWindow.count = offer.count

    SelectItemWindow.priceLabel:setText('New price: ')
    SelectItemWindow.priceEdit:setText(offer.price)
    SelectItemWindow.priceEdit:enable()

    SelectItemWindow.item:setItem(panel.offerItem:getItem())
    SelectItemWindow.item:setItemCount(offer.count)
    SelectItemWindow.item:setShowCount(true)

    local scrollbar = SelectItemWindow.amountScrollBar
    scrollbar:setMinimum(1)

    if panel.offerItem:getItem():isStackable() then
        local max = offer.count
        if newitem then
            scrollbar:setMinimum(offer.count)
            max = math.min(100, offer.count + newitem:getCount())
            SelectItemWindow.priceEdit:disable()
        end

        scrollbar:setMaximum(max)

        scrollbar.onValueChange = function(self, value)
            SelectItemWindow.item:setItemCount(value)
            SelectItemWindow.count = value
            panel.offerItem:setItemCount(value)
            if SelectItemWindow.price > 0 then
                SelectItemWindow.priceLabel:setText(
                    '(total earnings: ' .. SelectItemWindow.price +
                        SelectItemWindow.count .. ')')
            else
                SelectItemWindow.priceLabel:setText('New price: ')
            end
            scrollbar:setText(value)
        end

        scrollbar:enable()
    else
        scrollbar:setMaximum(1)
        scrollbar:disable()
    end

    scrollbar:setValue(offer.count)
    scrollbar:setText(offer.count)

    SelectItemWindow.buttonOk.onClick = function()
        if SelectItemWindow.price < 1 then
            return displayInfoBox("Enter a valid price.")
        elseif SelectItemWindow.count < 1 or SelectItemWindow.count > 100 then
            return displayInfoBox("Select a valid item count.")
        end

        local payload = {
            e = 'SHOP_EDIT_OFFER',
            d = {
                offer = offerId,
                count = SelectItemWindow.count,
                price = SelectItemWindow.price
            }
        }
        g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                    json.encode(payload))
        SelectItemWindow:hide()
    end

    SelectItemWindow.buttonCancel.onClick = function()
        SelectItemWindow.item:clearItem()
        panel.offerItem:setItemCount(offer.count)
        SelectItemWindow:hide()
    end

    SelectItemWindow:show()
    return true
end

function isOwnShop()
    return MainWindow.currentShop and MainWindow.currentShop.own == true
end

function onSelectOffer(widget)
    local item = widget.offerItem
    if not item then return end

    if isOwnShop() then return end

    if MainWindow.selectedPanel then
        MainWindow.selectedPanel:setChecked(false)
        MainWindow.buyButton:setEnabled(false)
        if MainWindow.selectedPanel == widget then
            MainWindow.selectedPanel = nil
            return
        end

        MainWindow.selectedPanel = nil
    end

    if widget.offerData.price > MainWindow.currentShop.funds then
        scheduleEvent(function()
            MainWindow.earnings:setColor("white")
            scheduleEvent(function()
                MainWindow.earnings:setColor("yellow")
            end, 350)
        end, 150)
        return
    end

    MainWindow.selectedPanel = widget
    MainWindow.selectedPanel:setChecked(true)
    MainWindow.buyButton:setEnabled(true)
end

local function onSlotHoverChange(widget, hovered)
    local draggingWidget = g_ui.getDraggingWidget()

    local panel = widget:getParent()

    if hovered then
        if draggingWidget and widget ~= draggingWidget then
            local gotItem = draggingWidget:getClassName() == 'UIItem' and
                                not draggingWidget:isVirtual()
            if gotItem then
                local item = draggingWidget:getItem()
                if not widget:isOn() then
                    if item:getId() == panel.offerData.cid or
                        not item:isStackable() then
                        widget:setOn(true)
                    else
                        return
                    end
                end

                if item and not table.contains(Config.money, item:getId()) and
                    not item:isContainer() and item:getPosition() and
                    item:getPosition().x == 0xFFFF and isOwnShop() then
                    widget:setBorderWidth(1)
                    draggingWidget.hoveredWho = widget
                    return
                end
            end

            draggingWidget.hoveredWho = nil
        end
    end

    widget:setBorderWidth(0)
end

local function onSelectItemToSell(widget, draggedItem, mousePos, forced)
    local panel = widget:getParent()

    if not widget:canAcceptDrop(draggedItem, mousePos) and not forced then
        return false
    end
    if not panel.offerItem:isOn() then return false end

    local item = draggedItem.currentDragThing
    if not item or not item:isItem() or not item:isPickupable() then
        return false
    end

    local count = item:getCount()

    widget:setBorderWidth(0)

    if table.contains(Config.money, item:getId()) or item:isContainer() then
        return false
    end

    if not table.empty(panel.offerData) then
        if item:getId() == panel.offerData.cid and item:isStackable() then
            return requestModifyOffer(panel.offerData.id, item)
        else
            widget:setOn(false)
            return false
        end
    end

    if item:getPosition().x ~= 0xFFFF then
        displayInfoBox("Error", "The item must be in your inventory.")
        return false
    end

    widget:setItem(Item.create(item:getId(), item:getCountOrSubType()))
    local fromPos = item:getPosition()

    SelectItemWindow:setText("Add Offer")

    SelectItemWindow.priceLabel:setText('Enter price: ')
    SelectItemWindow.priceEdit:clearText()
    SelectItemWindow.priceEdit:enable()

    local scrollbar = SelectItemWindow.amountScrollBar

    SelectItemWindow.item:setItemId(widget:getItemId())
    SelectItemWindow.item:setItemCount(count)
    SelectItemWindow.item:setItemSubType(widget:getItemSubType())

    SelectItemWindow.item:setShowCount(true)

    SelectItemWindow.count = item:getCount()

    scrollbar:setMaximum(count)
    scrollbar:setMinimum(1)

    scrollbar.onValueChange = function(self, value)
        SelectItemWindow.item:setItemCount(value)
        SelectItemWindow.count = value
        if SelectItemWindow.price > 0 then
            SelectItemWindow.priceLabel:setText(
                '(total earnings: ' .. SelectItemWindow.price *
                    SelectItemWindow.count .. ')')
        else
            SelectItemWindow.priceLabel:setText('Enter price: ')
        end
        scrollbar:setText(value)
    end

    scrollbar:setValue(count)
    scrollbar:setText(count)

    SelectItemWindow.buttonOk.onClick = function()
        if SelectItemWindow.price < 1 then
            return displayInfoBox("Enter a valid price.")
        elseif SelectItemWindow.count < 1 then
            return displayInfoBox("Select a valid item count.")
        end

        panel.offerItem:setOn(false)

        local payload = {
            e = 'SHOP_ADD_OFFER',
            d = {
                cid = item:getId(),
                subtype = widget:getItemSubType(),
                count = SelectItemWindow.count,
                pos = fromPos,
                price = SelectItemWindow.price
            }
        }

        g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                    json.encode(payload))
        SelectItemWindow:hide()
    end

    SelectItemWindow.buttonCancel.onClick = function()
        panel.offerItem:clearItem()
        panel.offerItem:setOn(true)
        SelectItemWindow:hide()
    end

    MainWindow.selectItem:show()
    MainWindow.selectItem:focus()
end

local function formatNumber(n)
    return tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):gsub(
               ",(%-?)$", "%1"):reverse()
end

function parseShopOpen(data)
    if MainWindow.currentShop ~= {} then
        if MainWindow.lockUpdate then
            MainWindow.lockUpdate = data
            return
        end

        MainWindow.currentShop = {}
        -- hide()
    end

    local message = data.info

    MainWindow.currentShop.message = data.info
    MainWindow.currentShop.seller = data.seller
    MainWindow.currentShop.own = data.own
    MainWindow.currentShop.maxOffers = data.maxOffers
    MainWindow.currentShop.offers = 0

    MainWindow.currentShop.earnings = data.earned

    if isOwnShop() then
        MainWindow.earnings:setText(formatNumber(data.earned))
        MainWindow.closeButton:setImageColor("red")

        MainWindow.closeButton:addAnchor(AnchorTop, 'pauseButton', AnchorBottom)

        MainWindow.buyButton:disable()
        MainWindow.buyButton:setHeight(0)

        MainWindow.pauseButton:show()
        MainWindow.pauseButton:enable()

        MainWindow.currentShop.open = data.open

        if data.open then
            MainWindow.pauseButton:setOn(true)
        else
            MainWindow.pauseButton:setOn(false)
        end

        MainWindow.pauseButton.onClick = function()
            local payload = {e = 'SHOP_TOGGLE'}

            g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                        json.encode(payload))
        end

        MainWindow.earningsLabel:setText("Your earnings: ")

        if data.earned < 100 then
            MainWindow.earnings:setColor("white")
        else
            MainWindow.earnings:setColor("green")
        end
    else
        MainWindow.pauseButton:hide()
        MainWindow.earningsLabel:setText("Your funds: ")

        MainWindow.buyButton:setHeight(25)
        MainWindow.buyButton:disable()

        MainWindow.closeButton:addAnchor(AnchorTop, 'buyButton', AnchorBottom)

        MainWindow.closeButton:setImageColor("#dfdfdf")

        if data.money then
            MainWindow.currentShop.funds = data.money
            MainWindow.earnings:setText(formatNumber(data.money))
            MainWindow.earnings:setColor("yellow")
        else
            MainWindow.currentShop.funds = 0
            MainWindow.earnings:setText("?")
            MainWindow.earnings:setColor("white")
        end
    end

    MainWindow.earningsLabel:resizeToText()

    -- MainWindow.earnings:addAnchor(AnchorLeft, 'earningsLabel', AnchorRight)

    for i = 1, 6 do
        local offer = data.offers[i]
        local panel = MainWindow:getChildById('offer' .. i)

        if panel.activeContainerPanel then
            panel.activeContainerPanel:destroy()
        end

        panel.offerItem.onHoverChange = onSlotHoverChange
        if not panel.offerData then panel.offerData = {} end

        panel:setTooltip("")

        panel.offerItem:setOn(false)

        panel:setChecked(false)

        if offer then
            local offerId = offer.offer

            panel.price:setColor("yellow")
            if panel.offerData.id ~= offerId or panel.offerData.cid ~= offer.cid or
                panel.offerData.count ~= offer.count or panel.offerData.price ~=
                offer.price then
                panel.emptyLabel:hide()

                local name = offer.name
                name = name:sub(1, 1):upper() .. name:sub(2)

                panel.itemName:setText(name)

                panel.priceLabel:show()

                local weightString = tr("%.2f oz.", offer.weight / 100)
                panel.weight:setText(weightString)

                panel.offerData = {
                    id = offerId,
                    cid = offer.cid,
                    price = offer.price,
                    count = offer.count,
                    content = offer.content,
                    attr = offer.attr
                }

                -- Decodificar attr para tooltip
                local attrData = {}
                if offer.attr and offer.attr ~= '' then
                    local jsonStatus, jsonData = pcall(function()
                        return json.decode(offer.attr)
                    end)
                    if jsonStatus and jsonData then
                        attrData = jsonData
                    end
                end

                -- Se attrData vazio, tentar preencher com dados básicos do item
                if not attrData.iLvl and not attrData.rarity and
                    not attrData.imp then
                    local itemType = g_things.getThingType(offer.cid)
                    if itemType then
                        attrData.type = "" -- deixar vazio por enquanto
                        if itemType.getAttack then
                            attrData.first = itemType:getAttack()
                        else
                            attrData.first = 0
                        end
                        if itemType.getDefense then
                            attrData.second = itemType:getDefense()
                        else
                            attrData.second = 0
                        end
                        if itemType.getExtraDefense then
                            attrData.third = itemType:getExtraDefense()
                        else
                            attrData.third = 0
                        end
                    end
                end

                -- Se attrData vazio, deixar básico (nome e peso apenas)

                panel.offerItem.getLinkedTooltip = function()
                    return {
                        id = offer.cid,
                        name = offer.name,
                        desc = attrData.desc or "",
                        iLvl = attrData.iLvl or 0,
                        imp = attrData.imp or {},
                        unidentified = attrData.unidentified or false,
                        mirrored = attrData.mirrored or false,
                        uLvl = attrData.uLvl or 0,
                        uniqueName = attrData.uniqueName or "",
                        rarity = attrData.rarity or 0,
                        maxAttributes = attrData.maxAttributes or 0,
                        attributes = attrData.attributes or {},
                        stackable = false,
                        type = attrData.type or "",
                        first = attrData.first or 0,
                        second = attrData.second or 0,
                        third = attrData.third or 0,
                        weight = offer.weight,
                        reqLvl = attrData.reqLvl or 0,
                        count = offer.count
                    }
                end

                panel.onHoverChange =
                    function(widget, hovered)
                        if hovered then
                            if _G.buildItemTooltip then
                                local tooltipData = panel.offerItem:getLinkedTooltip()
                                _G.buildItemTooltip(tooltipData)
                                if _G.showItemTooltip then
                                    _G.showItemTooltip()
                                else
                                    g_logger.warning("showItemTooltip not found in _G")
                                end
                            else
                                g_logger.warning(
                                    "buildItemTooltip not found in _G")
                            end
                        else
                            if _G.tooltipWindow then
                                _G.tooltipWindow:hide()
                            else
                                g_logger.warning("tooltipWindow not found in _G")
                            end
                        end
                    end

                panel.offerItem:setItemId(offer.cid)
                panel.offerItem:setItemCount(offer.count)

                panel.price:setText(formatNumber(offer.price))
                panel.price:show()

                if not panel.offerItem:getItem():isStackable() then
                    panel.offerItem:setItemSubType(offer.subtype)
                end

                panel.offerItem:setShowCount(true)
                panel:setOn(true)

                if offer.count > 1 then
                    panel:setTooltip("Total: " .. offer.price * offer.count ..
                                         "gp")
                end

                panel.offerItem:show()
                panel.itemName:show()
                panel.priceLabel:show()
                panel.weight:show()
            end

            if not isOwnShop() then
                if offer.price > data.money then
                    panel.price:setColor("#ff1212")
                else
                    panel.price:setColor("green")
                end
            end

            MainWindow.currentShop.offers = MainWindow.currentShop.offers + 1
        else
            panel.emptyLabel:show()
            panel.offerItem:hide()
            panel.itemName:hide()
            panel.price:hide()
            panel.priceLabel:hide()
            panel.weight:hide()

            panel.offerData = {}

            panel.offerItem:clearItem()
            panel:setOn(false)

            if isOwnShop() then
                panel.offerItem:setOn(true)
                panel.offerItem:show()
            end
        end

        if isOwnShop() then
            panel.offerItem.onDrop = onSelectItemToSell

            panel.onMouseRelease = function(self, mousePosition, mouseButton)
                if mouseButton == MouseRightButton and self:isOn() and
                    isOwnShop() then
                    local menu = g_ui.createWidget('PopupMenu')
                    menu:addOption('Remove', function()
                        return requestRemoveOffer(panel.offerData.id)
                    end)
                    menu:addOption('Modify', function()
                        return requestModifyOffer(panel.offerData.id)
                    end)
                    menu:setGameMenu(true)
                    menu:display(mousePosition)
                end
            end
        else
            -- Remove o evento onMouseRelease se não for o dono
            panel.onMouseRelease = nil
        end
    end

    -- Busca o vendedor pelo GUID (agora sempre é o GUID, não o sessionId)
    local seller = g_map.getCreatureById(data.seller)
    if not seller or not seller:isPlayer() then
        -- Vendedor offline: exibe outfit padrão e nome genérico
        MainWindow.creature:setOutfit({lookType = 128}) -- outfit padrão
        if isOwnShop() then
            MainWindow:setText("Your Shop")
        else
            MainWindow:setText("Shop de jogador offline")
        end
    else
        MainWindow.creature:setOutfit(seller:getOutfit())
        if isOwnShop() then
            MainWindow:setText("Your Shop")
        else
            MainWindow:setText(seller:getName() .. "'s shop")
        end
    end

    show()
end

function onPressBuy(button)
    local panel = MainWindow.selectedPanel
    if not panel then
        button:setEnabled(false)
        return
    end

    if not MainWindow.lockUpdate then MainWindow.lockUpdate = {} end

    local offerId = panel.offerData.id
    local itemcid = panel.offerData.cid
    local price = panel.offerData.price
    local count = panel.offerData.count

    local function requestBuy(selectedCount)
        local payload = {
            e = 'SHOP_BUY',
            d = {
                offer = offerId,
                count = selectedCount or count,
                cid = panel.offerData.cid
            }
        }
        g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                    json.encode(payload))

        if MainWindow.lockUpdate ~= {} then
            parseShopOpen(MainWindow.lockUpdate)
        end

        MainWindow.lockUpdate = nil
    end

    -- Se for stackable e > 1, permite escolher quantidade
    if panel.offerItem:getItem():isStackable() and count > 1 then
        local selectedCount = count
        local confirmWindow = g_ui.createWidget('ConfirmBuyAmountWindow',
                                                g_ui.getRootWidget())
        confirmWindow:getChildById('message'):setText(tr(
                                                          "You are about to buy %s for %d gp.",
                                                          panel.itemName:getText(),
                                                          price * selectedCount))
        confirmWindow:getChildById('amountLabel'):setText(tr(
                                                              "Select the amount:"))
        local scrollbar = confirmWindow:getChildById('amountScrollBar')
        local selectedLabel = confirmWindow:getChildById('selectedLabel')
        scrollbar:setMinimum(1)
        scrollbar:setMaximum(count)
        scrollbar:setValue(count)
        selectedLabel:setText(tr("Selected: %d", count))

        scrollbar.onValueChange = function(self, value)
            selectedCount = value
            selectedLabel:setText(tr("Selected: %d", value))
            confirmWindow:getChildById('message'):setText(tr(
                                                              "You are about to buy %s for %d gp.",
                                                              panel.itemName:getText(),
                                                              price * value))
        end

        confirmWindow:getChildById('buttonOk').onClick = function()
            requestBuy(selectedCount)
            confirmWindow:hide()
        end

        confirmWindow:getChildById('buttonCancel').onClick = function()
            confirmWindow:hide()
        end

        confirmWindow:show()
        confirmWindow:raise()
        confirmWindow:getChildById('buttonOk'):focus()
        return
    end

    local confirmBox
    confirmBox = displayGeneralBox(tr("Confirm Purchase"),
                                   tr(
                                       "You are about to buy %s for %d gp. Do you want to complete the purchase?",
                                       panel.itemName:getText(), price * count),
                                   {
        {
            text = tr("Ok"),
            callback = function()
                requestBuy(count)
                if confirmBox then confirmBox:destroy() end
            end
        }, {
            text = tr("Cancel"),
            callback = function()
                if confirmBox then confirmBox:destroy() end
            end
        }
    }, function() -- Enter
        requestBuy(count)
        if confirmBox then confirmBox:destroy() end
    end, function() -- Escape
        if confirmBox then confirmBox:destroy() end
    end)
end

local function parseShopClose() hide() end

local function parseShop(protocol, opcode, buffer)
    if opcode ~= Config.opcode then return end
    buffer = json.decode(buffer)
    local data = buffer.d
    local evt = buffer.e
    if not evt then return end
    if evt == 'SHOP_OPEN' then
        parseShopOpen(data)
    elseif evt == 'SHOP_CLOSE' then
        parseShopClose()
    end
end

function onEditShop()
    EditShopWindow:show()

    EditShopWindow:raise()
    EditShopWindow:focus()
end

local function parseShopClose(data)
    MainWindow:hide()
    MainWindow:setEnabled(false)
    MainWindow.currentShop = {}
end

function doShopClose()
    local payload = {e = 'SHOP_CLOSE', d = MainWindow.currentShop.seller}
    g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                json.encode(payload))
end

function show()
    MainWindow:show()
    MainWindow:focus()
end

function hide()
    MainWindow.lockUpdate = nil
    MainWindow:hide()
    EditShopWindow:hide()
    SelectItemWindow:hide()
end

local function requestShopCreate(player)
    if MainWindow.currentShop and MainWindow.currentShop.seller ==
        player:getId() then
        displayInfoBox("Error", "Your shop is already open.")
        return false
    end

    local payload = {e = 'SHOP_CREATE'}
    g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                json.encode(payload))
end

local function onShopCreate(player, data) end

function onPositionChange(player, newPos, oldPos)
    if player:isLocalPlayer() then show() end
end

function init()
    connect(g_game, {onGameEnd = onGameEnd, onGameStart = onGameStart})

    MainWindow = g_ui.loadUI('shops', g_ui.getRootWidget())
    EditShopWindow = g_ui.createWidget('EditShopWindow', g_ui.getRootWidget())
    -- MainWindow.onEscape = function() MainWindow:hide() end

    MainWindow.contentInfo = g_ui.createWidget('ContainerPanel',
                                               g_ui.getRootWidget())
    MainWindow.contentInfo.panel = nil
    MainWindow.contentInfo:hide()

    SelectItemWindow = MainWindow.selectItem

    hide()

    MainWindow.currentShop = {}

    MainWindow.offer5.offerItem:setImageSource("/images/ui/rarity_gold")
    MainWindow.offer6.offerItem:setImageSource("/images/ui/rarity_gold")

    if g_game.isOnline() then onGameStart() end
    ProtocolGame.registerExtendedOpcode(Config.opcode, parseShop)
end

local function onCreatureAppear(creature)
    local payload = {e = 'ASK', d = creature.id}

    g_game.getProtocolGame():sendExtendedOpcode(Config.opcode,
                                                json.encode(payload))
end
