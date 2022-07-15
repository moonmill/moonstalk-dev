util.InsertAfterArray("postie","scribe",elevator.sequences.start)
util.InsertBeforeArray("postie","scribe",elevator.sequences.stop)
elevator.servers.email = "postie"
elevator.servers.postie = "postie"

elevator.functions.postie = function ()
	display.status"Postie Server"
	local pid = util.FindPID "email/server"
	-- TODO: add launching status, upon launch write flag to node, then after finish remove flag from node, if process is not running, ignore flag but warn crashed
	if run.status then
		if pid then
			terminal.green "running"
		else
			terminal.yellow "not running"
		end
	end
	if run.stop then
		if pid and not run.status then
			if not run.restart then terminal.green "terminating" end
			os.execute("/bin/kill -15 "..pid) -- will catch SIGTERM in next loop -- TODO: report log status when waiting on tasks
		elseif not run.restart then
			terminal.yellow "not running"
		elseif run.ifrunning then
			run.start = nil -- prevents start if not running
		end
	end
	if run.start then
		if not pid or run.restart then
			io.popen(chroot.."applications/moonstalk.email/server.lua &"):close()
			-- TODO: check actual status, perhaps by opening a socket and polling
			local newpid = util.FindPID "email/server"
			if not newpid then
				terminal.erroneous "failed"; elevator.exit = 1
			elseif run.restart then
				if pid then
					terminal.green "relaunched"
				else
					terminal.yellow "launched"
				end
			elseif run.start then
				terminal.green "launched"
			end
		else
			terminal.yellow "already running"
		end
	end
	print""
end
