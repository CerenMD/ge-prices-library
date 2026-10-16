local UI = {}
local Settings = nil

--- Creates the settings UI within the Settings Layer when opened.
---@param event userdata Event which contains the root component of the settings layer.
---@return boolean success Returns true if the settings UI was successfully created.
Event.SettingsLayerReady.Subscribe("SettingsOpen", function(event)
    local rootLayer = event.component

    local background = ui.Rectangle.new(rootLayer)
    background:SetSize(rootLayer.width, 65)
    background.colour = Vector4.new(46 / 255, 40 / 255, 37 / 255, 1.0)
    background.fill = true

    local label = ui.Text.new(rootLayer)
    label:SetSize(200, 20)
    label:SetPos(5, 5)
    label.content = "Enable price fetching"
    label.font = config.Font.MUSEO_SANS_13PT_REGULAR.id
    label.colour = Vector4.new(180 / 255, 160 / 255, 146 / 255, 1.0)
    label.isShadowed = true

    local description = ui.Text.new(rootLayer)
    description:SetSize(500, 50)
    description:SetPos(5, 25)
    description.content = "Allows the plugin to retrieve new prices. If disabled, the last prices will be retained until re-enabled."
    description.font = config.Font.MUSEO_SANS_11PT_REGULAR.id
    description.colour = Vector4.new(219 / 255, 207 / 255, 199 / 255, 1.0)
    description.isShadowed = true

    local checkbox = ui.Check.new(rootLayer)
    checkbox:SetSize(rootLayer.width, 65)
    checkbox:SetPos(-10, 0)
    checkbox.value = Settings.config.enablePriceFetching
    checkbox.stylesheetID = id.StyleSheet.CHECKBOX_DEFAULT_RIGHT_ALIGNED
    checkbox.alignment = ui.CheckAlignMode.RIGHT
    checkbox.buttonSize = 20
    checkbox:Subscribe(ui.Hook.ONBUTTONPRESSED, "toggleCheckbox",
        function (check, ticked)
            Settings.config.enablePriceFetching = ticked == 1
        end)

    return true
end)

--- Binds the plugin settings to the UI module.
--- @param settings table The plugin settings to bind to the UI module.
function UI.BindSettings(settings)
    Settings = settings
end

--- Unsubscribes from the SettingsLayerReady event as part of cleanup.
function UI.Shutdown()
    Event.SettingsLayerReady.Unsubscribe("SettingsOpen")
end

return UI