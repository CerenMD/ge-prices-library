# GE Price Library - GEPL

The GE Price Library is a shared plugin library to access the [RS3 Wiki Prices API](https://prices.runescape.wiki/). This reduces the load of requests by sharing it across the client.

The goal is for this to be a temporary and that Jagex will create a solution within the client API that can serve this purpose better.

## Installation
Add the GEPL to your required dependencies in order to start using, then refer to the Methods and Type Definitions documentation.

```json 
//plugin.json
{
    ...,
    "requiredDependencies": { "gepl": 6414886 },
    ...
}
```

## Methods
### **getLatest**
`function gepl.getLatest(itemId : int) -> Latest`

Gets the latest price for a specific item ID from the loaded GE prices.

*Runescape Wiki API endpoint: `/api/v2/rs/latest`*

#### Params
`itemId : number` The ID of the item to get the price for.

#### Return
`latest : Latest` The price data for the specified item ID.

#### Important
An invalid itemId will result in an error being thrown. If you are not sure if the itemId is valid, be prepared for an error via `pcall()` or other methods.

#### Example
```lua
-- Retrieves the latest trade data for chronotes and prints the high and low price.
local chronotesLatestTrade = gepl.getLatest(49430)
print("High:", chronotesLatestTrade.high, "Low:", chronotesLatestTrade.low)
```

### **getFiveMinuteAverage**
`function gepl.getFiveMinuteAverage(itemId : int) -> Average`

Gets the five minute average price for a specific item ID from the loaded GE prices.

*Runescape Wiki API endpoint: `/api/v2/rs/5m`*

#### Params
`itemId : number` The ID of the item to get the price for.

#### Return
`average : Average` The average price data for the specified item ID.

#### Important
An invalid itemId will result in an error being thrown. The contents of an average can also be nil if corresponding trades were not made in the five minutes prior to the last cache.

#### Example
```lua
-- Retrieves the five minute average trade data for chronotes and prints the high average and low average price.
local chronotesFiveMinuteAverage = gepl.getFiveMinuteAverage(49430)
print("High Average:", chronotesFiveMinuteAverage.avgHighPrice, "Low Average:", chronotesFiveMinuteAverage.avgLowPrice)
```

### **getOneHourAverage**
`function gepl.getOneHourAverage(itemId : int) -> Average`

Gets the on hour average price for a specific item ID from the loaded GE prices.

*Runescape Wiki API endpoint: `/api/v2/rs/1h`*

#### Params
`itemId : number` The ID of the item to get the price for.

#### Return
`average : Average` The average price data for the specified item ID.

#### Important
An invalid itemId will result in an error being thrown. The contents of an average can also be nil if corresponding trades were not made in the one hour prior to the last cache.

#### Example
```lua
-- Retrieves the one hour average trade data for chronotes and prints the high average and low average price.
local chronotesOneHourAverage = gepl.getOneHourAverage(49430)
print("High Average:", chronotesOneHourAverage.avgHighPrice, "Low Average:", chronotesOneHourAverage.avgLowPrice)
```

### **getCurrentTimeseries** (async)
`function gepl.getCurrentTimeseries(lookback : string, success : function, error : function) -> boolean`

Gets the timeseries price data for the currently opened item in the Grand Exchange. The Buy/Sell interface must be visible and the item selected. Then this method can be used to make an asynchronous request for the timeseries data. The lookback period corresponds the valid lookback values accepted by the Runescape Wiki API timeseries endpoint.

*Runescape Wiki API endpoint: `/api/v2/rs/timeseries`*

#### Params
`lookback : '6h'|'24h'|'7d'|'30d'|'6m'|'1y'` The period for the range of the timeseries.

`success : function(data : table)` The callback function which is called when the fetch is succesful with the data provided as a parameter.

`error : function(errorMessage : string)` The callback function which is called when the fetch fails with the error message provided as a paramter.

#### Return
`fetching : boolean` Returns true if the fetch request is initiated, otherwise an error is thrown.

#### Example
```lua
-- Retrieves the six hour timeseries data for the currently selected item in the Grand Exchange buy/sell interface.
gepl.getCurrentTimeseries(
    "6h",
    function(data)
        print("Fetched timeseries data for 6h lookback:", tostring(data))
    end,
    function(err)
        print("Error message:", err)
    end
)
```

### DEPRECATED - **getPrice**
`function gepl.getPrice(itemId : int) -> Item`

This is an alias for `gepl.getLatest(itemId)`. This will be deprecated in an upcoming verison, use getLatest instead.

#### Params
`itemId : number` The ID of the item to get the price for.

#### Return
`item : Item` The price data for the specified item ID.

#### Important
An invalid itemId will result in an error being thrown. If you are not sure if the itemId is valid, be prepared for an error via `pcall()` or other methods.

#### Example
```lua
-- Retrieves the latest trade data for chronotes and prints the high and low price, using the getPrice alias.
local chronotesLatestTrade = gepl.getPrice(49430) --DEPRECATED: use -> gepl.getLatest(49430)
print("High:", chronotesLatestTrade.high, "Low:", chronotesLatestTrade.low)
```

### **updateDatabase**
`function gepl.updateDatabase(endpointName : string) -> Bool`

Checks if the cache period has expired and then fetches the prices from the corresponding prices.runescape.wiki endpoint.

#### Params
`endpointName : 'latest'|'5m'|'1h'` The corresponding endpoint name to fetch.

#### Return
`cacheExpired : boolean` Returns true if the cache expired, the prices will then be fetched.

### **isReady**
`function gepl.isReady(endpointName : string) -> Bool`

Checks if the GE price service is ready.

#### Params
`endpointName : 'latest'|'5m'|'1h'|'timeseries'` The corresponding endpoint name to check if it is ready.

#### Return
`IsReady : boolean` True if the service is ready, false otherwise.

### **isFetching**
`function gepl.isFetching(endpointName : string) -> Bool`

Checks if the GE price service is fetching. The service can still be ready while fetching with previous data.

#### Params
`endpointName : 'latest'|'5m'|'1h'|'timeseries'` The corresponding endpoint name to check if it is fetching.

#### Return
`IsFetching : boolean` True if the service is fetching, false otherwise.

## Type Definitions
Below are the type definitions for the objects returned by the library methods.
```
class Latest
    high : number               The last instant buy price for the item.
    highTime : integer          The timestamp for the last instant buy.
    low : number                The last instant sell price for the item.
    lowTime : integer           The timestamp for the last instant sell.
```

```
class Average
    avgHighPrice : number       The average price of instant buy offers fulfilled over the time period.
    highPriceVolume : integer   The number of items instantly bought over the time period.
    avgLowPrice : number        The average price of instant sell offers fulfilled over the time period.
    lowPriceVolume : integer    The number of items instantly sold over the time period.
```

```
class TimeSeries
    itemId : integer            The itemId for the fetched timeseries.
    startTimestamp : integer    The starting timestamp for the lookback period.
    endTimestamp : integer      The ending timestamp for the lookback period.
    timestep : integer          The period between data records.
    data : table<TimedAverage>  The data for the timeseries.
```

```
class TimedAverage
    timestamp : integer         The timestamp for the average, used in timeseries.
    avgHighPrice : number       The average price of instant buy offers fulfilled over the time period.
    highPriceVolume : integer   The number of items instantly bought over the time period.
    avgLowPrice : number        The average price of instant sell offers fulfilled over the time period.
    lowPriceVolume : integer    The number of items instantly sold over the time period.
```

## Credits
Plugin by Ceren with help from TheJoshJ, CookMePlox and Sudo Bash.

The structure was inspired by the [RuneLite WikiPriceService](https://github.com/runelite/api.runelite.net/blob/e9c4abce52bc4a7ed8847750a10855324c29362d/http-service/src/main/java/net/runelite/http/service/wiki/WikiPriceService.java) although adapted for the limited environment we have and expanded to align with the Runescape Wiki Prices API endpoints.