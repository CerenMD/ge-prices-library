---@class PriceResult
---@field data table<integer, Item>
---@field indices table<integer, {first: integer, last: integer}>
---@field lastUpdateTime number

---@class Item
---@field high number
---@field highTime integer
---@field low number
---@field lowTime integer

---@class PriceService
---@field getPrice fun(itemId: integer): Item
---@field isReady fun(): boolean
---@field isFetching fun(): boolean

local PriceService = {}

local PDB_BATCH_SIZE = 300 -- number of items per database entry
local CACHE_PERIOD = 5 -- in minutes
local PDB_STORAGE_KEY = "GEPL_"
local PDB_INDEX_KEY = "GEPL_INDEX_"
local PDB_LAST_SAVE_KEY = "GEPL_LAST_SAVE_TIME"


--- Creates the PriceService instance, keeping most of the functions private by embedding them within the constructor.
--- @param endpoint string The API endpoint for fetching GE prices.
--- @return table PriceService The PriceService instance.
function PriceService.new(endpoint)
    local PriceResult = {}
    local IsReady = false
    local IsFetching = false

    --- Inserts the given price data into the persistent database and returns the structured data and indices.
    --- @param price_data string The raw price data in JSON format.
    --- @return table<integer, Item> data The structured price data.
    --- @return table<integer, {first: integer, last: integer}> indices The indices for tracking batches.
    --- @return integer lastUpdateTime the last time the prices were fetched from prices.runescape.wiki.
    local insertPrices = function(price_data)
        local data = {}
        local indices = {}
        for id, high, highTime, low, lowTime in price_data:gmatch('"(%d+)"%s*:%s*{[^}]-"high"%s*:%s*(%d+)[^}]-"highTime"%s*:%s*(%d+)[^}]-"low"%s*:%s*(%d+)[^}]-"lowTime"%s*:%s*(%d+)[^}]-}') do
            local iid = tonumber(id)
            if iid then
                data[iid] = {
                    high = tonumber(high),
                    highTime = tonumber(highTime),
                    low = tonumber(low),
                    lowTime = tonumber(lowTime)
                }
            end
        end
        -- Save batches of prices to the persistent database, last and first index are saved to find the range of stored batches
        local batch = {}
        local count, first, last = 0, 0, 0
        local batch_num = 0
        for id, item in pairs(data) do
            table.insert(batch, {id = id, item = item})
            if count == 0 then first = id end
            last = id
            count = count + 1
            if count >= PDB_BATCH_SIZE then
                -- Save the batch to the database
                PersistentDB:SetStructuredData(PDB_STORAGE_KEY .. batch_num, batch)
                PersistentDB:SetStructuredData(PDB_INDEX_KEY .. batch_num, {first = first, last = last})
                indices[batch_num] = {first = first, last = last}
                batch_num = batch_num + 1
                batch = {}
                count = 0
            end
        end
        if count > 0 then
            -- Save the remaining batch to the database
            PersistentDB:SetStructuredData(PDB_STORAGE_KEY .. batch_num, batch)
            PersistentDB:SetStructuredData(PDB_INDEX_KEY .. batch_num, {first = first, last = last})
            indices[batch_num] = {first = first, last = last}
        end
        -- Update the last save time in the persistent database
        local update_time = var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        PersistentDB:SetInt(PDB_LAST_SAVE_KEY, update_time)
        return data, indices, update_time
    end

    --- Loads the GE prices from the PersistentDB into memory.
    --- @return table<integer, Item> data loaded price data.
    --- @return table<integer, {first: integer, last: integer}> indices loaded indices for tracking batches.
    --- @return integer lastUpdateTime the last time the prices were updated in the persistent database.
    local loadPrices = function()
        local data = {}
        local indices = {}
        local batch_num = 0
        while true do
            local batch = PersistentDB:GetStructuredData(PDB_STORAGE_KEY .. batch_num)
            local index = PersistentDB:GetStructuredData(PDB_INDEX_KEY .. batch_num)
            if not batch or not index then break end
            for _, entry in ipairs(batch) do
                data[entry.id] = entry.item
            end
            indices[batch_num] = index
            batch_num = batch_num + 1
        end
        local lastUpdateTime = PersistentDB:GetInt(PDB_LAST_SAVE_KEY)
        return data, indices, lastUpdateTime
    end

    --- Handles the HTTP response for the GE prices request. Updates PriceResult and readiness state based on the response.
    --- @param req HTTPRequest The HTTP request object containing the response data.
    local requestHandler = function(req)
        IsFetching = false
        if req.successful then
            PriceResult.data, PriceResult.indices, PriceResult.lastUpdateTime = insertPrices(req.data)
            IsReady = true
        elseif req.timedOut then
            log(req.url, "request timed out")
        elseif req.failed then
            log(req.url, "request failed, error code =", req.errorCode)
        end
    end

    --- Fetches the latest GE prices from the server if the plugin has the required HTTP access permission. Updates the fetching state and handles the HTTP request.
    local fetchPrices = function()
        if Plugin.HasPermission(PluginPermissions.httpAccess) then
            IsFetching = true
            local req = HTTPRequest.new(Plugin.urls.prices, endpoint)
            req:AddHeader("User-Agent", "ge-prices-library/1.0")
            req:Get(requestHandler)
        else
            log("Missing required permission: httpAccess")
        end
    end

    --- Gets the GE prices. First checking the cache in the PersistentDB and then fetching from prices.runescape.wiki. The data is loaded into PriceResult and the readiness state is updated.
    local getPrices = function()
        local curTimer = var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        local lastSave = PriceResult.lastUpdateTime
        if lastSave and math.abs(curTimer - lastSave) <= CACHE_PERIOD then
            -- Extract data from PersistentDB
            PriceResult.data, PriceResult.indices, PriceResult.lastUpdateTime = loadPrices()
            IsReady = true
        else
            fetchPrices()
        end
    end

    --- Checks if the cache period has expired and then fetches the prices from prices.runescape.wiki.
    ---@return boolean cacheExpired Returns true if the cache expired, the prices will then be fetched.
    local updateDatabase = function()
        local curTimer = var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        local lastSave = PriceResult.lastUpdateTime
        if lastSave and math.abs(curTimer - lastSave) <= CACHE_PERIOD then return false end
        -- Set lastUpdateTime now to prevent further iterations from initiating multiple fetches while the fetch is running.
        -- Check IsFetching as a safety percaution.
        PriceResult.lastUpdateTime = var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        if not IsFetching then fetchPrices() end
        return true
    end

    -- Initialize the GE prices by either loading from the cache or fetching from the server.
    getPrices()

    return {
        --- Checks if the cache period has expired and then fetches the prices from prices.runescape.wiki.
        --- @return boolean cacheExpired Returns true if the cache expired, the prices will then be fetched.
        updateDatabase = updateDatabase,

        --- Gets the price for a specific item ID from the loaded GE prices.
        --- @param itemId number The ID of the item to get the price for.
        --- @return Item item The price data for the specified item ID.
        --- @throw Invalid itemId resulting in the item not being able to be found.
        getPrice = function(itemId)
            if PriceResult and PriceResult.data and PriceResult.data[itemId] then
                if not IsFetching then updateDatabase() end
                return PriceResult.data[itemId]
            else
                error("Price not found for itemId: " .. tostring(itemId))
            end
        end,

        --- Checks if the GE price service is ready.
        --- @return boolean IsReady true if the service is ready, false otherwise.
        isReady = function()
            return IsReady
        end,

        --- Checks if the GE price service is fetching. The service can still be ready while fetching with previous data.
        --- @return boolean IsFetching true if the service is fetching, false otherwise.
        isFetching = function()
            return IsFetching
        end
    }
end

return PriceService