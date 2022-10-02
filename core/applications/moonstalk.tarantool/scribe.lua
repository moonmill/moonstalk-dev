-- NOTE: currently only supports openresty
-- TODO: add support for plain Lua and move to client.lua, enabling in functions

msgpack.NULL = "\xc0" -- FIXME: ???

tarantool.client = require"moonstalk.tarantool/client" -- WAS: package="lua-resty-tarantool"
local tarantool_client = tarantool.client

local function Error(err,detail)
	if type(err) ~='table' then err = {tarantool, title=err, level="Notice"} end
	err.detail = err.detail or detail
	return scribe.Error(err)
end

function tarantool.Connect(interface)
	if request[interface] then request[interface]:close() end
	local result,err
	request[interface],err = ngx.socket.tcp()
	if err then return moonstalk.Error{tarantool, level="Priority", title="socket error: "..err} end
	interface.connected = now
	-- request[interface]:settimeout(1000) -- HACK: this fixed the frequent corrupted msgpack transactions, but is only used for the initial connection on server startup
	result,err = tarantool_client.connect(interface)
	if not result then return moonstalk.Error{tarantool, level="Notice", title="connection failure with "..interface.role, detail=err} end
	return true
end

if moonstalk.initialise.coroutines ~=false then
	-- for async coroutine servers network calls must preserve the global environment
	local function TarantoolServerMethod(interface,method,is_retry,...)
		-- generic handler for running application server methods is wrapped by moonstalk.Resune, with an upvalue for the method function itself
		-- in case of error, a scribe.Error is generated, and we return nil,err just as the procedure should also do
		-- procedure functions may only return two paramters
		-- TODO: options to throw (preventing return/continuation), or not generate the error for handling by the routine
		-- unfortunately we have to do this with every query, even when sequential in the same request, as apparently reusing the socket is not possible -- OPTIMIZE: storing the server connection object in request[interface] = server is not reusable however the references may have been incorrect when original tested, for now we recreate the socket
		local server,err = ngx.socket.tcp()
		local result,err = server:connect(interface.host, interface.port, interface.socket_options)
		if not result then return Error("database connection failure to "..interface.role, err) end
		request[interface] = server -- FIXME: remove this in the client
		if server:getreusedtimes() ==0 then -- connection is freshly established, the server probably restarted, else the connection has been in the pool a while
			-- technically if we called tarantool.connect each time teh handshake and authentication woudl be transparently handled for us, albeit at teh cost of invoking serveral additional functions thus we've hoisted that functionality inline here
			-- request[interface]:settimeout(1000) -- HACK: this fixed the frequent corrupted msgpack transactions, but is only used for the initial connection on server startup
			result,err = tarantool_client.handshake(interface)
			if not result then return Error("database reconnection failure to "..interface.role, err) end
			log.Info("[re]connected to Tarantool instance '"..interface.role.."'") -- TODO: indicate reconnection
		end
		if interface.table then
			result,err = method(interface, interface.table, ...)
		else
			result,err = method(interface, ...)
		end
		if err =="closed" and not is_retry then
			-- retry to establish a new socket and connection
			log.Info("retrying connection to Tarantool instance '"..interface.role.."' due to: "..err)
			server:close()
			result = {tarantool.ServerMethod(interface,method,true,...)} -- result is expected to be a table for continuation
		end
		if result ==nil then
			--[[ -- FIXME: 
			local method = tarantool.methods[method]
			if method =="call" then method = pack(...)[1]
			elseif interface.table then method = method .." for "..interface.table end
			--]]
			method = pack(...)[1] or interface.table or ""
			return Error("procedure "..method.." failed on "..interface.role, err)
		end
		log.Debug(result)
		server:setkeepalive(0) -- return to pool with indefinate keep-alive
		return result[1],result[2]
	end

	local moonstalk_Resume = moonstalk.Resume
	tarantool.methods = {} -- holds server methods that we'll copy to each interface with Serve
	for name,kind in pairs{connect="server", disconnect="server", call="server", eval="server", ping="server", insert="table", upsert="table", select="table", replace="table", update="table", delete="table"} do
		do
			local method = tarantool.client[name]
			local moonstalk_Resume = moonstalk.Resume
			tarantool.methods[name] = function(interface, ...) return moonstalk_Resume(TarantoolServerMethod, interface, method, nil, ...) end
			tarantool.methods[tarantool.methods[name]] = name -- for introspection
		end
	end
	local tarantool_client_call = tarantool.client.call
	tarantool.methods.call = function(interface,procedure,...)
		log.Debug("calling tarantool procedure "..procedure)
		local arg = {...}; if not arg[1] then arg = nil end
		return moonstalk_Resume(TarantoolServerMethod, interface, tarantool_client_call, nil, procedure, arg)
		--return result[1],result[2]
	end
end


for _,bundle in pairs(moonstalk.applications) do
	-- TODO: only if there's a default server
	if bundle.files["tarantool.lua"] then
		-- are imported in server but we must parse the file for function name declrations to enable as proxies, because compiling tarantool files is not possible outside its environment
		local data,err = util.FileRead(bundle.files["tarantool.lua"].path)
		if not data then return moonstalk.Error{bundle, title="Error reading functions for Tarantool",detail=err} end
		for name in string.gmatch(data,"function ([^( ]+)") do
			if not string.find(name,".",1,true) then
				if bundle[name] then
					if not moonstalk.reserved[name] then
						log.Debug("  procedure does not replace function: "..bundle.id.."."..name)
					end
				else
					log.Debug("  procedure: "..bundle.id.."."..name)
					do local procedure = name; bundle[procedure] = function(...) return tt.default(bundle.id.."."..procedure,...) end end
				end
			end
		end
	end
end

function tarantool.Manifest(group,all)
	-- returns a table of updates (assignments or removals) with normalised and validated input if the form has changed it; field names must be namespaced and the updates will be returned in a subtable corresponding to the namespace, thus updates for multiple spaces (different namespaces) may be received from a single form
	-- Tarantool specific behaviour is use of .tuple=field_number attribute, which if present and if a value assignment (e.g. any key or subtable key) has changed, then an array of Tarantool updates will be returned per namespace
	-- when used as {"namespace.key" origin=table, tuple=n} the value assigned to the tuple will be table[key] (the second part of the namespace regardless of depth) unless tuple_value=anytable.subtable is specified
	-- if origin is not specified, the value will be the corresponding normalised input value
	-- NOTE: aggregate records aren't deleted and are just saved as empty tables (arrays)

	local changed = {}
	local changes = {}
	local table_insert = table.insert
	local type = type
	local util_TablePathAssign = util.TablePathAssign
	local util_TablePath = util.TablePath
	local string_match = string.match
	for _,validation in ipairs(page._validation) do
		if validation.groups and validation.groups[group] and (all or validation.changed) then
			local value = validation.value
			if validation.normalise then value = validation.returned end
			changed[validation[1]] = true
			local namespace,path = string_match(validation[1], "([^%.]+)%.(.*)")
			if path then -- we don't support without namespace
				local subtable = string_match(path, "([^%.]+)")
				local tuplespace = namespace..(validation.tuple or"")
				if validation.origin then
					-- update the changed value in the table
					util_TablePathAssign(validation.origin, path, value)
					changed[validation.origin] = true
					changed[namespace] = true
					changed[namespace.."."..subtable] = true
				end
				if validation.origin and validation.tuple then
					-- origin maps to a tuple
					if not changed[tuplespace] then
						changes[namespace] = changes[namespace] or {}
						table_insert(changes[namespace], {"=", validation.tuple, validation.tuple_value or validation.origin[subtable]})
						changed[validation.origin[subtable]] = true
						changed[tuplespace] = true
					end
				elseif validation.tuple then
					-- form field maps directly to a tuple field
					if not changed[tuplespace] then
						changes[namespace] = changes[namespace] or {}
						table_insert(changes[namespace], {ifthen(validation.returned,"=","#"), validation.tuple, validation.tuple_value or value})
						changed[tuplespace] = true
					end
				elseif validation.destination ~=false then
					-- aggregate form fields into a table, same as normal manifest behaviour
					if type(validation.destination)=='string' then
						changes[namespace] = changes[namespace] or {}
						util_TablePathAssign(changes[namespace],validation.destination,validation.origin[validation.destination])
					else
						changes[namespace] = changes[namespace] or {}
						util_TablePathAssign(changes[namespace],path,value)
					end
				end
			end
		 end
	end
	return changes,changed
end

-- the Run function is multipurpose and wraps a meta behaviour that includes cache updates; procedures called using this method may return whatever they want
-- the protocol uses msgpack and directly encodes the tarantool tuple, in the consuming client we can either access this directly, or normalise it into a table of fieldnames; this makes transfer from the database efficient, at the cost of normalisation in the client; further if a tarantool process has acted upon the record, and also normalised it, the cost is doubled unless that normalised result is returned as it would not then need normalisation in the client, but at the costs of a larger payload for transfer
-- WARNING: tarantool procedures must return some value explictly, e.g. return true; failure to return anything will actually generate an error as it is not actually the same as return nil
-- WARNING: procedures cannot return an array, and should instead use {result=array}
-- TODO: typically workload should be evenly distributed amongst clients thus even if one is not invoked for 30 mins it can only have updates * clients in its queue thus is not going to be an issue unless some workers are very slow or there are hundreds; in this case we could use a moonstalk.databases.cache_purge = mins value (default 5 mins?) with timer in each worker that recreates itself once done to repeat, this calls a dummy db.CachePurge() procedure that results in any outstanding cached itsems being returned; which ensures that when a real client call is made it's not slowed down by an unreasonably large cache payload; the tarantool server would also use cache_purge to remove old items from its queue instead of tracking subscriptions (a broken connection that is reestablished >cache_purge would be an issue, so in this scenario the cache would have to be purged and reintialised in the client just as at startup)


--[=[
function tarantool.Run(server,name,...)
	-- TODO: add a summary of requests and repsonses to request.sub for debugging
	log.Info("Running procedure: "..name)
	server = tarantool[server]
	local connection,result,err
	connection,err = server:connect()
	if err then return nil,err end -- TODO: retry
	--result,err = connection:call("Debug",{name,...})
	result = pack( connection:call(name,...) )
log.Debug(result)
	-- return; result=nil -- this is not supported, all procedures must return some value
	-- return nil; result = {}
	-- return nil,'error'; result = {nil} err= {'error'}
	-- return {"one","two","three"}; result= {"one","two","three"} -- arrays are not supported as return values as hard to distinguish from dicts
	-- return {foo="bar"}; result={{foo="bar"}}
	-- TODO: auto-retry another db when connection dropped/reset
	--connection:set_keepalive() -- FIXME: in nginx there are context switches (coroutine yields) after sockets are written to, and the coroutine (a request) does not resume until a read is possible thus we lose the context and sockets are automatically closed, therefore whenever using sockets we must call set_keepalive to maintain them in a pool rather than closing and reopening them between calls in the same request or even different requests
	if err then
		if result ~=nil then
			return result[1],err[1]
		else
			Error{title="Error with "..(name or "unspecified").." procedure", detail=err}; return nil,err
		end
	end
	return result[1]
end
--]=]
