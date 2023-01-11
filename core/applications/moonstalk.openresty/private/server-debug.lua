if not moonstalk then
	setmetatable(_G,nil)
	dofile "core/moonstalk/server.lua"
	moonstalk.Initialise{server="scribe",scribe="openresty",exit=false}
end

openresty.Request()
local result,error,trace = pcall(scribe.Request,debug.traceback) -- dev mode; we don't just catch errors, but give them a traceback
if not result then log.Alert(error) scribe.Errored(error,trace) end
openresty.Respond()
