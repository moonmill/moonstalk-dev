-- these functions are dependent upon modules that cannot be loaded by the elevator until they are installed, thus are maintained seperately and enabled by Initialise() in server which also loads the node table
-- TODO: move to generic app

_G.luabins = require "luabins"
_G.posix_stdlib = require "posix.stdlib" -- {package="luaposix"}
_G.mime = require "mime" -- {package="mimetypes"}
_G.socket = require "socket"
_G.lfs = require "lfs" -- {package="luafilesystem"}

local string_match = string.match
local string_gsub = string.gsub
local string_sub = string.sub


function moonstalk.DirectoryFlattenedFiles(path,ignore,cd,depth)
	-- see server.lua; this is an overload for use with lfs
	-- also returns a modified timestamp for every file, plus a global modified timestamp as the second argument
	if not cd then if ignore then copy(moonstalk.ignore_DirectoryFlattenedFiles, ignore) else ignore=moonstalk.ignore_DirectoryFlattenedFiles end end
	if string_sub(path,-1) ~="/" then path = path.."/" end
	if cd and cd ~="" then if string_sub(cd,-1) ~="/" then cd = cd.."/" end else cd = "" end
	local directory = {}
	local firstchar
	local modified = 0
	depth = depth or 1
	for name in lfs.dir(path..cd) do
		firstchar = string_sub(name,1,1) -- in superuser mode ls -A is default and can't be disabled
		if firstchar ~="." and firstchar ~="_" then
			-- NOTE: we traverse (symbolic) links, but they should not exist in site/app directories
			local item = {file=cd..name, path=path..cd..name, type=string_match(name,"%.([^%.]*)$")}
			local attributes = lfs.attributes(item.path, {"mode","modification"})
			item.modified = attributes.modification
			if item.modified > modified then modified = item.modified end
			if attributes.mode =="directory" then
				item.file = item.file.."/"
				-- recursively merge subdirectories;
				if (depth ==1 and not ignore[name]) or depth ==2 or depth ==3 then
					for _,subitem in pairs(moonstalk.DirectoryFlattenedFiles(path, nil, cd..name, depth+1)) do
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
	return directory,modified
end
function Folders (path)
	-- parses a directory, creating a table for each top-level folder
	local directory = {}
	local firstchar
	if path =="applications/" then log.Alert(lfs.dir(path)) end
	for name in lfs.dir(path) do
		firstchar = string_sub(name,1,1) -- in superuser mode ls -A is default and can't be disabled
		if firstchar ~="." and firstchar ~="_" and lfs.attributes(path.."/"..name, "mode")=="directory" then directory[name] = {} end
	end
	return directory
end
function FileModified(path)
	return lfs.attributes(path,"modification")
end
FileExists = FileModified

do
	local result,uuid = pcall(require,"lua_uuid") -- {package=false}; optional
	if result and uuid then
		function Token(length)
			-- much faster than ShortToken but without the custom chars; max length is 32
			local token = string.gsub(uuid(),"%-","")
			if length and length~=32 then return string.sub(token,1,length) end
			return token
		end
	end
end

--# Token creation and encoding
-- functions that handle integer record.id values are named FunctionID whilst those that handle tokens are named FunctionToken; tokens cannot be mapped to records unless indexes are specifically maintained
-- an address (public or authenticated) should never expose integer IDs from CreateID directly, apart from leaking data such as creation time, due to their compact address space which is semi-sequential (whilst not directly observable) it is nonetheless easily iterated to discover valid IDs, which in turn leads to potential attack vectors (such as directly requesting records for which the client has no permissions)
-- the encoding functions here are predominantly intended for use with such IDs to obfusticate them thus increasing their address space to a less easily iterated size (but not impossible, however another layer should ideally catch such traffic patterns)
-- tokens have much larger address-spaces which in turn requires higher overhead to attack, thus token values returned by these functions and exposed to clients must therefore be sufficiently random and non-repeatable, in addition to avoiding discovery of secrets/salts used in generating them
-- Encrypt is reverseable (can be decoded) which enables the transmission of directly used database keys, so avoiding the need to index and store additional tokens/hashes, however such use is ill-advised and additional record tokens should be generated and stored as these are easily invalidated and replaced, whereas an encoded ID cannot be without changing the ID itself and thus all references to records
-- Moonstalk uses Encrypted tokens for client sessions as the decryption routine is cheaper to perform in the case of a session address space attack, thus allowing such requests to be discarded without requiring a database check, use of Encrypt in database functions should be avoided due to its overhead, and in most cases of high-lookup incidence a preference should be for the generation of a per-record indexed token as this would be easily regenerated should need arise whereas IDs cannot be
-- the most most performant token generation included here is RandomID(), followed by Encrypt(CreateID()) whilst ShortToken is the slowest with even short lengths
-- NOTE: the 'hashids' library could be used as a 'ShortEncodeID' but has been considered to be unsuitable for inclusion due to the potential to missuse it with any sensistive record.id; if used solely with CreateID and its own salt (not node.secret) it may be more acceptable
-- NOTE: these functions are now implemented in servers

-- TODO: the mechianism of passing a locale does not support per-state (child locale) variations, until locale supports these itself (e.g. locales.us-ca.parent = locales.us)
-- WARNING: in most cases using absolute timestamps for reference datetimes is undesireable; should the parameters of calculation for the represented date-time change, the timestamp will no longer be accurately representative of its date-time; therefore a date-time whose calendar-intent should be preserved must be stored as a relative representation and calculated as an absolute timestamp only when consumed, ensuring the correct relative interpretaion at the time of consumtion rather than at the time of recoding; i.e. at the time of recording, we generate a timestamp for a future date-time, it represents an absolute point in time that assumes the same parameters of calculation (e.g. DST offset and start/end dates) will also be true at the time of consumption, however if they chnage, our timestamp will no longer be accurate
-- TODO: support reference times stored as relative-intent calendar digits e.g. yyyymmddhhmmss; the format being easily ascertained by the string length of the number (14 chars for relative A.D., 15 chars and negative value for relative B.C.; <14 for absolute, both ideally supporting optional decimals for sub-second accuracy) OR convert all timestamps to use this format
-- TODO: investigate using https://github.com/daurnimator/luatz
do
	local posix_setenv = posix_stdlib.setenv
	local os_time = os.time
	local os_date = os.date
	function _G.localtime(timedate,zone)
		-- convert either a reference date-time value (UTC epoch timestamp) or date table, to a date table adjusted to represent the corresponding date-time in the specified timezone (including DST handling)
		-- NOTE: the return date table contains a supplementary zone identifier for use with the reftime function, avoiding the need to store and pass it the original zone; however if the table is converted via any other function the zone will need to be provided
		timedate = timedate or now
		if not tonumber(timedate) then timedate = os_time(timedate) end
		zone = zone or moonstalk.timezones[request.client.timezone or site.timezone] or locale.timezone
		posix_setenv("TZ",zone.value)
		timedate = os_date("*t",timedate)
		timedate.zone = zone.value
		posix_setenv("TZ","UTC")
		return timedate
	end
	function _G.reftime(timedate,zone)
		-- convert either a date table or timestamp representing a date-time in the specified zone (including DST handling), to a Moonstalk reference date-time value (a UTC epoch timestamp); if provided with a date from the localdate function, there is no need to specify zone; date tables may having their values adjusted e.g. date.day = date.day +7 and the returned timestamp will acount for this
		if not timedate then return
		elseif tonumber(timedate) then
			timedate = os_date("*t",timedate)
			zone = zone or moonstalk.timezones[request.client.timezone or site.timezone] or locale.timezone
		else
			zone = timedate.zone or zone or moonstalk.timezones[request.client.timezone or site.timezone] or locale.timezone
		end
		posix_setenv("TZ",zone.value)
		timedate = os_date("!*t",os_time(timedate))
		timedate.isdst = nil
		timedate = os_time(timedate)
		posix_setenv("TZ","UTC")
		return timedate
	end
end
