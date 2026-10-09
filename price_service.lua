---@class PriceResult
---@field data table<integer, Item>
---@field indices table
---@field lastUpdateTime table

---@class Item
---@field latest Latest
---@field fiveMinute Average
---@field oneHour Average
---@field timeseries { [string]: TimeSeries }

---@class Latest
---@field high number
---@field highTime integer
---@field low number
---@field lowTime integer

---@class Average
---@field avgHighPrice number
---@field highPriceVolume integer
---@field avgLowPrice number
---@field lowPriceVolume integer

---@class TimedAverage
---@field timestamp integer
---@field avgHighPrice number
---@field highPriceVolume integer
---@field avgLowPrice number
---@field lowPriceVolume integer

---@class TimeSeries
---@field fetchTime integer
---@field startTimestamp integer
---@field endTimestamp integer
---@field timestep integer
---@field data table<TimedAverage>

---@class PriceService
---@field getPrice fun(itemId: integer): Item Deprecated as of 0.2.0. Use getLatest(itemId : number) instead.
---@field getLatest fun(itemId: integer): Latest
---@field getFiveMinuteAverage fun(itemId: integer): Average
---@field getOneHourAverage fun(itemId: integer): Average
---@field getCurrentTimeseries fun(itemId: integer, lookback: string): TimeSeries
---@field isReady fun(): boolean
---@field isFetching fun(): boolean

local Json = require("util/json_helper")
local Private = require("util/protected_helper")

local VERSION = "0.2.0"
local PDB_BATCH_SIZE = 200 -- number of items per database entry
local CACHE_PERIOD = {
    ["latest"] = 100,
    ["5m"] = 500,
    ["1h"] = 500,
    ["timeseries"] = 500,
}
local PDB_STORAGE_KEY = "GEPL_"
local PDB_INDEX_KEY = "GEPL_INDEX_"
local PDB_LAST_SAVE_KEY = "GEPL_LAST_SAVE_TIME_"
local PDB_VERSION_KEY = "GEPL_VERSION"

local LATEST_ENDPOINT = "/api/v2/rs/latest"
local FIVE_MINUTES_ENDPOINT = "/api/v2/rs/5m"
local ONE_HOUR_ENDPOINT = "/api/v2/rs/1h"
local TIMESERIES_ENDPOINT = "/api/v2/rs/timeseries"

local sessionTimer = 0

local PriceService = {}

--- Creates the PriceService instance, keeping most of the functions private by embedding them within the constructor.
--- @return table PriceService The PriceService instance.
function PriceService.new()
    local PriceResult = {
        data = {},
        indices = {},
        lastUpdateTime = {},
    }
    local IsReady = {
        ["latest"] = false,
        ["5m"] = false,
        ["1h"] = false,
        ["timeseries"] = false,
    }
    local IsFetching = {
        ["latest"] = false,
        ["5m"] = false,
        ["1h"] = false,
        ["timeseries"] = false,
    }

    local endpoints = {
        ["latest"] = "latest",
        ["5m"] = "fiveMinute",
        ["1h"] = "oneHour",
        ["timeseries"] = "timeseries",
    }

    -- Check the version of the persistent database and clear it if it doesn't match the current version.
    -- This keeps the persistent database in sync with the current version of the PriceService.
    local lastVersion = "0.0.0"
    if PersistentDB:CheckExists(PDB_VERSION_KEY) then
        lastVersion = PersistentDB:GetString(PDB_VERSION_KEY) or "0.0.0"
    end
    if true or lastVersion ~= VERSION then
        PersistentDB:Clear()
        PersistentDB:SetString(PDB_VERSION_KEY, VERSION)
    end

    --- Inserts the given price data into the persistent database and returns the structured data and indices.
    --- @param endpointName string the name of the endpoint to insert prices for.
    --- @param data string The raw price data in JSON format.
    --- @return table<integer, {first: integer, last: integer}> indices The indices for tracking batches.
    --- @return integer lastUpdateTime the last time the prices were fetched from prices.runescape.wiki.
    local insertPrices = function(endpointName, data)
        local indices = {}
        
        -- Save batches of prices to the persistent database, last and first index are saved to find the range of stored batches
        local batch = {}
        local count, first, last = 0, 0, 0
        local batch_num = 0
        for id, item in pairs(data) do
            batch[#batch + 1] = {id = id, item = item}
            if not PriceResult.data[tostring(id)] then
                PriceResult.data[tostring(id)] = {}
            end
            PriceResult.data[tostring(id)][endpointName] = item
            if count == 0 then first = id end
            last = id
            count = count + 1
            if count >= PDB_BATCH_SIZE then
                -- Save the batch to the database
                PersistentDB:SetStructuredData(PDB_STORAGE_KEY .. string.upper(endpointName) .. "_" .. batch_num, batch)
                PersistentDB:SetStructuredData(PDB_INDEX_KEY .. string.upper(endpointName) .. batch_num, {first = first, last = last})
                indices[batch_num] = {first = first, last = last}
                batch_num = batch_num + 1
                batch = {}
                count = 0
            end
        end
        if count > 0 then
            -- Save the remaining batch to the database
            PersistentDB:SetStructuredData(PDB_STORAGE_KEY .. string.upper(endpointName) .. "_" .. batch_num, batch)
            PersistentDB:SetStructuredData(PDB_INDEX_KEY .. string.upper(endpointName) .. batch_num, {first = first, last = last})
            indices[batch_num] = {first = first, last = last}
        end
        -- Update the last save time in the persistent database
        local update_time = sessionTimer -- var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        PersistentDB:SetInt(PDB_LAST_SAVE_KEY .. string.upper(endpointName), update_time)
        return indices, update_time
    end

    --- Loads the GE prices from the PersistentDB into memory.
    --- @param endpointName string the name of the endpoint for which prices are being loaded.
    --- @return table<integer, {first: integer, last: integer}> indices loaded indices for tracking batches.
    --- @return integer lastUpdateTime the last time the prices were updated in the persistent database.
    local loadPrices = function(endpointName)
        local indices = {}
        local batch_num = 0
        while true do
            local batch = PersistentDB:GetStructuredData(PDB_STORAGE_KEY .. string.upper(endpointName) .. "_" .. batch_num)
            local index = PersistentDB:GetStructuredData(PDB_INDEX_KEY .. string.upper(endpointName) .. "_" .. batch_num)
            if not batch then break end
            for _, entry in ipairs(batch) do
                local id = entry.id
                if not PriceResult.data[tostring(id)] then
                    PriceResult.data[tostring(id)] = {}
                end
                PriceResult.data[tostring(id)][endpointName] = entry.item
            end
            indices[batch_num] = index
            batch_num = batch_num + 1
        end
        local lastUpdateTime = PersistentDB:GetInt(PDB_LAST_SAVE_KEY .. string.upper(endpointName))
        return indices, lastUpdateTime
    end

    --- Handles the HTTP response for GE price requests.
    ---@param req any the HTTP request object containing the response data and status.
    local requestHandler = function(req)
        local segments = {}
        for segment in string.gmatch(req.url, "[^/]+") do table.insert(segments, segment) end
        local tableName = endpoints[segments[#segments]]

        IsFetching[tableName] = false
        if req.successful then
            local data = Json.safe_decode(req.data)["data"]
            PriceResult.indices[tableName], PriceResult.lastUpdateTime[tableName] = insertPrices(tableName, data)
            IsReady[tableName] = true
        elseif req.timedOut then
            log(req.url, "request timed out")
        elseif req.failed then
            log(req.url, "request failed, error code =", req.errorCode)
        end
    end    

    --- Adds the query parameters to the endpoint URL.
    ---@param endpoint string the base URL of the endpoint to which query parameters will be added.
    ---@param args table|nil the query parameters to be added to the endpoint URL.
    ---@return string endpoint the endpoint URL with the query parameters appended.
    local combineEndpoint = function(endpoint, args)
        if args then
            local query = {}
            for k, v in pairs(args) do
                table.insert(query, k .. "=" .. tostring(v))
            end
            if #query > 0 then
                endpoint = endpoint .. "?" .. table.concat(query, "&")
            end
        end
        return endpoint
    end

    --- Fetches the latest GE prices from the server if the plugin has the required HTTP access permission. Updates the fetching state and handles the HTTP request.
    ---@param endpointName string the name of the endpoint to fetch prices for.
    ---@param args table|nil optional query parameters for the request, typically used for timeseries requests.
    ---@param successCb function|nil a callback function to handle the response data, typically for timeseries requests.
    ---@param errorCb function|nil a callback function to handle any errors that occur during the request.
    local fetchPrices = function(endpointName, args, successCb, errorCb)
        local lookup = {
            ["latest"] = LATEST_ENDPOINT,
            ["fiveMinute"] = FIVE_MINUTES_ENDPOINT,
            ["oneHour"] = ONE_HOUR_ENDPOINT,
            ["timeseries"] = TIMESERIES_ENDPOINT
        }
        if Plugin.HasPermission(PluginPermissions.httpAccess) then
            IsFetching[endpointName] = true
            local req = HTTPRequest.new(Plugin.urls.prices, combineEndpoint(lookup[endpointName], args))
            req:AddHeader("User-Agent", "ge-prices-library/1.0")
            if successCb then
                local callbackWrapper = function(req)
                    IsFetching[endpointName] = false
                    if req.successful then
                        -- log(req.url, "request successful")
                        -- log("ID:", args["id"], "Time:", sessionTimer) -- var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value)
                        local data = Json.safe_decode(req.data)["data"]
                        if not PriceResult.data[endpointName] then PriceResult.data[endpointName] = {} end
                        if not PriceResult.data[endpointName][args["id"]] then PriceResult.data[endpointName][args["id"]] = {} end

                        PriceResult.data[endpointName][args["id"]][args["lookback"]] = {
                            data = data,
                            savedTime = sessionTimer -- var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
                        }
                        successCb(data)
                        IsReady[endpointName] = true
                    elseif req.timedOut then
                        log(req.url, "request timed out")
                        if errorCb then errorCb("request timed out") end
                    elseif req.failed then
                        log(req.url, "request failed, error code =", req.errorCode)
                        if errorCb then errorCb("request failed, error code =" .. req.errorCode) end
                    end
                end
                req:Get(callbackWrapper)
            else
                req:Get(requestHandler)
            end
        else
            log("Missing required permission: httpAccess")
        end
    end

    --- Gets the GE prices. First checking the cache in the PersistentDB and then fetching from prices.runescape.wiki. The data is loaded into PriceResult and the readiness state is updated.
    local getPrices = function()
        for key, endpointName in pairs(endpoints) do
            local curTimer = sessionTimer -- var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
            local lastSave = PersistentDB:GetInt(PDB_LAST_SAVE_KEY .. string.upper(endpointName))
            if lastSave and math.abs(curTimer - lastSave) <= CACHE_PERIOD[endpointName] then
                -- Extract data from PersistentDB
                PriceResult.indices[endpointName], PriceResult.lastUpdateTime[endpointName] = loadPrices(endpointName)
                IsReady[endpointName] = true
            elseif endpointName ~= "timeseries" then
                fetchPrices(endpointName)
            end
        end
    end

    --- Checks if the cache period has expired and then fetches the prices from prices.runescape.wiki.
    ---@return boolean cacheExpired Returns true if the cache expired, the prices will then be fetched.
    local updateDatabase = function(endpointName)
        if not ({ ["latest"] = true, ["5m"] = true, ["1h"] = true })[endpointName] then error("Invalid endpoint name: " .. tostring(endpointName)) end
        
        local curTimer = sessionTimer -- var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        local lastSave = PriceResult.lastUpdateTime[endpointName]
        if lastSave and math.abs(curTimer - lastSave) <= CACHE_PERIOD[endpointName] then return false end
        -- Set lastUpdateTime now to prevent further iterations from initiating multiple fetches while the fetch is running.
        -- Check IsFetching as a safety percaution.
        PriceResult.lastUpdateTime[endpointName] = sessionTimer -- var.VarPlayer.CLOCK_TIME_DATE_MINUTES.value
        if not IsFetching[endpointName] then fetchPrices(endpointName) end
        return true
    end

    -- Initialize the GE prices by either loading from the cache or fetching from the server.
    getPrices()

    return {
        --- Checks if the cache period has expired and then fetches the prices from prices.runescape.wiki.
        --- @return boolean cacheExpired Returns true if the cache expired, the prices will then be fetched.
        updateDatabase = updateDatabase,

        --- DEPRECATED: Use getLatest(itemId : number) instead. Will be phased out in future versions.
        --- Gets the latest trade for a specific item ID from the loaded GE prices. Subject to a five minute cache.
        --- @param itemId number The ID of the item to get the price for.
        --- @return Item item The price data for the specified item ID.
        --- @throw Invalid itemId resulting in the item not being able to be found.
        getPrice = function(itemId)
            if PriceResult and PriceResult.data and PriceResult.data[tostring(itemId)] then
                if not IsFetching["latest"] then updateDatabase("latest") end
                return Private.ReadOnly(PriceResult.data[tostring(itemId)].latest)
            else
                error("Price not found for itemId: " .. tostring(itemId))
            end
        end,
        
        --- Gets the latest trade for a specific item ID from the loaded GE prices. Subject to a five minute cache.
        --- @param itemId number The ID of the item to get the price for.
        --- @return Item item The price data for the specified item ID.
        --- @throw Invalid itemId resulting in the item not being able to be found.
        getLatest = function(itemId)
            if PriceResult and PriceResult.data and PriceResult.data[tostring(itemId)] then
                if not IsFetching["latest"] then updateDatabase("latest") end
                return Private.ReadOnly(PriceResult.data[tostring(itemId)].latest)
            else
                error("Price not found for itemId: " .. tostring(itemId))
            end
        end,
        
        --- Gets the five minute average for a specific item ID from the loaded GE prices.
        --- @param itemId number The ID of the item to get the price for.
        --- @return Item item The price data for the specified item ID.
        --- @throw Invalid itemId resulting in the item not being able to be found.
        getFiveMinuteAverage = function(itemId)
            if PriceResult and PriceResult.data and PriceResult.data[tostring(itemId)] then
                if not IsFetching["5m"] then updateDatabase("fiveMinute") end
                return Private.ReadOnly(PriceResult.data[tostring(itemId)].fiveMinute)
            else
                error("Price not found for itemId: " .. tostring(itemId))
            end
        end,
        
        --- Gets the hourly average for a specific item ID from the loaded GE prices.
        --- @param itemId number The ID of the item to get the price for.
        --- @return Item item The price data for the specified item ID.
        --- @throw Invalid itemId resulting in the item not being able to be found.
        getOneHourAverage = function(itemId)
            if PriceResult and PriceResult.data and PriceResult.data[tostring(itemId)] then
                if not IsFetching["1h"] then updateDatabase("oneHour") end
                return Private.ReadOnly(PriceResult.data[tostring(itemId)].oneHour)
            else
                error("Price not found for itemId: " .. tostring(itemId))
            end
        end,

        --- Asynchronously gets the current timeseries for the specified lookback period for the currently loaded GE item.
        --- A lookback period specifies the duration for which the timeseries data should be fetched.
        --- A callback function is required to handle the fetched timeseries data as this is an asynchronous operation.
        --- @param lookback any The lookback period for the timeseries. { '6h' | '24h' | '7d' | '30d' | '6m' | '1y' }
        --- @param successCb function The function to call once the timeseries data is fetched. Should take the fetched timeseries data as an argument.
        --- @param errorCb function The function to call if an error occurs during the timeseries data fetch. Should take the error message as an argument.
        --- @return boolean success True if the timeseries data fetch was initiated successfully, false otherwise.
        getCurrentTimeseries = function(lookback, successCb, errorCb)
            local loadedSprite = ui.Interfaces:GetComponent(id.Interface.STOCKMARKET, 154)
            if not loadedSprite.visibleGlobal or loadedSprite.associatedObjectID == -1 then error("Grand Exchange Buy/Sell window is not loaded.") end
            if not IsFetching["timeseries"] then
                if ({ "6h", "24h", "7d", "30d", "6m", "1y" })[lookback] then
                    fetchPrices("timeseries", { id = loadedSprite.associatedObjectID, lookback = lookback }, successCb, errorCb)
                else
                    error("Invalid lookback period: " .. tostring(lookback))
                end
            else
                error("Timeseries data fetch is already in progress.")
            end

            return true
        end,

        --- Checks if the GE price service is ready per endpoint. Defaults to "latest" if not supplied.
        --- @param endpointName "latest" | "5m" | "1h" | "timeseries" The endpoint name to check readiness for. Defaults to "latest" if not supplied.
        --- @return boolean IsReady true if the service is ready, false otherwise.
        isReady = function(endpointName)
            if not endpointName then return IsReady["latest"] end
            if not ({ ["latest"] = true, ["5m"] = true, ["1h"] = true, ["timeseries"] = true })[endpointName] then error("Invalid endpoint name: " .. tostring(endpointName)) end
            return IsReady[endpointName]
        end,

        --- Checks if the GE price service is fetching for a specific table. The service can still be ready while fetching with previous data.
        --- @param endpointName "latest" | "5m" | "1h" | "timeseries" The endpoint name to check fetching status for.
        --- @return boolean IsFetching true if the service is fetching, false otherwise.
        isFetching = function(endpointName)
            if not endpointName then return IsFetching["latest"] end
            if not ({ ["latest"] = true, ["5m"] = true, ["1h"] = true, ["timeseries"] = true })[endpointName] then error("Invalid endpoint name: " .. tostring(endpointName)) end
            return IsFetching[endpointName]
        end
    }
end

--- Subscribes to ServerLogic to track the session time for caching purposes.
Event.ServerLogic.Subscribe("TickClock", function()
    sessionTimer = sessionTimer + 1
end)

return PriceService