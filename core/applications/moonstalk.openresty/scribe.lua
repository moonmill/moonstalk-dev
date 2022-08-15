-- REFACTOR: use scribe.lua
-- NOTE: the _G.now timestamp is only updated upon a new request, therefore any function not invoked directly from the request cycle must instead call ngx.now()
-- WARNING: any function that calls an async operation MUST use moonstalk.Resume(function,…) which preserves and restore the global Moonstalk tables that change with every request (notably the request table itself), and so if they are to be consumed after a possible yield (request context change such as a database call), the use of moonstalk.Resume is required to preserve the context, and simply restores these tables after such context changes (albeit at a small cost)
-- WARNING: failure to use moonstalk.Resume but instead directly call an async function then use values from session globals request/session/user/etc WILL result in these referencing a different request/session/user/etc, thus resulting in a dangerous situation in which you will consume or leak the wrong data
-- applications may create globals only in their Starter or prior (inline in functions or settings with explict refernces to _G.), any attempt to define a global thereafter will result in an error
-- applications may add per-request global tables however this is generally not recommended as adds to the cost of the Resume function; moonstalk.globals[name]=true and this table will then be maintained across async calls, but MUST be initialised with each request, e.g. _G[name] = {} in a Curator, Collator or controller
-- NOTE: in high demand production, logging should be reduced to an essential value preferably avoiding any output, as even a single logged item involves using a blocking io.popen call to write to the log file, this is however done through a retained connection to a tee daemon thus does not itself have further blocking -- TODO: replace logger with ngx.pipe but will require wrapping with Resume(!)
-- NOTE: moonstalk is not currently designed for large numbers of concurrent long-lived connections (websockets) though can handle them albeit requiring more memory versus simple use of openresty out of the box, in which each persistent connection may only use a few upvalues (stack registers); for each request moonstalk initialises multiple tables with multiple values that may not be needed, which when yielded are also only kept in a stack, however must be iterated prior and post yield, to store from and reassign to the global table, plus involve multiple stacks (content_by_lua->pcall->scribe.Request<->handler<->yielding_handler<->Resume<->yield; handler typically being a controller or view, and yielding_handler typically a database or other network function called from within it) thus are significantly more expensive to keep in memory

if moonstalk.server ~="scribe" then if node.scribe.server ~="openresty" then log.Notice([[Openresty is not enabled because scribe.server="]]..node.scribe.server..[["]]) end return end

scribe.instance = ngx.shared.moonstalk:incr("worker",1,0) -- NOTE: dictionaries persist with reloads thus unless this is overridden by an application that registers with a cluster, worker ids increments with each reload and do not get reused
moonstalk.SetInstance(scribe.instance)
ngx.shared.moonstalk:incr("workers",1,0) -- active count is decremented on termination of a worker e.g. during reload or shutdown

function Shutdown() -- TODO: this really needs to be guarenteed last as otherwise logging and references will refer to an id that may already have been reassigned to another worker
	ngx.shared.moonstalk:incr("workers",-1)
	--ngx.shared.moonstalk:set("worker_"..scribe.instance, false) -- now deallocated out of use
end

_G.sleep = ngx.sleep
_G.socket = ngx.socket
DNSResolver = require"resty.dns.resolver" -- {package=false}

do
	local resty_string = require "resty.string" -- {package=false}; bundled
	local resty_sha1 = require "resty.sha1" -- {package=false}; bundled
_G.util.sha1 = function(var) -- TODO: implement generic version for other servers and let this be an override
	local sha1 = resty_sha1:new()
	sha1:update(var)
	var = sha1:final()
	return resty_string.to_hex(var)
end end
_G.util.b64 = ngx.encode_base64 -- faster than mime
_G.util.unb64 = ngx.decode_base64

multipart = { -- can be changed globally by setting openresty.multipart[key] or simply pass changed values to openresty.GetPost{max_file_size=10000000, timeout=30000}
	tmp_dir          = "temporary/upload",
	timeout          = 1000, -- millisecs
	chunk_size       = 4096,
	max_get_args     = 50,
	mas_post_args    = 50,
	max_line_size    = 512,
	max_file_size    = 100000000, -- bytes / 100MB; this is somewhat redundant as address.post.maxsize applies, however this applies to individual files thus might be set to a lower value if needed
	max_file_uploads = 1,
}
requests = 0 -- concurrent requests, e.g. when a coroutine or Resume is used during a request, another waiting one will start processing -- TODO: NOTE: will not decrement in case of an abort, need a method to solve this

do
	-- for future delayed callbacks use a task
	local function unpremature(_,callback,...)
		callback(...)
	end
	function Async(callback,...)
		-- use when the execution time is immediate and the premature param will not be given to the callback function; else call ngx.timer.at and handle the premature param correctly to persist state
		-- does not yield immediately, executes upon next yield, thus does not need to be wrapped
		-- TODO: name is misleading as all requests are async, should really be openresty.Decouple
		return ngx.timer.at(0,unpremature,callback,...)
	end
end

function Request()
	-- placeholder until server has finished starting as Nginx can handle and respond to requests before Moonstalk itself is configured and ready
	ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
	ngx.header['content-type'] = "text/html"
	ngx.print([[<hml><body><h1>The server is starting up</h1><p>We'll try again in a few seconds...</p><script>window.setTimeout(location.reload,2000)</script></body></html>]])
	ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

function Enabler()
	-- replace default handlers -- FIXME: we need a better way to do this, perhaps a moonstalk.StartServer function that can be called before enablers which may need to use http and other handlers
	scribe.Respond = Respond
	scribe.GetPost = openresty.GetPost
	http.Request = openresty.http_Request
	http.New = openresty.http_New
	http.Save = openresty.http_Save
	if email then
		-- NOTE: the following must normally be declared in a Starter as the order of application loading is unknown, however here we are overloading a core application that is guaranteed already loaded
		_G.smtp = require"resty.smtp" -- {package="resty-smtp"}
		_G.mime = require"resty.smtp.mime" -- {package=false}
		_G.ltn12 = require"resty.smtp.ltn12" -- {package=false}
		email._Dispatch = email.Dispatch -- preserve so we can still use it
		email.Dispatch = openresty.EmailDispatch -- replace with wrapped version that uses a coroutine or Resume
		email.ResolveMX = openresty.ResolveMX
	end
end
function Starter()
	return function() -- a finaliser, we can't use the Starter function itself as we don't know what other starters are still doing
	if node.dev and logging >3 then
		-- in debug mode we catch attempts to set errant globals, only being valid for creation prior to applications being started; must be configured here in the Starter as Enablers may create new globals
		scribe._globalcheck = {} -- to keep track of what we've already warned about to avoid recurrence with every request
		local meta = {}
		meta.__newindex=function(_,key,value)
			if not moonstalk.globals[key] and not scribe._globalcheck[key] then
				scribe._globalcheck[key] = true -- stop warning about this
				scribe.Error("Attempt to set a rogue global: ‘"..key.."’")
				moonstalk.BundleError(moonstalk,{realm="bundle",title="Attempt to set a rogue global: '"..key.."'"}) -- FIXME: detail= first seen in view/controller etc
			end
		end
		setmetatable(_G, meta)
	end
	if email then
		ngx.timer.every(300, email.Queue) -- no need to wrap as timers are assumed to maintain their own environment also this doesn't take arguments
		ngx.timer.every(86400, function(premature) if premature then moonstalk.Shutdown() end end) -- catches shutdown; applications must declare a Shutdown function which will be invoked by this one -- TODO: somehow enable this to run only after all other premature handlers are executued
	end
	openresty.Request = openresty._Request -- we must only handle requests after the moonstalk environment is fully ready which includes other Starters, thus we return an anonymous finaliser that is run only once all starters have completed
	openresty._Request = nil
	util.FileRead = openresty._util_FileRead
end end

local moonstalk_Resume = moonstalk.Resume
do
local reqargs = require"resty.reqargs" -- {package="lua-resty-reqargs"}
local ngx_req_get_post_args = ngx.req.get_post_args
local ngx_req_read_body = ngx.req.read_body
local util_MergeIf = util.MergeIf
local pairs = pairs
function GetPost()
	-- multipart_options = false to parse only urlencoded (e.g. for lighweight payloads such as signin)
	-- transparently handles file buffering to disk, which can also be configured in nginx.conf per https://github.com/bungle/lua-resty-reqargs
	-- check request.form._error or the second return argument
	-- causes processing to wait for the body to be received (it is thus preferable to call after having performed authentication and otehr preparatory database calls once more or all of the body is likely to have been received, e.g. call it from a controller)
	local request = _G.request
	if request.type =="application/x-www-form-urlencoded" then
		local foo,bar = moonstalk_Resume(ngx_req_read_body) -- async function (as can be invoked before the full payload has been received)
		local form,err = ngx_req_get_post_args()
		if err then scribe.Error{realm="form",title="Reqargs urlencoded form error: "..err} end -- TODO: option to not throw
		-- errors are only typical if client_body_buffer_size and client_max_body_size do not match
		request.form = form
	elseif request.type =="multipart/form-data" then
		local multipart_options = util_MergeIf(openresty.multipart, page.post)
		local get,form,files = moonstalk_Resume(reqargs, multipart_options)
		if not get and form then scribe.Error{realm="form",title="Multipart upload error: "..form} end -- nil,error -- TODO: option to not throw
		request.form = form
		if files then
			for key,item in pairs(files) do -- TODO: create a timer function/worker that removes these files when the request is done unless flagged file.remove=false
				-- normalise; {field.name={name="original-filename.extension", file="path/to/temp/file"},…}
				if item.size >0 then
					form[key] = item -- enables validation
					item.name = item.file
					item.file = moonstalk.root.."/"..item.temp
				else
					form.files[key] = nil
					os.remove(item.file) -- FIXME: empty files should not be saved by reqargs!
				end
			end
		end
	else
		-- when wanting to process other types of post: address.post={form=false}
		scribe.Error{realm="form",title="Unsupported post encoding: "..request.type}
	end
end end

do
local concurrency = 0
local ngx_print = ngx.print
local ngx_exit = ngx.exit
function Respond() -- this could be optimised to be inline in content_by_lua_block thus eliminating another function call, though it's log function would not be conditionally stripped, nor would upvalues be usable
	-- requires page.status, page.headers and output
	local ngx = ngx
	for name,value in pairs(page.headers) do ngx.header[name]=value end -- OPTIMIZE: can ngx.header be a local?
	ngx.status = page.status
	ngx_print(_G.output)
	concurrency = concurrency -1
	log.Debug("request completed with status "..page.status)
	log.Info() ngx.update_time(); page.headers["X-Moonstalk"] = table.concat{page.headers["X-Moonstalk"] or "", "; walltime=",util.Decimalise(ngx.now() - request.time,4)}
	ngx_exit(200)
end


local resty_cookie = require "resty.cookie" -- {package=false}
local CookieReader = {__index=function(cookies,name)
	-- handles on-demand values in request.cookies using Nginx's reader
	if not rawget(cookies,"_reader") then cookies._reader = resty_cookie:new() end
	return rawget(cookies,name) or cookies._reader:get(name)
end}

local ngx_req_get_headers = ngx.req.get_headers
local ngx_time = ngx.time
local ngx_req_get_uri_args = ngx.req.get_uri_args
local string_find = string.find
local string_match = string.match
local string_gmatch = string.gmatch
local pcall = pcall
local keyed = keyed
local split = split
local setmetatable = setmetatable
local EMPTY_TABLE = EMPTY_TABLE
function _Request()
	concurrency = concurrency +1 -- counter for async/concurrent requests -- OPTIMIZE: needs to reset when an error is thrown otherwise keeps growning in such cases, currently we can assume the most likely scenarios of errors in views and controllers are handled, errors in application functions are not caught but for now it can be considered a scenrario that is caught by testing and thus never deployed; this would require calling Request with pcall in server and handling the error there, and thus also handling all the variances notably for views and controllers
	local request = {
		domain =ngx.var.host,
		time = ngx_time(),
		method =ngx.var.request_method,
		query_string =ngx.var.query_string,
		path =ngx.var.uri,
		scheme =ngx.var.scheme, -- protocol http or https
		secure =ngx.var.scheme=="https",
		agent =ngx.var.http_user_agent or "", -- not always present
		client = {ip=ngx.var.remote_addr, keychain={}},
		cookies= {},
		-- form is specified in scribe as EMPTY_TABLE, then replaced by GetPost when required
		headers =ngx_req_get_headers(), -- transforms to lowercase but also provides a metatable to handle mixedcase and underscore variants -- TODO: use a metatable that only fetches from ngx.var[name] but has to transform dashes to underscore
	}
	_G.now = request.time
	if request.query_string then
		-- it is not notably expensive to parse the query string thus we always do so, unlike the form
		if string_find(request.query_string,'=',2,true) then
			-- ?foo&bar=baz = {foo=true,bar=baz}
			request.query = ngx_req_get_uri_args(10) -- only parses arguments without values (no key=value) e.g. ?aibble+wobble or ?wibble&wobble-wubble as booleans (wibble==true)
			if request.query[ string_match(request.query_string, "[^%+=&]+") ] ==true then -- the query string contains a mix of + delimited and key-value attributes, openresty only parses the + delimited as booleans, however we shall preserve them in order as well; this test only parses as far as the first + & or = then looks up the value in the table thus is not unduly expensive, however query strings using this mixed attribute scheme are somewhat expensive as they invoke 3 functions calls and an iteration
				local count = 0
				for argument in string_gmatch(string_match(request.query_string,"(.-)&"),"[^%+&]+") do
					count = count +1
					request.query[count] = argument
				end
			end
		else
			-- ?foo+bar+baz = {foo=true,bar=true;[1]=foo,[2]=bar}
			request.query = keyed(split(request.query_string,"+")) -- OPTIMIZE: in-line code, or single combined function
		end
	else
		request.query = EMPTY_TABLE
	end
	if request.headers.cookie then
		setmetatable(request.cookies, CookieReader) -- DEPRECATE: and simply use scribe.Cookie"name" which openresty can replace
	end
	_G.request = request
end
end

local query_options = {qtype=15}
local resolver_options = {nameservers=moonstalk.resolvers, retrans=2, timeout=400,}
function ResolveMX(domain,priority)
	local dns_client,err = DNSResolver:new(resolver_options)
	if err then return nil,err end
	local exchangers,err = moonstalk_Resume(DNSResolver.query, dns_client,domain,query_options)
	if err then return nil,err elseif exchangers.errstr then return nil,"DNS "..exchangers.errstr end
	util.SortArrayByKey(exchangers,"preference")
	if not exchangers[1] then return nil,"no MX found"
	elseif not priority then return exchangers[1].exchange
	else
		for _,exchanger in ipairs(exchangers) do
		if exchanger.preference > priority then return exchanger.exchange end
		end
	end
end

do local openresty_shell = require "resty.shell" -- {package=false}; bundled
function util.Shell(command,read) -- replaces util.Shell for native non-blocking support
	local ok, stdout, stderr = moonstalk_Resume(openresty_shell.run,command) -- ok, stdout, stderr, reason, status
	return stdout or stderr	-- the original behaviour is to return stdout or stderr; it is up to the caller to determine what is being returned by way of string inspection
end end

do local util_FileRead = util.FileRead
function _util_FileRead(path)
	return moonstalk_Resume(util_FileRead,path)
end end

-- # async http
-- async functions must not reference or modify the global environment as it will be for an unrelated request
-- when called syncronously the enviornment is preserved automatically

do
_G.http = _G.http or {}
copy(require"resty/http",http) -- "openresty/include/http"
local http = _G.http
local log=log; -- required for async
local function sync_err(request) return request.response,request.response.error end
function http_Request(request)
	-- TODO: connection pooling, by default we assume a connection is not reusable
	-- request = {url="http://host:port/path", method="GET", headers={Name="value"}, timeout=millis, json={…}, body=[[text]], urlencoded={…}, handler=namespace or function, defer=secs, ssl_verify=false}
	-- returns response,error -- NOTE: do not use 'if not response', instead use 'if err' or 'if response.err' as a response table should be returned in all cases; HTTP status codes other than 2xx do not return an error parameter but do return response.error with the code; presence of response.error without response.code implies a localised error
	-- response.json is a table if the response content-type is application/json
	-- method is optional, default is GET, or POST when json, body or urlencoded are present in the request
	-- defer=secs; =0 for immediate (guarenteed) decoupled execution; otherwise execution is not guarenteed without a persistence mechanism in place if the server is restarted before this time has elapsed; typically used with a handler, otherwise is silent; creation of a deferred request is not guaranteed even with persistence thus error handling should not differ
	-- handler=function or 'namespace' (allows persistence), optionally with defer=secs; decouples the request from the caller and the handler function will be passed the original request table once a response is received; when run outside the original scope the request table allows introspection to correlate the call to an initiator or origin e.g. with private values added prior to decoupling the call, and a request.response table has the usual response; this function MUST NOT use the moonstalk request envionrment (request,page,site), if it needs access to any of these, they must be passed explicitly (e.g. in the request table); if deferred/decoupled, the handler must have upvalue access to all dependent functions; if logging >1 the handler can utilise request.sub (an array of all sub request and response tables) to inspect details; request.env =false to disable subrequest aggregration when invoked from an out-of-scope function, else wrong _G.request will be used to record these subrequests
	-- timeout accepts either seconds or millis
	if request.env ~=false then -- FIXME: recursion
		-- introspection for logging
		_G.request.subrequests = _G.request.subrequests or {}
		table.insert(_G.request.subrequests, request)
	end
	request.response = {}
	log.Debug(); if request.handler and type(request.async)=='string' then if not util.TablePath(_G,request.async) then request.response.error = "handler "..request.async.." not found"; return request.response, request.response.error end end -- we accept a function or a namespace and with deferred calls only a namespace shoudl be used, we check for its validity only in debug mode
	if request.handler or request.defer then
		-- request will be decoupled and we'll return without waiting for the response
		local ok,err
		if not request.defer then
			ok,err = openresty.Async(http.New,request)
		else
			ok,err = ngx.timer.at(request.defer,http.Deferred,request)
		end
		if err then log.Notice(err); request.response.error=err end
		return request.response, request.response.error
	end
	return http.New(request)
end
function http_New(request)
	-- internal function providing synchronous request handling, in general use http.Request
	-- request.scheme,request.host,request.port,request.path,request.query = string.match(request.url,"^(.-)://([^:/]*):?([^/]*)([^%?]*)")
	-- if request.path =="" then request.path = "/" end
	-- if request.port =="" then request.port = nil end
	-- if request.query =="" then request.query = nil end
	if request.timeout and request.timeout <60 then request.timeout = request.timeout/1000 end
	--request.proxy = "http://127.0.0.1:8888/"
	local client = http.new()
	-- TODO: construct request.query from table
	request.headers = request.headers or {}
	if request.urlencoded then
		request.method ="POST"
		request.headers['Content-Type'] ="application/x-www-form-urlencoded"
		request.body =ngx.encode_args(request.urlencoded) -- TODO: server neutral
	elseif request.json then
		request.method = request.method or "POST"
		request.headers['Content-Type'] ="application/json"
		request.body =json.encode(request.json)
	end
	request.method = request.method or "GET"
	log.Info(request.method.." "..request.url)
	if request.log ~=false then if request.log =="dump" then scribe.Dump(request,"http") else log.Debug(request) end end

	local response,error = moonstalk_Resume(http.request_uri, client, request.url, request)
	response = response or {}
	request.response = response -- introspection for request object which has been recorded in _G.request.subrequests
	if request.async then request._handler = util.TablePath(_G,request.async) end
	if error then
		response.error = error
		log.Alert("http.Request error ‹"..error.."› on "..request.method.." "..string.match(request.url,"([^?]+)"))
		return (request._handler or sync_err)(request)
	elseif code ==301 or code ==302 then
		if request.redirects then
			-- TODO: log permananet redirects as an alert or notice
			-- else an error warned below
			request._handler = nil -- in case of persistence at this stage
			request.redirect = false -- must prevent recursion; this value indicates a redirect was attempted, therefore if another is attempted this will be false and the error will be a redirect code
			return http.New(request)
		else
			-- we don't return an error param in this case but do warn within the response
			response.error = code
		end
	end
	if string.sub(response.headers['content-type'] or '',1,16) =="application/json" then -- sometimes sent with ; charset=
		local err
		response.json,err = json.decode(response.body)
		if err then response.error = "JSON: "..err; log.Alert(response); return (request._handler or sync_err)(request) end
	end
	if request.log ~=false then log.Info(response) end
	if request._handler then request._handler(request) end -- contains request.response, no need to return as async
	return response
end
function http.Deferred(premature,request) -- TODO: this function should be replaced with one that can perform persistence, translating .defer to a time for resumption, and saving payloads to disk; upon persistence request._handler is discarded, and upon restoration restored by
	-- internal function providing deferred request handling, in general use http.Request
	if premature then
		log.Alert("Abandoned deferred http request")
		return -- decoupled from initiator
	end
	return http.New(request) -- not yet decoupled so needs to return any creation serror
end
function http_Save(request,path)
	-- request can be a complete request object or URL; defer=0 or n if a decoupled request
	-- the response will be saved to a file at the given path, replacing any existing, and retuning true
	-- cannot save if content-type is html or status is not 200, returning false
	-- use with defer=n to decouple, however note that if multiple are decoupled with 0 and no backoff the target server may be undable to respond before the request timesout
	-- use with defer=n requres a handler for retrying failed saves, and the given handler(request) must itself call http.SaveResponse(request) to invoke the save
	if type(request)=='string' then request = {url=request} end
	request.saveas = path
	if request.defer then
		request.handler = http.SaveResponse
		http.New(request)
	else
		http.New(request)
		return http.SaveResponse(request)
	end
end
end

function EmailDispatch(message)
	-- wraps the default dispatch function to provide async handling through ngx.timer which removes the courier socket handling from the current page response flow, and also removes extra return parameters by using the wrapped timer.at function
	if message.courier =="smtp" and not message.fail then message.fail = "email.Enqueue" end -- we use the default generic queue with a timer setup in Enabler
	-- email._Dispatch is the original
	if message.defer ==nil then
		-- run in seperate coroutine so we don't wait to return response; uses wrapped timer function to suppress nginx's interrupt param; does not use Resume because it doesn't return to anything
		return openresty.Async(email._Dispatch, message) -- does not actually yield now, so not wrapped, will yield next, either at the next yielding call or after the request is finished
	elseif message.defer ==false then
		-- wait for tansport to finish, probably interleaved with other request so must be wrapped to preserve ours
		return moonstalk.Resume(email._Dispatch, message)
	else -- if message.defer then
		-- TODO: don't use the wrapped function as we actually need the interrupt param, e.g. to allow retry on shutdown, rare and coud instead be handled using a persisted queue which is cleared with a message.sent handler -- FIXME:
		ngx.timer.at(message.defer, function(_,message) email._Dispatch(message) end, message)
	end
end
