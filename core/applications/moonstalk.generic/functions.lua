--[[	Moonstalk Generic

This application provides essential supporting functions and files to the Moonstalk Scribe.

		Copyright 2010, Jacob Jay.
		Free software, under the Artistic Licence 2.0.
		http://moonstalk.org
--]]

-- TODO: refactor signin/out probably move to teller as bundled behaviours and add equiavalents to tarantool, else add teller-generic and tarantool-generic apps

require "md5"
require "mime" -- {package="mimetypes"}
bcrypt = require "bcrypt" -- {url="https://raw.githubusercontent.com/mikejsavage/lua-bcrypt/master/rockspec/bcrypt-2.1-4.rockspec"}

_G.json = _json or require "cjson" -- OPTIMISE: nginx uses it's own version so we're actually replacing that
json._decode = json.decode
do local type=type; local null=json.null
local function removeNulls(t) -- OPTIMISE: this is only needed in ngx?
	for k,v in pairs(t) do
		if type(v) =='table' then t[k] = removeNulls(v)
		elseif v==null or v=="" then t[k]=nil end -- remove json null and empty strings
	end
	return t
end
function json.decode(data,nulls)
	if nulls then return json._decode(data) end
	return removeNulls(json._decode(data))
end end
_G.md5 = _G.md5 or require"md5"

function Enabler()
	vocabulary.en.Ordinal			= -- TODO: handle unicode ordinal indicators; we can do this in absence of any othe indicator by checking the page.type
	function(number)
		number = tonumber(number)
		if number ==11 or number==12 or number==13 then
			return "th"
		else
			number = tonumber(string.sub(number,-1))
			if number==1 then return "st"
			elseif number==2 then return "nd"
			elseif number==3 then return "rd"
			else return "th" end
		end
	end

	vocabulary.fr.Ordinal			= -- doesn't support gender or plurals
	function(number)
		number = tonumber(number)
		if number ==1 then
			return "er" -- masculine form but correct for numbers without context
		else
			return "ème"
		end
	end

	--[[vocabulary.id.OrdinalPre			= -- TODO: handle prefixes
	function(number)
		number = tonumber(number)
		if number ==1 then
			return "pertama"
		else
			return "ke-"
		end
	end--]]
	--ms.OrdinalPre			= id.OrdinalPre

	local normalised = {}
	local this
	for name,tags in pairs(web.html_allowed) do
		normalised[name] = {}
		this = normalised[name]
		this.strip = tags.strip or {}
		this.attributes = tags.attributes or {}
		for key,value in pairs(tags) do
			local tag
			if type(value)=='table' then
				-- attributes
				tag = key
				this.attributes[tag] = value
				this.attributes[string.upper(tag)] = value
				for _,attribute in ipairs(value) do
					value[attribute] = true
					value[string.upper(attribute)] = true
				end
			else
				tag = value
				this[tag] = "<"..tag..">"
				this[string.upper(tag)] = this[tag]
			end
			this["/"..tag] = "</"..tag..">"
			this["/"..string.upper(tag)] = tags["/"..tag]
		end
	end
	web.html_allowed = normalised

end

local table_insert = table.insert
local string_find = string.find
local string_gmatch = string.gmatch
local string_sub = string.sub
local string_gsub = string.gsub
local table_concat = table.concat

function Editor ()
	-- we must provide canonical links on all pages that are not being served from their primary domain or address, to avoid duplicating the web; this is not currently optional
	if page.status~=200 or page.type~="html" then return end
	if not node.production then page.headers['x-robots-tag'] = "none" end
	if (page.canonical and page.canonical~=request.path) or request.domain~= site.domain or (page.secure and request.scheme~='https') then
		-- TODO: move to page.headers.Link = [[<https://example.com/page-b>; rel="canonical"]] but requires support for multiple declarations
		_G.output = string_gsub(_G.output, '</head>', table_concat{'<link rel="canonical" href="', ifthen(page.secure,'https',request.scheme), '://', site.domain, page.canonical or request.path, '" />\n</head>'}, 1)
	end
end

--[=[
-- the following is an example of how to add developer mode functionality
if node.logging >3 and node.cssrefresh ==true then
	-- supplements the editor with developer-mode functionality, but without requiring an extra if statement in standard mode
local editor_main = editor
function Editor()
	editor_main()
	_G.output = string.gsub(_G.output, [[</head>]], [[<script type="text/javascript" src="/generic/cssrefresh.js"></script>]], 1) -- CSSRefresh uses continuous HEAD polling to determine when to refresh; this is generally undesirable, and use of the bookmark is preferable
end
end
-]=]

function Password(input,factor)
	-- returns a unique salted hash using bcrypt
	-- WARNING: do not use in the database; this function is CPU intensive, and should not be exposed through a public endpoint without a check mechanism to prevent its employment as a DDoS vector; e.g. in cases of increasing server-load and higher than average requests to the endpoint, a feature-flag should be enabled to require the completion of a CAPTCHA before its invocation, and/or access should be blocked where the same username or ip has been used multiple times
	return bcrypt.digest(input, node.bcrypt_factor or 12)
end

function SignoutClient()
	_G.page.authenticator = nil -- this routine populates user instead
	_G.request.client.session = nil
	_G.request.client.keychain = {}
	_G.user = {}
	-- scribe.Cookie("token",nil) -- TODO: should be configured in node
	-- we don't remove request.client.token/id as this is responsible for indicating an identified user, but not indicating an actual authenticated user (request.client.session/user.id)
end

function Signout()
	-- updates the database to disassociate the current client session from its user
	-- is usually run without having first performed CheckSession
	-- NOTE: as we don't have the user yet, we pass the token's ID
	-- WARNING: if the secret has changed, we cannot purge an old id from the db as we cannot decode it, thus these old sessions will only be removed upon their expiry or all sessions may be explicitly removed upon changing the secret
	-- typically a view or controller should change to another view after calling this to prevent access to restricted content, however we  clear the following to be safe
	_G.page.authenticator = nil -- this routine populates user instead
	if not request.client.token then return end
	request.client.id = request.client.id or util.DecodeID(request.client.token)
	teller.Run("generic.EndSession",request.client.id)
	generic.SignoutClient()
	scribe.Redirect([[http://]].. request.domain ..[[/?signed-out]]) -- TODO: use referrer
end

function SetSession(session)
	-- an authenticator is responsible for calling this, and ensuring that request.client.id is valid if a new session has been established
	-- session = {user={nick="name", seen=time, …}, client={seen=time, …}, error="ref"}
	-- client is optional and will always default to having an empty keychain, it provides a reliable way to access values which can be conditional in user, such as keychain, or session-specific values such as when this session was last seen
	-- error is propagated to and used by signin page
	-- user only exists if authenticated and is thus the definitive way to check this
	page.session = session -- anything in session is available from page.session, notably page.session.error
	local user = session.user
	local client = session.client or request.client
	if user then
		_G.user = user
		request.client = client
		client.ip = request.client.ip
			-- the follow prefer user values (i.e. persistent settings) but preserve client values (i.e. browser dervived values)
		-- TODO: support per-domain defaults instead of per-site (e.g. *.co.uk or uk.* locale=uk)
		client.language = user.language or site.language
		client.locale = user.locale or site.locale
		client.timezone = user.timezone or site.timezone
		client.keychain = user.keychain or EMPTY_TABLE
		if not user.token then user.token = util.EncodeID(user.id) end -- OPTIMISE: this should be done on demand using a metatable call e.g. local token = user.token or user.token()
		if client.seen and now > client.seen +time.hour*8 then
			scribe.Token(client.id) -- if the session hasn't been used for a while force renewal of token expiry, this avoids setting it everytime during a short session; this is slightly redundant when site.token_cookie.expiry is set to a large value but nonetheless still required with low-overhead
		end
	end
end

function Authenticator()
	-- an authenticator handler, must be enabled with assessor="generic.Authenticator" on node, site or addresses -- FIXME: not currently implemented
	-- supports authentication (with corresponding database), a preferences cookie, browser language and geoip
	-- TODO: these auth functions must invalidate the token if invalid; client.token = nil; scribe.Cookie"token"
	-- TODO: genericise database interface, e.g. using a function that can simply be replaced with a standard signature ({ip=,id=,browser=}), but preferably db.procedure.Signin() | Authenticate | Signout
	local request = request
	local client = request.client
	if request.post and request.form.action =="SignIn" then
		-- establish a user session
		-- in this model, the signin action preserves its location, thus are a change-state post to any page; in other models a post is made to a specific page with a query param specifying the original page to redirect to on success; signout on the other hand requires a post to the /signout address as it will generally result in a redirect
		return generic.SignIn() -- FIXME: must change the view if failed etc
	elseif client.token then
		-- has a user session
		generic.Authenticate() -- FIXME:
	end
	if not client.preferences and request.headers.cookie then
		-- no user session, fallback to a preferences cookie; applies also if the above failed
		local preferences = request.cookies.preferences
		if preferences then
			client.preferences = true
			client.language,client.locale,client.timezone = split(locale,",",true) -- DOCUMENT: neater and more efficient than seperate cookies
		end
	end
	if not client.preferences and geo and site.geo ~=false then
		-- fallback to GeoIP lookup to better localise the client: if geoip=true looksups are always made; else if geoip=nil lookups are only performed if a request language is ambiguous (used in multiple countries, e.g. English, thus most requests)
		-- we used to also do this after extracting browser languages and if they were ambigious, however this is rather redundant and better enabled explictly; (geo.geoip==true or (geo.geoip==nil and util_Match(request.languages,moonstalk.ambigiousLangs)))
		client.place = geo.LocateIp(client.ip) or {} -- this must be present when geo is enabled to avoid nil index errors in non-conditional code that expects it
		if locales[client.place.country_code] then
			request.locale = client.place.country_code
			client.locale = request.locale
		end
	elseif not client.preferences and request.headers['accept-language'] then
		-- fallback to parsing the browser headers to extract preferred language and locale
		-- TODO: see View() we really need client.culture
		local count = 1
		for lang_locale,language,locale in string_gmatch(string_lower( request.headers['accept-language'] ),"[q%A]*((%a*)%-?(%a*))") do
			if language =="" or count >4 then break -- ideally we'll find a locale in the first few added languages but we won't iterate any further just to do so; also protects against parsing of long input
			elseif moonstalk.languages[language] then
				client.language = language
				if locale and locales[lang_locale_match] then
					client.locale = lang_locale_match
				elseif locales[locale] then
					client.locale = locale
				end
				break
			end
			count = count +1
		end
		-- if there's still no language, moonstalk.Environment will simply default to the site.language and locale
	end
end

function Authenticate()
	 local response = teller.Run ("generic.CheckSession", {site=site.id, id=request.client.id, ip=request.client.ip, gather=page.gather})
	 generic.SetSession(response)
end

do local function InvalidSignin(reason)
	log.Info("failed signin: "..reason)
	page.data[reason] = true -- e.g. invalid
	_G.user = {}
	scribe.UserIdentity()
end
function Signin () -- not declared as action as is a default setup by Starter
	-- only compatible with bcrypt Password function
	-- we're only using email as the login id name for autofill compatability
	scribe.Posted()
	page.authenticator = nil -- this routine populates user instead
	if not request.form.email then return InvalidSignin("unknown")
	elseif not request.form.password then return InvalidSignin("invalid") end
	request.client.id = request.client.id or util.DecodeID(request.client.token)
	local result = teller.Run("generic.Signin", {login=string.lower(request.form.email)})
	if type(result) ~="table" then return InvalidSignin(result)
	elseif not bcrypt.verify(request.form.password,result.hash) then return InvalidSignin("invalid") end
	-- valid signin; start a session
	local agent = scribe.Agent()
	table.insert(agent,request.languages[1])
	scribe.Token(request.client.id) -- if existing extends the expiry, if unassigned creates, if invalid recreates)
	local session = teller.Run("generic.StartSession", {tenant=site.id, id=result.id, token=request.client.id, agent=agent.string, ip=request.client.ip})
	if type(session) =="table" then
		log.Info("successful signin")
		SetSession(session,request.client.id)
		-- users may not have persisted values for the following, in which case should save them so we can not only restore them at signin on another device, but also for use by indepedant (non-Scribe) Teller functions; if so any cookie values will take precedence, however cookie assignments are typically persisted at the same time and thus these values should remain in sync if so
		if site.localise ~=false and not user.locale then
			-- if the site has not disabled it and the user does not have any persisted localisation settings, we persist the current ones providing they don't match the site's defaults (as they'll always be used anyway; albeit not for Teller-originated functions without access to a user-site association)
			-- TODO: Teller transaction; however this should in most cases only ever be run on a user's first signin (i.e. after first-detection, thereafter they'll be saved onyl when changed from my-account or a locale UI)
			if request.client.locale ~=site.locale then save(users[user.id].locale, request.client.locale) end
			if request.client.language ~=site.language then save(users[user.id].languages, request.client.language) end
			if request.client.timezone then save(users[user.id].timezone, request.client.timezone) end
		end
		-- locale, etc. are assigned by Environment() providing this is called before collation, otherwise it must be called explicitly
	end
end
end

if moonstalk.server =="scribe" then
	function Authorised(...)
		for _,key in ipairs{...} do
			if _G.request.client.keychain[key] then return true end
		end
		scribe.UserIdentity()
	end
-- TODO: teller version
end

function Permit(...)
	-- issues an authentication token for a user (having a client session ID) to access a specified resource; functions as an authentication hash; this is bound to the user's session and the current site thus becomes invalid when the associated session is signed-out, but resumes validity if signed-in again; typically used for ephemeral session-specific client-side API requests such as via AJAX
	-- accepts a sequence of resource name or value parameters unique to the associated request (will always be bound to the session and site), typically this might just be a specific API endpoint e.g. Permit("notifications") but this endpoint might allow access to any specified stream, thus including that in the permit will restrict the function of the permit, e.g. Permit("notifications", stream_id)
	-- NOTE: because a permit is bound to a current session, and the session token is HttpOnly (where properly implemented by a user-agent), a permit is not transferable amongst user-agents unless the session token has been hijacked from the wire and is also accompanied by the corresponding session token cookie
	-- NOTE: keychain should also be checked for appropriate privileges
	local arg = {...}
	if type(arg[1]) =="table" then arg = arg[1] end -- accepts a table array instead of list of params; used from Permitted to avoid unpacking and repacking
	table.insert(arg, node.secret) -- this addition to the hash value introduces randomness that should be make it adequately hard to generate a matching permit given a known sequence of resources (e.g. a name, and possibly compromised session/site id)
	table.insert(arg, request.client.id)
	table.insert(arg, site.id)
	arg = string.gsub(
		mime.b64(md5.sumhexa(table.concat(arg))),
		"[/+]",{['/']="~",['+']="-"})
	return arg
end

function Permitted(...)
	-- verifies the match of a sequence of resource name or value parameters (exactly as previously used with Permit), and a last parameter of the encrypted original string from Permit
	local arg = {...}
	local permit = arg[#arg]
	arg[#arg] = nil
	if Permit(arg) ==permit then return true end
	scribe.UserIdentity()
end

-- IDEA: new permit-like mechanism grants a time-limited token that is simply an ID encoded with a future timestamp, checking its validity is as smple as check the time from it, cannot be renwed but can be replaced

-- # Other utility functions

if moonstalk.server =="tarantool" then return end-- FIXME:

_G.http = _G.http or {}
do if not http.New then
	-- must not replace already established interfaces for a specific server environment
	local httpclient = require "socket.http"
	local ltn12 = require "ltn12"
	-- by default these are synchronous blocking functions, and should be replaced with async versions in the async server environments by their Enabler
	-- for async use with openresty see moonstalk.openresty/include/server.lua which accepts defer=secs and/or async=true|func
	http.New = http.New or function(request)
		-- request = {url="http://host:port/path", method="GET", headers={Name="value"}, timeout=millis, json={…}, content=[[text]], urlencoded={…}}
		-- method is optional, default is GET or POST with json, body or urlencoded
		-- response.json is a table if the response content-type is application/json
		-- returns response,error -- NOTE: always use 'if err' not 'if not response' as the response object may nonetheless be returned with an error such as if it could not be decoded
		if request.timeout then httpclient.TIMEOUT = request.timeout/1000 else httpclient.TIMEOUT = 1 end
		request.headers = request.headers or {}
		if request.urlencoded then
			request.method ="POST"
			request.headers['Content-Type'] ="application/x-www-form-urlencoded"
			request.body =TODO(request.urlencoded) -- TODO: server neutral
		elseif request.json then
			request.method = request.method or "POST"
			request.headers['Content-Type'] ="application/json"
			request.body =json.encode(request.json)
		end
		request.method = request.method or "GET"
		log.Info(request.method.." "..request.url)
		request.headers.Host = request.headers.Host or string.match(request.url,"^.-//(.-)/")
		if request.log ~=false then if request.log =="dump" then scribe.Dump(request,"http") else log.Debug(request) end end
		local sink = {}
		request.sink = ltn12.sink.table(sink) -- new table for response body
		local success, code, headers = httpclient.request(request)
		local response = {status=code, headers=headers, content=table.concat(sink)}
		request.response = response -- introspection for request object which has been recorded in _G.request.subrequests
		if not success then log.Alert(response) return nil,code end
		if string.sub(response.headers['content-type'],1,16) =="application/json" then -- sometimes sent with ; charset=
			local err
			response.json,err = json.decode(response.body)
			if err then response._err = err; log.Alert(response); return nil,"JSON: "..err end
		end
		if request.log ~=false then log.Info(response) end
		return response
	end
	http.Request = http.Request or http.New -- no differentiation as deferred and async are not currently supported -- TODO: use task for deferred and call async regardless even though blocking
end
function http.Save(request,path)
	-- request can be a complete request object or URL
	-- the response will be saved to a file at the given path, replacing any existing, and retuning true
	-- cannot save if content-type is html or status is not 200, returning false
	if type(request)=='string' then request = {url=request} end
	request.saveas = path
	http.New(request)
	return http.SaveResponse(request)
end
function http.SaveResponse(request)
	-- this isn't for public use, but can be given as handler=http.SaveResponse and with request.saveas=path instead of calling the convenience function http.Save providing the sever environment supports this; see notes for Save in such envionrments (e.g. openresty)
	local response = request.response
	local result,err
	if response.status ~=200 or string.sub(response.headers['content-type'],1,9) =="text/html" then err = "Will not save html / non-200 responses"; log.Alert(err); return false,err end
	result,err = util.FileSave(request.saveas, response.content)
	if err then err = "Cannot save request from "..request.url.." to "..request.saveas.." because of error: "..err; log.Alert(err); return false,err end
	return true
end
end
