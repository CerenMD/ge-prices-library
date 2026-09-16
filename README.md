# GE Price Library - GEPL

The GE Price Library is a shared plugin library to access the [RS3 Wiki Prices API](https://prices.runescape.wiki/). This reduces the load of requests by sharing it across the client.

The goal is for this to be a temporary and that Jagex will create a solution within the client API that can serve this purpose better.

## Installation
Add the GEPL to your required dependencies in order to start using, then refer to the [Usage](#Usage) documentation regarding the available methods.

```json 
//plugin.json
{
    ...,
    "requiredDependencies": [ "gepl" ],
    ...
}
```

## Usage
### **updateDatabase**
`function gepl.updateDatabase() -> Bool`
> **Checks if the cache period has expired and then fetches the prices from prices.runescape.wiki.**

#### Return
`cacheExpired : boolean` Returns true if the cache expired, the prices will then be fetched.

### **getPrice**
`function gepl.getPrice(itemId : int) -> Item`
> **Gets the price for a specific item ID from the loaded GE prices.**

#### Params
`itemId : number` The ID of the item to get the price for.

#### Return
`item : Item` The price data for the specified item ID.

#### Important
An invalid itemId will result in an error being thrown. If you are not sure if the itemId is valid, be prepared for an error via `pcall()` or other methods.

### **isReady**
`function gepl.isReady() -> Bool`
> **Checks if the GE price service is ready.**

#### Return
`IsReady : boolean` True if the service is ready, false otherwise.

### **isFetching**
`function gepl.isFetching() -> Bool`
> **Checks if the GE price service is fetching. The service can still be ready while fetching with previous data.**

#### Return
`IsFetching : boolean` True if the service is fetching, false otherwise.

## Credits
Written by Ceren with help from TheJoshJ, Cook and Sudo Bash.

The structure was inspired by the [RuneLite WikiPriceService](https://github.com/runelite/api.runelite.net/blob/e9c4abce52bc4a7ed8847750a10855324c29362d/http-service/src/main/java/net/runelite/http/service/wiki/WikiPriceService.java) although adapted for the limited environment we have.