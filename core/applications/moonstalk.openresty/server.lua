if not moonstalk then -- first call initialises Moonstalk; this is an extremely lightweight check of initialisation to perform with each request without using the only slightly more expensive require mechanism
	setmetatable(_G,nil) -- temporarily remove openresty's default warning about setting globals whilst moonstalk and its applications initialise themselves in it, this is replaced with our own in the openresty Starter; see functions
	dofile "core/moonstalk/server.lua"
	moonstalk.Initialise{server="scribe"} -- TODO: node.scribe.server=="openresty"
end

if not pcall(scribe.Request, openresty.Request()) then scribe.Errored() end -- we catch errors, however without a traceback we know nothing about what caused it -- FIXME: given that runtime errors should be extremely rare, would be better to eliminate the pcall and just use a generic error page rather than handling in moonstalk

openresty.Respond()
