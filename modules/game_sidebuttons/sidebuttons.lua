
buttonsWindow = nil
battleButton = nil
skillsbutton = nil
vipButton = nil
bestiaryButton = nil

function init()
  buttonsWindow = g_ui.loadUI('sidebuttons', modules.game_interface.getRightPanel())
  buttonsWindow:disableResize()
  buttonsWindow:setup()
  buttonsWindow:open()

  battleButton = buttonsWindow:recursiveGetChildById("battleButton")
  skillsButton = buttonsWindow:recursiveGetChildById("skillsButton")
  vipButton = buttonsWindow:recursiveGetChildById("vipButton")
  bestiaryButton = buttonsWindow:recursiveGetChildById("bestiaryButton")
end

function terminate()
  buttonsWindow:destroy()
end

function toggle()
  if not inventoryButton then
    return
  end

  if inventoryButton:isOn() then
    inventoryWindow:close()
    inventoryButton:setOn(false)
  else
    inventoryWindow:open()
    inventoryButton:setOn(true)
  end
end
