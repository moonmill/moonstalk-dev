-- Moonstalk Server Library
-- functions used amongst components, e.g. to configure and use bundles
-- expects Elevator to have initialised and verified persisted states e.g. Node as few defaults are provided here; defaults from node or elevator dependant functions should thus be set/called in Initialise()
-- intialise a moonstalk server by using dofile"core/moonstalk/server.lua"; moonstalk.Initialise{server="name"}
-- TODO: minimal mode Initialise{mini=true}; will turn off views, starters etc
-- NOTE: is not loaded using pre-processing therefore cannot employ conditional logging

-- globals
-- we define these before running Host.lua as technically it can manipulate
-- _G.sleep should be specified by async capacble servers, and takes seconds
_G.now = os.time()
_G.host= {} -- TODO: move other host-specific values here
_G.request = {client={}} -- logger expects this, but most servers will replace it
_G.db = {} -- the public interface for table-field retrieval, is structured by db system apps when they claim tables managed by them, values are retrived on-demand by the db system's own assigned metamethods / interfaces
_G.model = {} -- a public interface used by some database systems to provide model conversion with named records from the schema e.g. model[record](…) will convert from/to the internal database structure; note that this should be performed transparently when using db or cache
_G.site = {} -- strictly this is scribe specific, but in the teller we propogate it with Environment()
_G.logging = 4

-- moonstalk tables
_G.moonstalk = {
	id = "moonstalk",
	instance = 0,
	applications = {},
	bundles = {}, -- applications are always bundles, sites may not be bundles
	defaults = {},
	readers = {}, -- handlers for reading views
	loaders = {}, -- handlers for configuring files
	databases = {tables={},roles={},systems={}},
	domains = {},
	sites = {},
	site_tokens = {},
	site_packaged = {}, -- last packaged timestamp; if any packaging dependent file exceeds this, packaging is invoked
	errors = {significance=10},
	files = {"functions.lua","elevator.lua","settings.lua","server.lua","request.client.lua", },
	reserved = {"Loader","Enabler","Starter","Shutdown"}, -- reserved keys
	globals = {site=true,locale=true,request=true,output=true}, -- "site","locale","request","output" are the defaults and must be declared as keys to avoid warnings when setting them; all in the array part of the table will be preserved and restored when using moonstalk.Resume before and after a coroutine yields; server environments and applications may add their own globals as names to the array with append({"global_name", …}, moonstalk.globals); globals must be used sparingly as they must be iterated for each request and each coroutine yield to both preserve and restore them using the Resume function; Resume is only defined in Initialise() so that this modified table may be consumed as an upvalue after being modified by any application that may append
	require = {"core/?.lua","core/applications/?.lua","applications/?.lua"},
	loaders = { -- moonstalk.AddLoader()
		lua={},
		html={},
	},
}
_G.enum = {}
setmetatable(_G.enum, {__newindex=function(t,key,value) assert(not t[key],"cannot assign enums to "..key.." as is already claimed"); rawset(t,key,value) end})

moonstalk.path = table.concat(moonstalk.require,";")..";"..package.path -- not to be confused with moonstalk.root; used exclusively by util.ModulePath for import() include()
table.insert(package.loaders,3,package.loaders[2])
package.loaders[2] = function(name)
	-- we only run on linux and have application folders that should contain periods for their creator name, thus we don't want Lua's default expansion of periods to directories, we do however fall back to this behaviour if ours fails, as that has the package manager paths
	for _,path in ipairs(moonstalk.require) do
		path = string.gsub(path,"?",name,1)
		local file = io.open(path)
		if file then file:close(); local path = path; local loader = function() return dofile(path) end return loader end
	end
end


-- Host config doesn't exist on first use of elevator and if we attempt to use the core functions without it then we must exit
-- all node defaults and changes are managed by elevator
local result,err = pcall(dofile,"data/configuration/Host.lua")
_G.node = node
node.databases = node.databases or {}
node.databases.default = node.databases.default or {}

if err and (not elevator or not string.find(err,"No such")) then print"" print(err) os.exit() end -- when executed from the elevator we need to ignore

if node.lua and node.lua.path then -- this is how we propogate luarocks modules to all moonstalk environments for immediate use; these paths are defined for luarocks when doing configuration with ./elevator
	package.path = node.lua.path..";"..package.path
	package.cpath = node.lua.cpath..";"..package.cpath
end

require "moonstalk/utilities" -- {package=false}
require "moonstalk/logger" -- must be after utilities as we need that to load with the conditional functions and this requires it as well
dofile "core/globals/Attributes.lua"

_G.EMPTY_TABLE = {} -- TODO: if node.debug set a metatable that throws an error when modified
if node.environment ~="production" and node.logging >=3 then
	setmetatable(_G.EMPTY_TABLE,{__newindex=function(_,key) moonstalk.Error{title="Attempt to assign key on reserved reused EMPTY_TABLE: "..key, level="Notice"} end})
end

keyed(moonstalk.reserved)
host.servers = keyed(copy(node.servers))
host.roles = keyed(copy(node.roles or {})) -- allows discovery of local roles, e.g. for database queries, if a table's role, is local it can be queried on the local server, not a remote one
moonstalk.root = util.Shell("pwd") -- we can run with sudo, which does not have the original env variables

-- default environments
-- NOTE: nested defaults should not be used unless the root key can be safely replaced during ReadBundle
moonstalk.defaults.applications = {
	translated={},
	addresses={},
	vocabulary={},
	urns_exact={},
	urns_patterns={},
	views={},
	controllers={},
	action={}, -- required to load settings.lua
	errors={significance=10,},
	files={},
	sequence={},
	enum=_G.enum,
}

-- # language localisation functions -- TODO: move to kit or internationalisation app
_G.vocabulary={en={}}
moonstalk.vocabulary_undefined={}
moonstalk.vocabulary_overloaded={}
moonstalk.ambigiousLangs = {}
moonstalk.ambigiousCountries = {}
languages.zh.plurals = util.Plurals[0]
languages.ja.plurals = util.Plurals[0]
languages.ko.plurals = util.Plurals[0]
languages.vi.plurals = util.Plurals[0]
languages.fa.plurals = util.Plurals[0]
languages.tr.plurals = util.Plurals[0]
languages.th.plurals = util.Plurals[0]
languages.lo.plurals = util.Plurals[0]
languages.en.plurals = util.Plurals[1]
languages.nl.plurals = util.Plurals[1]
languages.da.plurals = util.Plurals[1]
languages.de.plurals = util.Plurals[1]
languages.no.plurals = util.Plurals[1]
languages.sv.plurals = util.Plurals[1]
languages.fi.plurals = util.Plurals[1]
languages.hu.plurals = util.Plurals[1]
languages.el.plurals = util.Plurals[1]
languages.he.plurals = util.Plurals[1]
languages.it.plurals = util.Plurals[1]
languages.pt.plurals = util.Plurals[1]
languages.es.plurals = util.Plurals[1]
languages.ca.plurals = util.Plurals[1]
languages.fr.plurals = util.Plurals[2]
languages['pt-br'].plurals = util.Plurals[2]
languages.lv.plurals = util.Plurals[3]
languages.gd.plurals = util.Plurals[4]
languages.ro.plurals = util.Plurals[5]
languages.lt.plurals = util.Plurals[6]
languages.bs.plurals = util.Plurals[7]
languages.hr.plurals = util.Plurals[7]
languages.sr.plurals = util.Plurals[7]
languages.ru.plurals = util.Plurals[7]
languages.uk.plurals = util.Plurals[7]
languages.sk.plurals = util.Plurals[8]
languages.cs.plurals = util.Plurals[8]
languages.pl.plurals = util.Plurals[9]
languages.sl.plurals = util.Plurals[10]
languages.ga.plurals = util.Plurals[11]
languages.ar.plurals = util.Plurals[12]
languages.mt.plurals = util.Plurals[13]
languages.mk.plurals = util.Plurals[14]
languages.is.plurals = util.Plurals[15]

function moonstalk.SaveConfig()
	return util.FileSave("data/configuration/Host.lua","-- Moonstalk node (server) settings; to reconfigure use ./elevator configure\n-- this file is generated automatically, it may be edited but comments are removed\nnode = "..util.SerialiseWith(node,{maxdepth=5,truncate=false}))
end

function moonstalk.GetBundles (path)
	-- returns an array of bundles
	local bundles = {}
	for name,folder in pairs( util.Folders(path) ) do
		if string.sub(name,1,1)~="." and string.sub(name,1,1)~="_" then
			-- must ignore disabled and hidden folders
			folder.file = name
			folder.name = name
			folder.id = name
			folder.path = path.."/"..name
			if string.sub(path,-5) ~= "sites" and string.find(name,".",1,true) then
				-- remove the namespace prefix from application bundle ids (but not their names)
				folder.namespace,folder.id = string.match(name,"(.*)%.(.-)$")
			end
			table.insert(bundles,folder)
		end
	end
	return bundles
end

do
	function moonstalk.ReadBundle (bundle)
		-- loads the core .lua bundle files (settings, functions)
		-- TODO: all our internal vars should be stored somewhere other than the bundle's table as they're too easily replaced in it by the bundle's own values
		log.Info("reading "..bundle.id)
		bundle.id = bundle.id or bundle.name -- may be overridden by settings
		moonstalk.bundles[bundle.id] = bundle
		bundle.files,bundle.modified = moonstalk.DirectoryFlattenedFiles(bundle.path, {public=true}) -- all moonstalk bundles exist at the second level thus their prefix is the first path component (sites or spplications)

		-- define environment, restricts assignments to the current table namespace, unless explictly prefixed with _G.; lookups refer to either the current envionrment (bundle) table if a key matches else infers _G
		-- this allows consistent use of local references in bundle functions (no need for namespace prefixes), as well as having access to the global environment

		-- read the vocabulary before settings as settings may consume values from it
		moonstalk.ImportVocabulary(bundle)

		-- read the schema before settings as settings may consume enums from it
		if bundle.files["schema.lua"] then -- TODO: move to teller.Enabler? teller would then have to be a required app for any bundle using schemas
			moonstalk.BundleSchema(bundle)
		end
		local imported,err
		-- must explicitly load settings if present before processing
		if bundle.files["settings.lua"] then
			bundle.enum = _G.enum
			imported,err = util.ImportLuaFile(bundle.path.."/settings.lua", bundle)
			bundle.enum = nil
			if err then
				moonstalk.Error{bundle,title="Error loading settings for "..bundle.id,detail=err, level="Notice"}
			else
				for langid,language in pairs(bundle.vocabulary or {}) do
					language._id = langid
					language._plurals = (languages[langid] or {}).plurals
				end
			end
		end
		if node.environment ~="production" and bundle.development then
			log.Info("using development settings")
			copy(bundle.development,bundle,true)
		end

		if not err then return true end
	end

	function moonstalk.BundleSchema(bundle)
		-- loads and normalises bundle schemas; currently called from
		-- moonstalk.databases enables lookup of tables by table name, system or instance but assumes all have unique names (thus an instance cannot share a name with a table)
		if bundle.files["schema.lua"] then
			log.Debug("  schema")
			local err
			bundle.schema,err = import(bundle.path.."/schema.lua",{enum=_G.enum}) -- enum is a pointer to reallocate to the global table, which we then remove as is not a schema table
			bundle.schema.enum = nil
			if err then moonstalk.Error{bundle,title="Error in schema", detail=err, class="lua", level="Notice"} return end
		elseif not bundle.schema then return
		else log.Debug("  schema")
		end
		for name,conf in pairs(bundle.schema) do
			-- normalise
			conf.name = conf.name or name
			conf.postmark = bundle.id
			-- we do not add tables to _g.db these must be enabled with apropriate interfaces by the db system app
			moonstalk.databases[name] = moonstalk.databases[name] or conf
			-- populate meta
			if conf.supplemental then
				moonstalk.databases.supplemental[name] = moonstalk.databases.supplemental[name] or conf
				local supplemental = moonstalk.databases.supplemental[name]
				for _,field in ipairs(conf) do supplemental[field] =bundle.id end
			else
				conf.owner = conf.owner or bundle.id
				if moonstalk.databases[name] ~=conf then append(conf, moonstalk.databases[name]) end
				if conf.table ~=false then -- e.g. for models without persistence
					if moonstalk.databases[name] and conf.owner ~= bundle.id then
						moonstalk.Error{bundle,title=bundle.id.." cannot claim database '"..conf.name.."', already claimed by "..conf.owner, level="Notice"}
					else
						moonstalk.databases[name] = conf
						table.insert(moonstalk.databases, conf)
						moonstalk.databases.tables[name] = conf
						moonstalk.databases.systems[conf.system] = true -- currently just a flag to indicate the system is enabled; systems themselves should check this and exit if not enabled
						if type(conf.server) =='string' then
							conf.role = conf.server
							conf.server = nil
						elseif not conf.server then
							conf.role = "default"
						end
						moonstalk.databases[conf.role] = moonstalk.databases[conf.role] or {}
						moonstalk.databases[conf.role][name] = conf
						moonstalk.databases.roles[conf.role] = moonstalk.databases[conf.role]
						if not host.roles[conf.role] then conf.cluster = true end -- flag to resolve which server it is available on using cluster else is on this host (i.e. using localhost)
					end
				end
			end
			-- fields are handled by system apps
		end
	end
end

function moonstalk.EnableBundle(bundle)
	--local sandbox; if bundle.id sandbox=false end -- we want the server functions to have direct write access to the global enviornment rather than invoking a metatable via the bundle environment -- NOTE: this means local (bundle) assignments from functions in these files must use the full namespace, e.g. scribe.wibble=wobble
	--if sandbox ~=false then setmetatable(bundle,{__index=_G, _bundle=bundle.id}) end
	local result,err
	if bundle.files["functions.lua"] then
		-- TODO: setfenv on all functions in the bundle so they share a single namespace and can reference each other using keys not full paths, currently each ImportLuaFile call assigns a seperate environment; this could however only be done once all imports and function assignments are complete as due to nesting of calls (import(functions > import(client))) the deeper calls have no access to the original bundle environment
		bundle.enum = _G.enum
		local result,err = pcall(util.ImportLuaFile, bundle.path.."/functions.lua", bundle)
		bundle.enum = nil
		if not result then
			bundle.ready = false
			return moonstalk.Error{bundle, title="Error loading functions",detail=err,class="lua", level="Notice"}
		end
	end

	if bundle.Loader then -- DEPRECATED: REFACTOR: using a loader is entirely redundant as the functions file serves this purpose itself
		log.Debug(bundle.id..".Loader()")
		result,err = pcall(bundle.Loader)
		if not result then
			moonstalk.Error{bundle, title="Loader failed", detail=err, class="lua", level="Notice"}
			bundle.ready = false
			bundle.Loader = nil
		return end
	end
end

function moonstalk.Error(bundle,error)
	-- (string) or (bundle,string) or or {bundle,level="Alert",title=string,origin=bundle.id,global=false…} where all are optional except title
	-- TODO: err.name to prevent duplicates, typically a simple name, else title is used; if matched then simply the count and last occurance is updated, with the timestamp added to an array; if the error is not identical it is not linked
	-- bundle can be any table havign an errors table, such as a site, but in this case err.realm="site" to prevent propogation to the global moonstalk errors -- REFACTOR: use global=false instead of realm="site"
	-- error.ready=true to not change bundle ready state during startup
	-- error.public=true will show the error.detail, otherwise only the title
	-- error.ref="identifier" will result in errors with identical titles and descriptions being aggregrated, where error.refs[ref]=time; this also permits apps that propagate errors to dedup with a time threshold
	if not error then error = bundle; bundle = nil end
	if type(error) =='string' then error = {title=error} end
	if error[1] then bundle = error[1]; error[1] = nil end
	bundle = bundle or moonstalk
	error.origin = error.origin or bundle.id
	error.when = now
	error.level = log.levels[error.level] or log.levels.Info
	if not moonstalk.started and not error.ready and error.level >log.levels.Info then bundle.ready = false end
	if error.detail and type(error.detail) =='table' then error.detail = util.SerialiseWith(detail,"rootcompact") end
	if error.class =="lua" and error.detail then
		error.detail = string.gsub(error.detail,".-%[%w- \"(.*)","%1",1) or error.detail
		error.detail = string.gsub(error.detail,"\"]:(%d)",":%1",1)
	end
	if error.level <= log.levels.Notice then -- do not store Debug, Append, Info
		if bundle ~=moonstalk and (not error.id or not bundle.errors[error.id]) then
			bundle.errors.significance = bundle.errors.significance or 10 -- should be inherited from default application but isn't
			if error.level < bundle.errors.significance then bundle.errors.significance = error.level end
			-- check for dups and increment
			for _,checkerr in ipairs(bundle.errors) do
				if error.title ==checkerr.title and error.detail ==checkerr.detail then
					checkerr.count = (checkerr.count or 0) +1
					checkerr.when = now
					if error.ref then
						checkerr.refs = checkerr.refs or {}
						checkerr.refs[error.ref] = checkerr.when
					end
					return nil,error.title
				end
			end
			table.insert(bundle.errors,error)
			if error.id then bundle.errors[error.id] = error end
		end
		if error.ref then
			error.refs = {}
			error.refs[error.ref] = now
			error.ref = nil
		end
		if error.global ~=false and (not error.id or not moonstalk.errors[error.id]) then
			if error.level < moonstalk.errors.significance then moonstalk.errors.significance = error.level end
			table.insert(moonstalk.errors,error)
			if error.id then moonstalk.errors[error.id] = true end
		end
	end
	local msg = {error.title or'',tostring(error.detail or'')} -- in tarantool many errors are cdata
	if bundle.id ~= "moonstalk" then table.insert(msg,1,bundle.id) end
	log[log.levels[error.level]](table.concat(msg,' ⸱ '))
	return nil,error.title
end
moonstalk.BundleError = moonstalk.Error -- DEPRECATED: use Error -- TODO: merge into Error and remove references

function moonstalk.AddLoader(bundle,handler) -- TODO: not currently used
	table.insert(moonstalk.loaders,{postmark=bundle.id,handler=handler})
end

function moonstalk.LoadApplications(folder)
	-- get and load application bundles in a folder, adding to the global environment
	-- order is not guaranteed, and compile-time dependencies are not supported (e.g. references to not-yet loaded applications), instead one of the post-load/enable functions
	for _,application in ipairs(moonstalk.GetBundles(folder)) do
		if _G[application.id] then
			log.Info("Reusing global namespace for application: "..application.id)
			copy(application, _G[application.id], false, true) -- replaces -- TODO: check if the namespace contains application values and fail if so
		else
			_G[application.id] = application
		end
		if moonstalk.applications[application.id] then
			application.ready = false
			moonstalk.Error(moonstalk, {realm="bundle",title="Cannot load duplicate application name: "..application.id, level="Notice"})
		else
			moonstalk.applications[application.id] = application
			copy(moonstalk.defaults.applications, application)
			if application.global ~=false then
				_G[application.id] = application -- must be before load so that files can reference its own namespace (e.g. settings)
				if application.namespace then
					_G[application.namespace] = _G[application.namespace] or {}
					_G[application.namespace][application.id] = application
				end
			end
			if moonstalk.ReadBundle(application) then
				-- merge vocabularies and warn if there's any overlap
				for langid,language in pairs(application.vocabulary or {}) do
					vocabulary[langid] = vocabulary[langid] or {}
					if node.logging >=4 then
						moonstalk.vocabulary_overloaded[langid] = moonstalk.vocabulary_overloaded[langid] or {}
						for wordid,word in pairs(language) do
							if vocabulary[langid][wordid] then moonstalk.vocabulary_overloaded[langid][wordid] = application.id end
						end
					end
					vocabulary[langid] = vocabulary[langid] or {}
					copy(language,vocabulary[langid],true,false)
				end
			end
		end
	end
end

function moonstalk.EnableApplications(disable)
	-- TODO: failure mode should be configurable, currently failures are not stopping, which should be an option in case some applications require it, i.e. at any point that ready==false then break and don't continue; all enabler and starter routines should however be non-destructive thus this is not essential

	for name,application in pairs(moonstalk.applications) do
		if not disable[name] then moonstalk.EnableBundle(application) end
	end
	log.Info"Running enablers"
	for name,application in pairs(moonstalk.applications) do
		if not disable[name] then
			-- # Upgraders; -- NOTE: only used in elevator
			local position =1
			local file
			while true do
				-- remove upgraders from the file list to prevent conversion into controllers (in scribe) and enable use in all servers
				file = application.files[position]
				if not file then break end
				if string.find(file.file,"upgraders/",1,true) then
					local version = string.match(file.file,"([%d%.]+)%.lua$")
					if version then -- the folder may contain ancillary lua files shared amongst the upgraders, only version-numbered files are enabled as upgraders
						application.upgraders = application.upgraders or {}
						table.insert(application.upgraders, version)
					end
					application.files[file.file] = nil
					table.remove(application.files, position)
					-- position doesn't change as we just made a removal
				else
					position = position+1
				end
			end
			if application.upgraders then table.sort(application.upgraders) end
			if application.Enabler then
				log.Debug(name..".Enabler()")
				local result,error = pcall(application.Enabler)
				if not result then
					moonstalk.Error{application, title="Enabler failed", detail=error, class=ifthen(moonstalk.server~="tarantool","lua"), level="Notice"}
					application.ready = false
				end
			end
		else
			log.Info("Application disabled: "..name)
		end
	end

	moonstalk.Environment({language=node.language,locale=node.locale},{language="en",locale="eu"}) -- establish initial defaults; applicable to any server which does not set per-request, e.g. the elevator

	local sites_enabled = {scribe=true,elevator=true}
	copy(node.sites,sites_enabled)
	if sites_enabled[moonstalk.server] then
		log.Info"Gathering sites"
		for name,application in pairs(moonstalk.applications) do
			if not disable[name] then
				-- # Sites
				if application.Sites then
					log.Debug(name..".Sites()")
					local result,sites = pcall(application.Sites)
					if not result then
						moonstalk.Error{application, title="Sites failed", detail=sites, class="lua", level="Notice"}
					else
						for _,site in ipairs(sites) do
							scribe.Site(site)
			 			end
					end
				end
			end
		end
	else
		log.Debug("sites are not enabled for this server (requires node.sites."..moonstalk.server.."=true|setting)")
	end

	log.Info"Running starters"
	local finalisers = {}
	for name,application in pairs(moonstalk.applications) do
		if not disable[name] then
			-- # Tests
			if application.files["test.lua"] then -- FIXME: use /tests/*.lua but we need to identify which to run where as otherwise they'll run twice without command line flags, e.g. most will only be for servers, but some may be possible to check in elevator --TODO: should only enable if node.test==true or via some other mechanism
				-- the test file can define and change any bundle resource, such as addresses, views, controllers and enabler functions, through the application upvalue
				log.Debug(name.."/tests.lua")
				local imported,err = util.ImportLuaFile(application.path.."/test.lua",bundle)
				if err then moonstalk.Error(application,{realm="bundle",title="Error loading tests",detail=err,class="lua", level="Notice"}) end
				application.files["test.lua"] = nil
			end
			if application.ready ==nil then application.ready = true end
			if application.Starter then
				-- can optionally return a table defining a handler to run as a finaliser using an arbitrary priority
				log.Debug(name..".Starter()")
				local result,response = xpcall(application.Starter, debug.traceback)
				if not result then
					moonstalk.Error{application, title=name..".Starter failed", detail=response, level="Notice"}
					application.ready = false
				elseif response then -- optional finaliser
					if type(response) =='function' then response = {handler=response} end
					response.id = response.id or name
					response.bundle = response.bundle or application
					table.insert(finalisers, response) -- {bundle=,id=,handler=function,priority=n}
				end
				application.Starter = nil
			end
		end
	end

	if moonstalk.ready ==false then
		if moonstalk.initialise.exit ~=false then
			log.Priority"Failed to initialise; exiting"
			os.exit()
		end
	else
		moonstalk.ready = true
	end
	if moonstalk.initialise.ready ==false then
		-- finalisers must be run manually
		log.Info"Initialisation completed"
	else
		-- finalisers cannot care about server status and are run only if all starters were successful
		util.SortArrayByKey(finalisers,"priority")
		for _,finaliser in ipairs(finalisers) do
			log.Debug(finaliser.id.." ->finaliser")
			local result,error = xpcall(finaliser.handler, debug.traceback)
			if not result then
				local bundle = finaliser.bundle or moonstalk
				moonstalk.Error(bundle, {realm="application", title=finaliser.id.." ->finaliser failed", detail=error, class="lua", level="Notice"})
				bundle.ready = false
			end
		end
		log.Priority(moonstalk.server.." started")
	end
end

function moonstalk.BundleForPath(path)
	local bundle,name = string.match(path,".-/.+")
	if string.find(bundle,"%.",1,true) then
		return moonstalk.sites[bundle],name
	else
		return _G[bundle],name
	end
end

function moonstalk.Shutdown()
	log.Info("Shutting down")
	for id,app in pairs(moonstalk.applications) do
		if app.Shutdown then
			local result,err = pcall(app.Shutdown)
			if err then log.Alert(id..".Shutdown failed: "..err) end
		end
	end
	log.Alert(moonstalk.server.." shutdown")
end

-- # Resume
do
-- these upvalues need to include other application's globals for Resume but are populated by Initialise thus any attempt to call Resume until complete will not properly preserve a request environment
local ipairs=ipairs
local moonstalk_globals=moonstalk.globals
local globals_count = 0
function moonstalk.Resume(call,...)
	-- preserves the current request environment whilst a yielding call is awaiting its response, allowing other requests to be commenced and interleaved, then restores the environment to continue its initiating request
	-- WARNING: MUST be used in asynchronous servers using coroutines (co-operative threads/yielding cosockets) e.g. nginx/openresty; not necessary in synchronous blocking servers (e.g. FastCGI) or any server environment that does not use per-session/request globals (e.g. an email server as all transactions are likely to involve only upvalues)
	-- WARNING: in async servers globals such as _G.user are common across all requests and coroutine invocations, unless wrapped by this function; when a new request is commenced the globals are replaced thus if this not called for an async function the corresponding envionrment will be lost and replaced with the a random one, resulting in dangerous leaking and mixing up of the global environment across unrelated requests
	-- a called function MUST NOT consume any global value as these are not preserved during these calls (even though they may be present sometimes); called functions can thus only consume arguments passed to them (and Resume)
	-- cost is limited to iterating the array of envionrment key names to both fetch and set them to the preserved and global envionrments, thus fairly cheap to perform across multiple yields within a single request and amongst multiple requests, however ideally a request should avoid making multiple smaller yielding requests such as to a database, in favour of a single combined request
	-- where a server has a defined set of globals and does not permit applications to modify them, it may replace this function and only use its upvalues to avoid the cost of iterating moonstalk.globals; alternatively for even lower cost, simply inline the preservation and restoration of necessary globals as locals
	-- in async Moonstalk servers all blocking functions should use yielding coroutines, and therefore unlike with javascript the await is implicit (or rather, is burried in the called function, such as behind an FFI call), thus this function is named resume as only with it can we correctly resume Moonstalk's environment, as for every new interleaved request we replace existing globals
	-- NOTE: only supports five return values from the called function (for http)
	-- TODO: declarative usage so we can add the call to this dyanamically only in coroutine servers stripping calls to Resume in other servers; add to Tarantool when we use Environment; unwrap this function call into inline locals during code translation, which could use a cached list of the variables from last invocation to avoid iteration
	-- TODO: moonstalk.Defer() insert into page.defer and after returning the response run those functions and their arguments, this however is esentially just an immediately released task
	local _G = _G
	-- these are Moonstalk's default globals and we thus hardcode them to avoid iteration, which is used for application-defined globals
	local preserve_site = _G.site
	local preserve_locale = _G.locale -- TODO: this could be moved into request as well
	local preserve_request = _G.request
	local preserve_output = _G.output
	local preserve_env = {} -- these are optional globals
	for key=1,globals_count do key = moonstalk_globals[key]; preserve_env[key] = _G[key] end -- preserve globals as registered with moonstalk, so that other requests can reuse these in the _G table and replace globals within it for their own use
	local a,b,c,d,e = call(...) -- multiple yields may in fact occur between here and resume, however providing none reference the global envionrment or only use locals this is no issue
	if _G.request == preserve_env.request then
		-- no intervening requests so no need to restore
		return a,b,c,d,e
	end
	_G.site = preserve_site
	_G.locale = preserve_locale
	_G.request = preserve_request
	_G.output = preserve_output
	for key=1,globals_count do key = moonstalk_globals[key]; _G[key] = preserve_env[key] end -- restore globals registered with moonstalk back to the persistent _G table table so that views and controllers may continue to use them
	return a,b,c,d,e
end

function moonstalk.Initialise(options)
	-- options.applications=false defers loading
	-- options.ready=false should be used in client apps (named as a server) to silence their started status and finalisers, or in servers which carry out additional long running startup routines before they manually run finalisers and log.Priority"Started"
	-- options.exit=false if the process should remain running/interactive in cases of errors during initialisation (default is to exit, e.g. in the case of a database it shoudl not run if it cannot guarantee the integrity of its enviornment)
	-- options.server = "name" for any daemon process with an elevator.lua file
	-- options.procedures = true for a lua database server
	-- options.coroutines = false for a single-threaded server
	-- options.disbale = {"name"}; these applications will not be enabled
	-- options.async = false; single-threaded servers without native coroutine yielding for blocking operations -- TODO: use in loader to strip calls to moonstalk.Resume

	_G.now = os.time()
	moonstalk.started = false -- in progress
	moonstalk.instance = options.instance or moonstalk.instance
	moonstalk.initialise = options
	moonstalk.server = options.server
	local bundle,err = util.ImportLuaFile("moonstalk/utilities-dependent", util) -- modules now available so we'll add the dependent functions to util
	if err then moonstalk.Error(moonstalk, {realm="moonstalk",title="Failed to import 'utilities-dependent.lua'"; detail=err, class="lua", level="Notice"}) end

	moonstalk.resolvers = {}
	local resolvers = io.open("/etc/resolv.conf")
	if resolvers then
		for line in resolvers:lines() do
			table.insert(moonstalk.resolvers,string.match(line,"nameserver (.+)"))
		end
		resolvers:close()
	end
	if not moonstalk.resolvers[1] then
		moonstalk.resolvers[1] = "1.1.1.1"
		if moonstalk.server =="elevator" then
			display.error("No resolvers available, using 1.1.1.1",false)
		else
			moonstalk.Error(moonstalk, {realm="moonstalk",title="No resolvers available", level="Info"})
		end
	end
	options.disable = keyed(options.disable) or {}
	log.level = options.level or node.logging
	log.identifier = moonstalk.server
	_G.logging = node.logging -- this is used as a slightly cheaper way of checking the loadtime log.level on conditional actions
	log.Open(options.log or "temporary/moonstalk.log")
	log.Notice("Initialising Moonstalk for "..options.server.." on "..node.hostname)

	if node.logging > 3 and DISABLED then -- FIXME: see functions below
		moonstalk.translate = moonstalk.Debug_translate
		moonstalk.Translate = moonstalk.Debug_Translate
	else
		moonstalk.Debug_translate = nil
		moonstalk.Debug_Translate = nil
	end
	-- define a proxy for the vocabularies
	-- these are also defined as upvalues within LoadView
	_G.l = {} -- provides metable function for localised voacbularies; see translate()
	_G.L = {} -- Intial cap version of l
	setmetatable(_G.l,{__index=moonstalk.translate, __call=moonstalk.plural})
	setmetatable(_G.L,{__index=moonstalk.Translate, __call=moonstalk.Plural})

	math.randomseed(os.time()*10000)
	posix_stdlib.setenv("TZ","UTC")

	util.SysInfo()
	if sys.platform == "Linux" then
		sys.stat = "--printf %Y"
		sys.prefix = ""
	else
		sys.stat = "-f %m"
		sys.prefix = ""
	end

	-- # Timezones
	-- load tz timezone names and associate with matching country locales
	--if not posix.access("data/locales.lua","f") then -- TODO: cache the initialised locales and timezone data
	local file = io.open("core/globals/zone.tab","r")
	if not file then
		log.Notice ("Cannot open zone.tab")
	else
		for line in file:lines() do
		    local cc,name = string.match(line,"^(..)\t.-\t([^\t]+)")
		    -- TODO: index the location and index into geo so we can find other nearby timezones
			if cc then
			    cc = string.lower(cc)
			    timezones[name] = {value=name, label=name, comment=comment}
			    if locales[cc] then
			    	locales[cc].timezones = locales[cc].timezones or {}
					table.insert(locales[cc].timezones, timezones[name])
				end
				table.insert(timezones,timezones[name]) -- we also maintain a sorted array of all timezones
			end
		end
		file:close()
	end
	-- load timezone abbreviations
	-- TODO: this data source lacks offset values for all the timezones, which we use to sort the timezones table, thus those without it appear randomly
	local file = io.open("core/globals/GeoPC_Time_zones.csv","r") -- sourced from http://www.geopostcodes.com/GeoPC_Time_zones
	if not file then
		log.Notice ("Cannot open GeoPC_Time_zones.csv")
	else
		for line in file:lines() do
		    local name,offset,abbr,abbr_dst = string.match(line,[["..";.-;"(.-)";...;"UTC(.*)";"([^/]+)/?(.*)";.+]])
		    if timezones[name] then
		    	if abbr =="GMT" then abbr = "UTC" end
			    timezones[name].abbr = abbr
			    timezones[name].abbr_dst = abbr_dst
			    local direction,hours,minutes = string.match(offset,"(.)(%d+).?(%d*)")
			    direction = direction or "+"
			    hours = hours or "00"
			    minutes = minutes or "00"
			    hours = util.Pad(hours,2)
			    minutes = util.Pad(minutes,2)
			    timezones[name].offset = direction..hours..":"..minutes
			    offset = (tonumber(hours) or 0)*60+(tonumber(minutes) or 0) -- hours needs a fallback for "UTC"
			    if direction =="-" then offset = offset *-1 end
			    timezones[name].offset_minutes = offset
			    timezones[name].label = timezones[name].offset.." "..(timezones[name].abbr or "").." "..string.gsub(name,"%_"," ")
		    end
		end
		file:close()
	end
	timezones.UTC = {value="UTC",label="+00:00 UTC", offset=0, abbr="UTC"}
	table.insert(timezones,timezones.UTC)
	util.SortArrayByKey(timezones,"offset_minutes")

	--# Applications
	-- vocabularies need to be loaded before normalisation
	moonstalk.LoadApplications"core/applications" -- bundled
	moonstalk.LoadApplications"applications" -- user installed (seperate repos)

	-- # Locales
	-- index locales by country_code (required prior to timezones)
	locales.currencies = {} -- contains a pointer for the currency code to its root locale; also contains currency symbols set to true if ambigious (used for more than one currency code)
	for _,locale in ipairs(locales) do
		locales[locale.country_code] = locale
		locales[locale.iso3166_3] = locale
		if locale.cctld then locales[locale.cctld] = locale end
		if locale.currency_root~=false then locales.currencies[locale.currency_code] = locale end
		local symbol = locales.currencies[locale.symbol] -- if this value exists as true then the symbol is ambigious and the currency code may need to be used instead if the user locale does not match
		if locale.symbol then
			if symbol ==nil then
				locales.currencies[locale.symbol] = locale.currency_code -- for comparison if used by multiple currencies, will removed if not
			elseif symbol ~=locale.currency_code then
				locales.currencies[locale.symbol] = true
			end
		end
	end
	for symbol,code in pairs(locales.currencies) do if type(code)=='string' then locales.currencies[symbol]=nil end end -- remove the symbols with only one currency

	-- build a list of ambiguous languages with more than one country, and countries with more than one language; these are used when looking up a suitable locale with geoip
	-- sort and populate terms.languages with id=name for every localised language name
	-- sort and index locales by country_code
	-- both terms.languages and locales are keyed and may be iterated using ipairs for a sorted list, or accessed with key-lookups for their values
	local function NormaliseLocale(locale)
		-- this is run on both primary locales and variant locales
		-- TODO: parse the dates and transform them into compiled functions that only return the desired value
		locale.date = copy(locale.date or {})
		locale.dates = locale.dates or {}
		for name,default in pairs(terms.dates.day_month) do -- ensure defaults
			locale.date[name] = locale.date[name] or locale.dates.all or locale.dates[name] or default
		end
	end
	for code,e164 in pairs(terms.e164) do e164.code = code end -- TODO: use countryInfo and make this only for shared area codes
	local checks,additions = {},{}
	for _,locale in ipairs(locales) do
		locale.id = locale.id or locale.country_code
		locales[locale.id] = locale
		if locale.id ~= locale.country_code then locales[locale.country_code] = locale end -- indexed by both country code and id
		if locale.e164 then util.ArrayAdd(terms.e164[locale.e164], locale.e164) end
		locales[locale.urn] = locale
		locale.timezone = timezones[locale.timezone]
		locale.timezones = locale.timezones or {locale.timezone}
		if locale.symbol_r then
			locale.symbol_r = locale.symbol
		else
			locale.symbol_l = locale.symbol
		end
		for _,lang in ipairs(locale.languages) do
			if vocabulary[lang] and not terms.languages[lang] then
				terms.languages[lang] = vocabulary[lang]['language_'..lang] -- makes the table keyed
				table.insert(terms.languages, {value=lang, label=vocabulary[lang]['language_'..lang]})
			end
			if logging >3 then
				if not checks[lang] then
					checks[lang]=true
				else
					moonstalk.ambigiousCountries[locale.country_code]=true
					moonstalk.ambigiousLangs[lang]=true
				end
			end
		end
		local country_name = (vocabulary[locale.languages[1]] or vocabulary.en)['country_'..locale.country_code] or vocabulary.en['country_'..locale.country_code]
		if not country_name then
			country_name = "⚑"..string.upper(locale.country_code)
			log.Debug("  missing vocabulary "..locale.languages[1]..".".."country_"..locale.country_code)
		end
		locale.name = country_name
		if locale.variants then
			-- variants define per-language exceptions; thus the default locale needs an additional identifier with its default (first) language
			if not locale.languages[1] then log.Debug("	missing locale language for "..locale.id)
			elseif not vocabulary[locale.languages[1]] then log.Debug("	missing "..locale.languages[1].."vocabulary for "..locale.id)
			else
				locale.name = locale.name.." ("..(vocabulary[locale.languages[1]])["language_"..locale.languages[1]] or vocabulary.en["language_"..locale.languages[1]]..")" -- TODO: match the language, and if terms.langauges[matched].rtl then handle sorting for countries below based on code not label
			end
		end
		-- establish any locale (language) variants
		local variants = locale.variants or {}; locale.variants = nil -- we don't want this copied to the variants
		for name,variant in pairs(variants) do
			if not variant.languages then
				variant.languages = copy(locale.languages)
				table.insert(variant.languages,1,variant.language) -- this is the primary language
			end
			copy(locale,variant,false,false) -- each variant inherits all parent locale values except the overrides
			variant.variants = nil -- else woudld recurse
			variant.variantof = locale.id
			variant.id = name.."-"..locale.id
			local country = (vocabulary[name] or vocabulary.en)['country_'..locale.country_code]
			local language = (vocabulary[variant.language] or vocabulary.en)["language_"..variant.language]
			if country and language then
				variant.name = (vocabulary[name] or vocabulary.en)['country_'..locale.country_code].." ("..(vocabulary[variant.language] or vocabulary.en)["language_"..variant.language]..")"
			else
				variant.name = "⚑"..string.upper(variant.id)
				if not country then
					log.Debug("  missing vocabulary "..name..".".."country_"..locale.country_code)
				else
					log.Debug("  missing vocabulary "..name..".".."language_"..variant.language)
				end
			end
			NormaliseLocale(variant)
			locales[variant.id] = variant
			table.insert(additions, variant)
		end
		if locale.country ~=false then -- e.g. Europe
			terms.countries[locale.country_code] = true
			table.insert(terms.countries.options, {value=locale.country_code, label=country_name, sort=string.sub(country_name,1,2)})
			local country_prefix = string.sub(country_name,1,1) -- we only add names in other languages if they will sort significantly differently (i.e. first char differs)
			 -- TODO: add support for non-language locale country name variants e.g. "United Kingdom","Great Britain","England","Scotland" all mapped to the same locale; these should probably be listed in Attributes as locale variant codes and could even be stored in records (e.g. user.locale) but stripped to primary locale when not needed; e.g. gb-sc = en["gb-sct"]="Scotland"; gb-nir = "Northern Ireland"; some such already have established codes https://en.wikipedia.org/wiki/ISO_3166-2:GB
			for _,lang in ipairs(locale.languages) do
				local country_variant = (vocabulary[lang] or vocabulary.en)["country_"..locale.country_code] or vocabulary.en["country_"..locale.country_code]
				if country_variant and string.sub(country_variant,1,1) ~= country_prefix then
					table.insert(terms.countries, {value=locale.id, label=country_variant, sort=string.sub(country_name,1,2)})
				else
					-- country_variant = "⚑"..string.upper(lang)
					-- FIXME: log.Debug("  missing vocabulary "..lang..".".."country_"..locale.country_code)
				end
			end
		end
		locale.variants = variants
		NormaliseLocale(locale)
	end
	append(additions,locales)

	node.language = node.language or locales[node.locale].languages[1] -- language is not usually set

	for id,vocab in pairs(vocabulary) do
		local lang,culture = string.match(id,"(.-)%-(.+)")
		if culture and not vocabulary[lang] then
			-- if a cultured language is specified with no uncultured equivalent, we make them the same
			vocab._noculture = true
			vocabulary[lang] = vocab
			log.Info("Vocabulary "..id.." has no uncultured version, terms will be shared.")
		end
		-- FIXME: if not vocab.plurals then log.Alert("Vocabulary "..id.." has no plurals defined.") end
	end


	-- # Localisation

	locales[""] = {country=false,languages={},vocab={}} -- add a dummy locale to avoid errors looking up unknown country_codes without having to make the lookups conditional
	-- the following are for compatibility with browser language variations
	locales.gb = locales.uk
	-- the following are additional timezones associated with specific countries (e.g. as dependancies or territoires) but have their own country_code, and thus locale (if available in Moonstalk); we associate them here for the sake of usability (e.g. when selecting the parent locale, these timezones can appear with it); all timezones sharing the same country_code are grouped under their locale in the prior timezones parsing routine
	table.insert(locales.fr.timezones, timezones['Indian/Reunion'])
	table.insert(locales.fr.timezones, timezones['Indian/Mayotte'])
	table.insert(locales.fr.timezones, timezones['America/Guadeloupe'])
	table.insert(locales.fr.timezones, timezones['America/Martinique'])
	table.insert(locales.fr.timezones, timezones['America/Cayenne'])
	table.insert(locales.fr.timezones, timezones['America/Miquelon'])
	table.insert(locales.fr.timezones, timezones['America/Marigot'])
	table.insert(locales.fr.timezones, timezones['America/St_Barthelemy'])
	table.insert(locales.uk.timezones, timezones['Europe/Isle_of_Man'])
	table.insert(locales.uk.timezones, timezones['Europe/Jersey'])
	table.insert(locales.uk.timezones, timezones['Europe/Guernsey'])
	table.insert(locales.uk.timezones, timezones['Europe/Gibraltar'])
	table.insert(locales.uk.timezones, timezones['Atlantic/Stanley'])

	-- # Miscellaneous
	util.SortArrayByKey(terms.languages,"value") -- using id avoids unicodes being dumped at the bottom -- TODO: move the node default to the top?
	util.SortArrayByKey(terms.countries.options,"sort")
	util.SortArrayByKey(locales,"country_code")
	-- map utf8 character codes for transliteration
	terms.transliteration.utf8_ascii = {} -- maps directly to ascii
	terms.transliteration.utf8_codes = {} -- maps to codetable
	for _,codetable in ipairs(terms.transliteration) do
		terms.transliteration.utf8_ascii[codetable.utf8_upper] = codetable.ascii_upper
		terms.transliteration.utf8_ascii[codetable.utf8_lower] = codetable.ascii_lower
		terms.transliteration.utf8_codes[codetable.utf8_upper] = codetable
		terms.transliteration.utf8_codes[codetable.utf8_lower] = codetable
	end

	moonstalk.SetInstance(moonstalk.instance)

	--# Applications
	-- we can't call application functions (enablers/starters) until the environment is normalised
	-- and checks applications for errors
	moonstalk.EnableApplications(options.disable)

	if moonstalk.async ==false then
		log.Debug"Moonstalk is running in a synchronous server environment"
	else
		globals_count = #moonstalk.globals
		if globals_count >0 then log.Debug("Resume is maintaining "..globals_count.." supplementary moonstalk.globals: "..table.concat(moonstalk.globals,", ")) end
		keyed(moonstalk.globals)
	end
	setmetatable(_G.enum,nil)
	keyed(moonstalk.files)

	moonstalk.started = now
end
end



-- # ID functions

do
local continuum = {instance="000",current=0,time=0,min=10000,max=99999,placeholder="00000000"}
function moonstalk.Continuum()
	-- provides an incrementing id during for any given second scope, then resets to a random start to prevent ids from commencing at 1 which exposes use capacity within the scope
	if now ~= continuum.time then
		-- reset the continuum starting from a new random position scoped to the current second
		continuum.time = now
		continuum.threshold = math.random(continuum.min, continuum.max)
		continuum.start = continuum.current
	elseif continuum.current < continuum.max then
		continuum.threshold = continuum.threshold +1
	else -- continuum.current == continuum.last
		-- roll around
		continuum.threshold = 0
	end
	return continuum.threshold
end
function moonstalk.SetContinuum(key,value)
	-- WARNING: continuum.max and continuum.max must be the same length; continuum.max must have enough capacity for the intended use
	continuum[key]=value
end
function moonstalk.GetContinuum(key) return continuum[key] end
function moonstalk.SetInstance(instance) -- typically a number
	continuum.instance = util.Pad(instance, "0", 3)
	-- continuum.placeholder = string_rep("0", #continuum.instance + #continuum.min) -- insused by IDFromDate
	if instance >0 then log.identifier = moonstalk.server.."/"..continuum.instance end
end

local moonstalk_Continuum = moonstalk.Continuum
function util.CreateID ()
	-- generates a guaranteed unique (across clustered instances) 18-digit string for use as an ID, comprising a timestamp with second resolution (10 digits), the instance id (3 digits), and an incrementor (from the Continuum whose length is configurable but defaults to 5 digits for up to 90000 IDs per second)
	-- simplistic multipurpose ID generator with per-instance indpendence (standalone generation in a cluster)
	-- uses continuum to provide slots for IDs beyond the second-resolution capacity of the timestamp; as the continuum starts from a random number (but nontheless increments), any given ID does not reveal how many other IDs were generated within that scope (i.e. in the second it was created)
	-- NOTE: the timestamp is the first component of the ID and IDs can thus be used for date-based ordering, irrespective of the node it was generated on
	-- WARNING: instance must be defined as a 3 digit number (max 999); if the instance is not registered (i.e. default =="000") then uniqueness is only guarenteed with a single instance having this id
	-- Lua's default number precision handles integers up to 9007199254740992 (low end of 16 digits, thus essentially 15 digits if all reach 9) thus IDs cannot by default be coerced to numbers, but if the non-date part is 6 digits (instance and counter) it can actually reach 9 thus dates until around the year 2270 could be handled with either a 2-digit instance and continuum.max=9999 or 3-digit instance and continuum.max=999
	local id = moonstalk_Continuum()
	return continuum.time .. continuum.instance .. id
end
function util.IDFromDate(date)
	-- converts a date timestamp to a pseudo-ID that can be used for date-comparison with IDs from CreateID
	-- NOTE: can only be used for > or < comparisons to a resolution of seconds; cannot be used for date equality comparison as for any given date and ID with the same timestamps, the ID will always have a randomly greater value
	return date..continuum.placeholder
end
local string_sub = string.sub
local tonumber = tonumber
function util.DateFromID(id)
	-- returns the timestamp of a number ID from CreateID
	return tonumber(string_sub(id,1,10))
end
end


-- # Localisation
-- TODO: in dev mode show (e.g. with title attibute) where terms are defined; create an index of files and the terms defined in them in the order they are replaced (if multiple)
-- OPTIMIZE: pre-render views for each declared language (for an address? or perhaps by inheriting to the view with a <? languages = declaration, requring a metatable on its enviornment during initialisation ?> ) replacing calls to l.* with the term, this avoiding the overhead of a metatable call, function invocation and table lookup for each term
do
local vocab1,vocab2,vocab3 --,vocab4,vocab5
local util_Capitalise = util.Capitalise
function moonstalk.translate(_,term) return vocab1[term] or vocab2[term] or vocab3[term] end -- OPTIMISE: in the scribe this should use local voacab and inline instead of metatable func call
function moonstalk.Translate(_,term) return util_Capitalise( vocab1[term] or vocab2[term] or vocab3[term] or term ) end
function moonstalk.Debug_translate(_,term) -- FIXME: abbr insertion doesn't have reference to output? is disabled in Initialise()
	-- TODO: this is actually a scribe functionality as it uses HTML thus needs moving its enabler but would loose the upvalues, so probably just best to wrap in an if moonstalk.server =="scribe"
	-- TODO: this behaviour is significantly different from production as that will throw errors for nil values or fail to concatenate output, thus may be better to remove and instead compile all use of l.* l[*] etc and compare against available keys, to provide a report
	local translated = vocab1[term] or vocab2[term] or vocab3[term] or "⚑"..(term or "UNDEFINED")
	local open,close = string.match(_G.output[_G.output.length] or "","(<*).-(>*)[^>]*$") -- where translations are inserted directly into a tag, we'll find an open but not a close, however if other values are inserted prior to the translation then this will fail, thus we should check the preceeding one as well for an unclosed tag
	if type(translated) ~='string' or (open and not close) then return translated end
	return [[<abbr class='debug' title=']]..term..[['>]].. translated ..[[</abbr>]]
end
function moonstalk.Debug_Translate(_,term)
	local translated = util_Capitalise(vocab1[term] or vocab2[term] or vocab3[term] or "⚑"..(term or "UNDEFINED"))
	if type(translated) ~='string' then return translated end
	return [[<abbr class='debug' title=']]..term..[['>]].. translated ..[[</abbr>]]
end

local languages = languages
function moonstalk.plural(_,term,number)
	if vocab1[term] and languages[vocab1._id].plurals then
		return languages[vocab1._id].plurals (vocab1[term],number)
	elseif vocab2[term] and languages[vocab2._id].plurals then
		return languages[vocab2._id].plurals (vocab2[term],number)
	elseif vocab3[term] and languages[vocab3._id].plurals then
		return languages[vocab3._id].plurals (vocab3[term],number)
	else
		return moonstalk.translate(nil,term)
	end
end

do
local moonstalk_plural = moonstalk.plural
local util_Capitalise = util.Capitalise
function moonstalk.Plural(_,term,number) return util.Capitalise(moonstalk_plural(_,term,number)) end
end

local unpopulated = EMPTY_TABLE
local vocabulary = _G.vocabulary
function moonstalk.Environment(client, tenant, content)
	-- establishes normalised moonstalk settings, currently this only applies to locale and translations and must be called upon any change to the consuming client
	-- utilises an optional content-realm assigned vocabulary, then a tenant defined realm before finally fallingback to the global shared vocabulary realm
	-- a content realm may support a language not otherwise supported
	-- a page controller, curator or collator may set content.language in order to support other case specific languages such as dervived from routing
	-- client must be passed as a table providing optional values to use for language, locale and timezone, else those in tenant will be used; node is an adequate fallback for tenant if client deos not have all these values, however an envionrment may already have set client to a defaul such as tenant (site)
	-- all values are expected to be valid, i.e. must exist as defined languages
	-- the scribe ensures client always has language, either from user or browser detected and matching the site, but defaulting to site/tenant language, however other environments may not so here we default to the tenant values regardless
	-- not strictly necessary if node is only serving static pages, as all sites share the same language, and clients cannot set preferences, however fairly low cost thus standard in servers handling user configurable requests and as localised functions may nonetheless be called for formatting
	local language,locale
	if content then locale = content.locale end
	_G.locale = locale or locales[client.locale] or locales[tenant.locale]
	if (not content or not content.vocabulary) and not tenant.vocabulary then
		language = client.language or tenant.language
		vocab1 = vocabulary[language]
		vocab2 = unpopulated
		vocab3 = unpopulated
	elseif not content or not content.vocabulary then
		language = client.language or tenant.language
		vocab1 = tenant.vocabulary[language] or unpopulated
		vocab2 = vocabulary[language]
		vocab3 = unpopulated
	else
		language = content.language or client.language or tenant.language
		vocab1 = content.vocabulary[language] or unpopulated
		vocab2 = tenant.vocabulary[language]
		vocab3 = vocabulary[language]
	end
	-- TODO: add timezone; can't really use client.timezone as the table pointer as it's conditional but we need and easy-to-reference table that falls back: timezones[request.client.timezone or site.timezone] or locale.timezone
	return language
end
end

function moonstalk.Explore(path)
	local value = util.TablePath(_G,path)
	if type(value) ~="table" then return value end
	local items = {}
	for key,value in pairs(value) do
		if type(key) ~="string" and type(key) ~="number" then key = tostring(key) end
		local item = {key=key,type=type(value)}
		if item.type =="table" then
			if not next(value) then item.type = "empty" end
		elseif item.type =="string" then
			item.value = value
		elseif item.type =="number" then
			item.value = value
		elseif item.type =="boolean" then
			item.value = tostring(value)
		end
		table.insert(items,item)
	end
	return items
end

function moonstalk.ImportVocabulary(bundle) -- TODO: invoke on file change; remove hack from loadview
	-- unlike settings, vocabularies have no access to the global environment
	if not bundle.files["vocabulary.lua"] then return end
	bundle.polyglot = bundle.polyglot or true
	bundle.vocabulary = bundle.vocabulary or {}
	log.Debug("  vocabulary")
	bundle.files["vocabulary.lua"].imported = now
	bundle.vocabulary.vocabulary = bundle.vocabulary -- this is available so that long-form keys can be declared with the full-form syntax of vocabulary['en-gb'].key_name
	setmetatable(bundle.vocabulary, {__index=function(table, key) local value = rawget(table,key) if not value then value = {} rawset(table,key,value) end return value end}) -- adds language subtables ondemand -- TODO: if not value and languages[key]
	local imported,err = util.ImportLuaFile(bundle.path.."/vocabulary.lua",bundle.vocabulary,function(code)return string.gsub(code,"\n%[","\nvocabulary[")end) -- translates ['en-gb'].key_name long-form declarations to _vocabulary['en-gb'].key_name
	if err then moonstalk.Error(site,{realm="bundle",title="Error loading vocabulary",detail=err}) end
	setmetatable(bundle.vocabulary, nil)
	bundle.vocabulary.vocabulary = nil
	-- TODO: copy(language,vocabulary[langid],true,false)
end

function moonstalk.FileFunctions(path,into)
	local imported,err = import(path,{}) -- we don't want to keep the environment from this
	if err then return nil,err end
	local results = into or {}
	for name,item in pairs(imported) do
		if type(item)=="function" then results[name] = item end
	end
	return results
end

function moonstalk.dofile(path)
	-- removes logging from included files such as server components and libraries
	if logging >=5 then dofile(path) end
	local code,err = util.FileRead(path)
	if not code then err="Cannot read "..path.." to import"; log.Alert(err); return nil,err end
	moonstalk.StripLogging(code)
	code,err = loadstring(code)
	if not code then err="Cannot load "..path..": "..err; log.Alert(err); return nil,err end
	code()
end

function moonstalk.AddLoader(type,handler,bundle)
	-- applications may add handlers to process a type of file's data, bundle must be specified for introspection
	-- function handler(data,file) return data end -- where file is a table for introspection
	-- handlers must be well behaved and may not throw errors, in the case of an error they must handle it themselves
	table.insert(moonstalk.loaders[type], {handler=handler,postmark=bundle.id})
end

function moonstalk.StripLogging(data)
	-- not used on views as these should generally not contain logging
	if logging < 5 then data = string.gsub(data,"\n%s+log%.Debug","\n--") end
	if logging < 4 then data = string.gsub(data,"\n%s+log%.Info","\n--") end
	if logging < 3 then data = string.gsub(data,"\n%s+log%.Notice","\n--") end
	return data
end
moonstalk.AddLoader("lua",moonstalk.StripLogging,moonstalk)

moonstalk.ignore_DirectoryFlattenedFiles = {["sites"]=true,["public"]=true,["assets"]=true,["static"]=true,["source"]=true,["development"]=true,["dev"]=true}
-- the following is replaced by utilities-dependent and thus not actually used anywhere; in openresty this non-lfs version gets interrupted due to the use of :lines
local string_sub = string.sub
local string_gmatch = string.gmatch
local string_match = string.match
function moonstalk.DirectoryFlattenedFiles(path,ignore,cd,depth)
	-- returns a table (of filenames) with all flattened files in the given directory path; use with pairs or table[filename] lookup; each file value is a table having both a file key and a path key (from moonstalk root) plus a type key if the file has an extension; do not use pairs to iterate; follows symbolic links
	-- ignore is an additional table of keyed names that will not be traversed in the root
	-- recursive only to the third level e.g. myapp/folder/folder/file therefore application and site bundles cannot place views and controllers any deeper than a second folder, or override a view/controller in another application beyond the first folder e.g. myapp/otherapp/folder/override.file
	-- cd is a path to be prepended to the path (an internal param and not typically used), the aggregate representation of this is the .file value, thus root item .name==.file
	-- WARNING: we do not support modification dates with this version
	-- NOTE: is replaced in dependant with an equivalent using the lfs module and also including modified timestamps
	if not cd then if ignore then copy(moonstalk.ignore_DirectoryFlattenedFiles, ignore) else ignore=moonstalk.ignore_DirectoryFlattenedFiles end end
	if string_sub(path,-1) ~="/" then path = path.."/" end
	if cd and cd~="" then if string_sub(cd,-1) ~="/" then cd = cd.."/" end else cd = "" end
	local directory = {}
	local firstchar
	local files = io.popen("ls -1pwL "..path..cd):read("*a") -- cannot diretcly iterate with lines as in openresty such io usage gets interrupted
	depth = depth or 1
	for name,is_directory in string_gmatch(files,"(.-)(/*)\n") do -- doesn't match the last empty line
		firstchar = string_sub(name,1,1) -- in superuser mode ls -A is default and can't be disabled
		if firstchar ~="." and firstchar~="_" then
			local item = {file=cd..name, path=path..cd..name, type=string_match(name,"%.([^%.]*)$")}
			if is_directory ~="" then
				item.file = cd..name.."/" -- files are also allowed to exist with the name of a directory, therefore if we want to introspect existence of a directory we must suffix with slash
				if (depth ==1 and not ignore[name]) or depth ==2 or depth ==3 then
					for _,subitem in pairs( moonstalk.DirectoryFlattenedFiles(path, nil, cd..name, depth+1) ) do
						directory[subitem.file] = subitem
					end
				end
			else
				item.name = string_match(name,"^([^%.]+)")
				item.uri = cd..item.name
			end
			directory[item.file] = item
		end
	end
	return directory,0
end
