local SettingsConfig = {
    enablePriceFetching = true,
}

local Settings = {
    config = SettingsConfig
}

--- Loads the plugin settings from the persistent database.
function Settings.LoadSettings()
    if (PersistentDB:CheckExists("GEPL_Settings")) then
        SettingsConfig = PersistentDB:GetStructuredData("GEPL_Settings")
        Settings.config = SettingsConfig
    end
end

--- Saves the settings to the persistent databse.
function Settings.SaveSettings()
    PersistentDB:SetStructuredData("GEPL_Settings", SettingsConfig)
end

return Settings