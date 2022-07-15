if moonstalk.server ~="teller" then return end
do -- thread functions must define (non-standard) required packages (and values) as upvalues, which we restrict to the scope of the function (instead of all subsequent functions) using a dedicated container block
	tasks['email.Dispatch'] = {"send"}
	local socket = require "socket"
	local util_ArrayRange = util.ArrayRange
	function Dispatch(task,message)
		-- invoked from generic.Email; expects message or task.email to be an SMTPEnvelope (typically constructed by a TaskBegin function and returned as the second parameter, or saved as task.email at the time the task is created)
		-- TODO: handle https with LuaSec
		message = message or task.email
		local smtp = require "socket.smtp"
		message.source = message.source or smtp.message(message)
		local rcpt = message.rcpt
		local max = message.batch or 50
		for i=1,math.ceil(#rcpt/max) do
			message.rcpt = util_ArrayRange(rcpt, i*max-max+1, max*i)
			local result,err = smtp.send(message)
			if not result and (task.retry or 4) >= (task.run or 0) then -- TODO: handle failures so that we resume only batches of recipients not yet sent
				-- retries occur at 1m, 5m, 30m, 2h, 12h
				local when = {[0]=60,[1]=360,[2]=1800,[3]=7200,[4]=43200}
				task.status = message.server.." "..err
				task.when = task.when +when[task.run or 0]
				message.source = nil
				return task
			end
		end
		task.status = table.concat{"Sent '", message.subject or "[No subject]", "' to ", message.headers.to}
		message.source = nil
		return task
	end
end

-- deprecated interface
generic.EmailTask = Dispatch -- NOTE: when using this name in tasks resources will not be locked
