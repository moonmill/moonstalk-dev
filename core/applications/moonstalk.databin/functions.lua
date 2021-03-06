--[[ Moonstalk Databin database system
provides a rudimentary database using luabins serialisation; tables are simply in-memory lua tables, loaded on startup and serialised to disk on shutdown

if no other suppported database system is discovered node.databases.default = {system="databin"} is automatically set upon Moonstalk installation

to use, simply specify in schema.lua:
	table_name = {} -- default: {system="databin", autosave="scribe"}
	autosave is the name of a server for which the table shall be saved upon termination, providing the server only has 1 instance

there is no need to specify fields as db.table_name is serialised in its entireity; however be aware that copies (pointers) of tables shared between databases will be duplicated
WARNING: saving is only autmatic not compatible for saving with multiple nginx workers as an internal sync mechanism would be required and a single instance made authoratative
WARNING: not recommended for significant datasets due to serialisation overhead, check the log
WARNING: if using with critical data it is advisable to call databin.Save"table_name" as in the unlikely case NGINX crashes the shutdown process will not complete, however saving obviously may have a high serialisation cost during which time the server will be blocked and unresponsive, for small datasets this is not an issue, however when dealing with critical data we do not recommend using this system
WARNING: if permissions prevent saving files to data/ the tables will be lost at shutdown
TODO: test other serialisation libraries for loading speed
--]]

require"luabins"
managing = 0 -- count of managed tables

local luabins_save = luabins.save
function Save(name,data)
	local result,err
	data,err = luabins_save(data)
	if err then return moonstalk.Error{databin, level="Priority", title="Error encoding "..name, detail=err} end
	result,err = util.FileSave("data/"..name..".luabins", data)
	if err then return moonstalk.Error{databin, level="Priority", title="Error saving "..name, detail=err} end
end

local luabins_load = luabins.load
function Load(name,quiet)
	-- new databases are created in the runner
	local data,err = io.open("data/"..name..".luabins")
	if data then
		data,err = data:read("*a")
		if data then
			err,data = luabins_load(data) -- returns true,data or nil, err
			if err==nil then err=data else err=nil end
		end
	end
	if err and (not quiet or not string.sub(err,1,12) =="No such file") then return moonstalk.Error{databin, level="Alert", title="Cannot load "..name, detail=err} end
	return data,err
end

do local posix_unistd = require "posix.unistd" -- {package="luaposix"}
function Cache(options)
	-- TODO: expiries and runner recache commands
	-- provides a simple ad-hoc interface to (conditionally) populate or return a table, saved to disk as a file, and efficiently re-loaded subsequently thus avoiding running an expensive function to populate it at each startup
	-- options.file = "data/appname_cache"; if only this option is provided we simply return true if found
	-- options.table = table; a table to use for the cache and repopulate with it; omit if the the cache function should return the data instead
	-- options.keys = {"keyname","keyname",???}; an optional array of keynames from the table if only selective keys are to be used from it, omit this if an entire table is to be used; specifying keys facilitates placing cached data in an application namespace e.g. util.Cache{table=appname, keys=={"mycache",???}} would cache the appname.mycache table
	-- options.populate = function; should either populate the table and return true, or return the table to be cached if options.table is not used; return nil upon failure
	-- options.refresh = true; specify to invalidate and [re]generate the cache using the populate function; cache is always generated if the corresponding file has been deleted
	-- returns the cache table on success and nil on failure, you must explictly handle the failure case (typically because the populate function failed)
	-- NOTE: you should generate caches from a Elevator() function so as not to delay Teller/Scribe startup; do not generate caches from scribe Loader or Starter functions, especially if multiple instances are being used (when calling this function having previously generated the cache in the runner, simply omit the populate option)
	-- NOTE: cache files are many times larger than a CSV equivalent but avoid significant string parsing overheads
	-- WARNING: cannot cache tables with pointers or cyclical references (pointers are treated as entirely new tables, significantly increasing memory use)
	if not options.refresh and posix_unistd.access(options.file..".luabins","f") then
		if moonstalk.server ~="runner" then log.Info("Restoring cache "..options.file) end
		local result,cache = luabins_load(util.FileRead(options.file..".luabins"))
		if not result then return moonstalk.Error{databin, title="Failed to load cache "..options.file, detail=cache}
		elseif options.keys then
			for _,name in pairs(options.keys) do
				options.table[name] = cache[name]
			end
		elseif options.table then
			copy(cache,options.table,true,false)
		end
		return cache
	else
		if not options.populate then return end
		log.Info("Generating cache "..options.file)
		local cache = options.populate()
		if not cache then return end
		if options.keys then
			cache = {}
			for _,name in ipairs(options.keys) do
				cache[name] = options.table[name]
			end
		elseif options.table then
			cache = options.table
		end
		local result,err = util.FileSave(options.file..".luabins", luabins.save(cache), true)
		if err then return moonstalk.Error{databin, title="Failed to save cache "..options.file, detail=err} end
		return cache
	end
end
end

function Starter()
	local autosave_default = ifthen(moonstalk.scribe.instances ==1,"scribe")
	local errored,error
	for name,table in pairs(moonstalk.databases.tables) do
		table.system = table.system or "databin"
		table.autosave = table.autosave or autosave_default
		if table.system =="databin" then
			databin.managing = databin.managing +1
			if table.autosave ==moonstalk.server then databin.autosave = true end
			_G.db[name],error = databin.Load(name,true) or {}
			if error then errored = {databin, log.Priority, title="Cannot load table '"..name.."'", detail=error} end
		end
	end
	if errored then return moonstalk.BundleError(databin,errored) end
	if databin.autosave and moonstalk.server=="scribe" and moonstalk.scribe.instances >1 then
		moonstalk.Error{databin, title="Autosave is disabled because multiple scribe instances are in use"}
		databin.autosave = false
	elseif databin.managing >0 and not databin.autosave then
		log.Info"Autosave is not enabled for this server"
	end
	databin.managed = true
end

function Elevator()
	if node.scribe.instances >1 then
		local list = {}
		for name,table in ipairs(moonstalk.databases) do
			if table.system =="databin" and table.autosave =="scribe" then table.insert(list,name) end
		end
		if list[1] then moonstalk.Error{databin,"Notice",title="Databin tables cannot be autosaved",detail="When multiple scribe instances are in use, set ./elevator scribe.instances=1 to use the following tables, else to manually manage set them to autosave=false or a server name which will be authoratative for them: "..table.concat(list,", ")} end
	end
end

function Shutdown()
	if not databin.managed then return log.Notice"Shutting down without autosaving tables due to interrupted startup" end
	local started = os.time()
	local count = 0
	for name,table in pairs(moonstalk.databases.tables) do
		if table.system =="databin" then
			if _G.db[name] and table.autosave ==moonstalk.server and node[table.autosave] and (node[table.autosave].instances or 1) ==1 then
				count = count +1
				databin.Save(name, _G.db[name])
			elseif not table.autosave ==moonstalk.server then
				log.Info("Saving table "..name.." not enabled with this server")
			else
				log.Notice("Saving table "..name.." deactivated")
			end
		end
	end
	log.Info("Saved "..count.." tables taking "..(os.time()-started).."s")
end
