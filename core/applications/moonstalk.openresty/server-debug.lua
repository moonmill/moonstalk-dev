if not moonstalk then
	setmetatable(_G,nil)
	dofile "core/moonstalk/server.lua"
	moonstalk.Initialise{server="scribe"}
end

local result,error = xpcall(scribe.Request, debug.traceback, openresty.Request()) -- dev mode; we don't just catch errors, but give them a traceback
if not result then scribe.Errored(error,true) end

openresty.Respond()
