--[[ the Tarantool app provides shorthand/sugar for the following
Behaviours:
References to *enum.* and model.* are translated to their tuple field indice constants at compilation.
-- NOTE: in the Tarantool server use of tuple.fieldname to access field values invokes costly metamethods, therefore when maximum performance is a consideration the notation tuple[model.record.fieldname] is preferaable (with or without its compiled optimisations), whilst the use of direct tuple[n] references is only nominally better and may therefore be omitted

-- WARNING: do not use space:update(id, {tt.op.DELETE,"fieldname"}) as this modifies and reorders fields versus that declared in the schema resulting in corruption, DELETE or "#" should only be used with "fieldname.keyname" on map values or "fieldname.n" on array values; it may of course be used when no schema fields are declared should the fields themselves be variable
-- WARNING: In the tarantool «server box.NULL ==nil» so «»if not tuple.field» may be used for pseudo-empty fields (whose value has been set to box.NULL), however in other environments this is not true, and one must explictly use «if tuple.field ~=tt.null» unless the tuple has been converted to a table using model which removes the NULL value thus making the indice to nil, see model below. tt.NULL == msgpack.NULL == box.null (box is only available in the Tarantool server)

Node:
	node.databases = {rolename={host="address",port=number,password="secret"}} -- does not need to be specified if on the same host and will use a unix socket -- TODO: use cluster registry to set and get password

Get:
	db.records[id] † -- returns the entire record as a table (not tuple) -- TODO:
	db.records[id]"fieldset" -- returns only the fields named in the fieldset as a table (not tuple) -- TODO:
	db.records[id][fieldname] † -- returns value of the field -- TODO:
Set:
	db.records[id] = value † -- TODO:
† model conversion will be applied transparently
-- TODO: fire and forget non-waiting
Call:
	appname.ProcedureName(...) --  call the procedure on the default database
	db.servername.appname.ProcedureName(...) -- call the procedure on the named server -- TODO:
-- TODO: fire and forget non-waiting
Model:
	the following are only available if things={record="thing"} is specified in the schema
	model.record{…} -- returns the conversion between either a tarantool tuple/msgpack array (non-sparse arrays) or a moonstalk table (with named fields); when converting from a table, missing indices will be poperly populated with the msgpack.NULL placeholder, however any indices after the last provided field will not be populated with this if their schema field specifies is_nullable=true, thus the array will be trimmed in these cases
	model.record[fieldname] = n
	model.record[n] = fieldname

	Within the Tarantool server there's support for the following, for which Moonstalk populates the space format options if not otherwise declared:
		tuple_object:tomap(tarantool.names_only) -- convert from the tuple returning a lua table ('map'); names_only is an optional but advisable parameter else the table will contain both array indices and map keys; this method avoids having to deal with tuples, however for recursive or intensively used operations on just a few of a large tuple's fields, tuples are preferable versus decoding it to instantiate the Lua table
		space_object:frommap(table); takes a Lua table with keys matching the space field names and returns a tuple; can optionally take a second param tarantool.as_array which returns an array from the map not a tuple
	These conversion functions should be used when the number of operations upon a tuple exceeds the number of fields, as it's cheaper to convert and perform direct operations than do secondary array lookups. For best performance where a few operations are performed upon a tuple and readability needs to be maintained, use Moonstalk's model enums for field names, e.g. tuple[model.record.field]; these are compiled to the more performant but opaque tuple[n] references (being a direct indice not having nested tables to traverse). (Because these are compiled you must not create locals upon model.)

update/upsert both support field names instead of indices, and also paths for serialised data within maps
https://www.tarantool.io/en/doc/latest/reference/reference_lua/json_paths/
paths take the forms field_name.key_name and fieldname[index] both of any depth
-- path="." -- prefixed with period indicates

Schema:
table_plural = {system="tarantool", "first_field", "second_field", …}
table_plural = {system="tarantool", engine="vinyl", "first_field",{name="second_field", type="string", …}} with field options per space:format()
-- NOTE: when adding new fields to (the end of) an existing table, they must be specified with {"name", is_nullable=true} because this field will be nil in existing tuples
table_plural.record = "table_singular" enables moonstalk's model() functions

table_plural.indexes = {{name="primary", parts={{"field_name","type"}, …}, …}, …} with index and part options per space_object:create_index(); if omitted a default TREE index will be created for the first field, however note that if
	field_name can be a json style path for an array or map that the field contains, and the path may use [*] where an array of similar objects exist and will match those keys of all the objects, e.g. {"emails[*].address"}
	index.sequence can simply be true; any non-existant named sequence will be created using defaults; sequence names must be globally unique e.g. tablename_indexname
	index part.exclude_null=true will exclude fields having a nil/null value from the index
	tarantool.fieldset.fieldset_name = {"fieldname","fieldname"}

Notes:
Empty tables or a table with a [1] key are considered to be arrays, therefore to have an empty table or mixed array-map table with a [1] key serialised as a map value you must use key=tarantool.map(table) where table is optional; note however that it is simply preferable to avoid the use of indice 1 in mixed maps and to start the array part from 2 which can still be iterated (just not using ipairs).

Caching:
Allows infrequently updated but often queried values to be cached by every client, thus avoiding a database query and reducing overhead; it is not expected to be used for especially large datasets or those with unknown extents (such as users or comments), but those which have knowable or defined extents (e.g. tenants or blog posts). The mechanism allows the node to specify which tables are cached, and the database will then maintain the cache effectively in real-time. Only one database query will be made per request for any cachable table, however a seperate request will be made for each not yet cached value.
Procedures must update cached records using tarantool.Cache()
WARNING: currently the mechanism does not have purge or use restrictions thus could grow to the same number of possible records as the database itself
Consumption is transparent and uses the same global db table which is modified for the node-declared cached tables:
	node.databases.cache = {"tablename",…}
Caching only supports full records at the second level of the namespace e.g. table[record_id], however as with the usual db looksup, child values can still be queried.
A worker that updates a record updates its own cache simultaneously. Others will update when they query for any cached item.
In reality it does not update in real-time, but prior to a database query updates are predominantly sequential excepting updates from other works and for most cached items do not need to be aggregated as are expected to be infrequently updated
--]]

-- NOTE: for conversion of tables to tuples whilst not unduly expensive, it may be preferable to simply do this yourself inline for higher performance situations, especially where smaller tables and tuples are concerned thus avoiding invocation of a metamethod, function and iterator
-- TODO: cache(table/class) in client, fetches the dataset and flags in the db that it has been subscribed, the client then consumes directly from the cache, doing an async update, when the update is recived it must be propogated to other subscribers (may assume all of same client class); thus needs two mechanisms, one with handlers, for GETCACHE, UPDATECACHE, UPDATEDB, UPDATECACHES; another simply for an entire table

-- NOTE: server is enabled by the Enabler as it depends upon role normalisation that is performed by it
append({"tarantool.lua"},moonstalk.components)

_G.tt = _G.tarantool -- sugar, e.g. tt.table_name:select() tt.enum.op.ADD
-- WARNING: client databases proxies are placed in this namespace, however they should all use plural names
do local result
	result,_G.msgpack = pcall(require,"msgpack") -- {package="lua_cmsgpack"}; -- in tarantool this is bundled, but regardless we expect it to be installed for other servers/clients
	if not msgpack then
		-- fallback to a native non-compiled version, however this must be installed manually and the prior will always be reported as missing by the elevator
		_G.msgpack = require"MessagePack" -- {package=false} -- "lua-messagepack"
	end
end
NULL = 0xC0 -- the raw pack byte which is not valid for use in the Tarantool server where it and msgpack.NULL are cdata with metamethods providing equality comparison with nil

role = {} -- the tables for this node
_roles = {} -- the count of tables for each role (not present for roles without tables)
_tables = {}

names_only = {names_only=true}
enum = {}
enum.op = {SET="=",ADD="+",SUBTRACT="-",AND="&",OR="|",XOR="^",SPLICE=":",INSERT="!",DELETE="#"} -- sugar -- NOTE: tarantool refers to SET as 'assign' -- TODO: use glosub to replace this with string ints in tarantool and lua files
iter = {GT={iterator='GT'}, LT={iterator='LT'}, GE={iterator='GE'}, LE={iterator='LE'}, EQ={iterator='EQ'}, REQ={iterator='REQ'}} -- sugar; removing the need to keep creating tables, providing no other options are needed -- NOTE: EQ is the default therefore does not need to be declared in use

-- NOTE: the primary server startup invocation is at the end of this file, as we need to populate this environment first


function Enabler()
--[=[
	-- configure
	for _,table in ipairs(node.databases.cache or {}) do
		if not moonstalk.databases[table] then log.Priority("Cannot enable caching for undeclared table: "..table)
		else
			moonstalk.databases[table].cache = true
		end
	end
--]=]
	-- applies to all servers including the tarantool server itself so we enable that after
	for _,conf in ipairs(moonstalk.databases) do
		if conf.system =="tarantool" then
			conf.ready = true
			tarantool._tables[conf.name] = conf
			if node.databases[conf.role] or (host.roles[conf.role] and host.servers.tarantool) then
				if not tarantool._roles[conf.role] then
					tarantool._roles[conf.role] = 1
				else
					tarantool._roles[conf.role] = tarantool._roles[conf.role] +1
				end
				if host.roles[conf.role] then tarantool.role[conf.name] = conf end
				conf.format = conf.format or {}
				for position,name in ipairs(conf) do
					if type(name) =='table' then
						-- normalise to a list of field names, moving the table into a subtable
						 -- TODO: add support for field.record as _G.model[field] with nested deserialisation, or field.records for array of records
						conf.format[position] = name
						conf[position] = name.name
						conf[name.name] = position
					else
						conf.format[position] = {name=name}
						conf[name] = position
					end
				end
				conf.length = #conf
				if conf.record then
					-- add the enum interface, but only if it has a declared record name
					_G.model[conf.record] = conf -- public interface for enumeration
					_G.model[conf.record] = conf -- public interface for normalisation (record conversion between tuple and table)
					setmetatable(conf, {__call=tarantool.Normalise}) -- the table needs a call metamethod override to handle the public interface; the first param provided by Lua is the table (schema) itself
					-- add get and set interfaces
					-- these interfaces always use the default associaterd server
					-- FIXME:
					-- add query interface
					-- db.namespace.Procedure()
					-- add query interface for specific servers -- TODO:
					-- NOTE: servers may not be named the same as a table
					-- db[name].namespace.Procedure()
				end
			end
		end
	end
end

-- if schema does not specify server, then we look in node.databases for the role, else we assume local
function Starter()
	for name,conf in pairs(tarantool._tables) do
		if tarantool.client then tarantool.Serve(conf) end
		if conf.supplemental then -- TODO: support persisting and restoring supplemental fields, and registering with cluster
			-- merge supplemental fields into the owner's schema; tarantool tables do not have a fixed schema so it is not required for creation in the Enabler, thus we update the schema here after it is created and all apps schemas have been loaded by the Enabler
		end
		if conf.ready then
			-- database is enabled in this server
			for _,index in ipairs(conf.indexes or {}) do
				-- TODO: add aliases to database invoking the correct get params?
				local name = index.name or index.parts[1] or index.parts.name
			end
		end
	end
end


-- # generic interfaces

function Get(namespace,fieldset)
	-- TODO: wraps the default iterface to provide response normalisation
	local table,key = string_match(namespace,"([^%.]+)%.(.+)")
	if fieldset then
		return tarantool.Get("tarantool.Get", table, key, fieldset)
	end
	-- FIXME: return tarantool._tables[] connection:select("tarantool.Get", proxy.namespace, fieldset)
end

do
local tarantool_Run = tarantool.Run
local proxy = proxy
local function db_get(_, fieldset)
	local table,key = string_match(proxy.namespace,"([^%.]+)%.(.+)")
	if fieldset then
		return tarantool.Get("tarantool.Get", table, key, fieldset)
	end
	-- FIXME: return tarantool._tables[].connection:select("tarantool.Get", proxy.namespace, fieldset)
end
local cache = cache
local cache_serial = 0
local cache_checked = 0
local util_TablePathAssign = util.TablePathAssign
local function db_cache_get(_, fieldset)
	local result,err
	local ns = proxy.namespace
	if moonstalk.request ~=cache_checked then -- FIXME: no longer using this but can use request.identifier
		-- already cached but we must check for cache updates once per request, thus all values after the first check can be retreived from the cache if they exist
		result,err = tarantool_Run("tarantool.CacheUpdates", cache_serial, proxy.namespace, fieldset)
		if err then return result,err end -- FIXME: propogate
		for i=#result,1,-1 do -- currently oldest last and we have to work up to the latest to preserve integrity
			util_TablePathAssign(db,result[i][1],result[i][2]) -- uses rawset so we won't invoke db_set
		end
		cache_serial = result.serial
		cache_checked = moonstalk.request
	end
	if cache[ns[1]][ns[2]] ==nil then
		-- not yet cached
		result,err = db_get(ns) -- TODO: this should really call a procedure that fetches both the value and the cache queue if not already done
		if err then return result,err end -- FIXME: propagate
		if not result then
			result = false -- prevents re-fetching as didn't exist
		else
			result = model[moonstalk.databases[ns[1]].record](result)
		end
		cache[ns[1]][ns[2]] = result
	end
	if ns[3] then return util_TablePath(cache,ns) end
	return result
end
end


-- # abstractions

function Serve(dbtable)
	-- establish interfaces for both servers and schema tables used for making connections
	-- server is optional and will inherit from node roles i.e. node.databases.role = {system="tarantool",host="",password=""}
	-- may not be run from a request as does not use resume

	-- configure the server
	local server = tarantool[dbtable.role] -- may already exist
	if not server then
		server = dbtable.server
		if not server then server = node.databases[dbtable.role] end -- use a configured node database server by role if available
		if (not server or not server.host) and host.servers.tarantool and host.roles[dbtable.role] then
			-- use the default localhost server
			server = server or {}
			server.host = "unix:"..moonstalk.root.."/temporary/tarantool/"..dbtable.role..".socket"
			server.user = "moonstalk"
			server.password = node.secret
			server.role = dbtable.role
		end
		if not server.host then
			return moonstalk.Error{tarantool, title="no server configured for '"..dbtable.role.."'"}
		elseif tarantool[server.host] then
			server = tarantool[server.host]
		else
			tarantool[dbtable.role] = server
			server.call_semantics = "new"
			server._spaces  = {}
			server._indexes = {}
			log.Debug("establishing connection to Tarantool instance "..dbtable.role.."@"..server.host)
			server.socket_options = {pool_size=1,backlog=50} -- consumed by client and passed to socket.tcp:connect() -- FIXME: test it's unclear if this one connection can be shared between concurrent requests, but as any response esentially is sequential, we assume so
			local result,err = tarantool.Connect(server) -- establishes the initial connection pushing it into the request, and giving us first opportunity to check it
			if result then log.Info("connected to Tarantool instance '"..dbtable.role.."'")
			else moonstalk.Error{tarantool, title="cannot connect to '"..dbtable.role.."'", detail=err} end
			result,err = request[server]:setkeepalive(0) -- keep the connection alive in pool with no timeout
			if not result then moonstalk.Error{tarantool, title="cannot setkeepalive for '"..dbtable.role.."'", detail=err} end
		end
		copy(tarantool.methods, server) -- none of these are really actually needed but does provide ping
		local mt = {}
		mt.__call = server.call -- enables use of the server as the interface to Run, e.g. tarantool.role("app.function",parameters)
		setmetatable(server, mt) -- currently we only enable tarantool client methods e.g. tarantool.client:upsert()
	end

	-- configure the table
	if not tarantool[dbtable.name] then
		local proxy = copy(server)
		proxy.table = dbtable.name
		copy(tarantool.methods, proxy)
		tarantool[dbtable.name] = proxy
	end
end


-- ## Schemas

-- defines the database storage tables (Tarantool spaces) and data-structures (Tarantool tuples, Lua tables) with some application specific schema declaration and configuration utilities

-- WARNING: do not save empty table values unless an array, if the table is a hash but is empty msgpack will always save it as an array, therefore empty hashes should instead be saved as nil and created on demand / when their first key is assigned
-- WARNING: records (tuples) must always be terminated with a non-optional value otherwise setting values after a position having a nil value will fail; this can be avoided simply by converting records to a tuple using the model functions which automatically assign msgpack.NULL for missing fields

-- NOTE: the default expectation with regard to tuples in spaces is that most fields will be consumed at once thus a single retreival operataion is most desireable; activities like paging through records are fairly low-intensisity and if larger values have to be decoded a few at a time this is inconsequential; however the meta fields are intended for use by applications and may thus grow significantly, their use must be restricted to only values that are likely to be consumed, or details of which applications are enabled for a particular record; in cases where the data is conditional (e.g. an application has a seperate view for a record) a seperate table/space should be used, retreived and merged as needed

-- WARNING: when evaluting tuple fields directly (not converted with model), 'missing' (==msgpack.NULL) field values are actually cdata thus one MUST NOT use «if not tuple.field» as the field value always evaluates to true, one may however use «if tuple.field ==nil» as the equivalency test will fail (but invokes metamethods)
-- WARNING: in the scribe msgpack.NULL==nil, therefore tables should not be converted to records in the scribe -- TODO: check this as tarantool's unpacker may create a sparse array


-- # Utilities

-- db.name functions should be used when creating new records as they ensure nils are not used; updating records should be done using enum references i.e. NAME.field for the positions -- TODO: an update abstraction akin to the Teller

function Normalise(schema,record,fields)
	-- returns a new table converted from a record tuple to a keyed table, optionally only including the fields named in the fields array (which is efficient); or a keyed table into a tuple
	-- if fields = true when given a tuple will return a merged table but note that this cannot then be converted to a tuple by this function; this thus allows ephemeral keys to be added to this table that will be preserved
	-- record should not contain any array part
	-- TODO: use tuple:tomap() if no fields are specified
	-- TODO: add debug mode validation checks because incorrect index values when inserting are hard to trace; possibly also add metatable to log the individual box.space calls
	if record[1] ~=nil or fields then
		-- convert tuple to record by iterating the field names and fetching the corresponding positions
		local normalised
		if fields ==true then -- combirecord (tuple and record in same table)
			if moonstalk.server =="tarantool" then
				-- we can't simply add fields to a tuple because it's cdata, so instead for the combi usage we still need a new table but we add a metatable with access to the tuple cdata fields; this unfortunately still means iterating all the fields -- OPTIMIZE: perhaps edit the tuple metatable to lookup key names on demand, this however would not work for conversion back to a tuple but we never do this(??) as updates are always partial
				normalised = {}
				local record = record
				setmetatable(normalised,{__index=function(t,key) return record[key] end})
			else
				-- combi behaviour in the scribe simply reuses the tuple table which has been converted from cdata to a normal lua table before wire transmission
				normalised = record
			end
			fields = nil
		else
			normalised = {}
		end
		if not fields then
			for position,name in ipairs(schema) do
				normalised[name] = record[position]
				if normalised[name] ==msgpack.NULL then normalised[name] = nil end
			end
		else
			for _,name in ipairs(fields) do
				normalised[name] = record[schema[name]]
				if normalised[name] ==msgpack.NULL then normalised[name] = nil end
			end
		end
		return normalised
	else
		-- convert record to tuple by iterating the field positions and assigning their values, including NULL where there is a subsequent value
		local tuple = {}
		local name,populated,value
		local schema = schema
		local record = record
		for position = schema.length,1,-1 do
			name = schema[position]
			value = record[schema[position]]
			if not populated and value ~=nil then populated=true end -- any field hereon needs a value else the tuple could be sparse where fields are nil
			if value ~=nil then
				tuple[position] = value
			elseif populated or schema.format[position].is_nullable ~=true then -- this last is not an optimised lookup as should be very infrequent
				tuple[position] = msgpack.NULL
			-- else there's no values nor required values this far into the tuple so leave empty
			end
		end
		return tuple
	end
end


-- # finalise startup if we're the server
if moonstalk.server =="tarantool" then
	-- # enable the server
	-- because tarantoolctl runs moonstalk as a server directly from temporary/tarantool/role.lua we must now convert that generic moonstalk server into a trantool server
	-- TODO: this is messy as server wraps enablers etc; needs tidying up
	local result,err = include "applications/moonstalk.tarantool/server"
	if err then moonstalk.Error{tarantool,title="Error loading server environment",detail=err} end
end
