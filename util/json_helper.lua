-- Disclaimer: AI Generated, hope to replace with the native client implementation when that is included.
-- Generic JSON decoding helper for parsing JSON strings into Lua tables.

local M = {}

local function parse(json_str)
  if type(json_str) ~= "string" then
    return nil, "input is not a string"
  end

  local s = json_str
  local i = 1
  local len = #s

  local function peek()
    return s:sub(i, i)
  end

  local function next_char()
    local c = s:sub(i, i)
    i = i + 1
    return c
  end

  local function skip_ws()
    while i <= len do
      local c = s:sub(i, i)
      if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
        i = i + 1
      else
        break
      end
    end
  end

  local function parse_string()
    local quote = next_char() -- consume '"'
    if quote ~= '"' then return nil, "expected '\"'" end
    local chars = {}
    while i <= len do
      local c = next_char()
      if c == '"' then
        return table.concat(chars), nil
      end
      if c == '\\' then
        local esc = next_char()
        if esc == '"' or esc == '\\' or esc == '/' then
          chars[#chars+1] = esc
        elseif esc == 'b' then chars[#chars+1] = '\b'
        elseif esc == 'f' then chars[#chars+1] = '\f'
        elseif esc == 'n' then chars[#chars+1] = '\n'
        elseif esc == 'r' then chars[#chars+1] = '\r'
        elseif esc == 't' then chars[#chars+1] = '\t'
        elseif esc == 'u' then
          local hex = s:sub(i, i+3)
          if #hex < 4 or not hex:match("%x%x%x%x") then
            return nil, "invalid unicode escape"
          end
          i = i + 4
          local code = tonumber(hex, 16)
          if code then
            if utf8 and utf8.char then
              chars[#chars+1] = utf8.char(code)
            else
              if code <= 0xFF then
                chars[#chars+1] = string.char(code)
              else
                chars[#chars+1] = '?'
              end
            end
          else
            return nil, "invalid unicode code"
          end
        else
          return nil, "invalid escape char"
        end
      else
        chars[#chars+1] = c
      end
    end
    return nil, "unterminated string"
  end

  local function parse_number()
    local start = i
    local c = peek()
    if c == '-' then i = i + 1; c = peek() end
    if c >= '0' and c <= '9' then
      if c == '0' then i = i + 1
      else
        while peek():match('%d') do i = i + 1 end
      end
    else
      return nil, "invalid number"
    end
    if peek() == '.' then
      i = i + 1
      if not peek():match('%d') then return nil, "invalid fractional number" end
      while peek():match('%d') do i = i + 1 end
    end
    local e = peek()
    if e == 'e' or e == 'E' then
      i = i + 1
      local sign = peek()
      if sign == '+' or sign == '-' then i = i + 1 end
      if not peek():match('%d') then return nil, "invalid exponent" end
      while peek():match('%d') do i = i + 1 end
    end
    local numstr = s:sub(start, i-1)
    local n = tonumber(numstr)
    if not n then return nil, "invalid number conversion" end
    return n, nil
  end

  local function parse_value()
    skip_ws()
    local c = peek()
    if c == '{' then
      return (function()
        next_char() -- consume '{'
        skip_ws()
        local obj = {}
        if peek() == '}' then next_char(); return obj, nil end
        while true do
          skip_ws()
          if peek() ~= '"' then return nil, "object keys must be strings" end
          local key, err = parse_string()
          if not key then return nil, err end
          skip_ws()
          if next_char() ~= ':' then return nil, "expected ':' after key" end
          local val, err = parse_value()
          if err then return nil, err end
          obj[key] = val
          skip_ws()
          local ch = next_char()
          if ch == '}' then break end
          if ch ~= ',' then return nil, "expected ',' or '}' in object" end
        end
        return obj, nil
      end)()
    elseif c == '[' then
      return (function()
        next_char() -- consume '['
        skip_ws()
        local arr = {}
        if peek() == ']' then next_char(); return arr, nil end
        local idx = 1
        while true do
          local val, err = parse_value()
          if err then return nil, err end
          arr[idx] = val; idx = idx + 1
          skip_ws()
          local ch = next_char()
          if ch == ']' then break end
          if ch ~= ',' then return nil, "expected ',' or ']' in array" end
          skip_ws()
        end
        return arr, nil
      end)()
    elseif c == '"' then
      return parse_string()
    elseif c == '-' or c:match('%d') then
      return parse_number()
    else
      -- literals: true, false, null
      local rem = s:sub(i, i+4)
      if s:sub(i, i+3) == 'true' then i = i + 4; return true, nil end
      if s:sub(i, i+4) == 'false' then i = i + 5; return false, nil end
      if s:sub(i, i+3) == 'null' then i = i + 4; return nil, nil end
      return nil, "invalid value"
    end
  end

  local result, err = parse_value()
  if err then return nil, err end
  skip_ws()
  if i <= len then
    return nil, "trailing characters"
  end
  return result, nil
end

-- Decode a JSON string. Returns (value, nil) on success or (nil, error_message) on failure.
function M.decode(json_str)
  if not json_str or json_str == "" then
    return nil, "empty json string"
  end
  return parse(json_str)
end

-- Parse JSON, returning `default` when decode fails.
function M.parse(json_str, default)
  local v, err = M.decode(json_str)
  if not v then
    return default, err
  end
  return v, nil
end

-- Safe decode that returns an empty table on error.
function M.safe_decode(json_str)
  local v = M.parse(json_str, {})
  return v
end

return M
