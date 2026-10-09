local Private = {}

Private.ReadOnly = function(obj, cache)
    -- Cache prevents creating multiple proxies for the same table
    cache = cache or setmetatable({}, { __mode = "k" })

    if type(obj) ~= "table" then
        return obj
    end

    if cache[obj] then
        return cache[obj]
    end

    local proxy = setmetatable({}, {
        __index = function(t, key)
            local val = obj[key]
            -- Automatically wrap nested tables when they are accessed
            return Private.ReadOnly(val, cache)
        end,

        __newindex = function(t, key, value)
            error("Security Error: Attempt to modify a read-only library object.", 2)
        end,

        -- Blocks rawset, rawget, and metatable tampering
        __pairs = function()
            local function stateless_iter(tbl, k)
                local next_k, next_v = next(obj, k)
                if next_k ~= nil then
                    return next_k, Private.ReadOnly(next_v, cache)
                end
            end
            return stateless_iter, nil, nil
        end,

        __ipairs = function()
            local function stateless_iter(tbl, i)
                i = i + 1
                local v = obj[i]
                if v ~= nil then
                    return i, Private.ReadOnly(v, cache)
                end
            end
            return stateless_iter, nil, 0
        end,

        __metatable = "Protected Meta"
    })

    cache[obj] = proxy
    return proxy
end

setmetatable(Private, { __call = function(_, obj) return Private.ReadOnly(obj) end })

return Private