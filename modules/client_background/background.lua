-- private variables
local background
local clientVersionLabel
local playersOnlineLabel
local infoWindow

-- public functions
function init()
  background = g_ui.displayUI('background')
  background:lower()

  infoWindow = g_ui.createWidget('InfoWindow', background)
  infoWindow:hide()

  clientVersionLabel = background:getChildById('clientVersionLabel')
  clientVersionLabel:setText('OTClientV8 ' .. g_app.getVersion() .. '\nrev ' .. g_app.getBuildRevision() .. '\nMade by:\n' .. g_app.getAuthor() .. "")

  playersOnlineLabel = background:recursiveGetChildById('playersOnlineLabel')

  if not g_game.isOnline() then
    addEvent(function() g_effects.fadeIn(clientVersionLabel, 1500) end)
    -- Aguarda 2s antes da primeira requisição para garantir que os módulos carregaram
    scheduleEvent(fetchPlayersOnline, 2000)
  end

  connect(g_game, { onGameStart = hide })
  connect(g_game, { onGameEnd = show })
end

function terminate()
  disconnect(g_game, { onGameStart = hide })
  disconnect(g_game, { onGameEnd = show })

  g_effects.cancelFade(background:getChildById('clientVersionLabel'))
  background:destroy()

  infoWindow:destroy()
  infoWindow = nil

  Background = nil
end

function hide()
  background:hide()
end

function show()
  background:show()
end

function showInfoWindow()
  if not infoWindow:isVisible() then
   infoWindow:show()
  end
end

function hideVersionLabel()
  background:getChildById('clientVersionLabel'):hide()
end

function setVersionText(text)
  clientVersionLabel:setText(text)
end

function getBackground()
  return background
end

function fetchPlayersOnline()
  if not playersOnlineLabel or not Services or not Services.status or Services.status == "" then
    return
  end

  local ok, err = pcall(function()
    HTTP.getJSON(Services.status, function(data, httpErr)
      if not playersOnlineLabel then return end
      if httpErr then
        g_logger.warning('[status] httpErr: ' .. tostring(httpErr))
        playersOnlineLabel:setText('Servidor offline')
        playersOnlineLabel:setColor('#ff6666')
      elseif not data then
        g_logger.warning('[status] data is nil')
        playersOnlineLabel:setText('Servidor offline')
        playersOnlineLabel:setColor('#ff6666')
      else
        local count = tonumber(data.playersOnline) or 0
        if count == 1 then
          playersOnlineLabel:setText('1 jogador online')
        else
          playersOnlineLabel:setText(count .. ' jogadores online')
        end
        playersOnlineLabel:setColor('#aaffaa')
      end
      scheduleEvent(fetchPlayersOnline, 60000)
    end)
  end)

  if not ok then
    g_logger.warning('[background] fetchPlayersOnline: ' .. tostring(err))
    -- Tenta novamente em 30s se falhou
    scheduleEvent(fetchPlayersOnline, 30000)
  end
end
