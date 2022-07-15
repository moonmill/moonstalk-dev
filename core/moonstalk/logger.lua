-- when alerts are desired to be forwarded eslewhere, the log.Alert function should be wrapped and the notification forwarded by the wrapper
-- utilises the request.identifier string or log.identifier that is moonstalk.server by default; this is not an ID but an associative string that makes it easier to identify within a short sequence, such as an incrementing number that resets
_G.request = _G.request or {}

-- TODO: use ngx.pipe https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/pipe.md

require "moonstalk/utilities"
_G.log = _G.log or {}
_G.log.levels = keyed{Priority=0,Alert=1,Notice=2,Info=3,Debug=4}
local level = 4
local identifier = ""
local logger, err
local table_concat = table.concat
local os_date = os.date
local print = print

function log.PrintLog (msg)
	if msg ==nil then return end
	if type(msg) =="table" then msg = util.PrettyCode(msg,2) else msg = tostring(msg) end
	print (table_concat{os_date("!%H:%M:%S "), identifier, ifthen(request.identifier,"/",""), request.identifier or "", " [⸱] ", msg})
end
local Append = log.PrintLog
log.Append = Append

-- optionally we can ask to use a file, which may be shared to aggregate logging from multiple processes (tee provides pseudo arbitration for concurrent buffered writes)
function log.WriteLog (msg,prepend)
	if msg ==nil then return end
	if type(msg) =="table" then msg = util.Serialise(msg,2) else msg = tostring(msg) end
	logger:write (table_concat{os_date("!%Y%m%d %H:%M:%S "), identifier, ifthen(request.identifier,"/",""), request.identifier or "", prepend or " [·] ", msg, "\n"})
	logger:flush()
end
function log.Open(file)
	if logger then return end -- we've already opened the logfile
	logger,err = io.popen("tee -a "..file.." > /dev/null","w") -- we use tee for its file append buffering (with multiple instances, one per client) not for its pipe-jointing, thus the other joint is sent to dev/null instead of stdout to discard the unneeded copy, avoid broken pipe errors and prevent display to the terminal
	if err then print(err) end
	log.Append = log.WriteLog; Append = log.WriteLog
end

function log.Debug (msg)  if level > 3 then Append(msg," [ ] "); return nil,msg end end
function log.Info (msg)   if level > 2 then Append(msg," [i] "); return nil,msg end end
function log.Notice (msg) if level > 1 then Append(msg," [★] "); return nil,msg end end
function log.Alert (msg)  if level > 0 then Append(msg," [‼︎] "); return nil,msg end end
function log.Priority (msg)
	if not node.dev and node.admin then email.Send{to=node.admin,subject="Moonstalk critical message",body="on instance "..node.instance.." of "..node.server.." at "..node.hostname.."\n\n"..msg} end
	Append(msg," [✻] ")
	return nil,msg
end

-- TODO: cache notices and push to disk at intervals (does lighty already do this?) to reduce disk use for per-request accountancy logging; check if lighty already does this, in which case lighty logging can be used for accountancy

function log.Options(t,k,v) -- setter
	-- dual usage, can be called directly with a table of options, but is also the handler for the metatable
	if not k then -- direct call Options{level}
		level = t.level or level
		--if t.identifier then t.identifier = util.Pad(t.identifier,12," ",true) end
		identifier = t.identifier or identifier
		log.identifier = identifier
		level = t.level or level
		log.level = level
		return
	elseif k=="level" then
		level = v or level -- can't be set to nil, so preserves prior value
		v = level
		return -- don't attempt to set on table
	elseif k=="identifier" and v then -- can't be set to nil, so preserves prior value
		identifier = v -- util.Pad(v,12," ",true)
		v = v or identifier
		return -- don't attempt to set on table
	end
	rawset(t,k,v)
end
local log = _G.log
local function getter(t,k)
	-- these values cannot be stored in the table itself, else our newindex metamethod cannot be used
	if k=="level" then return level
	elseif k=="identifier" then return identifier
	else return rawget(log,k)
	end
end
setmetatable(log,{__newindex=log.Options, __index=getter}) -- this allows assignments directly to log.identifier = "foo" and which are then propagated as upvalues to this environment's functions, whilst preserving the ability to also lookup the values which cannot be maintained in our log table (as there is no __updateindex)

return log
