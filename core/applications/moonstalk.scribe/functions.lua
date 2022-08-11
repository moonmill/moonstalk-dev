-- scribe is responsible for defining access to and maintaining sites, plus generating and rendering views (including their controllers), it does not however provide any sites itself (see sitesfolder and tenant)
-- WARNING: in async servers except those using LuaJIT, View and Controller use pcall/xpcall which are not resumable and thus cannot contain yielding code -- TODO: add a toggle to remove this and run them unprotected which will of course break error handling and require a handler to catch the server's thrown error, if possible
-- OPTIMIZE: use a top level pcall in openresty and remove the view/controller pcalls except in dev mode as they provide more nuanced errors; but such a generic handler could in any case simply look at the page.state to define it's error title; we could also re-run the request enabling xpcall instead

states = {[0]="creation",[1]="curation",[2]="collation",[2]="identification",[4]="authentication",[6]="controller",[7]="view",[8]="template",[9]="",[10]="editing",[15]="abandoned"} -- only controller and view are set in all modes (due to introspection requirement for extensions), otherwise dev mode is required

default_site = {
	language=node.language,
	translated={},
	locale=node.locale,
	addresses={},
	keys={},
	urns_exact={},
	urns_patterns={},
	views={},
	controllers={},
	collators={},
	collate={}, -- contains the handler functions designated in collators and applications ={"name"}
	services={},
	errors={significance=10},
	editors={},
	files={},
	-- domains={}, -- created conditionally
	applications={},
	redirect=true,
}

hits = 0

-- temporary globals so that any attempts to test views can have access to somewhere to write to; it will be replaced with table references from sections when a request is invoked
_G.output = {length=0}
_G.page = {sections={}}
_G.request = {}

if moonstalk.server =="scribe" then append({"page","user",}, moonstalk.globals) end -- request is defined by moonstalk/server as a server primitive; with these scribe generics the total globals are 6 to be preserved -- TODO: use of scribe output functions without the scribe server would require resetting these globals and the output for each request
append({"scribe.lua"}, moonstalk.files)

if moonstalk.server =="scribe" then
	for _,bundle in pairs(moonstalk.applications) do
		if bundle.files["scribe.lua"] then
			log.Debug(bundle.id.."/scribe.lua")
			local result,imported = pcall(util.ImportLuaFile, bundle.path.."/scribe.lua", bundle)
			if not result then moonstalk.BundleError(bundle,{realm="bundle",title="Error loading functions for scribe",detail=imported,class="lua"}); return end
		end
	end
end

do -- Lua has an optimised register that cheaply handles many upvalues, thus desireable to global lookups on reoccuring request calls
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local pcall = pcall
local string_lower = string.lower
local string_gmatch = string.gmatch
local string_find = string.find
local string_match = string.match
local string_sub = string.sub
local table_concat = table.concat
local copy = copy
local split = split
local table_concat = table.concat
local string_sub = string.sub
local util_Transliterate = util.Transliterate
local util_Match = util.Match
local util_ArrayAdd = util.ArrayAdd
local util_Pad = util.Pad
local util_HttpDate = util.HttpDate
local table_insert = table.insert

local domains = moonstalk.domains
local moonstalk_Environment = moonstalk.Environment
local scribe_Controller,scribe_View,scribe_Section
local scribe_curators = {}; curators = scribe_curators
local scribe_xpowered = "Moonstalk/".. node.version -- we do not reveal the actual server (openresty) to avoid facilitating attacks, it may however be fairly obvious, and with logging >= Info the X-Moonstalk header is added with this detail
local scribe_xmoonstalk = "" -- placeholder until after intialisation
function Request(request) -- request can be built in the server, typically by calling the server's request generation function which returns it, but at this point has no access to other globals
	-- generic request handling after normalisation by the server
	local _G = _G -- the global environment as an upvalue to optimise performance
	-- NOTE: the server must set _G.now = os.time(), however os.time performs a syscall
	scribe.hits = scribe.hits +1

	-- # Moonstalk globals
	-- no locale is required until a site is available
	_G.request = request
	request.identifier = scribe.hits
	log.Info() request.identifier = util_Pad(scribe.hits,3)
	request.rooturl = request.scheme.."://"..request.domain.."/" -- ?(request.rooturl)my/path
	-- NOTE: request.client must be set by the server with ip; an asbtract representation of the merged conditions of request and user (if any) that may change from request to request, whereas a user should be mostly constant, and bound to a client via a session

	log.Info() request.cpuclock = os.clock()
	request[string_lower(request.method)] = true
	log.Info(request.client.ip.." "..request.method.." "..scribe.RequestURL())

	-- # Scribe globals
	_G.user = false
	_G.page = { state=0, status=200, type="html", data={}, headers={}, sections={content={"",length=1}, output="content"} } -- TODO: don't create data? -- NOTE: APIs and anything serving other content types must explictly declare the type
	_G.output = page.sections.content
	local page = page

	if request.path =="/" then
		page.address = "front"
		page.paths = EMPTY_TABLE
	else
		-- components are split into a table that comprises both lowercased transliterated keys and number positions, with their original value as strings or numbers
		page.address = request.path
		if string_sub(page.address,-1,-1)~="/" then page.address= string_sub(page.address,2)
		else page.address= string_sub(page.address,2,-2) end
		page.address,page.transliterated = util_Transliterate(page.address,true) -- a 'normalised' URI string value is transliterated and lowercase but punctuation is preserved; should an application need to compare address-path input with a normalised value it may call Normalise() or gsub(address,"[%p]","")
		page.paths = split(page.address,"/") -- if we need to lookup path components use util.ArrayContainsValue(page.paths,"normalised_value") or if there's multiple potential values first call keyed(page.paths)
	end

	-- # Curation etc : Lookup the site
	local site = domains[request.domain] -- most efficent way of mapping and finding sites
	if not site then
		-- Invoke application curators
		page.state = 1
		for i=1,scribe_curators.count do
			-- check all curators until one returns a site; the default (and last) is the scribe.Curator which handles unknown domains
			site = scribe_curators[i]()
			if site then break end
		end
		-- we don't handle the scenario of a missing site, as the generic application adds a final curator to handle that
	end
	_G.site = site

	-- # Routing etc : Map the view/controller
	page.state = 2
	for _,Collator in ipairs(page.collate or site.collate) do -- NOTE: if a curator wishes to prevent collation then it may set page.collate = {}
		if Collator() then page.collate = true; break end
		-- typically used to retreive and populate data, notably the page; must explictly return true to prevent any following collators from running (such as for default not found page handler); may also act upon globals such as user, and retreive and set static page content by calling write(content), set page.controller or page.view etc; should identify and populate user and preferences, with scribe.Token() and SetSession() as appropriate
		-- may also be set by the Curator/Binder site.collate={Function, …}; or page.collate may be set to false for sites or pages that do not need to check the db for the user session, such as for API methods where the client.id or some other token will be passed by the method's controller to it's own dedicated procedure; to avoid invoking when unnecessary, either the token cookie needs to be present (i.e. set upon signin) or a token query param needs to be provided which the authenticator will usually attempt to exchange for a corresponding cookie; authenticator functions should not invoke errors if the token is invalid and should generally remove it silently; if a page is locked after invocation the scribe will itself show the authenticate page
	end
	if not page.collate then page.view = "generic/not-found" end

	-- # client identification
	page.state = 3
	-- this takes place after curation because sites can set their own token names
	-- where curation wants to include the user, the curator should perform this itself
	if request.headers.cookie or request.query["≈"] then -- this query argument makes it possible to use a token to sign-in on any URL, but is thus a protected argument name; this is not strictly necessary to support in the generic codebase as is a fairly specific requirement, however the alternative would require using a collator function to perform the check and set the value
		request.client.token = request.query["≈"] or request.cookies[site.token_name] -- this indicates a signed-in or previously identified user
		request.client.id = util.DecodeID(request.client.token) -- matches an existing session ID; failure is silent (eg. if node.secret was changed) or in case of attack, and for protected resources would get caught by locks resulting in unauthorised, otherwise the usual signed-out representation
	end

	-- # authentication
	-- this depends upon page.locks which may prevent it, however if a collator wants to perform it earlier it may
	page.state = 4
	if page.locks ~=false and (request.client.id or request.form.action =="Signin") and (page.Authenticator or site.Authenticator) then (page.Authenticator or site.Authenticator)() end -- Authenticator can be set to false in both cases but if page.Authenticator is given site set to false will be ignored; Authenticators fetch the user identified by the request.client.token and populates the _G.user table generally with at least nick and keychain; can be disabled with address.locks=false if the page uses it's own authentication mechanism such as not employing the request.client.token
	-- now that we may have a user, we can validate against page if locked
	if page.locks then
		page.nocache = true -- nothing with authentication restrictions should be cached; this is currently implemented by Kit
		page.headers.Vary = util.AppendToDelimited("Cookie", page.headers.Vary, ",") -- ensure caches refresh protected content when requested with a cookie
		local unlocked
		if not next(page.locks) then
			unlocked = true
		else
			for _,key in ipairs(page.locks) do
				if request.client.keychain[key] then
					unlocked = true
					log.Debug("unlocked with key: "..key)
					break
				end
			end
		end
		if not unlocked then
			log.Debug("no key for locks") log.Debug(page.locks)
			scribe.UserUnauthorised()
		end
	end

	-- # Localisation
	-- a locale is required by most applications; and is derived from request and user; but may be overridden in sites using localise=false
	-- a language is required for collators to select localised page content (but should fallback to site default or first available)
	moonstalk_Environment(request.client,site)


	-- # Rendering
	-- function calls being expensive, these behaviours are inline, unlike curation and collation which can be hugely varied
	--log.Debug(); local _sections=page.sections; page.sections=nil; log.Debug(page);page.sections=_sections

	if page.controller then
		page.state = 6
		scribe_Controller(page.controller)
	end

	if page.view then -- defined by binder/address although a controller may specify it instead of calling scribe.View directly
		page.state = 7
		scribe_View(page.view) -- final call, flag to render not-found view
		-- TODO: page.headers.Vary = util.AppendToDelimited("Accept-Language", page.headers.Vary, ",") -- ensure caches refresh content when requested with a different language
	end

	if page.type =="html" and page.template ~=false then -- page.template==nil infers use of site.template; page.type~=html infers no template
		page.state = 8
		scribe_Section "template"
		if site.controllers[page.template or site.template] then scribe_Controller(page.template or site.template) end
		scribe_View( page.template or site.template or "generic/template" )
	end

	log.Debug(); scribe.Debug_Concat(output) -- debug handler; in production there should be no case where a non-string value is allowed for output, if there is the server will simply generate a generic 500 error and the error log would need to be inspected
	_G.output = table_concat(output) -- transforms the array of strings from output into a single string ready for yield as the complete response, and suitable for editors to transform


	-- # Post-processing
	if page.modified and not page.locks then -- POST invalidates cached pages thus last-modified is ignored
		page.headers["Last-Modified"] = page.headers["Last-Modified"] or util_HttpDate(page.modified or page.created) -- don't change if already set, otherwise nil if no dates; must disable when logging>4 to prevent webserver sending 304 not-modified
	end
	page.headers["Content-Type"] = types.content[page.type] or page.type
	page.headers["Content-Language"] = page.language or site.language
	page.headers["X-Powered-By"] = scribe_xpowered

	if page.editors ~=false then
		-- editors can be applied to any content-type, thus they must check the type themselves
		log.Debug() page.state = 10
		for _,Editor in ipairs(site.editors) do
			log.Debug("applying Editor "..site.editors[Editor])
			Editor()
		end
	end

	if page.cookies then scribe.SetCookies() end

	-- if page.error and not page.abandoned then
	-- 	-- an error view or any other handler can intervene to catch errors but must call Dump which will prevent further error handling unless subsequent errors occur which will have a subsequent dump
	-- 	-- any error beyond at this point can only be output as a serialised string
	-- 	scribe.Abandon "generic/error"
	-- 	_G.output = table_concat(_G.output)
	-- end

	log.Info(); local cpuclock=os.clock(); page.headers["X-Moonstalk"] = table_concat{scribe_xmoonstalk,"uptime=",calendar.TimeDifference(request.time,moonstalk.started,"?(days)d?(hours)h?(minutes)m"),"; request=",scribe.hits,"; cputotal=",cpuclock,"; cputime=",util.Decimalise(cpuclock - request.cpuclock,4)}
end


-- # Public Scribe functions

function Posted(options)
	-- must be called in order to consume request.form[field] values including request.form.files
	-- typical usage: if request.post then scribe.Posted(); if request.form.action=="" then … end end
	if request.form._parsed or request.method ~="POST" then return end
	request.type = string_match(request.type,"([^;]+)")
	log.Debug"preparing form"
	scribe.GetPost(options) -- provided by the server
	request.form._parsed = true
	local form = request.form
	if page.form then copy(page.form,form,false,false) end -- can be specified in addresses
	page.nocache = true -- nothing accepting GET or POST params should be cached; there are scenarios where however the GET params do not modify content and these should set nocache = nil
	-- strip empty values and sanitise
	local number
	local count = 0
	for name,value in pairs(form) do
		number = tonumber(value); if number and tostring(number) ==value then value = number end -- we coerce (small) integer values; but not numbers that contain any formatting to avoid locale and zero-prefixed number issues; -- NOTE: this also has the desirable side-effect that IDs are not coerced to numbers, and thus their (inappropriate) use outside the internal scope requires explicit coercion
		if count >60 then
			scribe.Error "Too many form parameters" break -- we only checked the size of GET with a POST to protect against runaway parsing, this covers GET or POST individually
		elseif value =="" then -- ignore, don't set thus becomes nil
		elseif string_find(name,".",1,true) then
			-- Create subtables from '.' delimited names
			util.TablePathAssign(form,name,value)
		else
			form[name] = value
		end
		count = count +1
	end
	-- WARNING: HTML5 multi file inputs are output as an array ONLY when they contain multiple files, see following example to handle correctly
	--[[ if not request.form.files[1] then -- one file, no array
			request.form.files = {request.form.files}
		elseif request.form.files.contents then -- there appears to be a bug with wsapi where only files > 1 get put in an array
			table_insert(request.form.files, 1, {contents=request.form.files.contents,['content-type']=request.form.files['content-type'], name=request.form.files.name, size=request.form.files.size,1} )
		end
	end
	--]]

	-- Log the form, but truncating long values
	log.Debug() local logform=truncate(form,42) if form.password then logform.password="…" end log.Debug(logform)
	form._parsed = true
end

function Page(path,env)
	-- executes a view and/or controller for the current site
	local result
	if site.controllers[path] then
		result = scribe.Controller(path,env)
	end
	if result ~=false and site.views[path] then
		return scribe.View(path,env)
	elseif not site.controllers[path] and not site.views[path] then
		return scribe.NotFound(path)
	end
	return true
end


function Controller(path,env)
	local controller = site.controllers[path]
	log.Debug() if not controller then return scribe.Error{realm="page",title="Missing controller",detail=path} end
	log.Debug("running controller: "..controller.path)
	log.Info() scribe.LoadController(controller) -- development mode; reload with every request
	return controller.loader()
	--local result,response = xpcall(controller.loader,debug.traceback)
	--if not result then return scribe.Errorxp({realm="page",title="Error in controller "..controller.id, detail=response}) end
	-- return response -- should check page.error for execution status
end
scribe_Controller = Controller
function ControllerSandbox(path,env)
	-- run with the given environment; the values in the table will be directly accessable as if they were named globals, but no globals will be unless there's a metatable with __index=_G
	-- can be used to run email views local env = {message={…}}; ViewEnv("emails/email-name",env); log.Info(env.message.html)
	local controller = site.controllers[path]
	-- setmetatable(env,{__index=_G}) -- not sandboxed
	if controller then setfenv(controller.loader,env) end
	env = scribe.Controller(path)
	setfenv(controller.loader, _G)
	return env
end

function View(path)
	-- creation of shared fragments may be done simply by declaring a function in a suitable namespace to wrap output, such as a local in any view; or with a functions.html file -- NOTE: such functions write to output and return nothing thus must use <? code ?> tags not ?(marco) markup
	-- cannot currently ask for a view with a specific translation without changing the request.client.language
	local view = site.views[path]
	log.Debug() if not view then return scribe.Error{realm="page",title="Missing view",detail=path} end
	if page.modified ==nil then page.modified = view.modified end -- best practice is to have a modified date so we use that of the first rendered view, typically the main content, otherwise must be explictly set
	page.type = view.type
	if view.translated then -- FIXME:
		view = view[request.client.language] or view[request.client.locale] or view[request.client.languages[2]] or view[request.client.languages[3]] or view -- the assumption is that the first language contains a locale and is therefore the best match
	end
	page.language = page.language or view.language or site.language -- the only value actually copied from view to page unless it has been defined elsewhere (probably address)
	log.Debug("running view: "..view.path)
	log.Info() scribe.LoadView(view) -- development mode; reload with every request -- the prefixed log call on this line ensures the line is disabled for lower log levels
	-- NOTE: unlike addresses, flags from the view are not copied to the page, therefore necessary values must be explictly set
	if page.template == nil then page.template = view.template end
	if view.static then -- html without dynamic markup from loader
		table_insert (output,view.static)
		page.static = true -- not used internally
		return true
	else
		view.loader()
		--[[
		local result,response = xpcall(view.loader,debug.traceback)
		if not result then
			if string.find(response,"invalid value",1,true) then
				result = string.match(response,"at index (%d+)")
				local section = page.sections.content -- TODO: this does not catch errors elsewhere
				response = web.SafeHtml(table.concat(util.Slice(section,result-20,result-1)))
				.."**"..tostring(section[result]).."**"..
				web.SafeHtml(table.concat(util.Slice(section,result+1,result+20)))

				-- log.Alert{realm="page",title="Invalid value in output", detail=response}
				return scribe.Error{realm="page",title="Invalid value in output", detail=response} -- we don't know which view that output position corresponds to -- TODO: record positions when we call View() -- FIXME: breaks
			else
				return scribe.Errorxp{realm="page",title="Error in view "..view.id, detail=string.gsub(string.gsub(response,view.id..":.-in main chunk\n",""),view.id..":","line ")}
			end
		end
		return result
		--]]
	end
end
scribe_View = View
function ViewSandbox(path,env)
	local view = site.views[path]
	-- setmetatable(env,{__index=_G}) -- not sandboxed
	if view then setfenv(view.loader, env) end
	env = scribe.View(path)
	setfenv(view.loader, _G)
	return env
end

function Extensions(name,env)
	-- runs either controllers or views (per the scpope from which it is called, it must thus be called from both a controller and a view if both are to be run) that have been extended by other applications or the active site; extensions are essentially linked fragments that can be executed with a specified environment
	-- returns true if all extensions ran without requesting an interrupt; otherwise returns nil if any extension returns a value other than nil to request an interrupt (by returning false); it is the responsibility of the calling function to check the return value and proceed/interrupt as appropriate
	name = name or page.view or page.controller -- inherits from address
	local status = true
	if page.state ==6 and site.controllers[name] and site.controllers[name].extensions then
		for _,controller in ipairs(site.views[name].extensions) do
			if scribe.Controller(controller.id, env) ~=nil then status = nil end
		end
	elseif page.state ==7 and site.views[name] and site.views[name].extensions then
		for id,view in ipairs(site.views[name].extensions) do
			if scribe.View(view.id, env) ~=nil then status = nil end
		end
	end
	return status
end

function Cookie(meta,value)
	-- Cookie(name,value)
	-- Cookie{name=name, value=value, expires=seconds from now, path="/subsite", "httpOnly", "secure", "SameSite=Strict",...}
	-- path defaults to root
	-- array part takes any number of ordered attributes, or name=value pair strings
	page.cookies = page.cookies or {}
	if type(meta)=="string" then
		_G.page.cookies[meta] = {value=value}
	else
		_G.page.cookies[meta.name] = meta
		meta.name = nil
	end
end
function SetCookies()
	for name,cookie in pairs(page.cookies) do
		-- TODO: add support for signed client-sessions
		if not cookie.value then -- delete
			cookie.expires = 0
			cookie.value = ""
		elseif cookie.expires then
			cookie.expires = now+cookie.expires
		end
		local setcookie = {name.."="..cookie.value} -- TODO: value should be encoded
		if cookie.expires then
			table_insert(setcookie, "max-age="..cookie.expires)
			-- table_insert(setcookie, "expires="..os.date("!%a, %d %b %Y %H:00:00 UTC",cookie.expires))
		end
		table_insert(setcookie, "path="..(cookie.path or "/")) -- must set path to root else browsers default it to current path
		if cookie.domain then table_insert(setcookie, "domain="..cookie.domain) end
		for _,attribute in ipairs(cookie) do table_insert(setcookie, attribute) end
		setcookie = table.concat(setcookie,"; ")
		log.Info("Cookie: "..setcookie)
		local cookies = page.headers["Set-Cookie"]
		if type(cookies) == "table" then
			table_insert(page.headers["Set-Cookie"], setcookie)
		elseif type(cookies) == "string" then
			_G.page.headers["Set-Cookie"] = { cookies, setcookie }
		else
			_G.page.headers["Set-Cookie"] = setcookie
		end
	end
end

function Token(id)
	-- assign an ephemeral session token (not necessarily yet a session-linked ID unless id is created elsewhere and passed, but may be reused as such when created here)
	-- should be called whenever the user has commenced a new visit (e.g. has been more than x hours since last visit) to extend the expiry; when called for this purpose request.client.id must be provided as the argument else a new ID will be generated
	request.client.id = id or request.client.id or util.CreateID()
	if id or not request.client.token then request.client.token = util.EncodeID(id or request.client.id) end -- only if new
	local cookie
	if site.token_cookie then cookie = copy(site.token_cookie) else cookie = {} end -- must be copied as is set upon response which may be interrupted by async operations that could also set tokens
	cookie.name = cookie.name or "token"
	cookie.value = request.client.token
	cookie.expires = cookie.expires or time.month*3
	util.ArrayAdd(cookie,"HttpOnly")
	if site.provider ~=false and node.tenant and node.tenant.subdomain and string_sub(request.domain,#node.tenant.subdomain*-1) ==node.tenant.subdomain then
		--  if the current domain has the same node tenant subdomain we assign the cookie to the subdomain -- TODO: support for this should be in the tenant or SaaS application, or we should simply set the cookie from the signin controller where any domain may be specified, rather than here
		table_insert(cookie,"domain=."..node.tenant.subdomain)
	end
	if site.secure then table_insert(cookie,"Secure") end
	scribe.Cookie(cookie)
	return request.client.id
end

function UserUnauthorised()
	if page.error then return end -- preserve errors
	if user then
		scribe.Abandon "generic/unauthorised"
	else
		scribe.Abandon "generic/signin"
	end
	_G.page.headers.Vary = util.AppendToDelimited("Cookie", page.headers.Vary, ",")
	log.Debug("identification required")
	if site.controllers[page.view] then _G.page.controller = page.view end
	-- NOTE: -- the originally specified template is used, and its view and controller must therefore handle both Guest and out states
end

function RequestURL()
	if not request.url then
		request.url = request.scheme.."://"..request.domain..request.path
		if request.query_string then request.url = request.url .."?".. request.query_string end
	end
	return request.url
end

-- the following all return false so that one can use return NotFound() in a controller and thus prevent the view from running
function Redirect (url,code)
	local cookies = page.cookies -- needs to preserve for redirect as abandon discards them
	scribe.Abandon(code or 302)
	_G.page.cookies = cookies
	_G.page.headers["Location"] = url
	log.Debug("redirecting to "..url)
	_G.output[1] = [[<a href="]],url,[[">Redirected to ]],url,[[</a>]]
	return false
end
function RedirectSecure (address,code)
	-- unlike Redirect() this does not accept absolute URLs with schema nor domain (URI)
	-- address may be ommitted and the redirect will be to the current address, thus converting a non-secure URL
	if page.error then return end -- preserve errors
	local cookies = page.cookies -- needs to preserve for redirect as abandon discards them
	scribe.Abandon(code or 302)
	_G.page.cookies = cookies
	_G.page.template = nil
	if not address then address = string_sub(request.path,2) end -- FIXME: request.path should not have the slash prefix as all internal addresses are absolute
	if request.query_string then
		page.headers["Location"] = table_concat{"https://",site.domain,"/",address,"?",request.query_string}
	else
		page.headers["Location"] = table_concat{"https://",site.domain,"/",address}
	end
	log.Debug("redirecting to "..page.headers["Location"])
	_G.output = {[[<a href="]],url,[[">Redirecting to ]],url,[[</a>]],length=1}
	return false
end

function NotFound (name)
	scribe.Abandon "generic/not-found"
	return false
end


-- ## Output utilities
-- these manipulate _G.output with page.sections

function _G.write (value) -- this is a global function and is not available within the scribe table
	-- the Scribe assembles its output/result from multiple (and typically very many) value fragments, which are captured in sequence in an output array [typically] by this function; for HTTP responses the Scribe server then concatenates the output array into a single response string
	-- all discrete non-code blocks should be wrapped by this functionality; code blocks may append to the output by calling this function explictly
	-- NOTE: wrapping (output) of non-code blocks in views is performed transparently by TranslateView(), but is optimised to instead of repetitively call this function, instead appends directly to the output table as a per-view local
	-- value must be coercible by the table.concat function, thus can only be a string or number else an error will occur; it is preferable to format numbers before output; nil values and additional parameters are safe and will be ignored
	output.length = output.length +1
	output[output.length] = value or ""
end

function Cut()
	-- capture output until Paste; see Section to define named captures
	page.sections._uncut = output -- to restore current output after Paste
	_G.output = {"",length=1} -- the temporary output container to capture for paste; the space will be replaced by the existing value on paste, which avoids reordering
end
function Paste(...)
	-- Paste(value,"mark",replace) insert the given value at the designated mark's position, with an optional true if replacing the existing content
	-- Paste("mark") insert output captured with Cut at the named mark
	-- Paste() simply returns the cut output
	-- e.g. paste a preceeding block use <? Cut() ?> <tags> <? Paste("mark") ?>
	-- if Paste(...,true) then the entire string value preceeding the mark will be replaced
	-- performs concatenation with the existing value, which may therefore be a number or string, and may be pasted to multiple times at a probably cheaper cost than reordering the table to insert the value
	local value,mark,replace,position
	local arg = {...}
	arg.length = #arg
	if arg.length ==1 then
		mark = arg[1]
	elseif arg[arg.length] ==true then
		replace = true
		if arg.length ==2 then
			mark = arg[1]
		else
			value = arg[1]
			mark = arg[2]
		end
	else
		value = arg[1]
		mark = arg[2]
	end
	position = page.sections._marks[mark] -- position in the output where we'll insert
	log.Info() if not position then scribe.Error ("Cannot Insert at undefined mark '"..mark.."'") return end
	if not value and page.sections._uncut then
		value = output
		_G.output = page.sections._uncut
		page.sections._uncut = nil
		if not replace then value[1] = output[position] end -- preserve the original ouput position value unless replacing
		value = table_concat(value)
		if not position then return value end
	elseif position and not replace then
		value = output[position] .. value
	end
	output[position] = value -- we replace the existing value which may have been preserved above, as otherwise an insert would result in the output being reordered which is expensive
end
function Mark (name)
	-- mark a place within the default output (e.g. a view) to Paste to
	-- marks cannot be defined in sections (other than the default "content" section)
	-- NOTE: name is not checked, and thus may replace an existing mark; best practice is to use the form "app/view#mark"
	-- NOTE: the use of Mark with Cut and Paste is a solution to extending some application views with additional fragments via their extensions, without needing to replace the view entirely, however this soution is somewhat expensive and it is therefore greatly preferable to replace the controller and view entirely
	-- NOTE: cannot use Mark in templates as templates are run after views; instead define a section in the view and then insert in the template
	table_insert(output,"")
	page.sections._marks = page.sections._marks or {}
	page.sections._marks[name] = output.length
end

function Section (name) -- TODO: -- DEPRECATE: easier just to use local functions that can be called
	-- capture the output giving it a name, defining a discrete block of output which can later be used by name elsewhere using Insert; provides the functionality for view templates
	-- sections must be closed by calling the function with no name i.e. Section(); if not closed, section capture becomes nested until closed
	-- name should not be that of a view (Insert accepts the name of either a view or section), and should be unique; best practice is to use the form "app/view#section"
	page.sections._priors = page.sections._priors or {"content"}
	if not name then -- close the current section restoring output to the prior section
		local prior = page.sections._priors[#page.sections._priors-1]
		log.Debug("Closing section "..page.sections.output.." reopening "..prior)
		_G.output = page.sections[prior]
		page.sections._priors[#page.sections._priors] = nil
		page.sections.output = prior
		return
	end
	log.Debug("Opening section "..name)
	page.sections[name] = page.sections[name] or {"",length=1} -- can reuse a section by declaring it again, thus appending additional output to it; see Paste for purpose of empty string
	_G.output = page.sections[name]
	page.sections._priors[#page.sections._priors+1] = name
	page.sections.output = name -- for simpler introspection -- TODO: get rid of this in favour of _priors
end
scribe_Section = Section

function Insert (section) -- TODO: maybe add a preserve option that does an append and adjusts marks associated with this section to the new positions (i.e. +#output)
	if not page.sections[section] then return end
	log.Debug("Insert "..section)
	-- appends the named section at the end of the output (e.g. the current point in a view / section)
	_G.output.length=_G.output.length+1; _G.output[_G.output.length] = table_concat(page.sections[section]) -- same as write(); performing concatenation is much faster than an array append, but destorys marks
end

do local file_cache={}
function InlineFile(path)
	-- reads and caches a file, inserting it into the output
	-- typically used for inlineing content that has been saved as a seperated self-contained file for better speration, e.g. <script>?(scribe.InlineFile"view.js")</script>
	-- TODO: watch the file for changes and update the cache automatically
	if not file_cache[path] or node.dev then
		local file,err = io.open(path,"r")
		if err then return scribe.Error{title="Cannot inline file: "..string.match(path,"[^/]+$"), detail=err} end
		-- TODO: strip comments from js files using a loader
		local type = string.match(path,"%.(.+)$")
		local data = file:read("*a")
		if type =="css" then
			data = string.gsub(data,"/* .-*/","")
		elseif type =="js" then
			data = string.gsub(data,"// .-\n","")
		end
		file_cache[path] = data
	end
	return file_cache[path]
end end

end -- of the locals


-- # Utility functions -- TODO: move to kit or util unless exclusively used by loader or server

function RecentUser(timestamp)
	if timestamp > request.client.session.last or timestamp > request.time-time.hour then return true end
end

function Agent(agent)
	-- determine a likely client; we don't attempt to identify all, just common ones
	-- this is intended for display to users (e.g. to identify sessions) and is not for compatibility profiling (come values may not be specified)
	local platform,platform_v,browser,browser_v
	agent = agent or request.agent
	local string_match = string.match
	platform = string.match(agent,"([^ /%+]+)")
	if platform =="Opera" then
		-- Opera Mini only uses platform Opera
		browser,browser_v = string_match(agent,"(Opera Mini)/(%d+)")
		if not browser then browser = platform end
		platform = nil
	elseif platform =="Mozilla" then
		-- this preserves other browsers, and devices like BlackBerryxx and Nokiaxx; for which we don't bother with the version
		platform,platform_v = string_match(agent,"(Windows Phone OS) (%d+)") -- all browsers on Windows Phone
		if not platform then
			platform,platform_v = string_match(agent,"(Windows) (.-);") -- all other browsers on Windows or Windows Mobile
		end
		if platform then
			-- MSIE is only on Windows
			local delim
			browser,delim,browser_v = string_match(agent,"(IEMobile)[/ ](%d+)")
			if browser then
				if delim =="/" then
					-- Trident; we can use the device; network; suffix strings for the platform instead of Windows Phone
					platform = string_match(agent,"IEMobile.-;.-;(.-)$")
					platform_v = nil
				end
			else
				browser,browser_v = string_match(agent,"(MSIE) (%d+)")
			end
		else
			for _,match in ipairs({ "(Mac OS X) (%d+[%._]?%d*)", "%((.-);.+OS (%d+[%._]?%d*).* like Mac", "(Android) (%d+%.?%d*)", "(Ubuntu)/(.*) ", "(Kindle)/(.-) ", "(Linux)[ ;]?([^; %-]*)", "(Symbian ?OS)/([^%); ]*)", "(BlackBerry .-);" }) do
				platform,platform_v = string_match(agent,match)
				if platform then break end
			end
		end
	end

	if not browser then
		-- we've already detected MSIE, IEMobile, and probably Opera
		for _,match in ipairs({ "(Opera)[ /](%d+)", "(Firefox)/(%d+)", "(Chrome)/(%d+)" }) do -- Opera before Firefox, as they can include each other's identifiers
			browser,browser_v = string_match(agent,match)
			if browser then break end
		end
		if not browser then
			-- we ignore identifiers from other vendors
			browser_v,browser = string_match(agent,"Version/(%d+)[%d%.]* (Safari)/") -- desktop version of Safari
			if not browser then
				browser_v,browser = string_match(agent,"Version/(%d+)[%d%.]* Mobile/.+ (Safari)/") -- iOS versions of Safari
			end
		end
	end

	if platform_v then platform_v = string.gsub(platform_v,"_",".",1) end
	agent = {platform=platform, platform_v = platform_v, browser=browser, browser_v=browser_v, string={}}

	if agent.platform then table.insert(agent.string,agent.platform) end
	if agent.platform_v then
		table.insert(agent.string, " ")
		table.insert(agent.string, agent.platform_v)
	end
	if agent.platform and agent.browser then table.insert(agent.string, " / ") end
	if agent.browser then table.insert(agent.string, agent.browser) end
	if agent.browser_v then
		table.insert(agent.string, " ")
		table.insert(agent.string, agent.browser_v)
	end
	agent.string = table.concat(agent.string)

	return agent
end


-- # Initialisation

function Enabler()
	if moonstalk.server ~="scribe" then return end
	-- a starter sets the instance; thus enable it here
	scribe_xmoonstalk = "server="..node.scribe.server..";instance="..moonstalk.instance..";"
	for _,key in ipairs(moonstalk.globals) do _G[key] = {} end -- just in case there's an error before they're assigned
	if node.curators then
		-- replace names with functions
		for i,application in ipairs(node.curators) do
			if _G[application] and type(_G[application].Curator) =="function" then
				util.ArrayAdd(scribe.curators,_G[application].Curator)
			else
				log.Alert("Invalid "..application..".Curator")
			end
		end
	end
	table.insert(scribe.curators, scribe.Unknown)
end

function Enable()
	-- a starter sets the instance; thus enable it here
	-- configure application bundles so their resources are ready to be enabled on sites
	-- this runs after all Enablers, but before Starters because it is invoked from Sites()
	for appname,application in pairs(moonstalk.applications) do
		local result,error = pcall(scribe.ConfigureBundle, application)
		if not result then
			log.Alert("Cannot load bundle "..appname)
			log.Alert(error)
			application.ready = false
		else
			if application.Curator and not node.curators then -- if node.curators is specified we'll define the curator order using it later
				table.insert(scribe.curators,application.Curator)
			end
			if application.reader then
				table.insert(moonstalk.readers,application.reader)
			end
		end
	end
	scribe.curators.count = #scribe.curators
end

function Starter()
	if moonstalk.server ~="scribe" then return end
	scribe.Abandon = scribe._Abandon; scribe._Abandon = nil
	return function() -- a finaliser
		moonstalk.Error = scribe.Error -- from this point errors can be handled in requests
	end
end


function Sites()
	-- define the admin domain/site, must be provided as per ReadBundle()
	local site = copy(scribe.default_site)
	site.name = "Moonstalk"
	site.id = "localhost"
	site.provider = false
	if not string.find(node.hostname,".",1,true) then moonstalk.BundleError(scribe,{title="Unqualified hostname",detail="You must set node.hostname with a fully qualified domain name to enable remote access such as for use with the Manager interface. ./elevator hostname=server.example.com"}) end
	site.domain = node.hostname or "localhost"
	site.domains = {{name=node.hostname,redirect=false},{name="localhost",redirect=false}}
	site.locale = node.locale
	site.path = "/dev/null"
	site.robots = "none"
	site.addresses = {
		{ matches="front", redirect="Manager"},
		{ matches="installed", view="generic/admin-installed"},
	}
	return{site}
end

function Site(site)
	-- this is used to normalise and add sites, usually by site providers when invoked from application.Sites()

	if not scribe.enabled then scribe.Enable(); scribe.enabled = true end -- prepare apps for sites
	moonstalk.sites[site.id] = site

	if site.authenticator or node.authenticator then
		site.Authenticator = util.TablePath(site.authenticator or node.authenticator)
		if not site.Authenticator then moonstalk.Error{site,title="Invalid authenticator: "..site.authenticator} end
	end
	-- must check and add bundle flags befor ConfigureBundle as that's where they get propagated to addresses
	if util.FileExists(site.path.."/private/ssl/public.pem") or util.FileExists("/etc/letsencrypt/live/"..site.domain.."/fullchain.pem") then
		site.secured = true
	end
	if site.secured and site.secure ~=false then
		site.secure = true
	elseif not site.secured and site.secure then
		-- NOTE: we may not want to mark the site as secured but rather have the user specify the domains, or inspect the certificate to do so -- this is  an error state that will cause further errors
		site.secure = nil
		bundle.Error(site,"Cannot secure an unsecured site; certificate missing")
	end

	scribe.ConfigureBundle(site,"sites")
	site.token = site.token or util.Encrypt(site.id)
	moonstalk.site_tokens[site.token] = site

	if site.token_cookie then site.token_name = site.token_cookie.name end
	site.token_name = site.token_name or "token"

	site.domains = site.domains or {{name=site.domain}} -- may come from settings, else need a default
	-- point each domain (alias) at its site
	for i,domain in ipairs(site.domains) do
		if type(domain) =='string' then domain = {name=domain}; site.domains[i] = domain end -- convert from settings strings array
	end
	if not util.ArrayContainsKeyValue(site.domains,"name",site.id) then table.insert(site.domains,1,{name=site.id}) end -- ensure the foldername domain is present
	if not util.ArrayContainsKeyValue(site.domains,"name",site.domain) then table.insert(site.domains,1,{name=site.domain}) end -- ensure the primary domain from settings is present
	if string.sub(site.domain,1,4)=="www." and not util.ArrayContainsKeyValue(site.domains,"name",string.sub(site.domain,5)) then
		-- add the missing root variant
		table.insert(site.domains,{name=string.sub(site.domain,5)})
	elseif string.sub(site.domain,1,4)~="www." and not util.ArrayContainsKeyValue(site.domains,"name","www."..site.domain) then
		-- add the missing www. variant
		table.insert(site.domains,{name="www."..site.domain})
	end
	for _,domain in ipairs(site.domains) do
		-- domains that redirect are pointed to a new pseudo-site table with a redirect collator
		if domain.name ~=site.domain and domain.redirect ~=false and site.redirect ~=false then
			local redirect_append = domain.redirect_append ==true
			if not redirect_append and site.redirect_append ==true then redirect_append = true end
			moonstalk.domains[domain.name] = {urns_exact={},language=node.language, controllers=moonstalk.applications.generic.controllers, views=moonstalk.applications.generic.views, errors={}, urns_patterns={{pattern=".", collate={scribe.RedirectCollator}, redirect= domain.redirect or site.redirect or ifthen(site.secure,"https://"..site.domain,"http://"..site.domain), redirect_append=redirect_append}}} -- a bit convoluted, compared simply an «if site.redirect» in the Request handler however sites that redirect should be rarely used and keeps the Request handler cleaner -- we need urns_exact as binder will evaluate it before attempting the patterns, and we also need language for establishing the page envionrment and controllers for the actual handling
		else
			moonstalk.domains[domain.name] = site -- pointer
		end
	end

	if moonstalk.server ~="scribe" then return end

	if site.collators then
		-- collators can be named in a collators array as application name (thus assuming its default .Collator) or as a function ("application.FunctionName"), these function handlers are copied to the .collate array which is used when handling requests
		-- any site-declared collators replace node.collator therefore if they're required the site must specify them, or an Enabler should be used to add them
		for _,name in ipairs(site.collators) do
			if site.collators[name] ~=false then -- can override node
				local collator = scribe.GetTablePath(name..ifthen(string.find(name,".",1,true),".Collator",""))
				if not collator then
					moonstalk.Error{site, title="Unknown collator: "..name}
				elseif not util.ArrayContainsValue(site.collate, collator) then
					table.insert(site.collate, collator)
					log.Info ("  collator = "..name)
				end
			end
		end
	end
	-- in addition any collator for an enabled application is added (in EnableSiteApplication), plus the default collator following that; note that collators in enabled applications may need to be specified in

	-- populate the site's applications
	if node.applications then for _,app in ipairs(node.applications) do util.ArrayAdd(site.applications,app) end end
	util.ArrayAdd(site.applications,"generic") -- required application, but loads last so that its resources may be overridden

	for _,name in ipairs(site.applications) do scribe.EnableSiteApplication(site,name) end

	table.insert(site.collate, scribe.Collator) -- this is not an application that is named to be enabled thus we always insert it as the default collator

	-- link extensions
	-- this must take place after all applications have been enabled as a site can extend views of an application, and each application can extend another
	for name,view in pairs(site.views) do
		local target = string.match(name, "^.-/(.+)_extension")
		if target and site.views[target] then
			site.views[target].extensions = site.views[target].extensions or {}
			log.Info("  extending "..target.." with "..view.bundle)
			table.insert(site.views[target].extensions, view)
		elseif target then
			moonstalk.BundleError(site, {realm="sites",title="Cannot extend missing view '"..target.."' from "..view.path})
		end
	end
	for name,controller in pairs(site.controllers) do
		local target = string.match(name,"^.-/(.+)_extension")
		if target and site.controllers[target] then
			site.controllers[target].extensions = site.controllers[target].extensions or {}
			log.Info("  extending "..target.." with "..controller.postmark)
			table.insert(site.controllers[target].extensions, controller)
		elseif target then
			moonstalk.BundleError(site, {realm="sites",title="Cannot extend missing view '"..target.."' from "..controller.path})
		end
	end

	-- find wildcard (ends="") and move to end of addresses
	local wildcard
	for i,address in ipairs(site.urns_patterns) do
		if address.pattern==".*$" then
			wildcard = wildcard or address -- will strip out others but only preserve the first
			table.remove(site.urns_patterns,i) -- FIXME: actually this will break as we're modifying the table whilst traversing it
		end
	end
	table.insert(site.urns_patterns,wildcard)
end

function EnableSiteApplication(bundle,name,dependent)
	-- application dependencies are enabled in the order specified by the settings (for a site, and an application); apps enabled after a prior cannot replace existing resources in a site or another application, unless they do so with their loaded(); a site's resources allways take precedence and are not replaced
	-- can only be called once all apps are enabled -- TODO: there is currently no mechanism for Site functions to wait for all Starters to finish (e.g. once a db connection is established), this would potentially require a new app.Ready function
	if bundle.applications[name] then return end -- already enabled
	local application = moonstalk.applications[name]
	if not application then moonstalk.Error{bundle, level="Notice", id=name, title="  application '"..name.."' was not found"} return end
	if not dependent then
		log.Debug("  enabling "..name)
	else
		log.Debug("  enabling "..name.." (depedency of "..dependent..")")
	end
	bundle.applications[name] = true -- prevent recursion
	-- load any application dependencies
	for _,dependent in ipairs(application.applications or {}) do
		scribe.EnableSiteApplication(bundle,dependent,name) -- recursive(!)
	end

	if site.collators[name] ~=false then util.ArrayAdd(site.collate, application.Collator) end -- {"AppName", OtherApp=false}

	-- load resources from app into the site
	for urnname,urn in pairs(application.urns_exact) do
		-- copy pointers to the app's matches= addresses
		local replace
		if bundle.urns_exact[urnname] then
			if bundle.urns_exact[urnname] ==false then log.Debug("  "..urnname .. " cannot be replaced by "..application.id)
			else
				urn = copy(urn) -- because site values need to be propagated into it
				if replace then log.Info("  "..urnname .. " replaced by "..application.id) end
				if bundle.secure and urn.secure ==nil then urn.secure = true end -- propogate the secure flag to the apps urn
				if bundle.polyglot and urn.polyglot==nil then urn.polyglot = true end
				bundle.urns_exact[urnname] = urn
			end
		end
	end
	for _,urn in ipairs(application.urns_patterns) do -- copy all the app's pattern addresses after each other; the first-specified app's addresses take precedence, and the order of addresses is preserved -- TODO: post-sort by priority?
		urn = copy(urn)
		if bundle.secure and urn.secure ==nil then urn.secure = true end -- propogate the secure flag to the apps urn
		if bundle.authenticator and urn.authenticator ==nil then urn.authenticator = bundle.authenticator end -- propogate -- NOTE: we do not replace an application specified one
		if bundle.polyglot ~=nil and urn.polyglot==nil then urn.polyglot = true end
		bundle.urns_patterns[#bundle.urns_patterns+1] = urn
	end
	copy(application.controllers, bundle.controllers, false, false)
	copy(application.views, bundle.views, false, false)
	if application.Editor then -- TODO: allow apps to declare priorities
		table.insert(bundle.editors,application.Editor)
		bundle.editors[application.Editor] = application.id
	end

	if application.Site then -- we never enable "scribe" for an app or site, thus scribe.Site will not be called as it would be recursive
		-- once dependancies are loaded, we enable
		log.Debug(application.id..".Site()")
		local result,error = pcall(application.Site,bundle)
		if not result then moonstalk.BundleError(bundle, {realm="site", title="Site enabler failed for "..application.id.." on "..bundle.id, detail=error, class="lua"}) end
	end
end

if node.dev or logging >3 then
	local moonstalk_Resume = moonstalk.Resume
	function moonstalk.Resume(...)
		-- adds debugging
		log.Debug"--> Preserving environment"
		local a,b,c,d,e = moonstalk_Resume(...)
		log.Debug"<-- Restoring environment"
		return a,b,c,d,e
	end
end

do
local string_match = string.match
local copy = copy
local ipairs = ipairs
function Collator()
	-- handles default routing using site.addresses through their normalised urns_exact and then urns_patterns tables
	-- sites have their own tables as each address can have different properties from site to site, however addresses may be inherited by all sites from, or added to specific sites by, an individual application
	-- first check for an exact urn match as that's a fast key lookup
	-- in a multi-tenant/CMS architecture, a collator should be specified that performs its own routing including exact matches and database lookups, if others are specified and this is also required it must be declared explictly
	-- this collator is the default where no collators are specified
	local found = site.urns_exact[page.address]
	if not found then
		-- otherwise check for a filter match
		-- NOTE: optimising matching using string.sub has no performance benefit
		local string_match = string.match
		local page_address = page.address
		for _,urn in ipairs(site.urns_patterns) do
			if string_match(page_address, urn.pattern) then found = urn; break end
		end
	end
	copy(found, page, true, false)
	return found
end end

do local empty_urn = {}
function RedirectCollator(from)
	-- both site and addresses may specify redirects; site is handled with a pseudo-site table using this as its curator
	-- if the site specifies redirect_appaend=true then the requested path will be appended, the target URL should therefore end with / or ?
	from = from or site
	local to = from.redirect
	if from.redirect_append then to = to .. from.address end
	if request.query_string then to = to..request.query_string end
	scribe.Redirect(to)
	return true
end end

function Unknown()
	-- default curator
	page.view = page.view or "generic/unknown" -- must preserve original view if any as may be an error
	page.status = 404
	page.collate = false
	return moonstalk.sites.localhost
end

function Abandon() end -- placeholder during intialisation
do local function RenderAbandon(what,name,object)
	if not object then
		_G.output={"Couldn't abandon to missing "..what..": "..name}
		scribe.Error(output[1])
		return false
	elseif object.static then
		_G.output[1] = object.static
	elseif not pcall(object.loader) then
		_G.output={"Couldn't abandon due to error in "..what..": "..object.id}
		scribe.Error(output[1])
		return false
	end
end
function _Abandon(to)
	-- takes either a numeric status in which case no content is rendered, or a page name in which case that page (view and/or controller) is responsible for setting the page.status else it defaults to 500
	-- disables any further in-request handling when not using a top-level server pcall
	-- only the first abandonment will define the view content
	-- does not use the usual scribe renderers and for simplicty implements its own
	-- site template must be capable of running without its controller (i.e. only references the root of page.temp)
	-- assumes the view uses a template -- TODO: check view.template
	-- TODO: (low) an error before the end of a view's output that does not return/is not caught results in additional output that should be dropped; only applies to non top-level pcall use
	if page.abandoned then return end
	to = to or "generic/error"
	log.Info("Abandoning to "..(to or "[empty]").." from "..(page.address or request.path or '-none-'))
	if output.length and output.length >1 then
		-- discard all failed output
		page.sections.content={"",length=1}
		_G.output = page.sections.content
	end
	-- NOTE: with a top-level pcall the following flags are redundant as the remainder of the request cycle is skipped
	page.abandoned = true
	page.headers = {
		['Content-Type'] = "text/html",
		['X-Powered-By'] = scribe.xpowered,
	}
	page.template = false
	page.collate = false
	page.view = false
	page.controller = nil
	page.editors = false
	if type(to) =='number' then
		-- no need to render content
		page.status = to
		return
	end
	page.status = 500 -- default, the given page may override
	if RenderAbandon("view",to,site.views[to]) ==false then return end
	scribe.Section"template"
	RenderAbandon("view","template",site.views["template"] or site.views["generic/template"])
end end

function Errored(err,trace)
	local err = {title="Error in "..scribe.states[page.state], detail=err}
	if trace then
		scribe.Errorxp(err)
	else
		scribe.Error(err)
	end
	if type(_G.output) =='table' then _G.output = table.concat(output) end
end

function Error(err)
	-- cancels server processing to show an error page
	-- proagation to other services can be handled by wrapping this function
	if type(err) ~="table" then err = {scribe, title=tostring(err)}
	elseif not err[1] then err[1] = scribe end
	-- TODO: aggregrate into bundle errors as per moonstalk.error, or delegate
	log.Info(table.concat({err[1].id, err.title or "",err.detail}," | "))
	if moonstalk.ready then err.at = request.url or scribe.RequestURL() end
	if err.title =="true" or err.detail==true then return end -- already caught
	err.instance = moonstalk.instance -- when in a cluster where errors are collected centrally
	if moonstalk.instance ==0 then err.instance = node.hostname end
	err.identifier = request.identifier -- to aggregrate cascading errors
	page.error = page.error or {} -- we don't currently collect more than one error, but it is possible for multiple to occur such as when a view and template fail
	table.insert(page.error,err)
	scribe.Abandon "generic/error"
end

function Errorxp(err)
	log.Info(err)
	if type(err) ~="table" then err = {realm="site",detail=err} end
	err.detail = string.gsub(err.detail,'"]','')
	err.detail = string.gsub(err.detail,'%[string "','')
	err.detail,err.trace = string.match(err.detail,"(.-)stack traceback%:\n\t(.+)")
	if page.state >=6 and page.state <=8 then
		-- controllers and views
		local name = string.match(err.detail,"([^:]+)")
		err.trace = string.gsub(err.trace,name..":.-\n","")
	end
	local snip = string.find(err.trace,"[C]",40,true)
	if snip then err.trace = string.sub(err.trace,1,snip-2) end
	err.detail = web.SafeText(err.detail)
	if logging > 3 then
		err.trace = web.SafeText(err.trace)
		err.trace = string.gsub(err.trace,'\n\t','<li>')
		err.trace = "<ul><li>"..err.trace.."</ul>"
	else
		err.trace = nil
	end
	scribe.Error(err)
end

function Dump(data,hint)
	page.errors = page.errors or 0 -- TODO: swap use of error (a table) and errors (a counter)
	page.errors = page.errors +1
	local dump = {data=data, form=form, node={hostname=node.hostname}, scribe={instance=moonstalk.instance, hits=scribe.hits}, page=page, request=request, client=client, user=(user or{}).id, site=site.id, merchant=(merchant or{}).id}
	util.FileSave("temporary/dumps/"..os.date("%h%d-%Hh%M").."-"..moonstalk.instance.."-"..scribe.hits.."-"..page.errors..(hint or "")..".lua", util.PrettyCode(dump,7,nil,nil,{env=true,_G=true},false))
	if not data then _G.page.error = nil end
end

function CheckVocabulary(data)
	if logging <4 then return end
	-- TODO: we could also check macros
	-- terms: l.term / L.term; not ending with ]] " '
	for term in string.gmatch(data, [=[[%W][lL]%.([%w_]-)[%s;,%]%)][^%]]]=]) do
		for langid,language in pairs(vocabulary) do
			if type(language[term]) ~="string" then
				vocabulary[langid]._undefined = vocabulary[langid]._undefined or {}
				vocabulary[langid]._undefined[term]=true
			end
		end
	end
	-- plurals: l("term",num)
	for term in string.gmatch(data, [=[[lL]%(['"](.-)[^'"]]=]) do
		for langid,language in pairs(vocabulary) do
			if type(language[term]) ~="string" then
				vocabulary[langid]._undefined = vocabulary[langid]._undefined or {}
				vocabulary[langid]._undefined[term]=true
			end
		end
	end
	-- functions: l.term(arg)
	for term in string.gmatch(data, "[%W][lL]%.([%w_]-)%(") do
		for langid,language in pairs(vocabulary) do
			if type(language[term]) ~="string" then
				vocabulary[langid]._undefined = vocabulary[langid]._undefined or {}
				vocabulary[langid]._undefined[term]=true
			end
		end
	end
end

--[[ not currently used
sequences = {}
function PutIdIntoSequence(item,id,into,sequence)
	-- this function tracks the position of items inserted into an array, and allows the insertion of new items before or after an item with an id specified in a sequence table
	-- sequence: {before|after="id"|{"id1","id2"}}
	local position
	if not sequences[into] then
		sequences[into] = {}
		position = 1
	elseif sequence then
		if sequence.first then
			position = 1
		elseif type(sequence.before)=="string" then
			for i,id in ipairs(sequences[into]) do
				if id == sequence.before then
					position = i
					break
				end
			end
		elseif type(sequence.before)=="table" then
			local lowest = #into
			for _,before in ipairs(sequence.before) do
				for i,id in ipairs(sequences[into]) do
					if id == before then
						if i < lowest then lowest = i end
						break
					end
				end
			end
			position = lowest
		elseif type(sequence.after)=="string" then
			for i,id in ipairs(sequences[into]) do
				if id == sequence.after then
					position = i+1
					break
				end
			end
		elseif type(sequence.after)=="table" then
			local highest
			for _,after in ipairs(sequence.after) do
				for i,id in ipairs(sequences[into]) do
					if id == after then
						if i > (highest or 1) then highest = i end
						break
					end
				end
			end
			position = highest
		end
	end
	position = position or #into
	table.insert(sequences[into],position,id)
	table.insert(into,position,item)
end
--]]

-- view handling

function TranslateView (data,view)
	-- adapted from CGILua's LuaPages functionality; translate() in cgilua/lp.lua © Kepler Project
 	-- translates markup from a view into a function comprising a sequence of string blocks representating static markup that is collated into the outpout table, plus dynamic output defined by either 1. ?(expression) variable macros/tags which append their evaluated value, and 2. <? code ?> inline server processing tags which simply run in place yet may call the write function to append output where necessary
	-- views may declare and utilise local functions, suchb as to wrap blocks of repeatable output and other code, that is called on demand (using server tags not macros, unless the function returns a string)
	local function outputString (s, i, f)
		s = string.sub(s, i, f or -1)
		if #s==0 then return nil end -- ignore blank values
		-- if node.dev then return [[ output[#output+1]= [=[]]..s..[[]=] or EmptyMacro(); ]] end -- TODO:
		return [[ output.length=output.length+1;output[output.length]= [=[]]..s..[[]=]; ]] -- escape the append assignment value as a long string
		--return [[ table.insert(output,[=[]]..s..[[]=]); ]] -- escape the append assignment value as a long string
	end

	-- remove comments -- TODO: disable in dev mode
	data = string.gsub(data, "<!%-%-.-%-%->", function(match) local _,count = string.gsub(match,"\n","\n"); return string.rep("\n",count) end) -- remove html comments including multi-line; preserving line numbers
	data = string.gsub(data, "<script>.-</", function(val)
		-- comments on the same line as the script tag are preserved, so can be used for attribution
		val = string.gsub(val, "/%*.-%*/", function(match) local _,count = string.gsub(match,"\n","\n"); return string.rep("\n",count) end) -- remove multiline comments; preserving line numbers
		val = string.gsub(val,"\n%s*//.-\n", "\n\n") -- remove start of line comments
		val = string.gsub(val,"\n%s-(.-)%s//.-\n", "\n%1\n") -- remove end of line comments; because // is valid in other contexts we have to check it is surrounded by space, thus comments will be preserved if not surrounded by space
		return val
	end)
	data = string.gsub(data, "<style>.-</", function(val)
		val = string.gsub(val, "/%*.-%*/", function(val) local _,count = string.gsub(val,"\n","\n"); return string.rep("\n",count) end) -- remove multiline comments; preserving line numbers
		return val
	end)

	-- rewrite our macro tags
	data = string.gsub(data, "%?(%b())", "\5%1\5") -- can't capture the contents alone, so a two-fold gsub using control chars is simplest
	data = string.gsub(data, "\5%((.-)%)\5","<?= %1 ?>")
--[=[ -- TODO: inline ifthen to avoid evaluating both ifthen values and the functional call; the following doesn't handle values that are function calls with multiple arguments, which would need parsing that iterates through the captured string
	function(capture)
		local count
		capture,replaced = string.gsub(capture, "ifthen%b()", function(captured) -- rewrite the ifthen convenience function as in-line output, avoiding the extra function call
			local expression,true_val,false_val = string.match(captured,"%(([^,]+),([^,)]+),?(.*)%)")
			local replace = " if "..expression.." then output.length=output.length+1;output[output.length]= "..true_val
			if false_val then replace = replace .." else output.length=output.length+1;output[output.length]= "..false_val end
			log.Append(replace .." end ")
			return replace .." end "
		end)
		if replaced >0 then return "<? "..capture.." ?>" end -- must not be further translated as an expression tag because we've already written to output
		return "<?= "..capture.." ?>"
	end)
--]=]

	-- rewrite code blocks and create the main output function
	local body = {"local l=l;local L=L;"} -- NOTE: output cannot be a local as it is reassigned within the scribe environment -- we use a length attribute in the table to improve append performance, as the #length operator traverses the array part each time; however most pages have a fairly limited number of string components thus this is minimaly notable only when many dynamic values are assemabled; there are nonetheless three global looks required in order to complete each value appended which is still cheaper than a traversal or function call; we cannot further optimise due to external calls being able to also append to the output, thus using a local for the length is not possible
	local start = 1 -- start of untranslated part in `s'
	while true do
		local startOffset, endOffset, isExpression, code = string.find(data, "<%?[lua]*[ \t]*(=?)(.-)%?>", start)
		if not startOffset then break end -- reached the end, or contains no processing directives
		table.insert(body, outputString(data, start, startOffset-1))
		if #code>0 then
		if isExpression == "=" then
			table.insert(body, "output.length=output.length+1;output[output.length]=") -- the only valid value is a string or number as required by merge and table.concat, however we do a final iteration replacing nils
			table.insert(body, code)
			table.insert(body, "or '';") -- we do not support nil values in expression and therefore default to an empty string in order to table.concat the output
		else
			-- code/string block
			--[=[
			code = string.gsub(code, "ifthen%b()", function(captured) -- rewrite the ifthen convenience function, but here we only evaluate the value in line not write it
				local expression,true_val,false_val = string.match(captured,"%(([^,]+),([^,)]+),?(.*)%)")
				local replace = " if "..expression.." then "..true_val
				if false_val then replace = replace .." else "..false_val end
				return replace .." end "
			end)
			--]=]
			table.insert(body, string.format(" %s ", code))
		end
		end
		start = endOffset + 1
	end
	table.insert(body, outputString(data, start, nil))
	return table.concat(body)
end

function ParseView(data,view)
	for _,reader in ipairs(moonstalk.readers) do
		data = reader(data,view)
	end
	scribe.CheckVocabulary(data)
	return data
end
function LoadView(view)
	local modified = lfs.attributes(view.path,"modification")
	if modified <= view.modified then return end
	-- NOTE: if the file is currently being uploaded and wiriting has not finished it will fail and subsequent requests don't reload it correctly as the mod date is unchanged; may also apply to controllers -- FIXME: this should be a feature that can be toggled on and off (ie on for dev); with a function to call to reload specific files, and could toggle off during uploads; there could also be a rescan function after upload that simply reloads all modified files; there may be a file flag to check
	view.modified = modified
	--log.Debug("  loading view "..view.id)
	local data,err = util.FileRead(view.path)
	for _,loader in ipairs(moonstalk.loaders.html) do
		-- TODO: use xpcall in dev mode and log the postmark
		data = loader.handler(data,view) or data
	end

	-- NOTE: attributes such as template must be copied from the view to the page in View() as the two are not merged (addresses are)
	if string.find(data,"<html",1,true) then view.template = false end
	--local app = moonstalk.applications[view.translator or "scribe"] -- TODO: this cannot actually be set anywhere, except
	if string.find(data,"?(",1,true) or string.find(data,"<?",1,true) then -- regardless of format, may be using variables or code
		view.loader,err = loadstring(scribe.ParseView(scribe.TranslateView(data,view),view),view.id)
		if err then -- TODO: stack traceback
			view.loader = function () scribe.Error({realm="page",title="Error loading view", detail=err}) end
			scribe.Error({realm="page",title="Error loading view", detail=err})
		end
		--setfenv(view.loader,_G)
	else
		view.static = scribe.ParseView(data,view)
	end

	-- # update modified vocabularies -- HACK: -- TODO: remove when using file change notifications; also remove _G.site assignment in ConfigureBundle
	if site.files["vocabulary.lua"] and lfs.attributes(site.files["vocabulary.lua"].path,"modification") > site.files["vocabulary.lua"].imported then moonstalk.ImportVocabulary(site) end

	return view,err
end

-- controller functions

function LoadController(controller)
	local modified = lfs.attributes(controller.path,"modification")
	if modified <= controller.modified then return controller end
	controller.modified = modified
	local data,err = util.FileRead(controller.path)
	if string.sub(data,1,2)=="#!" or string.sub(data,1,6)=="module" or string.find(data,"\nmodule") then return end -- a daemon/ CLI tool not to be loaded
	--log.Debug("  loading controller "..controller.id)
	for _,loader in ipairs(moonstalk.loaders.lua) do
		-- TODO: use xpcall in dev mode and log the postmark
		data = loader.handler(data,view) or data
	end
	scribe.CheckVocabulary(data)
	controller.loader,err = loadstring(data,controller.id)
	if err then controller.loader = function () scribe.Error({realm="page",title="Error loading controller", detail=err}) end end -- TODO: stack traceback
	setfenv(controller.loader,_G)
	return controller,err
end

-- bundle handling

local exclude = keyed(moonstalk.files)
function ConfigureBundle(bundle,kind)
	-- loads and configures bundle components, from applications and sites as some functionality is shared (e.g. addresses)
	-- kind defaults to application, else specify "sites"
	log.Notice("Configuring "..bundle.id)
	_G.site = bundle -- HACK: remove when using file notifications; LoadView's call to UpdateVocabulary needs a reference to the bundle vocabulary, currently using site

	if bundle.Curator then log.Info ("  curator") end
	if bundle.Editor then log.Info ("  editor") end
	if bundle.authenticator then
		bundle.Authenticator = scribe.GetTablePath(bundle.authenticator)
		log.Info ("  authenticator = "..bundle.authenticator)
	end

	-- define common settings and defaults
	-- FIXME: move to moonstalk server as the vocab and files may now be used in other servers, or disable the database interfaces for those enviornments and call scribe.ConfigureBundle from moonstalk/server
	bundle.name = bundle.name or bundle.id
	if bundle.template then
		log.Info("  template: "..bundle.template)
	elseif kind=="sites" and (bundle.files["template.html"] or bundle.files["template.lua"]) then
		-- we only use default template for sites; to avoid generic template being defined for all app-specified addresses
		bundle.template = "template"
		log.Info "  template"
	end

	-- load all views and controllers
	local counts = {controllers=0,views=0,addresses=0}

	local localised = {}
	for name,file in pairs(bundle.files) do
		if string.sub(file.file,1,8) ~="private/" then
			-- normalise files by uri and merge translations; also drop hidden/excluded files
			if moonstalk.loaders[file.type] then
				-- if translated the file value is meaningless as it only respresents the first recognised URI and consumer must check if file.translated is set
				-- if the file name has multiple formats i.e. name.html and name.lua then the format is meaningless but in some cases (views) will be set to the parsed view's format
				-- the following as used only if this is the first assignment of this name
				-- file and name preserve accented chars, uri and id are normalised
				-- preserve an existing name/id's table or set to this one if the first

				-- dotted segments in file names indicate localisation, otherwise are not allowed
				-- NOTE: translated files may use either format uri.lang.ext or uri.lang.lang-uri.ext, where the prior results in the scribe not assigning addresses for the translated files, and another routine will be required to address them, such as a collator using cookie or url prefix/domain, the latter defines a language-specific address uri, however it cannot be the same as any other language unless site.localise=true -- TODO:
				local locale,localised_name = string.match(file.name,"%.([^%.]*)%.?(.*)$")
				local merged_uri = file.file -- we don't merge different types
				if locales[locale] then
					file.uri = string.sub(file.file,1,-(#locale+1)) -- NOTE: name and file remain unchanged
					file.id = util.Transliterate(file.uri,true)
					localised[file.id] = localised[file.id] or {} -- all files with same id share the same locales table
					file.locales = localised[file.id]
					file.locales[locale] = file
				elseif locale then
					moonstalk.Error{bundle, title="Unknown localisation '"..locale.."' for file: "..file.file}
				else
					file.id = util.Transliterate(file.uri,true)
				end

				local subfolder = string.match(file.id,"^(.*)/")
				if kind ~="sites" then
					-- all applications resources must be prefixed with their id
					local target_app = bundle.id
					if moonstalk.applications[subfolder] and not string.find(file.id,"_extension",1,true) then -- extensions are kept in the app subfolder, and should not function as overrides
						-- an override for another application; the id already contains the app (its non-namespaced subfolder)
						log.Info("  overriding "..file.id)
					else -- add this app's id
						file.id = bundle.id.."/"..file.id
					end
				end -- if a site overrides an appliction no further action is required, as when the apps are loaded they will simply not replace existing resources (with the same id)
				-- TODO: handle translated images (name.language.format)
				file.imported = 0
				file.modified = 0 -- lfs.attributes(file.path,"modification") -- not currently needed for all files and would slow startup, the only place it's needed is on controllers and views which add it in those routines
				if file.type=="lua" and subfolder ~="include" and not exclude[merged_uri] then -- TODO: break out into file format handlers
					-- a controller; not mapped to a url; cannot be translated
					local controller,err = scribe.LoadController(file)
					if controller then
						bundle.controllers[file.id] = controller
						counts.controllers = counts.controllers +1
					elseif err then moonstalk.BundleError(bundle,{localised=(kind=="sites"),realm="bundle",title="Error loading controller",detail=err})
					end
				elseif file.type=="html" then
					-- a view; may be mapped to a url; can be translated (has a language)
					file.bundle = bundle.id
					local function load(file)
						local view,err = scribe.LoadView(file)
						if err then moonstalk.BundleError(bundle,{localised=(kind=="sites"),realm="bundle",title="Error loading view",detail=err,class="lua"}) end
						return view
					end
					if not file.locales then
						bundle.views[file.id] = load(file)
					else -- localised
						bundle.views[file.id] = file
						local view = bundle.views[file.id]
						for language in pairs(file.locales) do
							view[language] = load(path..'.'..language)
							view[language].language = language -- sets the content-language
							if #language >2 then
								-- for localised languages (en-gb) where either the nonlocalised language (en) or locale (gb) are not also defined, we'll define a localised variant as its equivalent
								if not file[string.sub(language,1,2)] then view[string.sub(language,1,2)] = view[language] end
								if not file[string.sub(language,4,5)] then view[string.sub(language,4,5)] = view[language] end -- NOTE: this has problems if both fr and ca-fr are defined as the canadian variant might become the default for french and/or france, however it is recommended that if localised variants are being used, that they must be specified fully in all cases, e.g. use ca-fr and fr-fr, the generic 'fr' version will then be random unless also otherwise specified
							end
							util.ArrayAdd(bundle.translated, language)
							view.translated = true
						end
					end

					if kind=="sites" and bundle.autoaddresses~=false and file.name~="template" then
						-- ids are case sensitive, but addresses are not
						local address = util.NormaliseUri(file.uri, {"/"}) -- TODO: filenames on OS X (via util.Shell) have a different Unicode byte sequence to that of an addresses received from WSAPI therefore Unicode file names are not supported with autoaddresses at present
						local canonical
						if file.uri~=address then canonical = "/"..file.uri end
						table.insert(bundle.addresses, {matches=address, view=file.id, canonical=canonical}) -- does not check if translations share an address, resulting in multiples, but during urn mapping assignment these will overwite each other
						counts.addresses = counts.addresses +1
					end
					-- TODO: configure bundle will be deprecated in favour of post app-loading, these routines should thus be moved to an app FileLoader declaration
					for _,loader in ipairs(moonstalk.loaders) do
						local result,msg = pcall(loader.handler,file,bundle)
						if not result then moonstalk.BundleError(bundle,{realm="bundle",title="Error loading file "..file.file,detail=msg}) end
					end
					counts.views = counts.views +1
				end
			end
		end
	end

	if bundle.views.functions then
		-- views/functions.html is a proxy for loading html fragments as declared functions in a single file
		-- TODO: in dev mode wrap these functions with a call to reload the view, or better just replace the event watcher with this as a discrete function
		util.RemoveArrayKeyValue(bundle.addresses, "matches","functions") -- should not be addressable so remove its default address
		local result,error = pcall(bundle.views.functions.loader)
		if not result then
			moonstalk.BundleError(bundle, {realm="application", title=bundle.name.."/views/functions failed", detail=error, class="lua"})
			bundle.ready = false
		end
	end

	-- map bundle address settings to urns_exact and urns_patterns
	local count = 0
	for i,urn in ipairs(bundle.addresses) do
		local branch
		local invalid
		-- urn.scope = "branch" -- pointer to the app/site for introspection
		-- convert convience syntax for redirects to full spec (i.e. with a controller)
		if urn.redirect then urn.controller = "generic/redirect" end -- more expensive than including handling in the default collator but should be infrequently used
		if bundle.secure and urn.secure ==nil then urn.secure = true end -- propogate bundle setting to urn
		urn.postmark = bundle.id -- allows identification of an address source per-request
		if urn.authenticator ~=false then urn.Authenticator = scribe.GetTablePath(urn.authenticator) end
		if bundle.locks and urn.locks ==nil then urn.locks = bundle.locks end -- this allows a site or app to lock all its addresses, except those that explictly set locks=false
		if urn.collator then urn.collate = scribe.GetTablePath(urn.collator) end

		if urn.polyglot ==nil and (site.polyglot or node.polyglot) then urn.polyglot = true end
		-- convert view and controller names to be unique (bundle-specific)
		-- convert key syntax to patterns
		if urn.matches then
			if type(urn.matches)~="table" then urn.matches={urn.matches} end
			for _,match in ipairs(urn.matches) do
				match = util.NormaliseUri(match, {"/"})
				if bundle.urns_exact[match] then
					branch = bundle.urns_exact[match]
					copy(urn,branch)
				else
					branch = urn
					bundle.urns_exact[match] = urn
				end
				branch.matches = nil
			end
		else
			table.insert(bundle.urns_patterns,urn)
			branch = bundle.urns_patterns[#bundle.urns_patterns]
			if urn.starts then
				branch.pattern = ("^"..util.NormaliseUri(branch.starts, {"/"}))
				branch.starts = nil
			elseif urn.ends then
				branch.pattern = (util.NormaliseUri(branch.ends, {"/"}).."$")
				branch.ends = nil
			elseif urn.contains then
				branch.pattern = (util.NormaliseUri(branch.contains, {"/"}))
				branch.contains = nil
			elseif urn.pattern then
				-- can't be matched to NormaliseUri as will contain pattern match chars
			else
				invalid = "path is invalid (matches|starts|ends|contains|pattern)"
			end
		end

		if kind ~="sites" then
			-- add the app name as a prefix to all names; providing not all ready prefixed (i.e. declared as a nother app's template
			-- TODO: the following is actually useless if files are organised into subfolders, may need to define absolutes with slash prefix again
			if branch.template and string.sub(branch.template,1,1)=="~" then
				branch.template = string.sub(branch.template,3)
			elseif branch.template and not string.find(branch.template,"/",1,true) then
				branch.template = bundle.id.."/"..branch.template
			elseif bundle.template and branch.template==nil then
				branch.template = bundle.id.."/"..bundle.template
			end
			branch.controller = util.Transliterate(branch.controller,true)
			if branch.controller and string.sub(branch.controller,1,1)=="~" then
				branch.controller = string.sub(branch.controller,3)
			elseif branch.controller and not string.find(branch.controller,"/",1,true) then branch.controller = bundle.id.."/"..branch.controller
			end
			branch.view = util.Transliterate(branch.view,true)
			if branch.view and string.sub(branch.view,1,1)=="~" then
				branch.view = string.sub(branch.view,3)
			elseif branch.view and not string.find(branch.view,"/",1,true) then branch.view = bundle.id.."/"..branch.view
			end
		end
		-- TODO: once we have event-driven content refresh, we can reference functions directly instead of their names, avoiding an extra function call; upon refresh the modified dates can be updated, and dev mode logging can be compiled into the function
		if urn.view and not urn.controller and bundle.controllers[urn.view] then
			branch.controller = urn.view
		end
		if urn.controller and not urn.view then
			if bundle.views[urn.controller] then
				branch.view = urn.controller
			end
		end
		-- NOTE: controller and view names should not be manipulated (e.g. with NormaliseUri) as this breaks dynamic reloading
		if invalid then
			moonstalk.BundleError(bundle,{realm="bundle",title="Error configuring address",detail=(i..": "..invalid..". "..util.Serialise(urn))})
		end
		count = count +1
	end
	log.Info("  "..counts.views.." views, "..counts.controllers.." controllers, and "..count.." addresses of which "..counts.addresses.." auto")
end

function GetTablePath(path)
	if not path then return end
	local value = util.TablePath(path)
	if not value then return scribe.Error("Can't get "..path) end
	return value
end

function Debug_Concat(array)
	-- used in place of table.concat to catch invalid types in output and display error page
	local valid,result = pcall(table.concat,array)
	if not valid then
		valid = string.match(result,"index (%d+) in")
		result = {}
		for i=valid-20,valid+26 do
			if i<0 or i> #array then
				valid = ""
			elseif type(array[i]) =="table" then
				valid = web.SafeText(util.Serialise(array[i]))
			else
				valid = web.SafeText(tostring(array[i]))
			end
			table.insert(result,"")
			table.insert(result,valid)
		end
		table.insert(result,43,"<b style='color:red'>")
		table.insert(result,45,"</b>")
		scribe.Error{title="Invalid non-string output",detail=table.concat(result)}
		return ""
	end
	return result
end
