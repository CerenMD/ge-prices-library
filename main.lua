-- Temporary assigning of permissions
ExecuteConsoleCommand("ppr gepl")
ExecuteConsoleCommand("ppe gepl http")

-- Loads the GE Price Service module and initializes the GEPrice instance.
local PriceService = require("price_service")
local GEPrice = PriceService.new("/api/v2/rs/latest")

return GEPrice