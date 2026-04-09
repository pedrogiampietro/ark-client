expWindow = nil
analyzerButton = nil
lootedItems = {}
killedCreatures = {}
creatureOutfit = nil
supplyItems = {}
totalLootValue = 0
totalSupplyCost = 0
runeWindow = nil
runeUpdateEvent = nil

local HUNT_ANALYZER_OPCODE = 55

function init()
  ProtocolGame.registerExtendedOpcode(HUNT_ANALYZER_OPCODE, onHuntAnalyzerData)
  
  connect(g_game, {
    onGameStart = refresh,
    onGameEnd = offline
  })

  mainWindow = g_ui.loadUI('mainWindow', modules.game_interface.getRightPanel())
  expWindow = g_ui.loadUI('expAnalyzer', modules.game_interface.getRightPanel())
  dropWindow = g_ui.loadUI('dropTracker', modules.game_interface.getRightPanel())
  dropWindow.onClose = dropWindow:hide()
  trackWindow = g_ui.loadUI('killTracker', modules.game_interface.getRightPanel())
  balanceWindow = g_ui.loadUI('balanceTracker', modules.game_interface.getRightPanel())
  runeWindow = g_ui.loadUI('runeTracker', modules.game_interface.getRightPanel())
  mainWindow:hide()
  dropWindow:hide()
  trackWindow:hide()
  expWindow:hide()
  balanceWindow:hide()
  runeWindow:hide()
  g_keyboard.bindKeyDown('Ctrl+H', toggle)

  expWindow:setup()
  dropWindow:setup()
  trackWindow:setup()
  balanceWindow:setup()
  runeWindow:setup()
  mainWindow:setup()

  lootedItemsLabel = dropWindow:recursiveGetChildById("lootedItemsLabel")
  lootedItemsLabel:setHeight(30)
  killedMonstersLabel = trackWindow:recursiveGetChildById("monsterLabel")
  killedMonstersLabel:setHeight(30)
  supplyItemsLabel = balanceWindow:recursiveGetChildById("supplyItemsLabel")
  supplyItemsLabel:setHeight(30)
  
  startFreshanalyzerWindow()
  
end

--//########## REAL MAGIC ##########//--
expHUpdateEvent = 0
expHVar = {
	originalExpAmount = 0,
	lastExpAmount = 0,
	historyIndex = 0,
	sessionStart = 0,
}
expHistory = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}



function showExpWindow()
	if not expWindow:isVisible() then
		expWindow:show()
		updateanalyzerWindow()
	else
		expWindow:hide()
	end
end

function showDropWindow()
	if not dropWindow:isVisible() then
		dropWindow:show()
	else
		dropWindow:hide()
	end
end
function showKillWindow()
	if not trackWindow:isVisible() then
		trackWindow:show()
	else
		trackWindow:hide()
	end
end

function showBalanceWindow()
	if not balanceWindow:isVisible() then
		balanceWindow:show()
		updateBalanceDisplay()
	else
		balanceWindow:hide()
	end
end

function resetSessionAll()
	 resetLootedItems()
	 resetKilledMonsters()
	 resetSupplyItems()
	 resetRuneTracker()
	 updateanalyzerWindow()
	 startFreshanalyzerWindow()
	 killedCreatures = {}
	 lootedItems = {}
	 supplyItems = {}
	 totalLootValue = 0
	 totalSupplyCost = 0
	 if not dropWindow:isVisible() then
		dropWindow:show()
	end
	if not trackWindow:isVisible() then
		trackWindow:show()
	end
	if not expWindow:isVisible() then
		expWindow:show()
		updateanalyzerWindow()
	end
	if not balanceWindow:isVisible() then
		balanceWindow:show()
		updateBalanceDisplay()
	end
end

function resetKillTracker()
	resetKilledMonsters()
	killedCreatures = {}
end



function zerarHistory()
	for zero = 1,60 do
		expHistory[zero] = 0
	end
end

function startFreshanalyzerWindow()
	resetExpH()
	if expHUpdateEvent ~= 0 then
		removeEvent(expHUpdateEvent)
	end
	
end

function updateanalyzerWindow()
	expHUpdateEvent = scheduleEvent(updateanalyzerWindow, 5000)
	local player = g_game.getLocalPlayer()
	if not player then return end --Wont go future if there's no player
  
	local currentExp = player:getExperience()
	if expHVar.lastExpAmount == 0 then
		expHVar.lastExpAmount = currentExp
	end
	if expHVar.originalExpAmount == 0 then
		expHVar.originalExpAmount = currentExp
	end
	local expDiff = math.floor(currentExp-expHVar.lastExpAmount)
	updateExpHistory(expDiff)
	expHVar.lastExpAmount = currentExp
	
	local _expGained = math.floor(currentExp-expHVar.originalExpAmount)
	
	local _expHistory = getExpGained()
	if _expHistory <= 0 and (expHVar.sessionStart > 0 or _expGained > 0) then --No Exp gained last 5 min, lets stop
		resetExpH()
		return false
	end
	
	local _session = 0
	local _start = expHVar.sessionStart
	if _start > 0 and _expGained > 0 then
		_session = math.floor(g_clock.seconds()-_start)
	end
	
	local string_session = getTimeFormat(_session)
	local string_expGain = number_format(_expGained)
	-----------------------------------------------------
	local _getExpHour = getExpPerHour(_expHistory, _session)
	local string_expph = number_format(_getExpHour)
	-----------------------------------------------------

	local _lvl = player:getLevel()
	local _nextLevelExp = getExperienceForLevel(_lvl+1)
	local _expToNextLevel = math.floor(_nextLevelExp-currentExp)
	
	local string_exptolevel = number_format(_expToNextLevel)
	
	local _timeToNextLevel = getNextLevelTime(_expToNextLevel, _getExpHour)
	local string_timetolevel = getTimeFormat(_timeToNextLevel)
	
	setSkillValue('session',		string_session)
	setSkillValue('expph',			string_expph)
	setSkillValue('expgained',		string_expGain)
	setSkillValue('exptolevel',		string_exptolevel)
	setSkillValue('timetolevel',	string_timetolevel)
end


function getNextLevelTime(_expToNextLevel, _getExpHour)
	if _getExpHour <= 0 then
		return 0
	end
	local _expperSec = (_getExpHour/3600)
	local _secToNextLevel = math.ceil(_expToNextLevel/_expperSec)
	return _secToNextLevel
end

function getExperienceForLevel(lv)
	lv = lv - 1
	return ((50 * lv * lv * lv) - (150 * lv * lv) + (400 * lv)) / 3
end

function getNumber(msg)
	b, e = string.find(msg, "%d+")
	
	if b == nil or e == nil then
		count = 0
	else
		count = tonumber(string.sub(msg, b, e))
	end	
	return count
end

function number_format(amount)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end
  return formatted
end

function getExpPerHour(_expHistory, _session)
	if _session < 10 then
		_session = 10
	elseif _session > 300 then
		_session = 300
	end
	
	local _expSec = _expHistory/_session
	local _expH = math.floor(_expSec*3600)
	if _expH <= 0 then
		_expH = 0
	end
	return getNumber(_expH)
end

function getTimeFormat(_secs)
	local _hour = math.floor(_secs/3600)
	_secs = math.floor(_secs-(_hour*3600))
	local _min = math.floor(_secs/60)
	
	if _hour <= 0 then
		_hour = "00"
	elseif _hour <= 9 then
		_hour = "0".. _hour
	end
	if _min <= 0 then
		_min = "00"
	elseif _min <= 9 then
		_min = "0".. _min
	end
	return _hour ..":".. _min
end

function updateExpHistory(dif)
	if dif > 0 then
		if expHVar.sessionStart == 0 then
			expHVar.sessionStart = g_clock.seconds()
		end
	end
	
	local _index = expHVar.historyIndex
	expHistory[_index] = dif
	_index = _index+1
	if _index < 0 or _index > 59 then
		_index = 0
	end
	expHVar.historyIndex = _index
end

function getExpGained()
	local totalExp = 0
	for key,value in pairs(expHistory) do
		totalExp = totalExp + value
	end
	return totalExp
end

function resetExpH()
	expHVar.originalExpAmount = 0
	expHVar.lastExpAmount = 0
	expHVar.historyIndex = 0
	expHVar.sessionStart = 0


	setSkillValue('session',		"00:00")
	setSkillValue('expph',			0)			setSkillColor('expph',			'#6eff8d')
	setSkillValue('expgained',		0)			setSkillColor('expgained',		'#edebeb')
	setSkillValue('exptolevel',		0)			setSkillColor('exptolevel',		'#edebeb')
	setSkillValue('timetolevel',	"00:00")	setSkillColor('timetolevel',	'#edebeb')
	
	zerarHistory()
end
--//########## REAL MAGIC ##########//--

-- Rune Tracker (self-contained, notified via onCharmProc from game_cyclopedia)
local runeTrackerData   = {}  -- [charmId] = { procs=N, totalDamage=N, name=S }
local runeSessionStart  = nil -- os.time() when window was opened

local charmNames = {
  [ 0] = 'Wound',        [ 1] = 'Enflame',      [ 2] = 'Poison',
  [ 3] = 'Freeze',       [ 4] = 'Zap',           [ 5] = 'Curse',
  [ 6] = 'Cripple',      [ 7] = 'Parry',         [ 8] = 'Dodge',
  [ 9] = 'Adrenaline',   [10] = 'Numb',           [11] = 'Cleanse',
  [12] = 'Bless',        [13] = 'Scavenge',       [14] = 'Gut',
  [15] = 'Low Blow',     [16] = 'Divine Wrath',   [17] = 'Vampiric',
  [18] = "Void's Call",  [19] = 'Savage Blow',    [20] = 'Fatal Hold',
  [21] = 'Void Inv.',    [22] = 'Carnage',        [23] = 'Overpower',
  [24] = 'Overflux',
}

-- Called by game_cyclopedia.parseCharmProc each time a charm fires
function onCharmProc(charmId, damage)
  local entry = runeTrackerData[charmId]
  if not entry then
    runeTrackerData[charmId] = {
      procs       = 1,
      totalDamage = damage,
      name        = charmNames[charmId] or ('Charm #' .. charmId),
    }
  else
    entry.procs       = entry.procs + 1
    entry.totalDamage = entry.totalDamage + damage
  end
  if runeWindow and runeWindow:isVisible() then
    runeDrawCharmRow(charmId, runeTrackerData[charmId])
    local noDataLabel = runeWindow:recursiveGetChildById('noDataLabel')
    if noDataLabel then noDataLabel:setVisible(false) end
  end
end

-- Draw/update a single charm row without touching other rows
function runeDrawCharmRow(charmId, data)
  local runeList = runeWindow:recursiveGetChildById('runeList')
  if not runeList then return end

  local rowId = 'charmRow_' .. charmId
  local row   = runeList:getChildById(rowId)
  if not row then
    row = g_ui.createWidget('RuneRow', runeList)
    if not row then return end
    row:setId(rowId)
  end

  local nameLabel  = row:getChildById('runeName')
  local procsLabel = row:getChildById('runeProcs')
  local dmgLabel   = row:getChildById('runeDmg')

  if nameLabel  then nameLabel:setText(data.name .. ':') end
  if procsLabel then procsLabel:setText(data.procs .. 'x') end
  if dmgLabel   then
    if data.totalDamage > 0 then
      dmgLabel:setText('(' .. number_format(data.totalDamage) .. ' dmg)')
    else
      dmgLabel:setText('')
    end
  end
  -- Atualiza altura do container (OTClient não auto-redimensiona com filhos dinâmicos)
  runeList:setHeight(runeList:getChildCount() * 22)
end

-- Rebuild the full list from runeTrackerData (used when window is reopened)
function runeRebuildList()
  if not runeWindow then return end
  local runeList    = runeWindow:recursiveGetChildById('runeList')
  local noDataLabel = runeWindow:recursiveGetChildById('noDataLabel')
  if runeList then runeList:destroyChildren(); runeList:setHeight(0) end
  local hasData = next(runeTrackerData) ~= nil
  if noDataLabel then noDataLabel:setVisible(not hasData) end
  if not runeList then return end
  for charmId, data in pairs(runeTrackerData) do
    runeDrawCharmRow(charmId, data)
  end
end

function showRuneWindow()
  if not runeWindow:isVisible() then
    if not runeSessionStart then
      runeSessionStart = os.time()
    end
    runeWindow:show()
    runeRebuildList()
    if not runeUpdateEvent then
      updateRuneTracker()
    end
  else
    runeWindow:hide()
  end
end

function resetRuneTracker()
  runeTrackerData  = {}
  runeSessionStart = os.time()
  local runeList    = runeWindow and runeWindow:recursiveGetChildById('runeList')
  local noDataLabel = runeWindow and runeWindow:recursiveGetChildById('noDataLabel')
  if runeList    then runeList:destroyChildren(); runeList:setHeight(0) end
  if noDataLabel then noDataLabel:setVisible(true) end
  if modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia then
    modules.game_cyclopedia.Cyclopedia.resetCharmAnalyzer()
  end
end

-- Only ticks the session timer; never touches the charm rows
function updateRuneTracker()
  if runeUpdateEvent then removeEvent(runeUpdateEvent) end
  runeUpdateEvent = scheduleEvent(updateRuneTracker, 1000)

  if not runeWindow or not runeWindow:isVisible() then return end

  local sessionLabel = runeWindow:recursiveGetChildById('sessionLabel')
  if sessionLabel then
    local secs = 0
    if runeSessionStart then
      secs = math.floor(os.time() - runeSessionStart)
    end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    sessionLabel:setText(string.format('Session: %02d:%02d:%02d', h, m, s))
  end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(HUNT_ANALYZER_OPCODE)
  disconnect(g_game, {
    onGameStart = refresh,
    onGameEnd = offline
  })

  g_keyboard.unbindKeyDown('Ctrl+J')
  if runeUpdateEvent then removeEvent(runeUpdateEvent); runeUpdateEvent = nil end
  mainWindow:destroy()
  expWindow:destroy()
  dropWindow:destroy()
  trackWindow:destroy()
  balanceWindow:destroy()
  runeWindow:destroy()
end

function expForLevel(level)
  return math.floor((50*level*level*level)/3 - 100*level*level + (850*level)/3 - 200)
end

function expToAdvance(currentLevel, currentExp)
  return expForLevel(currentLevel+1) - currentExp
end

function comma_value(n)
	local left,num,right = string.match(n,'^([^%d]*%d)(%d*)(.-)$')
	return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

function resetLootedItems()
local numberOfChilds = lootedItemsLabel:getChildCount()
for i = 1, numberOfChilds do
	lootedItemsLabel:destroyChildren(i)
end
	lootedItemsLabel:setHeight(30)
	return 
end

function resetKilledMonsters()
	local numberOfChilds = killedMonstersLabel:getChildCount()
	for i = 1, numberOfChilds do
		killedMonstersLabel:destroyChildren(i)
	end
	killedMonstersLabel:setHeight(30)
	return 
end

function setSkillValue(id, value)
	local skill = expWindow:recursiveGetChildById(id)
	local widget = skill:getChildById('value')
	widget:setText(value)
  end
  
  function setSkillColor(id, value)
	local skill = expWindow:recursiveGetChildById(id)
	local widget = skill:getChildById('value')
	widget:setColor(value)
  end



function onHuntAnalyzerData(protocol, opcode, buffer)
	if not buffer or buffer == "" then return end

	local msgType = buffer:sub(1, buffer:find(":") - 1)
	local msgData = buffer:sub(buffer:find(":") + 1)

	if msgType == "KILL" then
		onKillData(msgData)
	elseif msgType == "SUPPLY" then
		onSupplyData(msgData)
	elseif msgType == "LOOT" then
		onLootData(msgData)
	end
end

function onKillData(data)
	-- Format: monsterName;lookType,head,body,legs,feet,addons
	local parts = {}
	for part in data:gmatch("[^;]+") do
		table.insert(parts, part)
	end
	if #parts < 2 then return end

	local monsterName = parts[1]
	local outfitParts = {}
	for v in parts[2]:gmatch("[^,]+") do
		table.insert(outfitParts, tonumber(v) or 0)
	end
	local lookType = outfitParts[1] or 19
	local lookHead = outfitParts[2] or 0
	local lookBody = outfitParts[3] or 0
	local lookLegs = outfitParts[4] or 0
	local lookFeet = outfitParts[5] or 0
	local addons = outfitParts[6] or 0

	-- Track the creature kill
	if not killedCreatures[monsterName] then
		killedCreatures[monsterName] = {amount = 0, lookType = lookType, lookHead = lookHead, lookBody = lookBody, lookLegs = lookLegs, lookFeet = lookFeet, addons = addons}
	end
	killedCreatures[monsterName].amount = killedCreatures[monsterName].amount + 1

	updateKillTracker(killedCreatures)
end

function onLootData(data)
	-- Format: serverId:name:count
	local firstColon = data:find(":")
	local lastColon = data:find(":[^:]*$")
	if not firstColon or not lastColon or firstColon == lastColon then return end

	local serverId = tonumber(data:sub(1, firstColon - 1)) or 0
	local itemName = data:sub(firstColon + 1, lastColon - 1)
	local itemCount = tonumber(data:sub(lastColon + 1)) or 1

	if serverId > 0 then
		if not lootedItems[serverId] then
			lootedItems[serverId] = { amount = 0, name = itemName }
		end
		lootedItems[serverId].amount = lootedItems[serverId].amount + itemCount

		local price = LOOT_PRICES[serverId] or 0
		totalLootValue = totalLootValue + (price * itemCount)
	end

	updateDropTracker(lootedItems)
	updateBalanceDisplay()
end

function onSupplyData(data)
	local serverId = tonumber(data)
	if not serverId then return end

    if not supplyItems[serverId] then
        supplyItems[serverId] = { amount = 0 }
    end
    supplyItems[serverId].amount = supplyItems[serverId].amount + 1

    local price = SUPPLY_PRICES[serverId] or 0
    totalSupplyCost = totalSupplyCost + price

    updateSupplyDisplay(supplyItems)
    updateBalanceDisplay()
end

function copyKillToClipboard()
	if not killedCreatures or killedCreatures == nil then
	  return
	end
	local creatureNames = {}
	for name, kills in pairs(killedCreatures) do

        table.insert(creatureNames, string.lower(name) .. " (" .. kills.amount .. ")")
    end
	table.sort(creatureNames)  -- Sorts alphabetically by default.
  
	local text = table.concat(creatureNames, ", ")
	if text and text ~= "" then
	  g_window.setClipboardText("Kills Session: "..text)
	end
end

function copyLootToClipboard()
    if not lootedItems or next(lootedItems) == nil then
        return
    end
    local maxChars = 250
    local prefix = "Loot Session: "
    local suffix = " [max text exceeded]"
    local availableChars = maxChars - #suffix  -- Reserve space for the suffix
    local loot = {}
    local currentLength = #prefix
    local textExceeded = false 

    for itemId, data in pairs(lootedItems) do
        local count = data.amount
        if count >= 1000 then
            count = math.floor(count / 1000) .. "k" 
        end

        local entry = data.name .. " (" .. count .. ")"
        if currentLength + #entry + 2 <= availableChars then  -- +2 for ", " separator
            table.insert(loot, entry)
            currentLength = currentLength + #entry + 2
        else
            textExceeded = true 
            break  -- Stop adding more entries if the next one would exceed the limit of max chars
        end
    end
    local text = table.concat(loot, ", ")
    if text ~= "" then
        if textExceeded then
            text = text .. suffix
        end
        g_window.setClipboardText(prefix .. text)
    end
end

function updateKillTracker()
    local numberOfLines = 0
    for k, v in pairs(killedCreatures) do
        local creatureSprite = killedMonstersLabel:getChildById("monster"..k)
        if not creatureSprite then
            creatureSprite = g_ui.createWidget("Creature", killedMonstersLabel)
            creatureSprite:setId("monster"..k)
            creatureSprite:setTooltip(k)
        end

        local creatureName = killedMonstersLabel:getChildById("name"..k)
        if not creatureName then
            creatureName = g_ui.createWidget("MonsterNameLabel", killedMonstersLabel)
            creatureName:setId("name"..k)
            creatureName:addAnchor(AnchorLeft, "monster"..k, AnchorRight)
            creatureName:addAnchor(AnchorTop, "monster"..k, AnchorTop)
            creatureName:setMarginLeft(5)
        end

        local creatureCount = killedMonstersLabel:getChildById("count"..k)
        if not creatureCount then
            creatureCount = g_ui.createWidget("CreatureCountLabel", killedMonstersLabel)
            creatureCount:setId("count"..k)
            creatureCount:addAnchor(AnchorBottom,"monster"..k, AnchorBottom)
            creatureCount:addAnchor(AnchorLeft,"monster"..k, AnchorRight)
            creatureCount:setMarginLeft(5)
        end

        creatureCount:setText("Kills: "..v.amount)
        creatureName:setText(k)
        creatureSprite:setMarginTop(numberOfLines * 34 + 17)

        local creature = Creature.create()
        local outfit = {type = v.lookType, head = v.lookHead, body = v.lookBody, legs = v.lookLegs, feet = v.lookFeet, addons = v.addons}
        creature:setOutfit(outfit)


        creatureSprite:setCreature(creature)
        numberOfLines = numberOfLines + 1
    end
    killedMonstersLabel:setHeight(numberOfLines * 34 + 60)
end


function updateDropTracker(data)
    if dropWindow:isVisible() then
        local items = 0
        for k, v in pairs(data) do
            local itemSprite = lootedItemsLabel:getChildById("image"..k)
            if not itemSprite then
                itemSprite = g_ui.createWidget("ItemSprite", lootedItemsLabel)
                itemSprite:setId("image"..k)
            end
            itemSprite:setItemId(k)
            itemSprite:setMarginTop(items * 34 + 17)
            itemSprite:setMarginLeft(5)

            local count = v.amount
            if count >= 1000 then
                count = (count / 1000) .."k"
            end

            local itemLabel = lootedItemsLabel:getChildById("itemLabel"..k)
            if not itemLabel then
                itemLabel = g_ui.createWidget("ItemNameLabel", lootedItemsLabel)
                itemLabel:setId("itemLabel"..k)
                itemLabel:addAnchor(AnchorLeft, "image"..k, AnchorRight)
                itemLabel:addAnchor(AnchorTop, "image"..k, AnchorTop)
                itemLabel:setMarginLeft(5)
            end
            itemLabel:setText(v.name)

            local lootLabel = lootedItemsLabel:getChildById("lootLabel"..k)
            if not lootLabel then
                lootLabel = g_ui.createWidget("LootLabel", lootedItemsLabel)
                lootLabel:setId("lootLabel"..k)
                lootLabel:addAnchor(AnchorBottom, "image"..k, AnchorBottom)
                lootLabel:addAnchor(AnchorLeft, "image"..k, AnchorRight)
                lootLabel:setMarginLeft(5)
            end
            lootLabel:setText("Loot Drops: " .. count)

            items = items + 1
        end
        lootedItemsLabel:setHeight((items * 33 + 60) + 20)
    end
end

function resetDropTracker()
	resetLootedItems()
	lootedItems = {}
end

function resetSupplyItems()
	local numberOfChilds = supplyItemsLabel:getChildCount()
	for i = 1, numberOfChilds do
		supplyItemsLabel:destroyChildren(i)
	end
	supplyItemsLabel:setHeight(30)
end

function resetBalanceTracker()
	resetSupplyItems()
	supplyItems = {}
	totalLootValue = 0
	totalSupplyCost = 0
	updateBalanceDisplay()
end

function setBalanceValue(id, value)
	local skill = balanceWindow:recursiveGetChildById(id)
	if skill then
		local widget = skill:getChildById('value')
		if widget then
			widget:setText(value)
		end
	end
end

function setBalanceColor(id, color)
	local skill = balanceWindow:recursiveGetChildById(id)
	if skill then
		local widget = skill:getChildById('value')
		if widget then
			widget:setColor(color)
		end
	end
end

function formatGold(amount)
	if amount >= 1000000 then
		return string.format("%.1fkk", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.1fk", amount / 1000)
	end
	return tostring(amount)
end

function updateBalanceDisplay()
	setBalanceValue('lootValue', formatGold(totalLootValue) .. " gp")
	setBalanceValue('supplyValue', formatGold(totalSupplyCost) .. " gp")

	local balance = totalLootValue - totalSupplyCost
	local balanceStr = formatGold(math.abs(balance)) .. " gp"
	if balance < 0 then
		balanceStr = "-" .. balanceStr
		setBalanceColor('balanceValue', '#ff6e6e')
	elseif balance > 0 then
		balanceStr = "+" .. balanceStr
		setBalanceColor('balanceValue', '#6eff8d')
	else
		setBalanceColor('balanceValue', '#edebeb')
	end
	setBalanceValue('balanceValue', balanceStr)
end

function updateSupplyDisplay(data)
	if not balanceWindow:isVisible() then return end

	local items = 0
	for k, v in pairs(data) do
		local itemSprite = supplyItemsLabel:getChildById("supImg"..k)
		if not itemSprite then
			itemSprite = g_ui.createWidget("SupplyItemSprite", supplyItemsLabel)
			itemSprite:setId("supImg"..k)
		end
		itemSprite:setItemId(k)
		itemSprite:setMarginTop(items * 34 + 17)
		itemSprite:setMarginLeft(5)

		local count = v.amount
		local countStr = tostring(count)
		if count >= 1000 then
			countStr = string.format("%.1fk", count / 1000)
		end

		local price = SUPPLY_PRICES[k] or 0
		local totalCost = price * count

		local itemLabel = supplyItemsLabel:getChildById("supName"..k)
		if not itemLabel then
			itemLabel = g_ui.createWidget("SupplyItemNameLabel", supplyItemsLabel)
			itemLabel:setId("supName"..k)
			itemLabel:addAnchor(AnchorLeft, "supImg"..k, AnchorRight)
			itemLabel:addAnchor(AnchorTop, "supImg"..k, AnchorTop)
			itemLabel:setMarginLeft(5)
		end
		itemLabel:setText("x" .. countStr)

		local costLabel = supplyItemsLabel:getChildById("supCost"..k)
		if not costLabel then
			costLabel = g_ui.createWidget("SupplyItemCountLabel", supplyItemsLabel)
			costLabel:setId("supCost"..k)
			costLabel:addAnchor(AnchorBottom, "supImg"..k, AnchorBottom)
			costLabel:addAnchor(AnchorLeft, "supImg"..k, AnchorRight)
			costLabel:setMarginLeft(5)
		end
		costLabel:setText(formatGold(totalCost) .. " gp")

		items = items + 1
	end
	supplyItemsLabel:setHeight((items * 33 + 60) + 20)
end


function refresh()
	local player = g_game.getLocalPlayer()
	if not player then return end
	resetExpH()
	if runeWindow and runeWindow:isVisible() and not runeUpdateEvent then
		updateRuneTracker()
	end
end

function offline()
	startFreshanalyzerWindow()
	resetLootedItems()
	resetKilledMonsters()
	resetSupplyItems()
	if runeUpdateEvent then removeEvent(runeUpdateEvent); runeUpdateEvent = nil end
end

function toggle()
  mainWindow:setOn(not mainWindow:isVisible())
  if mainWindow:isVisible() then
	mainWindow:close()
  else
	mainWindow:open()
  end
end

function onMiniWindowClose()
end
