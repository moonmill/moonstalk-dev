-- configuration routines for using the Tarantool envionrment, and Lua functions (aka stored procedures) for aggregation, conditional handling and normalisation (using the schema); tarantool servers are started from temporary files created by the elevator that then initialise themselves with this environment
-- includes a testing featurein debug mode that allows faking the server time anywhere now() is used, simply by setting tt.now_offset to a desired number of seconds; its value must be set to nil to restore normal time bearing in mind that tasks will have been scheduled further into the future; to force the task scheduler to run without waiting for the window to expire the fucntion that sets now_offset may after doing so create a dummy task.at=tt.now() thus forcing the scheduler to run
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

-- _G.json = require "json" -- {package=false}; this is the built-in cjson module, which allows passing a config with the encode (much better than the rocks cjson but not available in openresty thus we standardise per the generic app)
_G.fiber = require "fiber" -- {package=false}
_G.socket = require "socket" -- {package=false }-- tarantool provides its own socket module that is mostly compatible with LuaSocket
_G.fio = require"fio" -- {package=false}; built-in
_G.csv = require"csv" -- {package=false}; built-in
-- msgpack is loaded by functions
NULL = box.NULL
ERROR = "\0"

_G.tasks = { -- TODO: move to dedicated application
	-- NOTE: not to be confused with db.tasks[handler|id] = task -- provides task persistence and lookup; used to build the pending array after startup
	window	= 60, -- to check for new tasks, any new task needed sooner (at=0) involve killing the sleeping coroutine and recreating it to run immediately, therefore in high demand environments this should be set as low as possible, e.g. 1sec thus avoiding the need to cancel and recreate
	pending = {},
	errors = {},
	wakeup = now, -- time for lazy tasks to be run on next wakeup window
}
-- NOTE: tasks are initialised from persistence in Enabler; tasks may thus only be created from a Starter or later

function tasks.runner(task)
	-- WARNING: expects server to be using UTC (or a time zone without daylight savings changes) and does not use the monotonic fiber.clock; time localisation should be performed with client context
	-- runs as new fiber to prevent being cancelled with the scheduler, permitting safe use of fiber.yield -- TODO: test
	-- as an async task it will already have been removed from pending as this does not run until the next yield
	log.Info("running task "..task[1])
	task.finished = nil
	task.started = tt.now()
	task.scheduled = task.at -- allows introspection if rescheduled
	local result,error,failure = pcall(util.TablePath(task[1]), task)
	-- remove the task from pending as has now run and shoudl be rescheduled or removed
	task.finished = tt.now() -- timer only, does not indicate completed
	task.duration = task.finished - task.started
	task.started = nil
	if result and not failure then
		task.error = nil
	else
		task.error = error or failure
		tasks.errors[task.id or task[1]] = task
		moonstalk.Error{tt, level="Priority", title="task "..task[1].." failed", detail=err}
	end
	if task.scheduled ~=task.at then task.rescheduled = true end
	task.scheduled = nil
	if task.repeats or task.rescheduled then -- needs rescheduling (regardless of error)
		log.Debug("rescheduling task "..task[1])
		task.runs = (task.runs or 0) +1
		tasks.Schedule(task)
	else -- does not run again
		task.completed = true
	end
end
function tasks.scheduler()
	-- currently only supports a single task at a time
	-- tasks.pending is ephemeral and rebuilt on intitialisation (just after startup, when this first runs)
	-- TODO: support resource limits and concurrent tasks (i.e. scheduling a new task if the current is waiting on async actions such as webservices or processes), allow them to run concurrently rather than getting stuck in a single task queue); tasks would thus need to indcate async=false if not cooperative, else indicate their resource usage, e.g. http=1, cpu=1
	local pending = tasks.pending
	while true do
		local now = tt.now()
		local wakeup = now +tasks.window
		local task = pending[pending.count]
		local sleep
		if not task or task.at > wakeup then -- not due before next wakeup
			tasks.wakeup = wakeup
			fiber.sleep(tasks.window)
		elseif task.at <= now then -- due
			local pending = tasks.pending
			pending[pending.count] = nil
			pending.count = pending.count -1
			fiber.new(tasks.runner,task):name(task[1])
			fiber.yield() -- must yield after each task in case we have a big backlog
		else -- else task.at <= wakeup; due before next wakeup
			tasks.wakeup = now -task.at
			fiber.sleep(now -task.at)
		end
	end
end

function tasks.Persistent(task)
	-- initialise a task that persists and may thus be polled, preserves original if already created, thus only initialises if not existing; ephemeral tasks must be removed by their polling mechanism -- TODO: expiry task to remove completed tasks, probably using a tasks.expire window
	-- id = true to create a unique ID, or specify the identifier for polling instead of the handler name, e.g. when a handler is used by multiple individual tasks
	if db.tasks[task.id or task[1]] then return db.tasks[task.id or task[1]] end
	if task.id ==true then task.id = util.CreateID() end
	db.tasks[task.id or task[1]] = task
	task.persistent = true
	return tasks.Schedule(task)
end

function tasks.Schedule(task)
	-- WARNING: tasks must be given an ID if their handler is shared by multiple tasks
	-- {"namespace.Function", at=timestamp or repeats={hour=0,min=0}, async=false, keep=true}; at=nil to run at next wakeup (tasks.window); at=0 to run asap (after the next implict yield); repeat daily at the given hour (and min), the task may check days and dates and simply return if it is to skip execution
	-- rescheduling using task.repeats only applies if task.at is not changed, thus if changed will apply on the next run if not changed again
	-- handlers receive the task table as their only argument; tasks are removed after being run regardless of outcome, if the task has repeats it will be rescheduled, else it may change task.at =time.at+interval or a new timestamp, otherwise if it returns an error it will be kept for lookup
	-- handlers may return nil and an error message to fail
	-- handlers that fail are temporarily kept in the ephemeral tasks.errors table until restart -- TODO: error retry for non-repeating/non-rescheduled tasks
	-- handlers should use fiber.yield if carrying out multiple actions; handlers must not use sleep as this would sleep the scheduler itself
	-- handlers may pseudo-sleep by rescheduling themselves, returning nil; they may be interrupted or error and be retried; for all these they should simply set a state on themself, and check the state when run to resume appropriately
	-- TODO: mechanism for emphemeral tasks to be pollable, e.g. id=true;
	local now = tt.now()
	if task.repeats and not task.rescheduled then
		-- NOTE: currently we only handle hour daily; if not meant to run on a given day the task may simply return causing rescheduling to the next day
		local date = os.date"*t"
		date.hour = task.repeats.hour
		date.min = task.repeats.min or 0
		date.sec = 0 -- we currently onyl support minute resolution
		local at = os.time(date)
		if at >now then
			task.at = at
		else -- passed, schedule for tomorrow
			date.day = date.day +1
			task.at = os.time(date)
		end
	elseif not tasks.at then -- run immediately
		task.at = 0
	end
	log.Info("scheduling task "..task[1].." in "..(task.at - now).." secs")
	local pending = tasks.pending
	if pending.count ==0 or task.at <pending[pending.count].at then
		-- next to run, add to top
		pending[pending.count+1] = task
		if task.at <tasks.wakeup then
			log.Debug("restarting scheduler")
			tasks.scheduler_fiber:cancel() -- stops at first yield following this call
			tasks.scheduler_fiber = fiber.new(tasks.scheduler)
			tasks.scheduler_fiber:name"scheduler"
		end
	elseif task.at >= pending[1].at then
		-- last to run, add to bottom
		table.insert(pending,1,task)
	else
		-- iterate forwards to find the position; this assumes new tasks are added with a close at and rescheduled tasks are generally the oldest
		for i=1,pending.count do
			if task.at >pending[i].at then table.insert(pending,i,task); break end
		end
	end
	pending.count = pending.count +1
	return task
end

function tasks.Run(id)
	-- run a persistent task immediately; if repeats the original schedule will still apply else task.at is replaced and the task may reschedule
	-- id can be a handler name
	local task = db.tasks[id]
	local pending = tasks.pending
	for i=1,pending.count do
		if pending[i] ==task then
			table.remove(pending,i)
			pending.count = pending.count -1
			return tasks.runner(task)
		end
	end
	return nil,'unknown task'
end
-- TODO: tasks.Reschedule


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
	_G.now = nil -- remove so its use fallsback to a metatable
	setmetatable(_G,{__index=now_tarantool}) -- has no overhead as is only used when the lookup is nil, does have a minor overhead on values that can be nil as both tables must be checked, and the function invoked
	function now() -- more efficient than invoking _G.now via its metatable
		log.Debug() if node.environment ~="production" and tt.now_offset then return math_floor(fiber_time()) +tt.now_offset end -- debug feature
		return math_floor(fiber_time()) -- the only function that efficiently returns epoch time but with decimals for milli precision which we don't want, mainly for direct timestamp equivalence between different envionrments, whereas comparison is no issue, and also for CreateID which needs second precision though could be optimised to call math.floor itself, nonetheless consistency is better
	end
end

do local enabler = tarantool.Enabler
function Enabler()
	util.Shell = tarantool.Shell
	util.Encrypt = tarantool.Encrypt
	util.Decrypt = tarantool.Decrypt
	util.EncodeID = util.Encrypt -- OPTIMIZE: use a cheaper scheme than EcnryptID as this is used frequently to construct URLs containing ids
	util.DecodeID = util.Decrypt -- OPTIMIZE: use a cheaper scheme than EcnryptID as this is used frequently to construct URLs containing ids

	-- initialise from persistence
	local pending = tasks.pending
	local count = 0
	for _,task in pairs(db.tasks) do
		if not task.completed then
			count = count +1
			pending[count] = task
		end
	end
	pending.count = count
	util.SortArrayByKey(pending,"at")

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
			if not result then moonstalk.Error{bundle, title="Error loading Tarantool functions",detail=imported,class="lua", level="Notice"} end
		end
	end
end end

do local starter = tarantool.Starter -- preserve the original as we're replacing it
function Starter() -- replaces the default in functions
	tarantool.started = os.time()
	starter() -- run the original
	tasks.scheduler_fiber = fiber.new(tasks.scheduler)
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

do
local httpclient = require"http.client" -- {package=false} tarantool's builtin implicit async module
local function sync_err(result,err) return result,err end
_G.http = _G.http or {}
local urlencode = require"applications/moonstalk.tarantool/urlencode"
function http.Request(request) -- FIXME: update to use new .handler and defer behaviours (per openresty)
	-- request = {url="http://host:port/path", method="GET", headers={Name="value"}, timeout=millis, json={…}, body=[[text]], urlencoded={…}, async=true or function}
	-- method is optional, default is GET or POST with json, body or urlencoded
	-- all tarantool network operations are async with implict yields, however to support the explict behaviour in other environments we support the use of the async callback function, which will receive(response,err,request) thus the request table can be used to pass additional data; the additional defer=secs key-value may be sepcified however execution is not guarenteed if the server is restarted before this time has elapsed	-- TODO: support defer
	-- response.json is a table if the response content-type is application/json
	-- returns response,response.error -- NOTE: always use 'if response.error'
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
		request.body =urlencode.table(request.urlencoded) -- DEPRECATE: -- OPTIMISE: this is an expensive native function, tarantool should now include a native function though doesn't appear to be exposed, or use the curl native one
	elseif request.json then
		request.method = request.method or "POST"
		request.headers['Content-Type'] ="application/json"
		request.body =json.encode(request.json)
	end
	if request.ssl_verify ==false then
		request.verify_host = 0
		request.verify_peer = 0
	end
	request.method = request.method or "GET"
	log.Info(request.method.." "..request.url)
	log.Debug(request)
	local response,err = client:request(request.method, request.url, request.body, {headers=request.headers, timeout=request.timeout}) -- https://tarantool.org/en/doc/1.7/reference/reference_lua/http.html
	if err then request.error = err; log.Alert(err) return (request.async or sync_err)(nil,err) end
	if string.sub(response.headers['content-type'] or '',1,16) =="application/json" then
		response.json,err = json.decode(response.body)
		if err then response.error = err; log.Alert(response); return (request.async or sync_err)(response,"JSON: "..err) end
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
_G.util.b64 = encode
local decode = digest.base64_decode
_G.util.unb64 = decode
_G.crypto =  require "crypto" -- {package=false} -- bundled
local encrypt = digest.aes256cbc.encrypt
local decrypt = digest.aes256cbc.decrypt
function Encrypt(value)
	-- encrypt (aes-256-cbc); base64; substitutes chars (for URL safety)
	return string_gsub( encode( encrypt(value, secret, iv) ),
			"[/+]",{['/']="~",['+']="-"})
end
function Decrypt(value)
	-- NOTE: this is an exposed method as it handles any incoming token value
	if not value then return end
	return decrypt( decode(string_gsub( value,"[~-]", {['~']="/",['-']="+"} )), secret, iv )
end
end

do local popen = require"popen" -- {package=false}; bundled
local stderr = {stderr=true}
function Shell(command,options) -- does not support read limits/lines
	local shell = popen.shell(command,"r")
	local result,err = shell:read()
	-- TODO: some kind of stderr detection
	shell:close()
	if result=="" then return end
	return result
end end