-- Temporary assigning of permissions
ExecuteConsoleCommand("ppr gepl")
ExecuteConsoleCommand("ppe gepl httpAccess")

-- Loads the GE Price Service module and initializes the GEPrice instance.
local PriceService = require("price_service")
local GEPrice = PriceService.new()

-- Cleans up the plugin when it is shut down.
function PluginShutdown()
    -- Nothing right now.
end

return GEPrice