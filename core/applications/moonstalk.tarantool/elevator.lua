-- NOTE: tarantoolctl uses the pid stored in temporary/tarantool thus if swapping between multiple moonstalk directories, tarantool must be shutdown from the directory that started it -- TODO: use kill

util.InsertBeforeArray("tarantool","web",elevator.sequences.start)
util.InsertAfterArray("tarantool","web",elevator.sequences.stop)

local tarantoolctl = { -- this is obviously a lua table, which we serialise in the runner function for tarantool to then executes, but because of this we cannot execute actual code in the config, unless we were to hardcode the lua
	instance_dir = moonstalk.root.."/temporary/tarantool",
	default_cfg = {
		work_dir = moonstalk.root,
		log_level = 5, -- TODO: propagate moonstalk's log level
		log = moonstalk.root.."/temporary/tarantool",
		pid_file = moonstalk.root.."/temporary/tarantool",
		wal_dir = moonstalk.root.."/data/tarantool",
		memtx_dir = moonstalk.root.."/data/tarantool",
		vinyl_dir = moonstalk.root.."/data/tarantool",
	}
}

local function Started(command,role)
	local result = util.Shell(elevator.deprivelege("tarantoolctl "..command.." "..role),"*a")
	if not string.find(result, "started") then
		-- daemon didn't start; unlikely
		terminal.red"failed "
		display.error(result)
		return
	end
	result = util.Shell(elevator.deprivelege("sleep 1; touch temporary/tarantool/"..role..".log; tail -r temporary/tarantool/"..role..".log | grep -m 1 -e 'Start failed' -e 'LuajitError'")) -- we may be attempting to check too soon
	-- FIXME: look for "stopped" to indicate failure
	if not result then return true end -- log indicates started
	terminal.red"error "
	display.error(string.match(result,">(.+)"))
end

elevator.functions.tarantool = function()
	util.Shell(elevator.deprivelege"mkdir -p temporary/tarantool")
	-- TODO: selectively restart just a changed tarantool process (database.role), not all of them
	local enabled
	for role in pairs(tarantool._roles) do
		enabled = true
		local pid = util.FindPID("tarantool "..role)
		display.status("Tarantool","/"..role.." (DB)")
		if run.status then
			if pid then
				terminal.green "running\n"
			else
				terminal.yellow "not running\n"
			end
		end
		local result
		if not run.restart and run.start and pid then
			terminal.yellow "already running\n"
		elseif not run.restart and run.stop and not pid then
			terminal.yellow "not running\n"
		elseif not run.restart and run.stop then -- NOTE: we assume tasks shutdown safely
			result = util.Shell(elevator.deprivelege("tarantoolctl stop "..role),"*a")
			terminal.green "stopping\n"
		elseif run.start then
			util.Shell(elevator.deprivelege("mkdir -p data/tarantool/"..role.." temporary/tarantool; mv -f temporary/tarantool/"..role..".log  temporary/tarantool/"..role..".prior.log")) -- move the current log as we need to check the status in it (with Started) just for the current attempt, we don't keep more than prior, thus always overwrite
			-- tarantool needs a fixed configuration file that specifies which directories to use, either .tarantoolctl in the current directory, or a system file
			-- we always rewrite the control file in case config has changed
			local ctlfile = moonstalk.root.."/.tarantoolctl"
			if elevator.config.rootuser and not elevator.config.sudouser then
				if sys.platform =="Linux" then
					ctlfile = "/etc/tarantool"
				elseif sys.platform =="Darwin" then
					ctlfile = "/usr/local/etc/tarantool"
				end
			end
			if not util.FileExists(ctlfile) then
				util.FileSave(ctlfile, util.SerialiseWith(tarantoolctl,{executable=true}))
			end
			-- default config disables feedback daemon because it was crashing on macos, and anyway may be considered intrusive
			util.FileSave("temporary/tarantool/"..role..".lua",
[=[box.cfg {feedback_enabled=false, log_format="plain", log_level="info", listen="]=]..moonstalk.root..[=[/temporary/tarantool/]=]..role..[=[.socket",}-- background = true,
dofile"core/moonstalk/server.lua"
moonstalk.Initialise{server="tarantool",prefix=function() return "tt/]=]..role..[=[" end,tarantool={role="]=]..role..[=["}}]=])
			if run.restart then
				if Started("restart", role) then terminal.green"restarting\n" end -- TODO: move before Shell and rewrite line if not Started
			else
				if Started("start", role) then terminal.green"starting\n" end
			end
			if not moonstalk.databases.systems.tarantool or not tarantool._roles[role] then
				terminal.red "disabled" display.error[[No tables assigned. Use an application/schema.lua to allocate tablename={system="tarantool"}]]
			end
		end
	end

	if not enabled then
		display.status("Tarantool (DB)") terminal.red "disabled" display.error([[No roles assigned. Use an application/schema.lua to allocate a tablename={role="role_name"} corresponding to this node's roles (]]..util.ListGrammatical(node.roles,", ",", ","")..[[), or remove "tarantool" from node.servers in data/configuration/Host.lua]])
	end
end
