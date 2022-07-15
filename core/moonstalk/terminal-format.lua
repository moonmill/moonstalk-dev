local tostring = tostring
local formatter = {}

function formatter:__tostring()
    return self.value
end

function formatter:__concat(other)
    return tostring(self) .. tostring(other)
end

function formatter:__call(string)
	if not string then return self.value end
    return self .. string .. default
end

formatter.__metatable = {}

local function define(value)
    return setmetatable({ value = value }, formatter)
end

local formats = {
    -- attributes
    default = "\27[0m",
    bold = "\27[1m",
    dim = "\27[2m",
    underscore = "\27[4m",
    blink = "\27[5m",
    reverse = "\27[7m",

    erroneous = "\27[1;31m",

    -- foreground
    black = "\27[30m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m",

    -- background
    onblack = "\27[40m",
    onred = "\27[41m",
    ongreen = "\27[42m",
    onyellow = "\27[43m",
    onblue = "\27[44m",
    onmagenta = "\27[45m",
    oncyan = "\27[46m",
    onwhite = "\27[47m",

    -- behaviours
    overwrite = "\27[2K\27[200D", -- this is an assumption, if the last string is longer it won't be properly erased
}

local this = getfenv()
for format,meta in pairs(formats) do
    this[format] = define(meta)
end
--setmetatable({},prior) -- TODO
