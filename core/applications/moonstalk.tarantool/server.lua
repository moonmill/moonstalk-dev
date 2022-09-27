-- configuration routines for using the Tarantool envionrment, and Lua functions (aka stored procedures) for aggregation, conditional handling and normalisation (using the schema); tarantool servers are started from temporary files created by the elevator that then initialise themselves with this environment
-- WARNING: returns that are empty tables are discarded by the Tarantool protocol encoding, use return {n=0} or somesuch
-- NOTE: do not return with no parameters, use return nil
-- NOTE: tuples are constants representing the in-memory msgpack data, thus efficient to read from; some of our procedures modify need to modify Lua tables, such as when using _updates, in which cases only reading from these and recoding for Lua is more efficient with only the needed fields, than doing so for all a tuples fields
--[[
Caching:
	when procedures update cached table values they much add them to the cache, e.g. table.insert(cache,)

--]]

-- # configure and enable the server environment
-- NOTE: the server envionrment is already running, but this file is loaded by the Enabler in functions thus this inline code is equivalent to the Enabler; any errors are non-breaking as the server is already running, thus moonstalk applications in this envionrment may not be fully functional
-- TODO: capability to reinitialise moonstalk in case of errors, so we don't have to restart
moonstalk.instance = node.tarantool.instance or "999" -- FIXME:

_G.json = require "json" -- {package=false}; this is the built-in cjson module, which we use in favour of the rocks one as it has some tweaks
_G.fiber = require "fiber" -- {package=false}
_G.socket = require "socket" -- {package=false }-- tarantool provides its own socket module that is mostly compatible with LuaSocket
_G.fio = require"fio" -- {package=false}; built-in
_G.csv = require"csv" -- {package=false}; built-in
-- msgpack is loaded by functions
NULL = box.NULL
ERROR = "\0"

print = box.session.push -- else goes to log, but in Moonstalk we use explict log functions

cache = {}
map = function(t) return setmetatable(t or {}, {__serialize='map'}) end

box.ctl.on_shutdown(moonstalk.Shutdown)
box.session.on_connect(function() log.Info("new client connected: "..box.session.id()) end)
box.session.on_disconnect(function() log.Info("client disconnected: "..box.session.id()) end)

do
	-- the standard moonstalk behaviour is for now to simply be to a key populated and cached per request (and at startup thus removing it to enable the metatable invocation), however in Tarantool we have no call invocation with which to populate it, native (tarantool.lua) functions should instead call tarantool.now() which returns a cached result to avoid the metamethod overhead, yet this otherwise provides the expected behaviour for multi-server/generic functions referencing now; use of fiber.time directly is not advised as it uses decimals for higher resolution
	local fiber_time = fiber.time -- usually gives 4 deciamls
	local math_floor = math.floor
	local now_tarantool = function(_,key) if key=="now" then return math_floor(fiber_time()) end end
	_G.now = nil
	setmetatable(_G,{__index=now_tarantool})
	function now() -- more efficient than invoking _G.now via its metatable, and the only function that efficiently returns epoch time 
		return math_floor(fiber_time())
	end
end

do local enabler = tarantool.Enabler
function Enabler()
	enabler()
	if not box.space._user.index.name:get{"moonstalk"} then
		box.schema.user.create("moonstalk", {password=node.secret})
		box.schema.user.grant("moonstalk", "read,write,execute", "universe")
	end
	local crud_methods = getmetatable(box.space._user).__index
	for name,table in pairs(tarantool._tables) do
		if table.role ==moonstalk.initialise.tarantool.role then
			if not box.space[table.name] then
				log.Info("  creating table "..table.name)
				box.schema.space.create(table.name) -- table contains format, and may contain other flags
			end
			box.space[name]:format(table.format) -- this will update each startup, however any new fields must specify is_nullable=false
			table.indexes = table.indexes or {name="primary", type="tree", parts={{field=1,type="scalar"}}} -- create a primary index
			for i,index in ipairs(table.indexes) do
				-- TODO: check for new indexes; check for changed indexes (add a version to each, which is also persisted in Tarantool, then delete and recreate if newer
				if index.sequence ==true then index.sequence = name end
				if index.sequence and not box.sequence[index.sequence] then box.schema.sequence.create(index.sequence) end
				if not box.space[table.name].index[index.name] then
					local result,error = pcall(crud_methods.create_index, box.space[table.name], index.name, index)
					if not result then moonstalk.Error{tarantool, title="Error in table "..name.." index "..(index.name or i), detail=error} end -- FIXME: remove 
				end
			end
		end
	end
	for _,bundle in pairs(moonstalk.applications) do
		if bundle.files["tarantool.lua"] then
			local result,imported = pcall(util.ImportLuaFile, bundle.path.."/tarantool.lua", bundle)
			if not result then moonstalk.Error{bundle, title="Error loading Tarantool functions",detail=imported,class="lua"} end
		end
	end
end end

do local starter = tarantool.Starter -- preserve the original as we're replacing it
function Starter() -- replaces the default in functions
	tarantool.started = os.time()
	starter() -- run the original
	--[=[ FIXME: TEST:
	_G.task = {
		pending={[0]={scheduled=999999999999999,default=true},count=0}, -- reverse order with lowest number last, so easy to remove and add new items to end for consumption; 0-position item is not sorted and remains as default
	}
	do
	local scheduler -- the fiber
	local window = 10 -- every x seconds to check for new tasks, any new tasks sooner involve killing the coroutine and recreating it to reschedule it, therefore in high demand environments this should be set as low as possible, e.g. 1
	local pending = task.pending -- must be kept sorted with oldest (lowest numbered) at top
	local scheduled = 0
		function Scheduler()
			local now,next
			while true do
				now = os.time()
				next = pending[pending.count]
				if next.scheduled >= now then
					if not next.handler() then -- run the next task; must return true to preserve
						pending[pending.count] = nil -- remove the task as completed
						pending.count = pending.count -1
					end
					fiber.yield() -- must yield after each task in case we have a big backlog
				elseif next.scheduled < now +window then
					fiber.sleep(now - next.scheduled)
				else
					fiber.sleep(window)
				end
			end
		end
		function task.Schedule(event)
			table.insert(pending,event)
			util.SortArrayByKey(pending,"scheduled",true)
			--box.space.tasks:insert(event)
			if event.scheduled < next_event then
				-- need to run sooner
				scheduler:kill()
				scheduler = fiber.create(Scheduler)
			end
		end
	scheduler = fiber.create(Scheduler)
	end
	--]=]
end end


-- # database functions

function Get(table,key,fieldset)
	return box.space[table]:get(key) -- TODO: trim to fieldset
end

function GetGlobal(key)
	-- TODO: needs to simply be an interface on the client database table
	log.Append(util.TablePath(key) or "NONE")
	return util.TablePath(key)
end

do local string_match =string.match
function Run(updated,name,...)
	local app,func = string_match(name,"^([^%.])%.(.+))")
	local result,response,error = pcall(_G[app][func],...)
	if not result then error = response; response = nil end
	-- if updated < cache and cache.cleaning ~=false then
	-- 		fiber.create(tarantool.CleanCache)
	-- end
	return {response,error}
end end


-- Caching
-- cached namespaces are two-part and take the form namespace[objectid]

do local table_insert = table.insert
local cache = cache
function Cache(path,object)
	-- object is expected to be a tuple
	cache.serial = cache.serial +1
	object._cached = cache.serial
	object._name = name
	table_insert(cache,{cache.serial,path,value})
end end

function CacheUpdates(since)
	if cache.serial <= since then return end
	local updates = {serial=cache.serial}
	local count = 0
	for i=#cache,1,-1 do
		local update = cache[i]
		if update.serial <=since then break end -- OPTIMIZE: currently returning updates in reverse order to avoid having to iterate all older updates; with persistent connections can record the last position and do away with the serial; resetting all positions to 1 upon purge
		count = count+1
		updates[count] = {update.path,update.value}
	end
	return updates
end

function CachePurge()
	-- this purges old values from the queue by re-creating the queue as removing items from the bottom of the table one by one is slow
	local clean_cache = {}
	local count = 0
	local expire = now -300
	for _,item in ipairs(cache) do
		if item._cached > expire then
			count = count+1
			clean_cache[count] = item
		end
	end
	cache = clean_cache
	_G.cache = clean_cache
end

function CacheGet(ns)
	return box.space[ns[1]]:get(ns[2])
end

function Connected(client)
	-- populate a client cache for the first time by calling all declared cache handlers
	local cached = {}
	for name,handler in pairs(cache) do
		cached[name] = handler()
	end
	return cached
end

function Ping()
	-- used by elevator to check status -- TODO:
	return "pong"
end

do local type = type
function table.update(from,to)
	-- similar to copy() but without the additional options and accepting null ("\0") values for removals
	-- tables in from will be created in to if missing
	for k,v in pairs(from) do
		if v =="\0" then -- remove value
			to[k] = nil
		elseif type(v) =='table' then -- recurse
			if not to[k] then to[k] = {} end -- new table
			table.update(v,to[k])
		else -- assign new value
			to[k] = v
		end
	end
end end

function Stats()
	local stats = box.stat.net()
	return {started=tarantool.started, connections=stats.CONNECTIONS.current, rps=stats.REQUESTS.rps, total=stats.REQUESTS.total}
end


-- # Abstractions

do local httpclient = require"http.client" -- {package=false} tarantool's builtin implicit async module
local function sync_err(result,err) return result,err end
_G.http = _G.http or {}
function http.Request(request) -- FIXME: update to use new .handler and defer behaviours (per openresty)
	-- request = {url="http://host:port/path", method="GET", headers={Name="value"}, timeout=millis, json={…}, body=[[text]], urlencoded={…}, async=true or function}
	-- method is optional, default is GET or POST with json, body or urlencoded
	-- all tarantool network operations are async with implict yields, however to support the explict behaviour in other environments we support the use of the async callback function, which will receive(response,err,request) thus the request table can be used to pass additional data; the additional defer=secs key-value may be sepcified however execution is not guarenteed if the server is restarted before this time has elapsed	-- TODO: support defer
	-- response.json is a table if the response content-type is application/json
	-- returns response,error -- NOTE: always use 'if err' not 'if not response' as the response object may nonetheless be returned with an error such as if it could not be decoded
	-- if run async the calling function is responsible for handling errors, otherwise if logging >1 the error consumer can utilise request.sub (an array of all sub request and response tables) to inspect details
	request.scheme,request.host,request.port,request.path = string.match(request.url,"^(.-)://([^:/]*):?([^/]*)(.*)")
	request.path = request.path or "/"
	if request.port =="" then request.port = nil end
	if request.timeout then request.timeout = request.timeout/1000 end
	local client = httpclient.new()
	-- TODO: request.query from table
	request.headers = request.headers or {}
	if request.urlencoded then
		request.method ="POST"
		request.headers['Content-Type'] = "application/x-www-form-urlencoded"
		request.body =ngx.encode_args(request.urlencoded) -- TODO: server neutral
	elseif request.json then
		request.method = request.method or "POST"
		request.headers['Content-Type'] ="application/json"
		request.body =json.encode(request.json)
	end
	request.method = request.method or "GET"
	log.Info(request.method.." "..request.url)
	log.Debug(request)
	local response,err = client:request(request.method, request.url, request.body, {headers=request.headers, timeout=request.timeout}) -- https://tarantool.org/en/doc/1.7/reference/reference_lua/http.html
	if err then log.Alert(err) return (request.async or sync_err)(nil,err) end
	if response.headers['content-type'] =="application/json" then
		response.json,err = json.decode(response.body)
		if err then response._err = err; log.Alert(response); return (request.async or sync_err)(response,"JSON: "..err) end
	end
	if request and logging >1 then
		-- keep a record in case there's a subsequent error
		request.sub = request.sub or {}
		table.insert(request.sub, {request= request, response =response})
	end
	log.Info(response)
	if type(request.async) =='function' then request.async(response,nil,request) end
	return response
end end

do
	-- NOTE: these routines are typically isolated in their use for public exposure of internal references and values (such as IDs, thus preventing iteration of them), thus each server's implementation need not be compatible except where encrypted values are exchanged between servers, however these should generally be handled using a dedicated scheme and user-specific salt and/or IV 
local secret = node.secret
local iv = string.sub(node.secret,-16)
local string_gsub = string.gsub
_G.digest = require "digest" -- {package=false} -- bundled
local encode = digest.base64_encode
local decode = digest.base64_decode
_G.crypto =  require "crypto" -- {package=false} -- bundled
local encrypt = digest.aes256cbc.encrypt
local decrypt = digest.aes256cbc.decrypt
function util.Encrypt(value)
	-- encrypt (aes-256-cbc); base64; substitutes chars (for URL safety)
	return string_gsub( encode( encrypt(value, secret, iv) ),
			"[/+]",{['/']="~",['+']="-"})
end
function util.Decrypt(value)
	-- NOTE: this is an exposed method as it handles any incoming token value
	if not value then return end
	return decrypt( decode(string_gsub( value,"[~-]", {['~']="/",['-']="+"} )), secret, iv )
end
end
util.EncodeID = util.Encrypt -- OPTIMIZE: use a cheaper scheme than EcnryptID as this is used frequently to construct URLs containing ids
util.DecodeID = util.Decrypt -- OPTIMIZE: use a cheaper scheme than EcnryptID as this is used frequently to construct URLs containing ids
