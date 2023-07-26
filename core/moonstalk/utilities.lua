--[[	Moonstalk Utilities
		Generic utility functions
--]]
module ("util", package.seeall)

local string_gsub = string.gsub
local string_sub = string.sub
local string_match = string.match
local string_find = string.find
local string_gmatch = string.gmatch
local table_insert = table.insert
local string_format = string.format
local tostring = tostring

-- TODO: some of these should be moved to kit as they change the environment significantly, others that are core to scribe functionality should be moved to scribe functions, or toolkit

_G.time = {
	second = 1,
	minute = 60,
	hour = 3600,
	day = 86400,
	week = 604800,
	month = 2419200, -- lunar
	year = 29030400, -- lunar
}


-- # Proxy tables
-- create an empty table traversable with arbitrary namespaces and then return the namespace
--[[ two modes of use, either introspective, or via call call handler, if no call handler is provided proxy.consume is used
myproxy = proxy() or proxy("myproxy") or proxy("myproxy", HandlerFunc) or proxy(HandlerFunc)
an anonymous proxy has no root path, whereas a named proxy includes the name as the root of the namespace
if no HandlerFunc is provided, a call to the proxy returns its namespace using proxy.consume; when provided that function may call proxy.consume() to acquire the namespace from which it was called or (more efficiently) simple consume proxy.namespace
introspection consumption: proxyname = proxy(); ns = proxyname.namespace; if ns._proxy then ns = proxy.consume(ns) end; if a proxy is an expected argument introspection may not be necessary and proxy.consume could be called unconditionally
--]]
-- WARNING: do not attempt to log, output or serialise a proxy, as it will cause an overflow due to recursion
_G.proxy = {namespace=false}
do local proxy = _G.proxy
function proxy.traverse (parent,name)
	-- uses the global proxy.table to track recursion amnd always returns the same proxy table as the child for further recusion; using the global is not an issue in async environments as yields never occur during construction
	if parent._traverse then proxy.namespace = {parent._root} end -- first invocation upon a proxy root, must therefore reset the global to collect a new namespace, starting with the root (if any)
	table_insert(proxy.namespace, name or "NIL") -- collect the child name
	return root
end
local util_NamespaceString = util.NamespaceString
function proxy.consume(asTable)
	-- proxy.consume() for a string or proxy.consume(true) for an array table
	if not asTable then return proxy.namespace end
	return util_NamespaceString(proxy.namespace)
end
function proxy.set(...)
	-- root,handler,metatable; all optional in any order
	-- handler is a function invoked if the proxy namespace is called; the function may itself call proxy.consume() if desired
	local root,handler,metatable
	local args = {...}
	for i=1,select("#",...) do
		local val_type = type(args[i])
		if val_type == "function" then handler = args[i]
		elseif val_type == "table" then
			metatable = args[i]
			metatable.__index = metatable.__index or proxy.traverse
		elseif val_type == "string" then root = args[i]
		end
	end
	local proxy_table = {
		_root = root, -- optional as may be anonymous
		_traverse = { -- this is the table used for traversal
			_proxy = true, -- allows introspection
		}
	}
	util.ChangeMetatable(proxy_table._traverse, {__index=proxy.traverse, __call=handler or proxy.consume})
	util.ChangeMetatable(proxy_table, metatable or {__index=proxy.traverse})
	return proxy_table
end
end
setmetatable(proxy,{__call=proxy.set}) -- allows proxy "foo" | foo = proxy(...)


-- ## Web functions
_G.web = _G.web or {}

web.html_allowed = {
	-- named tag sets may be declared from any application as web.html_allowed = {"tagname",…, tagname={"attributename"}, strip={"tagname",…},…}}; they are normalised by the generic Enabler
	default = {
		"ul","ol","li","h1","h2","h3","h4","br","p","b","i","em","strong","img","hr","table","td","tr","strike","q","blockquote","center","small", -- these are allowed tags but their attributes are removed
		a={"href"}, -- these have the specified attributes preserved
		strip={"head","style","script"},}, -- these and their content are removed
	none = { -- none are allowed, and many have their content stripped
		strip={"table","center","small","ul","ol","head","style","script"}},
	text = {"b","i","em","p","time",a={"href"}},
}
function web.TextFromHTML(value,allowed)
	allowed = web.html_allowed[allowed or "text"]
	-- a faster variation of SanitiseHTML generally for use with TruncatePunctuated and should be proviuded with a substring (longer than used for TruncatePunctuated to allow for remove of tags and content) to further speed it up; removes all tags, but preserves content for only the tags given in allowed, removing all other tag content
	-- first find tags with content and remove just the tags if allowed, else tags and their content
	value = string_gsub(value,"</?([^ >]+).->(.-)</%1>",function(tag,content) if allowed[tag] then return content or "" end return "" end)
	-- finally remove tags without content
	return string_gsub(value,"<.->","")
end
function web.SanitiseHTML(value,allowed)
	-- removes non-conforming tags and optionally, their content
	-- WARNING: do not use on plain text as strings such as <email@address> will be removed; these should previously have been normalised and encoded for use in HTML
	-- TODO: only allow close tags if opened
	allowed = web.html_allowed[allowed or "default"]
	for _,tag in ipairs(allowed.strip) do
		-- this is a little expensive especially on larger values and assumes the tags are never nested
		local offset = string_find(value,"<"..tag,1,true)
		if offset then
			local _,offset_end = string_find(value,"</"..tag,offset,true)
			value = string_sub(value, 1, offset -1) .. string_sub(value, offset_end +2)
		end
	end
	value = string_gsub(value,"<([^ >]+)(.-)>", function(tag,attributes)
		if allowed.attributes[tag] then
			return "<"..tag .. string_gsub(attributes,[[%s*([^=]+)(=".-")]], function(name,value)
				local replace = ""
				if allowed.attributes[tag][name] then replace = replace.." "..name..value end
				return replace
			end) .. ">"
		else return allowed[tag] or "" end
	end)
	return value
end
function web.StripHTML(value, allowed)
	-- removes all html tags and the content of those specified
	-- WARNING: do not use on plain text as strings such as <email@address> will be removed
	allowed = web.html_allowed[allowed or "default"]
	for _,tag in ipairs(allowed.strip) do
		local offset = string_find(value,"<"..tag,1,true)
		if offset then
			local _,offset_end = string_find(value,"</"..tag,offset,true)
			value = string_sub(value, 1, offset -1) .. string_sub(value, offset_end +2)
		end
	end
	return string_gsub(value,"<.->","")
end
function web.RemoveURLs(value)
	-- NOTE: doesn't match simple domains as is best to normalise these at time of creation
	return string_gsub(value,"https?://[^ ]+","")
end
function web.IsHTML(value)
	-- looks for a matching tag, which isn't of course guarenteed
	-- won't catch <email@addresses> in plain text
	-- may be used to construct values, e.g. my_html = web.IsHTML(value) or "<html>"..value.."</html>"
	if string_match(value,"<(.-)>.-</%1>") then return value end
end
function web.NotHTML(value)
	-- looks for a matching tag, which isn't of course guarenteed
	-- won't catch <email@addresses> in plain text
	-- may be used to construct values, e.g. my_text = web.NotHTML(value) or web.StripHTML(value)
	if not string_match(value,"<(.-)>.-</%1>") then return value end
end


function web.SafeHtml (text) -- TODO:
	-- sanitises user-input for output in HTML, to prevent XSS hijack
	-- strips all non-allowed tags and attributes
	if not text then return end
	return string_gsub(text,".",terms.htmlsafe_encode)
end
function web.SafeText (text)
	-- sanitises user-input for output in HTML, to prevent XSS hijack
	-- converts all tags to text
	if not text then return end
	return string_gsub(text,".",terms.htmlsafe_encode)
end
function web.SafeAttr (text)
	-- check for safety of text when used as an html tag attribute inside quotes e.g. <tag attribute="value">
	-- does not sanitise but instead returns nil if unsafe
	if not string_find( text, "[<>\'\"]" ) then return text end
end
function web.UrlEncode (text)
	-- this handles both standard HTTP query format (ampersand delimited) and Moonstalk format (comma delimited)
	-- NOTE: may not be suitable for requests to non-Moonstalk applications; definately not suitable for non-URL use
	if not text then return end
	return string_gsub( text, ".", {
		[' ']="%20",
		['\"']="%22",
		['\'']="%27",
		[',']="%2C",
		['.']="%2Z", -- Moonstalk specific behaviour; should be %2E but many browsers automatically decode this back to a period in the URL!
		['&']="%26",
		['=']="%3D",
		['%']="%25",
		['#']="%23",
		['?']="%3F",
		})
end
function web.UrlDecode (text)
	-- this is only to be used for queries originating from a Moonstalk app itself, as it does not handle the full possible sequence of encoded values
	-- TODO: test %%%d%w for speed, and also compare with full urldecode function
	if not text then return end
	text = string_gsub( text, [[(%%[23][270C6D53FZ])]], {
		["%20"]=" ",
		["%22"]="\"",
		["%27"]="\'",
		["%2C"]=",",
		["%2Z"]=".",
		["%2E"]=".",
		["%26"]="&",
		["%3D"]="=",
		["%25"]="%",
		["%23"]="#",
		["%3F"]="?",
		})
		return text
end

-- TODO: test the difference between these functions
function web.UrlEncodeFull(str)
	if not str then return end
	str = string_gsub (str, "\n", "\r\n")
	str = string_gsub (str, "([^%w ])",
		function (c) return string_format ("%%%02X", string.byte(c)) end)
	return str
end
function web.UrlDecodeFull(str)
	if not str then return end
	str = string_gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
	str = string_gsub (str, "\r\n", "\n")
	return str
end

function web.SafeHref(url)
	-- see also util.DisplayUri and web.DisplayHref
	return string_gsub(url,".",terms.urlsafe_encode)
end
function web.DisplayHref(url)
	-- same as SafeHref but also replaces spaces with dash; useful in localised names used as links
	-- see also util.DisplayUri and web.SafeHref
	return string_gsub(url,".",terms.urldisplay_encode)
end
function web.LinkTag(url,maxlength,returnvalue)
	-- takes a url and returns a tag for it with a display value comprising at least the domain, truncating the path if longer than maxlength; if returnvalue=true does not render the link only returning the display value
	-- if maxlength==0 only the domain is shown and always without an elipsis
	if not url then return end
	maxlength = maxlength or 32
	if string_sub(url,1,4) ~="http" then url = "http://"..url end
	local display = string_match(url,"://(.+)/?")
	if string_sub(display,1,4) =="www." then display = string_sub(display,5) end
	local first,second,more
	display,first,second,more = string_match(display,"^([^/]+)/?([^/]*)/?([^/]*)/?(.?)")
	if maxlength>0 then
		if first~="" and #display >maxlength or #first +#display >maxlength then
			display = display.."/…"
		elseif first~="" then
			display = display.."/"..first
			if second~="" and #second +#display >maxlength then
				display = display .. "/…"
			elseif second~="" then
				display = display.."/"..second
				if more~="" then display = display .. "/…" end
			end
		end
	end
	if returnvalue then return display end
	return [[<a href="]]..url..[[">]]..display..[[</a>]]
end

-- # format functions format values for output in a human consumable format (e.g. using locales)
-- TODO: we need better seperation between plain string output and HTML output; currently these functions output a mix of both
 _G.format = {}
do
	local placeholders = {WWW="wday",WW="wday",W="wday",MMM="month",MM="month",M="month"} -- this allow us to cross-reference between the placholders and their initial values from the date table
	function format.ReferenceDate(datetime,formatting,toggle)
		-- same as format.Date, but accepts a reftime (not a date table) and preserves it as UTC without converting it to the site's localtime
		return format.Date(os.date("*t",datetime),formatting,toggle)
	end
	function format.Date(datetime,formatting,toggle)
		-- general purpose date formatter
		-- format may be either a named format, a format string, or omitted to use the default "numeric" format
		-- if a format is specified and toggle is omitted, dates are output as relative, i.e. if the date is within one week, weekday is shown amd year omitted, else weekday and year are omitted, except beyond 9 months, when the year is included; toggle may be be specified as "weekday", "year" or "complete" to include one or both of these unconditionally in the returned string; the "numeric" format always includes year and never weekday
		-- datetime should be either a date table (e.g. the result of calling localtime() or a reftime which will be converted to localtime using the site's timezone (this behaviour should differ client-side where we can convert a reftime to the user's actual localtime, but which we may not reliably know server-side, especially as a user's location can change dynamically)
		-- by default weekday and year are output conditional on age (i.e. the date is relative)
		-- format names follow, with an example of their format string and output:
	--[[
		"numeric" = "d|/m|/yy" -- default
		"long" = "WWW, |ddd MMM| yy" | Monday, 9th July 2012
		"short" = "WW |ddd MM| yy" | Mon. 9th July 2012
		"abbreviated" = "WW |d M.|'y" | Mon. 9 Jul.'12
		"mini" = "W d M| y" | Mo 9 Dec 12
	--]]
		-- NOTE: if no punctuation is used to seperate fields, or its placement is ambigious (notably to the left of the field), use of the vertical bar character is required to delimit the conditional weekday and year fields in a string; where there is punctuation preceeding or following (per the placement of the vertical bar) and the field was optionally removed (i.e. for weekday and year) its punctuation will also be removed; use of hair spaces is preferred instead of plain spaces
	--[[ format strings may be constructed using the follow placeholder names:
		-- day of month
		d = 9
		dd = 09
		ddd = 9th -- with ordinals or punctuation (per the locale)
		-- weekday name
		W = Mo -- abbreviated; typically two letters (length conforms per-locale)
		WW = Mon. -- short; typically three letters with punctuation (length varies per-locale)
		WWW = Monday -- long
		-- month of year
		m = 8
		mm = 08
		-- month name
		M = Jul -- abbreviated; typically three letters (length	 may conform per-locale)
		MM = July | Aug. -- short; typically three letters with punctuation, or complete name if short (length varies per-locale)
		MMM = December -- long
		-- year
		y = 12
		yy = 2012
	--]]
		-- TDOD: this function needs to invoke a date-format specific compiled function (from server.lua/Initialise) instead of parsing the string on each call to (expensively) handle every possible interpretation

		local timestamp
		if not datetime then
			return
		elseif type(datetime) =="table" then
			timestamp = os.time(datetime)
		else
			timestamp = datetime
			datetime = localtime(datetime, site.timezone or locales[site.locale].timezone)
		end
		formatting = formatting or "numeric"
		if formatting =="numeric" or toggle =="year" or (toggle ==nil and timestamp <now-864000) then -- not displayed beyond 10 days
			datetime.W = false
			datetime.WW = false
			datetime.WWW = false
		end
		local current = os.date("*t",now)
		if formatting =="numeric" or toggle =="year" or toggle =="complete" or datetime.year ~= current.year then -- not displayed if the same year -- TODO: we should have some scope either side of now (e.g. 2 weeks) to avoid ambiguity in case we're around the end of the year
			datetime.y = string_sub(datetime.year,3,4)
			datetime.yy = datetime.year
		else
			datetime.y = false
			datetime.yy = false
		end
		datetime.d = datetime.day
		if datetime.d < 10 then
			datetime.dd = "0"..datetime.d
		else
			datetime.dd = datetime.d
		end
		datetime.ddd = table.concat{datetime.d,"<sup>",l.OrdinalDayHTML(datetime.d),"</sup>"}
		datetime.m = datetime.month
		if datetime.m < 10 then
			datetime.mm = "0"..datetime.m
		else
			datetime.mm = datetime.m
		end
		if formatting ~="numeric" and datetime.month==current.month and toggle ~="month" and toggle ~="complete" then
			datetime.M = false
			datetime.MM = false
			datetime.MMM = false
		end
		for pre,placeholder,post in string_gmatch(locale.date[formatting] or terms.dates[formatting] or formatting, "([^dDmMyW]*)([dDmMyW]+)([^dDmMyW|]*)|*") do
			if datetime[placeholder] ~=false then
				table_insert(datetime, pre) -- we reuse the table, but only it's array part
				table_insert(datetime, datetime[placeholder] or l[placeholder][datetime[placeholders[placeholder]]])
				table_insert(datetime, post)
			end
		end
		return table.concat(datetime)
	end
end

function format.ReferenceTime(datetime,formatting)
	-- same as format.Time, but accepts a reftime (not a date table) and preserves it as UTC without converting it to the site's localtime
	return format.Time(os.date("*t",datetime),formatting)
end
function format.Time(datetime,formatting)
	-- general purpose time formatter
	-- format is optional and will use the current locale's time format if not specified
	-- see format.Date for handling of timezone; also see format.ReferenceTime()
	--[[ the following placeholders may be used in the format string interspered with any other required delimiters:
	?(hour12)	= 9 | [l.noon | l.midnight] | 2 -- note that in the case of noon/midnight, the formatting string is replaced by the translated term entirely
	?(Hour12)	= 9 | 12 | 2
	?(hour)		= 9 | 12 | 14
	?(Hour)		= 09 | 12 | 14
	?(min)		= [0 is not displayed] | 07 | 23
	?(Min)		= 00 | 07 | 23
	?(ampm)		=  a.m. | p.m.
	--]]
	-- TODO: the use of Moonstalk macro placeholders is ugly, unclear, and should be refactored in a manner similar to format.Date
	if not datetime then
		return
	elseif type(datetime) ~="table" then
		datetime = localtime(datetime, site.timezone or locales[site.locale].timezone)
	end
	if datetime.hour ==12 and datetime.min ==0 and string_find(formatting,"hour12",1,true) then
		return l.noon
	elseif datetime.hour ==0 and datetime.min ==0 and string_find(formatting,"hour12",1,true) then
		return l.midnight
	elseif datetime.hour <12 then
		datetime.ampm = " a.m."
		datetime.Hour = "0"..datetime.hour
		datetime.hour12 = datetime.hour
		datetime.Hour12 = datetime.hour
	elseif datetime.hour >=12 then
		datetime.ampm = " p.m."
		datetime.Hour = datetime.hour
		datetime.hour12 = datetime.hour -12
		datetime.Hour12 = datetime.hour -12
	else
		datetime.ampm = " p.m."
		datetime.Hour = datetime.hour
		datetime.hour12 = datetime.hour
		datetime.Hour12 = datetime.hour
	end
	if datetime.min ==0 then
		datetime.Min = "00"
		datetime.min = ""
	elseif datetime.min < 10 then
		datetime.Min = "0"..datetime.min
	else
		datetime.Min = datetime.min
	end
	formatting = formatting or string_gsub(locale.time, "%?%((.-)%)", datetime)
	if not request.client.timezone and site.timezone and moonstalk.timezones[site.timezone] ~= uselocale.timezone then formatting = formatting.." "..(uselocale.timezone.abbr or uselocale.timezone.offset) end
	return formatting
end

function format.Number(number,places,nlocale)
	-- accepts a string or number
	-- if places is not specified and decimals are 00 they are removed
	-- NOTE: places==0 truncates decimals leaving the major unit unchanged, you may want to use util.Round or util.RoundTo instead
	-- TODO: check for a locale number formatter function
	if not number then return end
	nlocale = nlocale or locale
	local thousands,decimals
	if places==0 then
		thousands = string_match( string_format("%.1f",number), "%d+" ) -- we add a decimal to avoid rounding
	else
		thousands,decimals = string_match( string_format("%."..(places or 2).."f",number), "(%d+)%.(%d+)" )
		if places==nil and tonumber(decimals)==0 then decimals = nil end
	end
	local formatted = {}
	if tonumber(number) < 0 then
		table_insert(formatted, "−") -- Unicode
	end
	if #thousands > 3 then
		if #thousands > 6 then -- TODO: handle locale e.g. every two digits in India
			table_insert(formatted, string_sub(thousands,1,-7))
			table_insert(formatted, locale.digitgroup_utf) -- Unicode
			table_insert(formatted, string_sub(thousands,-6,-4))
		else
			table_insert(formatted, string_sub(thousands,1,-4))
		end
		table_insert(formatted, locale.digitgroup_utf) -- Unicode
		table_insert(formatted, string_sub(thousands,-3))
	else
		table_insert(formatted, thousands)
	end
	if decimals then
		table_insert(formatted, locale.decimal) -- Unicode
		table_insert(formatted, decimals)
	end
	return table.concat(formatted)
end

function format.Money(...)
	-- same as html.Money but without the HTML; does not use currency code
	local arg = {...}
	local number = arg[1]
	local places,nlocale,ulocale
	if type(arg[2])=='number' then
		places = arg[2]
		nlocale = arg[3]
		ulocale = arg[4]
	else
		nlocale = arg[2]
		ulocale = arg[3]
	end
	if not number then return "n/a" end
	nlocale = locales[nlocale] or locales.currencies[nlocale] or nlocale or locales[site.locale]
	if number <1 and number >0 then
		number = util.GetDecimals(number) -- we're rendering minor units so leading zeros are not important
		if #number ==1 then number = number.."0" end -- add trailing zero for numbers scuh as 0.50 -- TODO: this assumes 100-base currency
		return number..nlocale.symbolminor
	end
	number = util.Decimalise(number,2)
	local formatted = {}
	if not nlocale.symbol_r then table_insert(formatted, nlocale.symbol) end
	table_insert(formatted, format.Number(number,0,ulocale))
	local decimals = util.GetDecimals(number,places)
	if (places and places ~=0) or tonumber(decimals) ~=0 then
		table_insert(formatted, nlocale.decimal_utf) -- FIXME: should be ulocale
		table_insert(formatted, decimals)
	end
	if nlocale.symbol_r then
		table_insert(formatted, nlocale.symbol)
	end
	return table.concat(formatted)
end

_G.html = _G.html or {}
function html.Money(...)
	-- number[,places][,currency-locale],[user-locale][,microformats]
	-- wraps format.Number to provide number formatting as currency, but implements own decimal handling; the number formatting respects the user's locale, unless ulocale is also provided
	-- the places parameter may be omitted e.g. Money(number,currency-locale) to only show decimals if not 0; else specified as 0 to cut off decimals unless the value is <1
	-- the currency locale may be a currency code, locale table, locale id or nil for the current site's locale
	-- adds microformats and microdata attributes unless last parameter is false
	local arg = {...}
	local microformats
	if arg[#arg] == false then
		arg[#arg] = nil
		microformats = false
	end
	local number = arg[1]
	local places,nlocale,ulocale
	if type(arg[2])=='number' then
		places = arg[2]
		nlocale = arg[3]
		ulocale = arg[4]
	else
		nlocale = arg[2]
		ulocale = arg[3]
	end
	-- will use microdata and microform syntax
	if not number then return "n/a" end
	nlocale = locales[nlocale] or locales.currencies[nlocale] or nlocale or locales[site.locale]
	number = util.Decimalise(number,2)
	local formatted = {}
	table_insert(formatted, [[<abbr title="]])
	table_insert(formatted, nlocale.currency_code)
	table_insert(formatted, [[ ]])
	table_insert(formatted, number)
	if microformats ~=false then
		table_insert(formatted, [[" itemprop="price" class="price"><meta itemprop="priceCurrency" content="]])
		table_insert(formatted, nlocale.currency_code)
	end
	table_insert(formatted, [["/>]])
	if arg[1] >=1 or arg[1] ==0 then
		if not nlocale.symbol_r then
			table_insert(formatted, [[<sup>]])
			table_insert(formatted, nlocale.symbol)
			table_insert(formatted, [[</sup>]])
		end
		table_insert(formatted, format.Number(number,0,ulocale))
		local decimals
		if places ~=0 or not places then decimals = util.GetDecimals(number,places) end
		if decimals and tonumber(decimals) ~=0 then
			table_insert(formatted, [[<sup>]])
			table_insert(formatted, nlocale.decimal_utf) -- FIXME: should be ulocale
			table_insert(formatted, decimals)
			table_insert(formatted, [[</sup>]])
		end
		if nlocale.symbol_r then
			table_insert(formatted, [[<sup>]])
			table_insert(formatted, nlocale.symbol)
			table_insert(formatted, [[</sup>]])
		end
	else
		number = util.GetDecimals(number,places)
		if tonumber(number) <10 then number = string_sub(number,2) end
		table_insert(formatted, number)
		table_insert(formatted, nlocale.symbolminor) -- TODO: this assumes right positioning for all locales
	end
	table_insert(formatted, [[</abbr>]])
	return table.concat(formatted)
end

function format.TelPrefix (number)
	-- changes the prefix of a number if the visitor is not in the same country
	-- leaves the rest of the number formatted as is
	if not number then return end
	local sitelocale = locales[site.locale]
	if request.client.locale ==site.locale then -- visitor is in same locale
		if string_sub(number,1,1)=="+" then -- number is + format, so strip prefix
			number = (sitelocale.trunkprefix or "0")..string_sub(number,#sitelocale.e164+2)
		end
	else -- visitor is from another locale
		if string_sub(number,1,1)~="+" then
			local trim = 1
			if string_sub(number,1,#(sitelocale.trunkprefix or "0")) == (sitelocale.trunkprefix or "0") then trim = trim + #(sitelocale.trunkprefix or "0") end
			number = "+"..sitelocale.e164.." "..string_sub(number,trim)
		end
	end
	return number -- site may format its numbers any way it wants
end

function format.url(url,args)
	-- only for URLs to Moonstalk apps
	local append = "?" -- assume unprepared url
	if string_sub(url,-1) == "?" then -- already prepared
		url = string_sub(url,1,-2) -- normalise by removing
	elseif string_find(url,"?",1,true) then -- contains existing query
		append = "," -- change to sperarator
	end
	url = {url,append} -- construct table with url and seperator
	if string_sub(url[1],5,5) ~= ":" then table_insert(url,1,"http://") end
	-- the following is kit specific
	if #args then -- preserve array of items (indices are not preserved)
		for _,v in ipairs(args) do
			table_insert(url,util.urlencode(v))
			table_insert(url,",")
		end
	end
	--
	for k,v in pairs(args) do -- add pairs if any
		table_insert(url,k)
		table_insert(url,"=")
		table_insert(url,util.urlencode(v))
		table_insert(url,",")
	end
	table.remove(url,#url) -- remove final terminator
	return table.concat(url) -- return url string
end


-- # Utilitiy functions

function ChangeMetatable(object,append)
	local metatable = getmetatable(object) or {}
	for key,value in pairs(append) do metatable[key]=value end
	setmetatable(object,metatable)
end

function Empty(object)
	if object==nil or object=="" or (type(object)=="table" and not next(object)) then return true else return end
end
_G.empty = Empty

Plurals = {} -- https://developer.mozilla.org/en/Localization_and_Plurals
-- these are used by the _G.plural function in the scribe
-- TODO: this could be extended with a string flag that includes digit punctuation
Plurals[0] = function (forms) -- Asiann (Chinese, Japanese, Korean, Vietnamese), Persian, Turkic/Altaic (Turkish), Thai, Lao
	return forms -- forms should be a simple string when translated for this rule NOT an array
end
Plurals[1] = function (forms,number) -- Germanic (Danish, Dutch, English, Faroese, Frisian, German, Norwegian, Swedish), Finno-Ugric (Estonian, Finnish, Hungarian), Language isolate (Basque), Latin/Greek (Greek), Semitic (Hebrew), Romanic (Italian, Portuguese, Spanish, Catalan)
	number = number or 2
	if number ==1 then
		return forms[1]
	else
		return forms[2]
	end
end
Plurals[2] = function (forms,number) -- Romanic (French, Brazilian Portuguese)
	number = number or 2
	if number ==0 or number ==1 then
		return forms[1]
	else
		return forms[2]
	end
end
Plurals[3] = function (forms,number) -- Baltic (Latvian)
	number = number or 999 -- CHECK: indefinite
	if number ==0 then
		return forms[1]
	elseif number ==1 or (number ~=11 and string_sub(number,-1) =="1") then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[4] = function (forms,number) -- Celtic (Scottish Gaelic)
	number = number or 999 -- CHECK: indefinite
	if number ==1 or number ==11 then
		return forms[1]
	elseif number ==2 or number ==12 then
		return forms[2]
	elseif number ~=0 and number <20 then
		return forms[3]
	else
		return forms[4]
	end
end
Plurals[5] = function (forms,number) -- Romanic (Romanian)
	number = number or 999 -- CHECK: indefinite
	if number ==1 then
		return forms[1]
	elseif number <20 or tonumber(string_sub(number,-2)) <20 then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[6] = function (forms,number) -- Baltic (Lithuanian)
	number = number or 999 -- CHECK: indefinite
	if number ==1 or (number >20 and string_sub(number,-1) =="1") then
		return forms[1]
	elseif number ==0 or number <21 or string_sub(number,-1) =="0" or tonumber(string_sub(number,-2)) <21 then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[7] = function (forms,number) -- Slavic (Bosnian, Croatian, Serbian, Russian, Ukrainian)
	number = number or 999 -- CHECK: indefinite
	if number ==1 or (number >20 and string_sub(number,-1) =="1") then
		return forms[1]
	elseif number <5 or (number >20 and tonumber(string_sub(number,-1)) <5) then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[8] = function (forms,number) -- Slavic (Slovak, Czech)
	number = number or 999 -- CHECK: indefinite
	if number ==1 then
		return forms[1]
	elseif number <5 then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[9] = function (forms,number) -- Slavic (Polish)
	number = number or 999 -- CHECK: indefinite
	if number ==1 then
		return forms[1]
	elseif (number ~=0 and number <5) or (number >21 and tonumber(string_sub(number,-1)) <5) then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[10] = function (forms,number) -- Slavic (Slovenian, Sorbian)
	number = number or 999 -- CHECK: indefinite
	if number ==1 or (number >100 and string_sub(number,-2) =="01") then
		return forms[1]
	elseif number ==2 or (number >101 and string_sub(number,-2) =="02") then
		return forms[2]
	elseif number ==3 or number ==4 or (number >101 and (string_sub(number,-2) =="03" or string_sub(number,-2) =="04")) then
		return forms[3]
	else
		return forms[4]
	end
end
Plurals[11] = function (forms,number) -- Celtic (Irish Gaeilge)
	number = number or 999 -- CHECK: indefinite
	if number ==1 then
		return forms[1]
	elseif number ==2 then
		return forms[2]
	elseif number >2 and number <7 then
		return forms[3]
	elseif number >6 and number <11 then
		return forms[4]
	else
		return forms[5]
	end
end
Plurals[12] = function (forms,number) -- Semitic (Arabic)
	number = number or 999 -- CHECK: indefinite
	if number ==0 then
		return forms[6]
	elseif number ==1 then
		return forms[1]
	elseif number ==2 then
		return forms[2]
	elseif number <11 or (number >102 and tonumber(string_sub(number,-2)) <11) then
		return forms[3]
	elseif number <100 or (number >110 and tonumber(string_sub(number,-2)) <100) then
		return forms[4]
	else
		return forms[5]
	end
end
Plurals[13] = function (forms,number) -- Semitic (Maltese)
	number = number or 999 -- CHECK: indefinite
	if number ==1 then
		return forms[1]
	elseif number ==0 or number <11 or (number >100 and tonumber(string_sub(number,-2)) <11) then
		return forms[2]
	elseif number <20 or (number >110 and tonumber(string_sub(number,-2)) <20) then
		return forms[3]
	else
		return forms[4]
	end
end
Plurals[14] = function (forms,number) -- Slavic (Macedonian)
	number = number or 3 -- CHECK: indefinite
	if number ==1 or string_sub(number,-1) =="1" then
		return forms[1]
	elseif number ==2 or string_sub(number,-1) =="2" then
		return forms[2]
	else
		return forms[3]
	end
end
Plurals[15] = function (forms,number) -- Icelandic
	number = number or 2 -- CHECK: indefinite
	if number ==1 or (number ~=11 and string_sub(number,-1) =="1") then
		return forms[1]
	else
		return forms[2]
	end
end

function Random(array)
	return array[math.random(#array)]
end
_G.random = Random

function Wrap(a,b,c,d)
	-- conditional concatenator of 2–4 arguments the last of which must always be present but the prior can be optional; typically used in the form wrap("prepend",conditional_value,"append") such as to insert an html tag with it's content if present e.g. wrap("<p>",content_value,"</p>"); the fourth argument may be used as a terminator e.g. ?(wrap(firstname," ",lastname,", "))
	-- NOTE: does not handle 3 arguments where the 3rd is conditional, use WrapIf
	if a and b and not c and not d then return a..b
	elseif a and b and c then return table.concat{a or "", b or "", c or "", d or ""} end
end
_G.wrap = Wrap
function WrapIf(a,b,c,d)
	-- per wrap but only if the 4th argument (d) is truthy, else returns only the second argument (b)
	if not d then return b
	elseif not a or not b then return end
	return table.concat{a or "", b or "", c or ""}
end
_G.wrapif = WrapIf


function Keyed(a,b,c)
	-- keyed {table} or keyed("key", "value", {table}) or keyed "alphabet-string" or keyed{key-value}
	-- general purpose for configs; not optimised
	-- modifies either an array table into a hashmap supporting indexed lookups of its values without iteration (at the expense of additional memory use for the hashmap pointers) or inverts a hashmap so that values can also be looked up for their names (must not contain an array)
	-- when passed only a string, returns a table with every char set in that string as a key and also having an array part with the char at its original string position e.g. keyed"abc" becomes {"a","b","c";a=true,b=true,c=true}
	-- a 'keyed' table may thus be used with ipairs to get each item as per the original table, but also with a table[value] lookup to check if a value exists; generally used for configuration tables
	-- for an array of strings the key is the value, and its value is its position, thus {"wibble","wobble"}, is converted to {"wibble","wobble", wibble=1,wobble=2} allowing both use as if table.wibble then or enumerated
	-- for an array of subtables the keys are dervived from either the specified key name or the "value" key, and the value will be either the specified key name or will poit to the subtable itself; thus {{id="one",value="One"},{id="two",value="Two"}} would become {{id="one",value="One"},{id="two",value="Two"},one=One,two=Two} or without a value key specified {{id="one",value="One"},{id="two",value="Two"},one={id="one",value="One"},two={id="two",value="Two"}}
	-- if only an array of tables is provided with no key and value parameters, the new table is index by either a value subkey, or the index position]
	if not a then return
	elseif not b and type(a) =='string' then -- special case, conversion of charstring into table with each char keyed
		local keyed = {}
		local char
		for position=1,#a do
			char = string_sub(a,position,position)
			keyed[#keyed+1] = char
			keyed[char] = true
		end
		return keyed
	elseif not b and a[1] and type(a[1]) ~='table' then -- keyed{"enum1","enum2"} simple enumeration, maps the array value to its position {enum1=1,enum2=2}
		for i,value in ipairs(a) do a[value] = i end
		return a
	end
	local keyed = a; if c then keyed = c elseif b then keyed = b end
	if not b and not keyed[1] then -- keyed{key=value,…} inverts to add value=key
		for k,v in pairs(keyed) do keyed[v]=k end
	elseif not b and type(keyed[1])=='table' and keyed[1].value then -- keyed{{value=key},…} keys subtables by their value
		for _,item in ipairs(keyed) do keyed[item.value] = item end
	elseif b then -- keyed("key",{{key=value},…}) keys subtables by the given key (instead of value above)
		for _,item in ipairs(keyed) do keyed[item[a]] = item end
	elseif c then -- keyed("key","value",{{key=value,value=123},…}) keyes subtable values with the given key
		for _,item in ipairs(keyed) do keyed[item[a]] = item[b] end
	end -- NOTE: we used to support mixed-mode tables with both subtables and enum values
	return keyed
end
_G.keyed = Keyed

function Options(table)
	-- converts an array of table members to an enumerated table, the array may be specified in any order; each member is indexed in the enumerated table by its "value" (enumerated position number) having the value of its name or label, it is also indexed by its name or label with its value with the value; additionally the full tables are available with the same indexes from an 'options' subtable, and an 'ordered' subtable preserves the original order for ipairs iterations
	-- options named 'ordered' or 'options' are not valid because they represent internal tables
	-- the value/label syntax is compatible with the kit application tag.select function
	-- member = {value=n, name="string", label="string", wibble=wobble}
	-- table[member.value] = member.name
	-- table.options[member.name or member.value] = member
	table.ordered = table.ordered or {} -- preserve if re-indexing
	local count = #table
	for i=1,count do
		table.ordered[i] = table[i]
		table[i] = nil
	end
	table.options = table.options or {}
	for i,member in ipairs(table.ordered) do
		table[member.value or i] = member.name or member.label
		table[member.name or member.label] = member.value or i
		table.options[member.value or i] = member
		table.options[member.name or member.label] = member
	end
	return table
end
_G.options =Options

function _G.ifthen(test, true_value, false_value)
	-- convenience handler giving the functionality of a ternary operator, for return or output of values based upon conditions(s) e.g. "checked" for a radio button ?(ifthen(request.form.radio==1,"checked"))
	-- NOTE: this routine is more expensive than a simple if statement, however it is more compact for in-line use; both the true and false values are evaluated irrespective of the condition, thus cannot themselves be conditional
	-- NOTE: in scribe views, this function is automatically expanded as an in-line if statement thus has no penality there, and only the value matching the condition is evalulated -- TODO:
	if test then return true_value else return false_value end
end

function Varkey (value)
	-- provides a safe way to specify keys for teller queries
	-- e.g.: fetch ("database"..varkey(variable)..".subkey")
	-- also handles digits compatibility
	if not value then return end
	if type(value) =="number" then
		return "["..digits(value).."]"
	else
		if string_find(value,[=[[%[%]"]]=]) then return nil,"path contains illegal characters" end
		return '["'..value..'"]'
	end
end
_G.varkey = Varkey

function Copy(outof,a,b,c,_depth)
	-- copies the contents of one table to another (fully recursive), but by default does not replace values
	-- copy(table,recurse) returns a deep copy by default preserving the metatable
	-- copy(from,to,replace,recurse) performs a deep copy without replacing(!)
	-- deep copies ensure all tables are unique, a shallow copy means table are shared having the same pointers; if recurse is false performs a simple (more efficient) assignment of root values from one table to the other; if replace is false or nil, value will only be copied if not existing; if recurse is true and replace is nil (the defaults) subtable keys will be copied across; false value are preserved
	-- recursion is limited to 4 levels
	-- performs best if outof has fewer keys than into
	-- use append() to copy only array values
	-- WARNING: not safe with arrays except in the root with replace=true -- TODO: add array detection and replace?
	local into,replace,recurse
	if b ==nil and (a == nil or a == true or a == false) then
		if a ==false then recurse=false else recurse=true end
		into = {}
		local mt = getmetatable(outof)
		if mt then setmetatable(into,mt) end
	else
		into = a or {}
		replace = b -- default: don't replace
		recurse = c if recurse==nil then recurse=true end -- default: recurse
	end
	if not into or not outof then
		return
	elseif recurse then
		local vtype
		for k,v in pairs(outof) do
			vtype = type(v)
			if vtype ~='table' and (replace or into[k] ==nil) then
				into[k] = v
			elseif vtype =='table' then
				_depth = (_depth or 0) +1
				if _depth >4 then return nil,'recursion too deep' end
				if type(into[k]) =='table' then
					copy(v,into[k],replace,true,_depth)
				elseif replace or into[k] ==nil then
					into[k] = copy(v,nil,nil,nil,_depth)
				end
				_depth = _depth -1
			end
		end
	elseif replace then
		-- shallow replace, all root values are replaced with pointers
		for k,v in pairs(outof) do into[k] = v end
	else
		-- shallow add, only new root values are added as pointers
		for k,v in pairs(outof) do
			into[k] = into[k] or v
		end
	end
	return into
end
_G.copy = Copy

function CopyFields(from,to,...)
	-- shallow copy, takes a list of fieldnames as parameters to copy from one table to another
	to = to or {}
	for _,key in ipairs({...}) do
		to[key] = from[key]
	end
	return to
end
function CopyFieldsIf(from,to,...)
	-- as CopyFields but preserves the to value if not present in from
	to = to or {}
	for _,key in ipairs({...}) do
		to[key] = from[key] or to[key]
	end
	return to
end

function Append(from,appendto)
	-- a general purpose array append function similar to copy() but optimised for a source array; from should be a complete array (no nils) but may be a table from which only the array part is to be copied; appendto may be any table to which the array values are appended
	-- append{to=table.ref; first_item, second_item, …}
	-- if to is omitted will return extract and return just the array part of the from table as a new table
	-- may be used to append a non-existant value as will be ignored, i.e. appendto will be return unchanged
	if not from or not from[1] then return appendto or from.to end
	appendto = appendto or from.to or {}
	local offset = #appendto
	for _,item in ipairs(from) do
		offset = offset + 1
		appendto[offset] = item
	end
	return appendto
end
_G.append = Append

function ArrayOfKeys(from,matching)
	-- returns an array of all keys, or only keys where its table value containsone of the given array of keys
	local array = {}
	local count = 0
	for key,value in pairs(from) do
		if not matching or util.AnyKeysExist(value,matching) then
			count = count +1
			array[count] = key
		end
	end
	return array
end

if table.clear then
	function Reuse (reuse,newvalues)
		-- empty and then repopulate a table with new values, preserving all its original pointers
		table.clear(reuse)
		for key,value in pairs(newvalues) do
			reuse[key] = value
		end
	end
else
	function Reuse (reuse,newvalues)
		-- empty and then repopulate a table with new values, preserving all its original pointers
		for key in pairs(reuse) do
			reuse[key] = nil
		end
		for key,value in pairs(newvalues) do
			reuse[key] = value
		end
	end
end

function MergeIf (defaults,merge)
	-- if merge is provided, copies defaults to it, else returns defaults unmodified
	-- ic a merge should not be modified pass it as a copy util.MergeIf(defdaults,copy(merge))
	-- useful for modifying a default table conditionally, e.g. table overrides may or may not exist
	if not merge then return defaults end
	for key,value in pairs(defaults) do
		merge[key] = merge[key] or value
	end
	return merge
end

function Concat(...) return table.concat({...}) end -- accepts values as parameters, returning them as a concatenated string; syntactically similar to .. operator but accepts and ignores nils
_G.concat = Concat

function Pack(...) return {...} end -- complements Lua's unpack; accepts a list of parameters (e.g. as returned by a function), and instead returns them as an array; can be used where it is not possible to use a table constructor, e.g. when calling a function such as string_match with multiple captures; -- NOTE: arg, the returned array, contains a key 'n' with a value for the count of the arguments, to properly iterate the result you must use for i=1,table.n as any of the arguments/values may be nil
_G.pack = Pack

function Split(input, delimiter, dounpack)
	-- returns an array unless dounpack=true
	-- WARNING: ignores the first item if it is an empty string i.e. starts with the delimiter
	local array = {}
	local count = 0
	if #delimiter ==1 then
		-- optimisation for handling single character delimiter
		for name in string_gmatch(input, "[^%"..delimiter.."]+") do
			count = count +1
			array[count] = name
		end
		if dounpack then return unpack(array) end
		return array
	end
	local fpat = "(.-)" .. delimiter
	local last_end = 1
	local s, e, cap = input:find(fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			count = count +1
			array[count] = cap
		end
		last_end = e+1
		s, e, cap = input:find(fpat, last_end)
	end
	if last_end <= #input then
		cap = input:sub(last_end)
		count = count +1
		array[count] = cap
	end
	if dounpack then return unpack(array) end
	return array
end
_G.split = Split

function Truncate (value,length)
	-- unlike string_sub, this acts on both strings and tables (recursively) returning a copy in which strings longer than length are truncated with […]
	length = length or 42
	if type(value) =="string" then
		if #value > length then return string_sub(value,1,length) .. "[…]" else return value end
	elseif type(value)=="table" then
		value = copy(value,false) -- replace with a shallow copy, as recursion will provide deep copy
		local truncate = truncate
		for key,subvalue in pairs(value) do
			value[key] = truncate(subvalue,length)
		end
		return value
	else -- we leave anything else as is
		return value
	end
end
_G.truncate = Truncate

function Slice(array,from,to)
	local slice = {}
	for i= from, to or #array, 1 do table_insert(slice,array[i]) end
	return slice
end

function Oneshot ()
	-- provides a one shot container, typically used as a LTN12 source
	return function (arg)
		if not contents then -- set
			local contents = arg or ""
		elseif contents then -- get
			local temp = contents
			contents = nil
			return temp
		else -- used and thus empty
			return nil
		end
	end
end
_G.oneshot = oneshot

function Digits(number)
	-- used for number coercion to strings; numbers are floats (loosing precision the larger they get) and tonumber() typically converts to exponential/scientific notation (loosing precision); this function converts all whole integers (not having decimals) between 0 and 16 digits (including negative values) to a string preserving their precision at this length; typically used for outputting Moonstalk's internal IDs although it is generally not recommended to expose these in pages and one should instead use EncodeID
	-- use GetDigits to extract digits irrespective of surrounding characters
	if not tonumber(number) then return number end -- not actually a number
	return string_format("%d",number)
	-- NOTE: use util.Decimals, %g or %.2f to preserve decimals and smaller numbers
	-- WARNING: Lua is built with double-precision only, therefore numbers larger than 1024727600999999 will loose precision *and* be converted to exponential notation regardless
	-- NOTE: rebuilding Lua with long support instead of double-precision floats would allow tonumber() to be used throughout; longer numbers should otherwise be preserved as strings at the slight additional costs of memory and coercion when comparisons are required
end
_G.digits = Digits

do
	-- a lines iterator handling both \r\n and \n
	local function next_line(state)
		local text, begin, line_n = state[1], state[2], state[3]
		if begin < 0 then return nil end
		state[3] = line_n + 1
		local b, e = string_find(text,"\n", begin, true)
		local line
		if b then
			state[2] = e+1
			line = string_sub(text, begin, e-1)
		else
			state[2] = -1
			line = string_sub(text, begin)
		end
		return line_n, line
	end
	function Lines(text)
		text = string_gsub(text,"\r\n","\n")
		return next_line, {text, 1, 1}
	end
	_G.lines = Lines
end

function GetDecimals (number)
	-- returns a string, as decimals maybe 00 or zer0-prefixed
	return string_match( number, "%.(%d+)$" )
end
function SplitDecimals (number,optional)
	-- does not return a value for decimals if ==0 and optional is true
	-- WARNING: uses default number coercion thus will not work with large numbers; these must be formatted as a string for use
	local major,minor = string_match( number, "(%d+)%.?(%d*)" )
	minor = minor or 0
	if optional and minor =="0" then return major end
	return tonumber(major),tonumber(minor)
end
function Decimalise(number,places)
	-- accepts a string or number
	-- returns string, defaulting to two places whilst ignoring "00"
	number = string_format("%."..(places or 2).."f",number)
	if not places and tonumber(string_match(number, "%.(%d+)" ))==0 then
		return string_sub(number,1,-4) -- without decimals as not present; only for default of two places
	end
	if as_number then return tonumber() end
	return number
end
function RoundDecimals(number,places)
	-- accepts string or number, and returns number, using default midpoint rounding of decimals longer than the specified places (default 2)
	return tonumber(string_format("%."..(places or 2).."f",number))
end
function IntoDecimals(number,units)
	-- returns from a decimal value, a number that is the value of the whole number multiplied into the decimal units
	-- e.g. 10.99 with units of 100 will return 1099
	-- typically units would be obtained from locale -- TODO: accept currency code instead of units
	units = units or 100
	if type(number)=='number' then number = string_format("%.2f",number) end
	local number,decimals = string_match( number, "^(%d+)%.?(%d*)" )
	return (number *units) +decimals or 0
end

_G.sys = sys or {}
function SysInfo()
	sys.platform = util.Shell("sysctl -n kernel.ostype") -- need to redirect err to stdin else throws error
	if sys.platform == "Linux" then
		sys.processors = tonumber(util.Shell("grep -c processor /proc/cpuinfo")) -- NOTE: may include hyperthreading if enabled
	else
		sys.platform = util.Shell("/usr/sbin/sysctl -n kern.ostype") -- OS X has a different key than linux!
		if sys.platform == "Darwin" then
			sys.processors = tonumber(util.Shell("/usr/sbin/sysctl -n hw.physicalcpu"))
		else
			log.Alert("Unsupported platform")
			sys.platform = nil
			return
		end
	end
	return true
end

function HttpDate(timestamp)
	if not timestamp then return end
	return os.date("!%a, %d %b %Y %T GMT",timestamp)
end

function Sync(path,table)
	-- if only file is specified, loads, compiles and returns lua values from the file
	-- slightly different than import and load as invokes a bundle error, thus is a blocking issue
	local file,result,err
	result,file,err = pcall(io.input,path)
	if not result then
		if string.find(err or file,"No such",1, true) then return nil end
		moonstalk.BundleError(moonstalk,{title=path.." has an error",detail=err or file}); return nil,err or file
	end
	if file then
		result,err = io.read("*a")
		io.close()
		if result then
			result,err = loadstring("return "..result)
			if result then result,err = result() end
		end
	end
	if not result then
		moonstalk.BundleError(moonstalk,{title=path.." has an error",detail=err})
	end
	return result,err
end

function FindPID(command)
	local running = util.Shell("ps -o pid= -o command= -A | grep '\\d*.*"..command.."' | grep -v -e grep -e elevator")
	if running then
		return tonumber(string_match(running,'%d+'))
	end
end

function SumRange(x,y)
	-- sums all whole numbers from x to y, or from 1 to x if y is not specified
	local from,to = x,y
	if not y then to = x from = 1 end
	local aggregate = 0
	for i=from,to do
		aggregate = aggregate + i
	end
	return aggregate
end

function SumFrom(t,key)
	-- total the values for all keys in a table (array or map), or in an array of tables for the given key
	local total = 0
	if key then
		for _,child in ipairs(t) do total = total + child[key] end
	elseif not t[1] then
		for _,val in pairs(t) do total = total + val end
	else
		for val in ipairs(t) do total = total + val end
	end
	return total
end

function RoundDown (x) if x >0 then return math.floor (x) else return 0 end end

function RoundTo (number,length,rounded) -- FIXME: broken and unclear functionality; needs to handle changing the last digit(s) to a specified sequence e.g. 173 to 175 | 26 to 25 | 130 to 129; strictly this should work with any length e.g. 132355 to 132300 perhaps using a percentage scope within which rounding occurs to the largest digit
	-- rounds to a specified sequence of values, the last digits (specified as length) of the number to the nearest value specified in rounded, an array of numbers (where the last number actually represents the first)
	-- decimals are discarded unless length is specified as "." then only the decimals are rounded
	local input,output
	if length =="." then
		input,number = string_match(number,"(.*%.)(%d%d)")
		input = input or "0"
		number = tonumber(number)
		length = 2
	else
		length = length or 2
		input = string_sub(string_match(number,"%d*"), 1, (length-length-length-1)) or ""
		number = tonumber(string_sub(number,(length-length-length)))
	end
	rounded = rounded or {0,25,50,75,100} -- proximity to the last number returns the first
	local last = rounded[1]
	local mid
	for _,val in pairs(rounded) do
		mid = val - ((val - last) / 2)
		if number <= mid then output = last break end
		last = val
	end
	output = output or rounded[1]
	return tonumber(input..util.Pad(output,length or 2))
end

function RoundDecimals(num,up) -- OPTIMISE: probably some way of doing this mathematically instead of using strings
	-- rounds decimals places, such as from a monetary calulation, down to the nearest two places; or up if specified as true
	-- for rounding to nearest (up or down) use Round() or RoundTo()
	-- returns an integer but also accepts strings
	local int,decimals = string_match(tostring(num),"(%d+)%.?(%d+)")
	if not decimals or #decimals<3 then return num end -- whole integer or already less than two places
	if not up then
		return tonumber(int.."."..string_sub(decimals,1,2))
	else
		up = string_sub(decimals,1,2)+1
		if up <100 then return tonumber(int.."."..up) end
		return int+1
	end
end

function Round(num, places)
	-- rounds to the nearest preceeding whole for the given number of decimals, default is none (i.e. returns a whole integer); -- NOTE: rounds up on .5 beyond the decimal places
	places = math.pow(10, places or 0)
	if num >= 0 then
		return math.floor(num*places + 0.5)/places
	else
		return math.ceil(num*places - 0.5)/places
	end
end

function Pad(value,to,with,right)
	-- takes a number or string; returns a string padded on the left, or right
	with = with or "0"
	value = tostring(value)
	local dif = to - #value
	if dif <1 then
		return value
	elseif not right then
		return string.rep(with,dif)..value
	else
		return value..string.rep(with,dif)
	end
end

function Upper(text)
	-- all uppercase
	-- TODO: proper unicode
	-- OPTIMIZE: just about okay for small strings not otherwise
	local string_sub = string.sub
	local result = {}
	local count = 1
	local last,first = 0,0
	text = string.upper(text)
	local transliteration_upper = terms.transliteration_upper
	local unicode
	for i=1,#text do
		unicode = string_sub(text, i, i +1)
		if transliteration_upper[unicode] then
			result[count] = string_sub(text,first,i -1)
			result[count+1] = transliteration_upper[unicode]
			first = i +2
			count = count +2
		end
	end
	result[count] = string_sub(text,first)
	return table.concat(result)
end
function Lower(text)
	-- TODO: proper unicode
	-- OPTIMIZE: just about okay for small strings not otherwise
	local string_sub = string.sub
	local result = {}
	local count = 1
	local last,first = 0,0
	text = string.lower(text)
	local transliteration_lower = terms.transliteration_lower
	local unicode
	for i=1,#text do
		unicode = string_sub(text, i, i +1)
		if transliteration_lower[unicode] then
			result[count] = string_sub(text,first,i -1)
			result[count+1] = transliteration_lower[unicode]
			first = i +2
			count = count +2
		end
	end
	result[count] = string_sub(text,first)
	return table.concat(result)
end

function Capitalise(text)
	-- first uppercase, rest preserved
	local first = string_sub(text,1,1)
	if string.byte(first) ==195 and terms.transliteration.utf8_codes[string_sub(text,1,2)] then
		-- matched a utf8 byte sequence
		return terms.transliteration.utf8_codes[string_sub(text,1,2)].utf8_upper..string_sub(text,3)
	else
		return string.upper(first)..string_sub(text,2)
	end
end
function Uncapitalise(text) -- TODO: support unicode
	-- first lowercase, rest preserved
	local first = string_sub(text,1,1)
	local byte = string.byte(first)
	if byte >90 or byte <65 then return text end -- already lower case, or some other char
	return string.lower(first)..string_sub(text,2)
end
function CapitaliseLower(text)
	-- first uppercase, rest lowercase
	return string.upper(string_sub(text,1,1))..string.lower(string_sub(text,2))
end
function TitleCase(str)
	-- makes titel case
	local function tchelper(first, rest) return first:upper()..rest:lower() end
	return string_gsub(str, [[(%a)([%w']*)]], tchelper)
end

function string.fromhex(text)
    return string.gsub(text,'..', function (cc)
        return string.char(tonumber(cc, 16))
    end)
end
function string.tohex(text)
    return string.gsub(text,'.', function (c)
        return string.format('%02X', string.byte(c))
    end)
end

function TableCount(table)
	-- counts keys in a table (i.e. same as #table on arrays)
	-- slow on large tales as must traverse the entire table
	local count = 0
	for _ in pairs(table) do count = count+1 end
	return count
end

function TableToText(keys,...)
	local arg = {...}
	local data = {}
	local prepend,append,delimit
	local count = 0
	if #arg == 1 then
		delimit = arg[1]
	else
		prepend = arg[1]
		append = arg[2]
		delimit = arg[3]
	end
	for key,value in pairs(keys) do
		table_insert(data,prepend)
		if #keys==0 then -- a dictionary
			table_insert(data,key)
		else -- an array
			table_insert(data,value)
		end
		table_insert(data,append)
		table_insert(data,delimit)
		count = count + 1
	end
	if delimit then table.remove(data,#data) end --remove last item, calling fucntion can terminate if not empty
	data = table.concat(data)
	if data == "" then data = nil end
	return data,count
end

function AppendToDelimited(value,to,delimiter)
	if not to then
		return value
	elseif not value then
		return to
	else
		return to..delimiter..value
	end
end

format.default={ -- readable multiline; use compact otherwise
	key_indent = "   ",
	key_open = "['",
	key_close = "']",
	key_match = "[\\']",
	key_gsub = {['\\']=[[\\]],['\'']=[[\']]},
	numberkey_open = "[",
	numberkey_close = "]",
	longstring_open = "[[",
	longstring_close = "]]",
	table_open = "{ ",
	table_close = "}",
	quote = "\"",
	equals = " = ",
	comma = ", ",
	['nil'] = "nil",
	['true'] = "true",
	['false'] = "false",
	linebreak = "\n",
	newline = "\n",
}
format.html_simple = {
	key_indent = "",
	key_open = "",
	key_close = "",
	numberkey_open = "<b>",
	numberkey_close = "</b>",
	longstring_open = "",
	longstring_close = "",
	table_open = "{ ",
	table_close = "}",
	quote = "\"",
	equals = "=",
	comma = ", ",
	['nil'] = "nil",
	['true'] = "<b>true</b>",
	['false'] = "<b>false</b>",
	linebreak = "",
	newline = "",
}
format.html = copy(format.html_simple); format.html.newline = "<br>"; format.html.table_open="{<blockquote>"; format.html.table_close="</blockquote>}"
format.root = copy(format.default); format.root.comma=""; format.root.table_open=""; format.root.table_close=""
format.compact = copy(format.default); format.compact.indent=""; format.compact.linebreak=""; format.compact.newline=""
format.rootcompact = copy(format.compact); format.root.table_open=""; format.root.table_close=""

do local type=type
do local _format = format.default
function Serialise (object,maxdepth,lines,depth)
	-- converts lua tables to serialised text; faster than SerialiseWith but not as fast as proper serialisation routines such as cjson and luabins; outputs a somewhat hard to read compressed format unless lines is true, when a new line is output for each to-level key, slightly aiding reading; userdata and functions are effectively ignored, however their keys will appear with a value of nil to aid identification
	-- safe to use for loading
	-- depth parameter is internal
	-- NOTE: values must never contain [=[ or ]=]
	-- WARNING: number keys must be integers; number values are serialised with 16 digit precision, with decimal precision depending upon the size of the integer; for other behaviours with number values you should coerce to strings as required before using this routine; in general you do not want to try storing or serialising float values that with arbitrarily long decimal precision such as 1/3, this routine should thus only be used with real-world numbers such as monetary values and coordinates having defined precision
	-- WARNING: keys with values being functions or userdata will be shown however their values will be nil as cannot be serialised, thus would not be preserved if latterly used with loadstring
	-- TODO: prevent recursion by keeping a list of all table references and if it appears more than once, return an error
	if lines then lines = "}\n" end
	depth = depth or 0
	depth = depth + 1
	maxdepth = maxdepth or 8 -- also defined below for warnings
	local serialised = {}
	local typed = type(object)
	if typed == 'string' then
		table_insert(serialised,"[=[")
		table_insert(serialised,object)
		if string_sub(object,-1,-1) == "]" then table_insert(serialised," ") end -- TODO: this is a hack to prevent trip close brackets which breaks loadstring, and should be removed when we move to a better datagram scheme
		table_insert(serialised,"]=]")
	elseif typed == 'number' then
		table_insert(serialised,string_format("%.16g",object))
	elseif typed == 'table' then
		if depth > maxdepth then return "{...}" end
		table_insert(serialised,"{")
		for key,value in pairs(object) do
			if lines then table_insert(serialised,"\n") end
			if type(key) == 'number' then
				table_insert(serialised,"[")
				table_insert(serialised,string_format("%d",key)) -- number keys must never contain decimals as the key parser does not support them except as ['strings']
				table_insert(serialised,"]")
			else
				table_insert(serialised,"['")
				key = string_gsub(tostring(key),_format.key_match,_format.key_gsub)
				table_insert(serialised,key)
				table_insert(serialised,"']")
			end
			table_insert(serialised,"=")
			table_insert(serialised,util.Serialise(value,maxdepth,nil,depth) or "")
			table_insert(serialised,",")
		end
		if lines then table_insert(serialised,"\n") end
		table_insert(serialised,lines or "}")
	elseif typed == 'userdata' or typed =='function' then
		table_insert(serialised,"_function_or_userdata_")
	elseif object ~= nil then
		table_insert(serialised,tostring(object))
	end
	return table.concat(serialised)
end end

local util_Decimals = util.Decimals
local reserved = keyed{"and","break","do","else","elseif","end","false","for","function","if","in","local","nil","not","or","repeat","return","then","true","until","while"}
function SerialiseWith (object,options, _depth)
	-- slower than Serialise, but constructs readable multi-line indented output
	-- second argument can specify either a named format or a table of format keys
	-- _depth is an internal recursion value and must not be specified, not to be fonfused with options.depth
	-- TODO: add linewrap and indented value formatting
	-- WARNING: for number behaviours see Serialise()
	local _format
	if type(options) =='string' then options={format=options} end
	options = options or {}
	if options.executable then
		-- handles the root table object as executable lua
		_format = options.format or format.root
		options.executable = nil -- musn't apply to sub tables
		options.truncate = false
		_depth = -1
	else
		_format = util.format[options.format] or options.format or format.default
	end
	local tonumber = tostring
	if options.decimals then tonumber = util_Decimals end
	_format.table_suffix = _format.newline
	_depth = _depth or 0
	local maxdepth = options.maxdepth or 5
	local serialised = {}
	if type(object) =='string' then
		if options.truncate~=false and #object > 200 then object = "* "..tostring(#object).." chars * beginning: "..string_sub(object,1,100) end
		if string_find(object,'[\"\n]') then
			object = string_gsub(object,"\n",_format.linebreak..string.rep("\t",_depth+1))
			table_insert(serialised,_format.longstring_open) table_insert(serialised,object)
			table_insert(serialised,_format.longstring_close)
		else
			table_insert(serialised,_format.quote)
			table_insert(serialised, object)
			table_insert(serialised,_format.quote)
		end
	elseif type(object) =='number' then
			table_insert(serialised,string_format("%.16g",object))
	elseif type(object) =='table' then
		_depth = _depth +1
		if _depth > maxdepth then return _format.table_open.."... ".._format.table_close end
		local table_close = _format.newline..string.rep(_format.key_indent,_depth-1).._format.table_close
		table_insert(serialised,_format.table_open)
		local array={}
		for key,value in ipairs(object) do
			table_insert(serialised,util.SerialiseWith(value,options,_depth))
			table_insert(serialised,_format.comma)
			array[key]=true
		end
		local haskeys
		for key,value in pairs(object) do
			if exclude and exclude[key] then
				table_insert(serialised,_format.newline)
				table_insert(serialised,string.rep(_format.key_indent,_depth))
				table_insert(serialised,key)
				table_insert(serialised,"=")
				table_insert(serialised,"EXCLUDED")
				table_insert(serialised,_format.comma)
			elseif not array[key] then
				table_insert(serialised,_format.newline)
				table_insert(serialised,string.rep(_format.key_indent,_depth))
				if type(key) =='number' then
					table_insert(serialised,_format.numberkey_open)
					table_insert(serialised,string_format("%d",key))
					table_insert(serialised,_format.numberkey_close)
				elseif string_match(tostring(key), "^[%a_]+$" ) and not reserved[key] then
					table_insert(serialised,tostring(key))
				else
					table_insert(serialised,_format.key_open)
					if _format.key_match then key = string_gsub(tostring(key),_format.key_match,_format.key_gsub) end
					table_insert(serialised,tostring(key))
					table_insert(serialised,_format.key_close)
				end
				table_insert(serialised,_format.equals)
				table_insert(serialised,util.SerialiseWith(value,options,_depth))
				table_insert(serialised,_format.comma)
			end
		end
		table_insert(serialised,table_close)
	elseif object ==nil then
		table_insert(serialised,_format['nil'])
	elseif object ==true then
		table_insert(serialised,_format['true'])
	elseif object ==false then
		table_insert(serialised,_format['false'])
	else
		table_insert(serialised,tostring(object))
	end
	return table.concat(serialised)
end
end

function FileRead(path)
	local file,err = io.open(path)
	if err then log.Notice(err) return nil,err end
	local data,err = file:read("*a")
	if err then log.Notice(err) return nil,err end
	file:close()
	return data
end
function FileSave(path,data,createdirs)
	-- if data is not a string, it will be serialised as Lua using util.Serialise (use SerialiseWith if you want it to be human readable)
	if createdirs then
		local parent = string_match(path,"(.+)/.-$")
		if parent then
			local result,err util.Shell("mkdir -p "..parent)
			if err then return nil,err end
		end
	end
	local file,err = io.open(path, "w+")
	if err then log.Notice(err) return nil,err end
	if type(data) ~='string' then data = util.Serialise(data,nil,true) end
	file:write(data)
	file:close()
	return true
end
function LoadSerialised(path)
	-- expects the given file to be an anonymous table as created by Serialise and then saved
	local data,err = util.FileRead(path)
	if err then return nil,err end
	return loadstring("return "..data)()
end
function SaveSerialised(path,data)
	return util.FileSave(path, util.Serialise(data))
end

function io.linesbackward(filename)
  local file = assert(io.open(filename))
  local chunk_size = 4*1024
  local iterator = function() return "" end
  local tail = ""
  local chunk_index = math.ceil(file:seek"end" / chunk_size)
  return
    function()
      while true do
        local lineEOL, line = iterator()
        if lineEOL ~= "" then
          return line:reverse()
        end
        repeat
          chunk_index = chunk_index - 1
          if chunk_index < 0 then
            file:close()
            iterator = function()
                         error('No more lines in file "'..filename..'"', 3)
                       end
            return
          end
          file:seek("set", chunk_index * chunk_size)
          local chunk = file:read(chunk_size)
          local pattern = "^(.-"..(chunk_index > 0 and "\n" or "")..")(.*)"
          local new_tail, lines = chunk:match(pattern)
          iterator = lines and (lines..tail):reverse():gmatch"(\n?\r?([^\n]*))"
          tail = new_tail or chunk..tail
        until iterator
      end
    end
end

function ExportRecords(path,records,options)
	-- records is a table (or array) with subtables each of which represents an individual record (row), keys within the table map to a column
	-- options is table, which should include an array of ordered column names corresponding to keys within the table, note that if the column order is not included, we will select the first record (if an array) or a random record to use its keys for the columns, therefore if records have non-stanrd keys the column names must be specified
	-- options.key="id" adds the key name for each row as an additional column named with the value  ("id" here)
	-- options.separator="\t" sets the column seperator, by default a comma (CSV) but in this example a tab (TSV)
	-- options.quotes=true forces wrapping values in double quotes
	-- options.sub = {[\q]="\q\q",}
	-- options.number = function defines the function to be used to output numbers, default is tostring
	local export = {}
	options = options or {}
	local header = options.header or true
	local number = options.number or tostring
	local separator = options.separator or ","
	local sub = options.sub or {}
	local quotes = options.quotes or false
	local id = options.key or false

	local table_insert = table_insert -- TODO: wrap with coercian, gsub and quotes
	local ipairs = ipairs
	local pairs = pairs
	if not options[1] then -- undefined column order
		for key,value in pairs(records[1] or next(records)) do
			table_insert(options,key)
		end
	end
	if header then
		if id then table_insert(export,id) table_insert(export,",") end
		for i,column in ipairs(options) do
			table_insert(export,column)
			if options[i+1] then table_insert(export,",") end
		end
	end
	local columns = #options
	for key,row in pairs(records) do
		if id then table_insert(export,key) table_insert(export,",") end
		for i,column in ipairs(options) do
			table_insert(export,value)
			if i<columns then table_insert(export,",") end
		end
	end
	return util.FileSave(path,table.concat(export))
end

function RunString(instructions,name)
	--> accepts lua code as an uncompiled string
	--< returns a boolean status, and the result of the function (or its error)
	local instructions,err = loadstring(instructions,name)
	if not instructions then return nil,err end -- failed to compile
	setfenv(instructions,_G) -- sandbox the instructions function
	return pcall(instructions)
end

function ModulePath(name)
	if string_sub(name,-4) ==".lua" then return name end -- already a path
	local file
	for path in string_gmatch(moonstalk.path,"[^;]+") do
		path = string_gsub(path,"%?",name,1)
		file = io.open(path)
		if file then file:close(); return path end
	end
end
function IncludeLuaFile (name,environment,preprocess)
	-- wraps ImportLuaFile to discover the environment of the calling function and make assignments to that table, which may be _G, this allows use inside modules and bundles; however if environment is specified it has exactly the same behaviour as ImportLuaFile (making a new environment for its functions)
	-- also has the same behaviour as require and module, accepting module names as well as paths, and caching imports that may receive multiple calls in the package table
	-- from any environment that should not have a metatable assigned (except _G which is ignored) do not call this function without specifying an environmentfrom any environment that should not have a metatable assigned (except _G which is ignored)
	if not environment then environment = getfenv(2) or _G end -- 1 is the util module, therefore 2 is the environment of the function calling include, such as another module
	local module = package.loaded[name]
	if module and module ~=true then return module end -- already loaded
	module = util.ImportLuaFile(name,environment,false,false)
	package.loaded[name] = module
	return module
end
_G.include = IncludeLuaFile
function ImportLuaFile(name,environment,preprocess,globalise)
	-- returns the results of a loadstring in a specified environment table or a new one, plus an option to pass the imported file data to a preprocess function, moonstalk.loaders will be applied as preprocessors regardless
	-- assignments from imported files are made to their table, whilst functions retain use of the global enviornment thus locals/upvalues must be used for any value shared between the file's functions, and full global paths must be specified for references and lookups
	-- assignments to the global environment by code loaded from this must be prefixed _G
	-- see IncludeLuaFile/include for more common use
	local path = util.ModulePath(name)
	if not path then assert(path, "Cannot import '"..name.."' as not found") end
	local code,err = util.FileRead(path)
	if not path then assert(path, "Cannot import '"..name.."' as unable to read: "..path) end
	if preprocess then code = preprocess(code) end
	for _,loader in ipairs(moonstalk.loaders.lua) do code = loader.handler(code) end -- e.g. toggles logging
	code,err = loadstring(code,path) -- compiles with global environment, but receives the envionrment it is set in (usually the bundle), and it's path if the preprocessor must perform additional file discovery
	if not code then assert(codde, "Cannot import '"..name.."' as compilation failed: "..err) end
	environment = environment or {}
	if environment ~=_G and not getmetatable(environment) then setmetatable(environment,{__index=_G}) end -- a sandbox that has read access to global environment, and write via _G
	setfenv(code,environment) -- replace default global environment with (new or specified) sandboxed environment
	local result,err = pcall(code) -- run and populate the environment
	if not result and err then assert(result,name..": "..err) end
	environment = getfenv(code) -- get the newly populated environment
	--if environment ~=_G then setmetatable(environment,nil) end -- remove the sandbox -- we can't remove it because local functions still reference it and would thus loose their ability to use globals
	if globalise ~=false then
		for name,value in pairs(environment) do
			-- reassign the global environment to functions; we only look for functions at depths 1-2
			if type(value) =='function' then pcall(setfenv,value,_G) -- sometimes there are non-modifiable functions
			elseif type(value) =='table' then
				for name,value in pairs(value) do if type(value) =='function' then pcall(setfenv,value,_G) end end
			end
		end
	end
	return environment
end
_G.import = ImportLuaFile

function SetBundleFunctions(bundle,functions)
	-- functions in bundles should have their envionrment set to that bundle's table so that assignments and lookups first take place in it rather than in the global, thus functions created outside that bundle that ae then copied will lack the correct environment, this function sets the correct environment
	-- the functions argument is a table of keynames to be set in the target bundle, with values being functions from the old bundle
	for k,f in pairs(functions) do
		setfenv(f,bundle)
		bundle[k] = f
	end
end

function ImportRecords(path, options) -- TODO: update to match ExportRecords, and add merging with an existing table, plus saving when in the teller: options.merge=table OR options.persist="tablekey"; options.update=false prevents creation of missing rows
	-- returns an array, containing a table for each line in the CSV file, with keys corresponding (exactly) to the field names defined in the header (first) row of the file; empty fields are removed/nil
	-- handles quote escaped values as exported from Excel
	-- NOTE: this is a multipurpose function intended for reading an arbitrary CSV file, if repeatedly reading a file with a known field structure, better performance can be acheived using a per-line pattern match
	-- OPTIMISE: ideally replace with C module
	local fields
	local data = {}
	for line in io.lines(path) do
		if string_sub(line,-1) =="\r" then line = string_sub(line,1,-2) end -- handle CRLF
		if fields then
			local record = {}
			local field = 1
			local offset = 1
			local value
			local line_length = #line
			while true do
				value = string_match(line,"([^,]*)",offset)
				if offset >line_length then
					break
				elseif string_sub(value,1,1) ==[["]] then
					local ends = (string_find(line,[[",]],offset) or #line) -1 -- trims the last quote
					value = string_sub(line,offset,ends,true)
					offset = offset +#value+2
					value = string_gsub(string_sub(value,2),[[""]],[["]]) -- trim off the first quote, and replace any double (escaped) quotes
				else
					offset = offset +#value+1
				end
				if value =="" then value = nil end
				record[fields[field]] = value
				field = field +1
			end
			table_insert(data,record)
		else
			fields = {}
			for name in string_gmatch(line,"([^,]+),?") do
				table_insert(fields,name)
			end
		end
	end
	return data
end


function InsertOrderedTablesAfter(value,comparator,into,after)
	-- table_insert does not work if the desired position is surrounded by nil
	-- this inserts a new table into an array of tables at a position determined by comparing each array item[key] to the desired at position
	local position
	if not into[1] or after <= into[1][comparator] then position = 1
	elseif after > into[#into][comparator] then position = #into+1
	else
		for i,item in ipairs(into) do
			if after <= item[comparator] then position=i break end
		end
	end
	table_insert(into,position,value)
end

function AnyTableHasKeyValue(tables,key,value)
	for _,record in pairs(tables) do
		if record[attribute] ==value then return true end
	end
end
function FindKeyValueInTable(attribute,value,items,max)
	-- returns nil if no matches, the first match, or if max >1 then a table of the matches
	max = max or 1
	local count = 0
	local results = {}
	for _,record in pairs(items) do
		if record[attribute] == value then
			table_insert(results,record)
			count = count +1
			if count ==max then break end
		end
	end
	if count ==0 then return
	elseif max ==1 then return results[1] end
	return results
end

function TableContainsAnyValue(table,values)
	for _,value in pairs(values) do
		if table[value] then return true end
	end
end

function TableContainsValue(table,find)
	for key,value in pairs(table) do
		if value ==find then return key end
	end
end

function SubtableContainsValue(tables,find)
	for key,table in pairs(tables) do
		for subkey,value in pairs(table) do
			if value ==find then return key,subkey,value end
		end
	end
end


function TableContainsAnyKeyValue(this,those)
	for key,value in pairs(those) do
		if this[key] == value then return true end
	end
end

function ArrayContains(array,value)
	if not value or not array then return end
	for position,arrayvalue in ipairs(array) do
		if arrayvalue==value then
			return position
		end
	end
end
ArrayContainsValue = ArrayContains -- DEPRECATED: remove asap

function ArrayContainsKeyValue(array,key,value)
	-- value may be a keyed table of possible key values {value=true} to match, i.e. if value is a table it is indexed for the arraytable value
	if not value or not key or not array then return end
	if type(value) ~='table' then
		for position,arraytable in ipairs(array) do
			if arraytable[key] ==value then return position end
		end
	else
		for position,arraytable in ipairs(array) do
			if value[arraytable[key]] then return position end
		end
	end
end

function ArrayContainsAll(array,values)
	-- look in an array of values, for alls values from another array (ideally the smaller)
	-- returns true if all matched
	if not values or not array then return end
	local matches = {}
	local count = #values
	for i,value in ipairs(values) do
		matches[value] = true
	end
	local matched = 0
	for i,value in ipairs(array) do
		if matches[value] then
			matched = matched +1
			if matched ==count then return true end
		end
	end
end

function ArrayContainsAny(array,values)
	-- look in an array of values, for any value from another array
	-- returns the matched value and its position in the array
	if not values or not array then return end
	local has = {}
	for position,value in ipairs(values) do has[value] = true end
	for position,arrayvalue in ipairs(array) do
		if has[arrayvalue] then return arrayvalue, position end
	end
end

function ArrayRemove(array,value)
	if not value or not array then return end
	for i,arrayvalue in ipairs(array) do
		if arrayvalue==value then
			table.remove(array,i)
			return true
		end
	end
	return false
end

function ArrayRemoves(array,values)
	-- values is an array or keyed table
	-- returns the count of removals
	if not values or not array then return end
	keyed(values)
	local removed = 0
	local length = #array
	for i=length,1,-1 do
		if values[array[i]] then
			table.remove(array,i)
			removed = removed +1
		end
	end
	return removed
end


function SubTablesContainKeys(tables,keys)
	-- check for the existence of any key from subtables in keys
	-- e.g. {{foo=bar}},{foo=true} would be true but {{bar=baz}},{foo=true} would not
	-- keys may be either an array or hashmap
	if keys[1] then keys = keyed(keys) end
	for _,table in pairs(tables) do
		for key in pairs(table) do
			if keys[key] then return true end
		end
	end
end

function KeysExistInSubTables(keys,tables)
	-- check for the existence of any of a small number of keys in a larger number of subtables
	-- keys must be an array
	if not keys or not tables then return end
	for _,table in pairs(tables) do
		for _,key in ipairs(keys) do
			if table[key] then return true end
		end
	end
end

function AnyKeysExist(keys,table)
	-- {"keyname", …}, {keyname=true,otherkeyname=false, …}
	if not keys or not table then return end
	for _,key in ipairs(keys) do
		if table[key] then return true end
	end
end
function AnyKeysNotExist(keys,table)
	-- {"keyname", …}, {keyname=true,otherkeyname=false, …}
	if not keys or not table then return end
	for _,key in ipairs(keys) do
		if not table[key] then return true end
	end
end
function AllKeysExist(keys,table)
	-- {"keyname","keyname"}
	if not key or not table then return end
	for _,key in ipairs(keys) do
		if not table[key] then return false end
	end
	return true
end
function AllKeysNotExist(keys,table)
	-- {"keyname","keyname"}
	if not key or not table then return end
	for _,key in ipairs(keys) do
		if table[key] then return false end
	end
	return true
end


function ParentKeyValue(tables,key,value,return_id)
	-- recurse tables and return the key and table of the first subtable that has the specified key and value
	for id,parent in pairs(tables or{}) do
		if parent[key] and parent[key] == value then
			if not return_id then
				return parent
			else
				return parent,id
			end
		end
	end
end
function RemoveArrayKeyValue(array,key,value)
	-- recurse array and delete the item table of the first item table that has the specified key and value
	for i,parent in ipairs(array or{}) do
		if parent[key] and parent[key] == value then
			table.remove(array,i)
			return true
		end
	end
	return false
end

function TableToArray(items)
	local array = {}
	local count = 0
	for _,item in pairs(items) do
		count = count +1
		array[count] = item
	end
	return array
end

function TableKeysToArray(items)
	local array = {}
	local count = 0
	for key in pairs(items) do
		count = count +1
		array[count] = key
	end
	return array
end

function CopyUniqueIdArray(outof, into, ids)
	-- copies subtables having unique "id" key outof one array into the other
	if not outof then return nil end
	ids = ids or {}
	into = into or {}
	local insert = table_insert
	for _,object in ipairs(outof) do
		if not ids[object.id] then insert(into, object) ids[object.id]=true end
	end
end

function ReplaceTableKeys(worktables,key,find,replace)
	for _,table in pairs(worktables) do
		if table[key]==find then table[key]=replace end
	end
end

function Match(these,those)
	-- returns the first array item in the table 'these' matching a key in the table 'those'
	-- does not break if any item is nil
	if not these or not those then return end
	if these[1] then -- array
		for _,name in ipairs(these) do
			if those[name] then return name end
		end
	else -- keys
		for name in pairs(these or {}) do
			if those[name] then return name end
		end
	end
end

function ArrayAddKeyed(to, value, maxlength, first)
	-- adds a value to a keyed table if not already in the table
	if not to[value] then
		to[value] = true
		if maxlength and #to >= maxlength then
			if first then
				table.remove(to,#to)
			else
				table.remove(to,1)
				first = 1
			end
		end
		to[first or #to+1] = value
	end
end

function ArrayAdd(to, value, maxlength, position)
	-- adds a value to an array table if not already in the table
	-- position=1 for first item, and implies removal from end with maxlength
	if not value then return end
	for _,this in ipairs(to) do
		if value ==this then return end
	end
	if maxlength and #to >= maxlength then
		if position then
			to[#to] = nil
			position = 1
		else
			table.remove(to,1)
		end
	end
	to[position or #to+1] = value
	return true
end
function InsertAfterArray(value,find,array)
	-- inserts at end if not found
	local target_pos
	for pos,found in ipairs(array) do
		if found==find then target_pos = pos+1; break end
	end
	table_insert(array,target_pos or #array+1,value)
end
function InsertBeforeArray(value,find,array)
	-- inserts at end if not found
	local target_pos
	for pos,found in ipairs(array) do
		if found==find then target_pos = pos; break end
	end
	table_insert(array,target_pos or #array+1,value)
end

function MoveLast(find,key,array)
	-- (item,array) if array items are not tables or can be compared directly
	-- does not add, use if not MoveToEnd then table.insert() end
	local found
	local moving
	local length
	if array then
		length = #array
		for i=length,1,-1 do
			if array[i][key] ==find then found = i; moving = array[i]; break end
		end
	else
		array = key
		length = #array
		for i=length,1,-1 do
			if array[i] ==find then found = position; moving = object; break end
		end
	end
	if not found then return
	elseif found ==length then return true end
	table.remove(array,found)
	table.insert(array,#table,moving)
	return true
end
function MoveFirst(find,key,array)
	-- (item,array) if array items are not tables or can be compared directly
	-- does not add, use if not MoveToEnd then table.insert() end
	local found
	local moving
	local length
	if array then
		length = #array
		for position,object in ipairs(array) do
			if object[key] ==find then found = position; moving = object; break end
		end
	else
		array = key
		length = #array
		for position,object in ipairs(array) do
			if object ==find then found = position; moving = object; break end
		end
	end
	if not found then return
	elseif found ==1 then return true end
	table.remove(array,found)
	table.insert(array,1,moving)
	return true
end


function NamespaceString(namespace)
	-- serialises a namespace-table as a Lua-syntax path-string
	local path = {namespace[1]} -- root table can not be escaped
	local insert = table_insert
	local match = string_match
	local key
	for i=2,#namespace do
		key = namespace[i]
		if type(key) =="number" then
			insert(path,"[")
			insert(path,digits(key))
			insert(path,"]")
		elseif match(key,"%A",1) then -- a value starting with a digit is not allowed
			if string_find(key,[=[[%[%]"]]=]) then return nil,"path contains illegal characters" end
			insert(path,"['")
			insert(path,key)
			insert(path,"']")
		else
			insert(path,".")
			insert(path,key)
		end
	end
	proxy.table = false
	return table.concat(path)
end

function StringNamespace(path)
	-- returns an array representing the split components of a string path
	-- path may be a dot-delimited string (e.g. "parent.child") or a Lua syntax table-path (e.g. parent['child'])
	-- NOTE: square brackets are not supported in string paths, and number are coerced using sugar syntax (e.g. "parent.123.child") unless Lua quoted index syntax is used (e.g. "parent['123'].child")
	-- WARNING: user-input used in constructing string paths may pose a security risk, a table-path is more secure
	local escaped = {}
	for offset,name in string_gmatch(path, "()(%b[])()") do
		escaped[offset+1] = name
	end
	local namespace = {}
	local skip = 0
	for offset,name in string_gmatch(path, [[()([^%[%].]+)]]) do
		if offset >= skip then
			skip = 0
			if escaped[offset] then
				name = escaped[offset]
				skip = offset + #name
				if string_sub(name,2,2)==[["]] or string_sub(name,2,2)==[[']] then
					namespace[#namespace+1] = string_sub(name,3,-3)
				else
					namespace[#namespace+1] = tonumber(string_sub(name,2,-2))
				end
			else
				namespace[#namespace+1] = tonumber(name) or name
			end
		end
	end
	return namespace
end

function TablePath(within,namespace)
	-- recurses the table or string given as within, for the specified key-path (namespace), returning the matching key's value; within is optional and defaults to _G
	-- namespace maybe a namespace-table (e.g. {"parent","child"}, or a StringNamespace (e.g. "parent.child")
	-- OPTIMIZE: for table depths over 2 using Lua syntax, or 4 using sugar (dot syntax) it's around 25% slower per table using this versus loadstring("return "..key)
	if not namespace then namespace = within; within = _G end
	if not namespace then return
	elseif type(namespace) =='string' then -- TODO: support proxies
		namespace = util.StringNamespace(namespace)
	end
	local length = #namespace
	if length == 0 or not within then return nil end
	within = within[namespace[1]]
	if not within or length == 1 then return within end
	within = within[namespace[2]]
	if not within or length == 2 then return within end
	within = within[namespace[3]]
	if not within or length == 3 then return within end
	return within[namespace[4]]
end
function TablePathParent(within,path,assign)
	-- as TablePath but returns the penultimate value, e.g. for path "wibble.wobble.wubble" it returns wobble instead of wubble; if the path does not contain a child, the root table is returned
	-- optionally takes an assign value which assigns the value to the designated key e.g. wibble.wobble.wubble = assign; this removes the need to determine if the path is root or not when using TablePathAssign
	local parent = string_match(path,"(.+)%.(.-$)")
	if not parent then if assign then within[parent or path] = assign end return within end
	within = util.TablePath(within,path)
	if assign then within[parent or path] = assign end
	return within
end
do local rawset = rawset; table_remove = table.remove
function TablePathAssign(within,namespace,assign,force, _ns_table,_ns_pos)
	-- recurses the table given as within, creating missing tables and assigning the value
	-- NOTE: if the value is nil, any missing parent tables within the namespace will not be created unles force = true
	-- path maybe a namespace-table (e.g. {"parent","child"}, or path-string
	-- if a root namespace is not available or unknown e.g. _G then utilise TablePathParent with the assign value instead
	-- OPTIMIZE: use an iterator loop rather than recursive function call
	-- OPTIMIZE: need a native C function
	-- pretty efficient for a parent.child assignment as doesn't invoke recursion, progressively less the deeper it goes
	if not _ns_table then
		-- first call, make sure we have a consumable namespace
		_ns_pos = 1 -- tracks how deep we are in the namespace for recursion, and avoids having to copy the table then remove namespace components as we traverse it
		if type(namespace) =="string" then
			_ns_table = util.StringNamespace(namespace)
		else
			_ns_table = namespace
		end
		if #_ns_table >6 then return scribe.Error("Recursion too deep for assignment in "..table.concat(_ns_table)) end
	else
		_ns_pos = _ns_pos+1
	end
	if _ns_table[_ns_pos+1] ==nil then
		-- last key in namespace
		rawset(within,_ns_table[_ns_pos],assign)
	else
		local key = _ns_table[_ns_pos]
		if not within[key] then
			if not force and assign ==nil then
				-- some part of the namespace doesn't exist, and our value is nil, so no further assignment is necessary
				return
			else
				-- create missing namespace tables so that we can make our assignments within it
				rawset(within,key,{})
			end
		end
		util.TablePathAssign(within[key],namespace,assign,force, _ns_table,_ns_pos)
	end
end
end

function TablePieces(original,keys)
	-- returns a trimmed table containing only the specified namespaced-keys of the original table; useful as a "Reduce" function (and is used in teller.Filter for this purpose)
	-- keys may be either an array of namespaced-keys e.g. {"key","key.path"} where the same string is used as the key in the resulting table, or a map of names and values e.g. {newkey="key",path="key.path"} where the key is used in the resulting table, but the value is used as the key to find its value; but the two cannot be mixed
	-- NOTE: doesn't perform deep copy
	local response = {}
	local util_TablePath = util.TablePath
	local util_TablePathAssign = util.TablePathAssign
	local string_find = string_find
	local named = not keys[1]
	local iterator = ipairs
	if named then iterator = pairs end
	for key,name in iterator(keys) do
		if not named then key = name end
		if string_find(name,".[%[%.]") then -- we do this test because tablepath calls namespace string and this is more efficient
			util_TablePathAssign(response, key, util_TablePath(original, name))
		else
			response[key] = original[name]
		end
	end
	return response -- an empty table if no keys matched
end
_G.pieces = TablePieces

function TablePiecesLocalised(original,keys,languages)
	-- same as the TablePieces but accepts a list of languages, then for any key ending [localised] it's value will be replaced with the nested corresponding language value (or a random one if none match)
	-- NOTE: doesn't perform deep copy
	local response = {}
	local string_find = string_find
	local string_sub = string_sub
	local language
	local value
	local util_TablePath = util.TablePath
	local util_TablePathAssign = util.TablePathAssign
	local named = not keys[1]
	local iterator = ipairs
	if named then iterator = pairs end
	for key,name in iterator(keys) do
		if not named then key = name end
		if string_sub(name,-2) =="d]" then -- NOTE: long string double-brackets are reencoded with a space from the scribe
			-- "key[localised] " table
			name = string_sub(name,1,-12) -- TODO: support [localised] as a permanent flag in the keyname?
			local piece = util_TablePath(original, name)
			if piece then -- we ignore missing pieces
				language = util.Match(languages, piece) -- last matching piece defines the language
				if language then -- user preferred
					value = piece[language]
				else -- random fallback (could also be an empty localised table)
					language, value = next(piece)
				end
				util_TablePathAssign(response, key, value)
			end
		else
			-- not a localised table
			if string_find(name,"[%[%.]") then -- we do this test because tablepath calls namespace string and this is more efficient
				util_TablePathAssign(response, key, util_TablePath(original, name))
			else
				response[key] = original[name]
			end
		end
	end
	return response, language -- response is an empty table if no keys matched
end

function StripLongComponents(value,max)
	-- remove long words/strings from space delimited text, this includes values such as URLs, and hyphentated words
	-- useful for prepping text for truncation
	-- expensive on large strings, therefore onyl use on a substring, or first do a simpler check such as string_find(value,"http",1,true)
	max = max or 32
	return string_gsub(value,"([^%s]-)", function(value) if #value> max then return "" end end)
end

do
	local terminal_punctuation = keyed".?!;…\r\n"
	local suggestive_punctuation = keyed",'(<\""
	local replace_punctuation = {['…']="",[';']=""}
	local tonumber=tonumber
function TruncatePunctuated(text,min,max,append)
	-- truncates within the specified range, preferring to truncate on terminal punctuation after min or before suggestive when closer to max, else at the first space preceeding max, and failing these, at max itself
	-- short form use is (text,max,append) which causes truncation on any punctuation within 25% of max with a minimum of 16 chars, else the standard behaviour
	-- does not expect html, use web.StripHTML(text,"remove") on the text first
	-- does not work with long string values such as URLs, use web.RemoveUrls(text) first
	-- will not truncate in delimited numbers (e.g. "123.000" "123,000", "10.99" etc.)
	local prefer_suggestive
	if type(max) ~='number' then
		append=max; max=min
		min = max *0.75 -- 25%
		if max -min <16 then min = max -16 end
		prefer_suggestive = 0
	else
		prefer_suggestive = min - (max - min) /2 -- suggestive only applies half way between min and max
	end
	if #text < max then return text end
	if append ==nil then append = " […]" elseif append ==false then append = "" end
	local truncated
	for position,matched in string_gmatch(string_sub(text,min+1),"()([%.%?%(%[!,;'…\"\r\n])") do -- OPTIMISE: a better behaviour would be to work backwards from max, as that would guarenteee the best fit
		local isnumber = (matched =="." or matched ==",") and tonumber(string_sub(text,min+position+1,min+position+1))
		if position+min >max then break
		elseif not isnumber and terminal_punctuation[matched] then
			truncated = string_sub(text,1,min+position-1)
			truncated = truncated..(replace_punctuation[matched] or matched)
			break
		elseif not isnumber and position >prefer_suggestive and suggestive_punctuation[matched] then
			truncated = string_sub(text,1,min+position-1)
			break
		end
	end
	if not truncated then
		truncated = string_sub(text,1,max)
		truncated = string_match(truncated,"(.+) [^ ]-$") or truncated
	end
	return string_match(truncated,"(.-)%s*$") .. append or "" -- trim all whitespace
end end

function Transliterate (text,lower)
	-- returns two parameters therefore cannot be called as parameter to a function itself if that function accepts further parameters (e.g. string_sub)
	if not text then return end
	-- TODO: refactor and introduce funcs that perform transliterated case changes seperately
	if lower then text = string.lower(text) end
	local utf8_ascii = terms.transliteration.utf8_ascii
	local utf8_codes = terms.transliteration.utf8_codes
	local ascii = {}
	local utf8
	local transliterated
	local table_insert = table_insert
	local string_sub = string_sub
	local string_byte = string.byte
	local first
	for i=1,#text do
		first = string_sub(text,i,i)
		if not utf8 and string_byte(first) ==195 then
			utf8 = string_sub(text,i,i+1)
			if utf8_ascii[utf8] then
				if not lower then
					table_insert(ascii, utf8_ascii[utf8])
				else
					table_insert(ascii, utf8_codes[utf8].ascii_lower)
				end
				transliterated = true
			else
				utf8 = nil
				table_insert(ascii,first)
			end
		elseif utf8 then
			utf8 = nil
		else
			table_insert(ascii,first)
		end
	end
	return table.concat(ascii),transliterated
end

do
	local util_Transliterate = util.Transliterate
	local ifthen = ifthen
	local keyed = keyed
function Normalise(text)
	-- a normalised string value is transliterated and lowercase without spaces or punctuation, facilitating db looks-ups on user-input values
	text = string_gsub(text or "", "[%s%p]", "")
	local transliterated
	text,transliterated = util_Transliterate(text,true)
	return text,transliterated
end

function NormaliseUri(text,supplement,seperator,lower)
	-- takes any given user-derived text and renders it into a URI-safe value with user-friendly punctuation; the value is normalised but as it can also contain punctuation it is not typically used for indexing as the corresponding normalise function will not
	-- the counterpart function DisplayUri can be used to format a user-exposed value without normalisation
	-- seperator should be specified as an empty string "" if no replacement punctuation seperator is to be used i.e. spaces and punctuation are removed
	-- lower defaults to true, only specify as false if your matching routines are case sensitive (Moonstalk's adressing is not)
	-- supplement is an array that may specify additional characters that are allowed in the URI, e.g. {'/'} if the input may be a path; all other characters are removed all replaced with generic punctuation
	-- prefix and suffix punctation characters are removed; if you require slash prefixed or suffixed values you must validate the input yourself and then modify the returned value
	-- NOTE: this is a fairly expensive operation for longer strings, it should be run during create operations and its result stored
	-- WARNING: this function only supports the defined terms.urlsafe characters, any other character is considered unsafe and cannot therefore be used with other languages unless supported by transliteration -- TODO: only strip know problematic characters on a per-locale basis
	if not text then return end
	text = util_Transliterate(text, ifthen(lower==false,false,true))
	if supplement then keyed(supplement) else supplement = {} end
	seperator = seperator or "-"
	local char,lastchar
	local uri = {}
	local string_sub = string_sub
	local table_insert = table_insert
	for i=1,#text do
		char = string_sub(text,i,i)
		if terms.seperators[char] then if lastchar~=seperator then char = seperator else char=nil end end
		if terms.urlsafe[char] or supplement[char] then
			table_insert(uri,char)
			lastchar = char
		end
	end
	if uri[1]=="-" then table.remove(uri,1) end
	if uri[#uri]=="-" then table.remove(uri,#uri) end
	return table.concat(uri)
end
end

function DisplayUri(text,path)
	-- this function prepares without normalisation a user-derived value typically containing punctuation, for use in a URL (as normalisation occurs upon request this value can be anything that will eventually be normalised acceptably), however for the purpose of user-friendliness we do replace spaces with dashes to avoid ugly URL encoded values, the browser is expected to be able to encode the remaining values
	-- web.SafeHref is a much cheaper version of this function for simple or pre-formatted values not containing punctuation; this function provides some HREF protection from user-values e.g. " is removed
	-- the counterpart function NormaliseUri can be used to create a normalised value
	-- path must be true if / slash is allowed in the result
	if not text then return end
	local char,lastchar
	local url = {}
	local string_sub = string_sub
	local table_insert = table_insert
	for i=1,#text do
		char = string_sub(text,i,i)
		if (not path and char =="/") or terms.seperators[char] then if lastchar~="-" then char = "-" else char=nil end end
	end
	if url[#url]=="-" or url[#url]=="/" then table.remove(url,#url) end
	url = table.concat(url)
	return string_gsub(url,".",terms.urlsafe_encode)
end

function Lines(lines)
	if not lines then return
	elseif lines:sub(-1)~="\n" then lines=lines.."\n" end
	return lines:gmatch("(.-)\n")
end

function Shell(command,read)
	-- executes a command using the shell, capturing the standard and/or error outputs, thus providing the command's response regardless of executation status; the result should generally be interpreted as successful or failed using substring validation on the response
	-- returns only the first line of the response unless the second parameter is "*a" for all; the response will include blank lines from merge of stderr and stdout
	-- NOTE: do not use with multiple semi-colon delimited commands, as only the last will have both its output captured and others may output to the terminal; instead you must call each seperately
	-- NOTE: os.execute() returns the status code, but stdout is sent to the current terminal
	-- NOTE: replaced in openresty for non-blocking
	local shell = io.popen(command.." 2>&1")
	local result = shell:read(read or "*l")
	shell:close()
	if result =="" then return end
	return result
end

function Folders (path)
	-- parses a directory, creating a table for each top-level folder
	local directory = {}
	local files = io.popen("ls -1pwL "..path):read("*a")
	for name in string_gmatch(files,"(.-)\n") do
		firstchar = string_sub(name,1,1) -- in superuser mode ls -A is default and can't be disabled
		if firstchar ~="." and firstchar~="_" and string_sub(name,-1) =="/" then
			directory[string_sub(name,1,-2)] = {} -- must remove the trailing slash
		end
	end
	return directory
end
function FileModified(path)
	return io.popen("stat -f '%m' "..path):read("*a") -- NOTE: this gets replaced by dependent to use the lfs module
end
function FileExists(path)
	local file = io.open(path)
	if not file then return end
	file:close()
	return true
end


function FileExt(name)
	if not name then return end
	local extension = {}
	for i=0,#name do
		local char = string_sub(name,#name-i,#name-i)
		if char == "." then return table.concat(extension) end
		table_insert(extension,1,char)
		if #extension > 20 then return end
	end
	return false
end

function JsDate(timestamp)
	return os.date("!%F %T",timestamp or 0)
end

function CountKeys(object)
	local count = 0
	for _ in pairs(object or {}) do count =  count + 1 end
	return count
end

function ResumeToCols(text,cols)
	-- takes one or more lines of text and wraps them at punctuation, whilst preserving the (tab or space) indentation
	-- _G.terminal = require 'moonstalk/terminal'
	if not terminal.inited then terminal.init() end
	cols = cols or terminal.columns
	local offset,char,indent,indents,wrapped,length
	local breakpoints = {[' ']=true, [',']=true, ['\n']=true}
	local output = {} -- more memory efficient than constantly concatenating
	local table_insert = table_insert
	-- iterate over each line
	for line in string_gmatch(text.."\n","(.-)\n") do
		-- determine indentation
		indent = ""
		indents = 0
		for char,position in string_gmatch(line,"(%s)()") do
			if position > (#indent + 2) then break end
			indent = indent .. char
			if char == "\t" then indents = indents + 8 -- assuming the terminal displays tabs as 8 spaces
			else indents = indents + 1 end
		end
		-- check each line
		if #line + indents - #indent < cols then
			-- doesn't need to be wrapped, so output unchanged
			table_insert(output,line)
		else
			-- does need to be wrapped
			-- work backwards from the wrap point to find punctuation
			local _,invisibles = string_gsub(string_sub(line,1,cols),"\27%[%d+m","") -- invisbles shouldn't count against our columns
			invisibles = invisibles *4
			offset = cols -indents +invisibles
			local string_sub = string_sub
			while offset > 0 do
				char = string_sub(line,offset,offset)
				if breakpoints[char] and string_sub(line, offset -1, offset -1)~='\27' then break end --prevent escape codes being used as a break point
				offset = offset -1
			end
			-- output the trimmed line
			local begins = 1; if string_sub(line,1,1)==" " then begins=2 end -- strip carried spaces -- OPTIMISE: these should just be left on the end of the preceeding line
			table_insert(output,string_sub(line,begins,offset))
			table_insert(output,"\n")
			-- determine if the wrapped line also needs wrapping
			wrapped = indent..string_sub(line,offset+1)
			if (#wrapped + indents - #indent) > cols then
				-- does need wrapping as well, so call self with new value
				table_insert(output,util.ResumeToCols(wrapped,cols))
			else
				-- output the wrapped line
				table_insert(output,wrapped)
			end
		end
		table_insert(output,"\n")
	end
	table.remove(output,#output) -- removes the final linebreak we added initially
	return table.concat(output)
end

local months = keyed{"jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"} -- TODO: use locale and vocab
function GetDate(userinput,nlocale,astable)
	-- expects a user-input date string (numerical and without a time), returns an estimated reftime representing the date adjusted from the site timezone (not user's); this value may be output for display with the format.ReferenceDate function, but if used with format.Date the returned timestamp may need to be adjusted from the site timezone; returns nil if no date was found (should not be used for date detection); when astable==true returns only the table of extracted values
	-- TODO: handle partial dates and months specified as text/abreviations, using locale language
	if not userinput then return end
	local date={hour=12,minute=0}
	local guessed,a,b
	nlocale = nlocale or locale
	a,b = string_match(userinput,"(%a+)%A*(%a*)")
	if a or b then
		-- contains words (non-digits)
		if a then a = string.lower(string_sub(a,1,3)) end
		if b then b = string.lower(string_sub(b,1,3)) end
		date.month = util.ArrayContains(months,a) or util.ArrayContains(months,b)
		if month then
			-- now lets get the day and year
			a,b = string_match(userinput,"(%d+)%D*(%d*)")
			-- TODO: we don't handle 2 digit years; could detect with prefix '
			if a then
				a = tonumber(a)
				b = tonumber(b)
				if a and a > 32 then
					-- yyyy, day
					date.day = b
					date.year = a
				else
					-- day, year
					date.day = a
					date.year = b
				end
			-- else no day or year, defaults will be used
			end
		-- else no month so an invalid date
		end
	elseif #userinput >7 and #userinput <11 then
		-- ?/?/yyyy; 8 chars
		local match = pack(string_match(userinput,"%D*(%d+)%D*(%d+)%D*(%d+)%D*"))
		if #match[1] == 4 then -- yyyy/mm/dd
			date.year = match[1]
			date.month = match[2]
			date.day = match[3]
		else
			if #match[3] ~= 4 then return end
			date.year = match[3]
			-- ??/??/yyyy
			if not locale.mmdd or not match[2] then -- Commonwealth style dd/mm or only day specified
				date.day = match[1]
				date.month = match[2]
			else -- US style mm/dd
				date.month = match[1]
				date.day = match[2]
			end
			-- we could check the value of month and day but this would create variable behaviour in scenarios
		end
	elseif #userinput >3 then -- ?/yy; 4 chars or ?/yyyy; 6 chars
		date.month,date.year = string_match(userinput,"%D*(%d+)%D*(%d+)%D*")
	end
	if not date.day then
		guessed = 'day'
		date.day = 1
	end
	if not date.year then
		guessed = 'year'
		date.year = os.date("*t").year
	end
	if not date.month then
		return nil -- Unsupported date format
	end
	if astable then
		for k,v in pairs(date) do date[k] = tonumber(v) end
		return date,guessed
	end
	return os.time(date),guessed
end

function GetNumber(str)
	-- used to handle localised number input; should be used on any input value having numbers beyond 999 or with decimals
	-- e.g. "1.200" in Europe would be 1 thousand 2 hundred, but in the UK would be 1 point 2, with decimal accuracy to 3
	-- TODO: accept locale as param; currently uses user/site locale
	-- TODO: handle digitgroup/thousands
	if not str then return
	elseif type(str)=='number' then str = tostring(str) end
	local number={}
	local decimal = locale.decimal or "."
	for i=1,#str do
		local char = string_sub(str,i,i)
		if tonumber(char) then
			table_insert(number,char)
		elseif char==decimal then
			table_insert(number,".")
		end
	end
	return tonumber(table.concat(number))
end
function GetDigits(str)
	-- extract and concatenates all digits in the string
	local result = {}
	local count = 0
	for digit in string_gmatch(str,"%d+") do
		count = count+1
		result[count] = digit
	end
	return table.concat(result)
end

function HumaniseUrn(str)
	-- discard first slash
	slash = string_find(str,"/",1,true)
	if slash then
		str = string_sub(str,1,slash-1).." "..string_sub(str,slash+1)
		-- pad remaining slashes with spaces
		str = str:gsub([[/]]," / ")
	end
	-- replace dashes with spaces
	str = str:gsub("-"," ")
	-- replace underscores with padded colons
	str = str:gsub("_"," : ")
	-- should iterate through the words and replace those found in words
	return util.TitleCase(str)
end

do local metatable = {__index=function(t,k)return rawget(t,k)or"" end}
function macro(combined,values,extra)
	-- provides a simplified way of substituting values in a localised string ('macro'), or building a localised string from conditional values ('macro function'); by handling both these usage scenarios from a single method, we can swap between both as their use evolves without refactoring; not intended for non-localised usage (can just call gsub on a string directly)
	-- should be called with a vocabulary term e.g. l.macro_name and a table of variable names with their corresponding values for substitution/construction
	-- the vocabularly term may be declared in an app's settings as either a string containing variable placeholders e.g. vocabulary.en.macro_name = [[hello ?(name)]]; note that placeholders with no value will also be removed, if some are conditional use a function
	-- or a function that returns a constructed string e.g. vocabulary.en.macro_name = function(vars) return "hello "..vars.name end
	-- you can call this function with either a table, or params which additional allows an extra paramater to be passed to a macro function

	if not values then
		-- macro{term, placeholder_name="value", …}
		if not combined[1] then return end
		setmetatable(combined,metatable) -- ensures missing values are removed
		if type(combined[1]) =="function" then
			return combined[1](combined)
		end
		return string_gsub(combined[1], "%?%((.-)%)", combined)
	else
		-- macro(term, {placeholder_name="value", …}, extra)
		if not combined then return end
		setmetatable(values,metatable) -- this ensures missing values are removed
		if type(combined) =="function" then
			return combined(values,extra)
		end
		return string_gsub(combined, "%?%((.-)%)", values)
	end
end end
_G.macro = macro

function TableMacro(keys,macro)
	-- keys should be a table of key-values, and macro is an array of key names that may or may not be in keys; the result is an array of only the keys with values
	-- ({foo="a",bar="b",baz="c"},{"bar","wibble","foo"}) = {"b","a"}
	-- this function is useful as a constructor for conditional macros/phrases, where the resulting array is consumed by GrammaticalList or table.concat with a separator
	local result = {}
	for _,key in ipairs(macro) do
		if keys[key] then table_insert(result,keys[key]) end
	end
	return result
end

function ListGrammatical(...)
	-- (list) defaults to «first, second and third.»
	-- returns an empty string for an empty list, nil if missing
	-- (list,", "," and ",".")
	local arg = {...}
	local list = arg[1]
	if not list then return end
	local delimiter = arg[2] or ", "
	local last,terminator
	if #arg>1 then
		last = arg[3] or ""
		terminator = arg[4] or ""
	else
		last = " "..l['and'].." " -- TODO: use locales
		terminator = "."
	end
	if #list==1 then return list[1]..terminator end
	local grammar = {}
	local length = 0
	for _,item in ipairs(list) do
		length = length +2
		grammar[length-1] = item
		grammar[length] = delimiter
	end
	grammar[length-2] = last
	grammar[length] = terminator
	return table.concat(grammar)
end

function IndexSubTablesByKey(tables,key)
	-- indexes a table by a specified key of its contained tables; existing keys will be replaced so they should be saved as a key=value inside the contained tables if not already
	local newTable = {}
	local keyValue = ""
	for x,subTable in pairs(tables) do
		keyValue = subTable[key]
		newTable[keyValue] = subTable
	end
	return newTable
end

function InvertArray(array)
	-- returns a new table with the opposite order of the original
	-- NOTE: it may be preferable to simply use the ArrayDecsend iterator
	local inverted = {}
	local top = array[#array]
	local bottom = 1
	while true do
		inverted[bottom] = array[top]
		bottom = bottom +1
		top = top -1
	end
end

function Shuffle(array)
	-- fisher yates; modify in place
	local count = #array
	local math_random = math.random
	for i = count, 2, -1 do
		local j = math_random(i)
		array[i], array[j] = array[j], array[i]
	end
	return array -- same table
end

function ArrayTrim(array,length)
	-- returns a trimmed version of the array, which may be a new table
	-- makes the very simplistic assumption that copy items to a table is half as fast as setting existing items to nil -- FIXME: test this
	if #array - length > length * 2 then
		-- simply set surplus values to nil
		for i=length+1,#array do
			array[i] = nil
		end
		return array
	else
		-- copy the required items to a new table
		local new = {}
		for i=1,length do
			new[i] = array[i]
		end
		return new
	end
end
function ArrayRange(array,first,last,contains_nil)
	-- returns a new table containing only the specified range of values (inclusive) from the array
	-- if array contains nil then ignore_nil must be specified as true, if the value of last is also > the position of the last value in the array, this function will continue iterating until reaching that value which could be expensive for large differences
	first = first or 1
	last = last or #array
	if not contains_nil and last > #array then last = #array end
	local range = {}
	for offset=first,last do
		range[#range+1] = array[offset]
	end
	return range
end

function SortArrayByKey (array,key,invert,normalise)
	-- invert=true typically results in descending sort, otherwise ascending
	-- if a table without an array part, will not sort the original table but will return a new table
	-- normalise is an optional function to run upon each value, such as tostring or tonumber
	if empty(array) or not key then return
	elseif not array[1] and next(array) then
		-- convert table keys to an array
		array = util.TableToArray(array)
	end
	local comparator
	if not invert then
		if not normalise then
			comparator = function (a,b)
				return (a[key] or 0) < (b[key] or 0)
			end
		else
			local normalise = normalise
			comparator = function (a,b)
				return normalise(a[key]) < normalise(b[key])
			end
		end
	else
		if not normalise then
			comparator = function (a,b)
				return (a[key] or 0) > (b[key] or 0)
			end
		else
			local normalise = normalise
			comparator = function (a,b)
				return normalise(a[key]) > normalise(b[key])
			end
		end
	end
	table.sort(array,comparator)
	return array
end


function SortArrayByLookup(array,lookup,invert,key)
	-- lookup must be a table providing comparison values for array[key]
	-- mainly useful where creating a list of results that can't be modified to include a per query rank or sort order, or where cloning its table to then modify would be expensive; instead we define the sort order in a seperate lookup table that may be throwaway or retained; if the array is an array of tables to sort, the key in the lookup table would be an array table itself
	-- the lookup table values may optionally be tables themselves, such as if additional ranking values are aggregrated together for rendering; in this case key must be specified as the key name within the lookup table result upon which to sort such; this is slightly more expensive when sorting large arrays as it involves an extra table lookup though negligable for most uses
	-- e.g. items={id,id,…} local sorts={}; for _,item in ipairs(items) do ranks[item]=some_value end SortArrayByLookup(items,sorts)
	-- e.g. items={{…},…} local ranks={}; for _,item in ipairs(array_of_tables) do if item.some_match then rank=1 end; if rank>0 then ranks[item]=rank end end SortArrayByLookup(results,ranks) -- in this case the items are a persitent/cached value that is reordered for each consumption
	-- e.g. local results={} local ranks={}; for key,item in pairs(origin_items) do if item.some_match then rank=1 end; if rank>0 then table.insert(results, item); ranks[item]=rank end end SortArrayByLookup(results,ranks) -- in this case origin_items are the persisted values and are not resorted as we simply copy its values into results whilst also adding a sort value to ranks; obviously you'll want a ranking mechanism not a static value;  if the sort order is defined by a persistent value in the item, and origin_items is an array whose persistence order is unimportant simply use SortArrayByKey
	if empty(array) or empty(lookup) then return array end
	local comparator
	if not key then
		if not invert then
			comparator = function(a,b) return lookup[a] < lookup[b] end
		else
			comparator = function(a,b) return lookup[a] > lookup[b] end
		end
	else
		if not invert then
			comparator = function(a,b) return lookup[a].value < lookup[b].value end
		else
			comparator = function(a,b) return lookup[a].value > lookup[b].value end
		end
	end
	table.sort(array,comparator)
	return array
end

function ArrayDescend(array,start,finish)
	-- returns an iterator similar to ipairs but descending and accepting additional optional parameters that start and stop the iterator at a specific position; a convience function for traversing a small designated range
	start = start or #array
	start = start+1
	finish = finish or 1
	return function()
		start = start -1
		if start < finish then return nil end -- stop
		return start,array[start]
	end
end

function ArrayAscend(array,start,finish)
	-- returns an iterator similar to ipairs but accepting additional optional parameters that start and stop the iterator at a specific position; a convience function for traversing a small designated range
	start = start or 0
	finish = finish or #array
	return function()
		start = start +1
		if start > finish then return nil end -- stop
		return start,array[start]
	end
end

function ClearArray(table)
	-- remove the array part of a table, preserving the dictionary part (if any)
	for position in ipairs(table) do table[position]=nil end
	return array
end

function TableFilterConfig(criteria)
	if type(criteria)=="string" then
		return util.TablePath(_G, criteria)
	elseif type(criteria)=="function" then
		return criteria
	elseif type(criteria)=="table" then
		return nil,criteria
	end
end

function ArrayFilter(array,criteria)
-- NOTE: teller.Filter provides additional functionality that encapsulates this
--[[ returns a sequence of records within an array, optionally filtered with a match criteria

	count = number; records per page (default is 16)
	plus one of the following positional indicators, to be specified as a negative value if descending the array:
	start = number; a fixed index in the array from which to start iterating
	offset = number; number of records from start or end of the array
	page = number; a convenience offset calculator

returns a table containing an array of results, and the following additional keys:
		total; the total number of records in the array
		next; criteria table to get the subsequent page of results, if any
		prior; criteria table to get the preceeding page of results, if any
		note that prior and next maintain their meaning relative to the direction of iteration
--]]
	-- TODO: apply match to prior and next
	-- NOTE: it is left as an exercise to the implementor to determine the best method for maintaining positional accuracy with paging when additions/removals modify the array between requests
	-- TODO: better preservation of positional accuracy by looking forward/back for an ID, thus allowing for removals as well as additions, would need to revert to last know position if ID is not found within a certain scope; should use a secondary function to look for the ID which then delegates here once found (probably filter)
	local results = {total=array.count or array.length or #array}
	criteria = criteria or {}
	local increment
	local maximum = criteria.count or 16
	local position = criteria.start or criteria.offset or criteria.page or 1
	if position <0 then
		increment = -1
		if criteria.start then
			position = position* -1
		else
			if criteria.page then
				position = ((position+1)*maximum) -1
			end
			position = (results.total) -(position* -1) +1
		end
	else
		increment = 1
		if criteria.page then
			position = (maximum*(position-1)) +1
		-- else position is already valid as is position/offset from start
		end
	end
	local prior = position +(increment* -1)

	local matchfunction,matchkey = util.TableFilterConfig(criteria.match)

	-- is there a record before the record we're starting on?
	if array[prior] then
		results.prior = {start=(position-(maximum*increment)) *increment}
		if criteria.page then results.prior.page = criteria.page -increment end
	end

	local count = 0
	-- the following are maintained as seperate loops as a case optimisation (one less block if no filter)
	if matchfunction or matchkey then
		-- iterate array from start position to collect the desired sequence of records applying the match filter to the desired sequence of records
		local util_TablePath = TablePath
		while true do
			local result = array[position]
			if not result or count >maximum then
				break
			elseif matchfunction then
				local matched = matchfunction(position,result,criteria)
				if matched then
					count = count + 1
					results[count] = matched
				end
			else
				local value = util_TablePath(result, matchkey[1])
				if (matchkey[2] ==result) or (matchkey[2] =="*" and result ~=nil) then
					count = count + 1
					results[count] = result -- * ~=nil (i.e. exists)
				end
			end
			position = position + increment
		end
	else
		-- iterate array from start position to collect the desired sequence of records
		local result
		while true do
			count = count + 1
			result = array[position]
			if not result or count >maximum then break end
			position = position + increment
			results[count] = result
		end
	end
	-- is there a record after our last collected record?
	if array[position] then
		results.next = {start=position*increment}
		if criteria.page then results.next.page = criteria.page +increment end
	end

	return results
end

function TableRecordConformity (records)
	-- provides a count of keys found in a table's subtables
	-- useful for acertaining irregularly used attributes in records for cleanup and consistency checking
	local keys = {}
	for _,record in ipairs(records) do
		for name in ipairs(record) do
			if keys[name] then keys[name] = keys[name] + 1
			else keys[name] = 1 end
		end
	end
	return keys
end

function CountryCodeIn(telephone)
	-- TODO: return only the country code
	return ""
end

function AsciiSum(ascii)
	local string_byte = string.byte
	local string_sub = string_sub
	local value = 0
	for i=1,#ascii do
		value = value + string_byte(string_sub(ascii,i,i))
	end
	return value
end


do local math_random = math.random; local string_sub = string_sub;
local alphabets = { -- TODO: move to terms and lookup from there (allows other apps to add)
	unique = keyed "abcdefghijkmnpqrstuvwxyz2346789",
	alphanum = keyed "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
	alpha = keyed "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
}
-- REFACTOR: the following two functions are essentially the same, remove one of them
function RandomString (length, chars)
	-- generates a random string of an even-numbered length, by default without special characters
	length = length or 32 -- 256-bits
	chars = chars or "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local random = {}
	for i=1,#chars do random[math_random(1000)] = string_sub(chars,i,#chars) end
	local randomised = {}
	for _,char in pairs(random) do
		randomised[#randomised+1]=char
	end
	randomised = table.concat(randomised)
	random = {}
	for i=1,length/2 do
		local offset = math_random(1,#randomised-1)
		table_insert(random,string_sub(randomised,offset,offset+1))
	end
	return table.concat(random)
end
function ShortToken(length,alphabet)
	-- generates a non-unique random ID string of the specifed length using only the provided characters or named alphabet (default is 'unique' which handles use as lowercase but also excludes some similar looking chars, thus is suitable for user-input and random email addresses)
	-- math.randomseed must have been initialised
	-- for longer IDs this function becomes expensive therefore it is prefable to utilise Token()
	-- when uniqueness is desired this may be called repeatedly until a unique value is produced, where the longer both the length and alphabet the more likely a unique return value will be, thus it is not appropriate for calling repeatedly on very short lengths with high population, see hashids (ref utilities-dependent)
	-- to avoid potentially endless repeated calls when generating unique IDs there must be sufficent empty address space, thus roughly speaking length should correspond to the number of expected random IDs, e.g. if you need 999 IDs a length of 3 would be acceptable, and longer alphabets would reduce this (the 'unique' alphabet has 31 chars * 3 = 29791 which is enough space to cheaply find 1000 unique IDs/tokens (i.e. 1/30th of the available space); for 1,000,000 IDs the 'alphanum' alphabet with a length of 7 characters might be adequate
	-- a short-id generated from an incrementing integer is never secure when simply hashed or encoded (e.g. hashids) as its length does not have sufficient entropy, its neighbours and sequence can thus be discovered, whereas cryptographic hashing algorithms such as sha224, md5 are longer and thus more secure; however when used with CreateID which , the obfustication of hashids is probably adequate to guard against abuse; if security is critical and a short version of an ID is required use Encrypt
	if alphabet then alphabet = alphabets[alphabet] or keyed(alphabet) else alphabet = alphabets.unique end
	length = tonumber(length) or 32
	local id = {}
	local max = #alphabet
	for position=1,length do id[position] = alphabet[math_random(1,max)] end
	return table.concat(id)
end
end

local alphabet = {chars="JWDFKMQLNPABCSTGHVYXRZ34589267"} -- no vowels prevents creation of words, similarly doesn't use 0 and 1 -- TODO: randomise and save to node -- TODO: allow alphabet to be specified
for i=1,#alphabet.chars do
	local letter = string.sub(alphabet.chars,i,i)
	alphabet[letter] = i
	alphabet[i] = letter
end
function EncodeAlphabet(number)
	-- encodes a number as an alphanumeric string, using the default alphabet of 30 chars, accommodates numbers just under 1m (6 digits) in 4 chars, or just under 1b (9 digits) in 6 chars
	local encoded = ""
	local max = #alphabet
	while number >=0 do
		encoded = (alphabet[ number % max ] or alphabet[max]) .. encoded -- needs a default for when the number deviveds as0, which is the same as max thus the last letter
		if number <= max then break end
		number = math.floor(number / max)
	end
	return encoded
end
function DecodeAlphabet(encoded)
	local number = 0
	local max = #alphabet
	for i=1,#encoded do
		number = number *max +alphabet[ string.sub(encoded,i,i) ]
	end
	return number
end

return util
