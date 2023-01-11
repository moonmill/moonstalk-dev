#!/usr/bin/env lua5.1

--[[ Moonstalk Postie

A basic SMTP server with the Moonstalk environment for receiving incoming messages and handling delivery with applications, functioning akin to webhooks yet embedded within the moonstalk environment.

Handler functions are similar to scribe Editors and Curators, many can be defined by adding them to the email.handlers table and each will be attempted until one accepts the message for delivery; ideally the most frequently used is specified first.
Intended for use behind a primary MTA such as Postfix to performing spam filtering and domain-based rejections, before relaying to this process, which delegate the message to a receiving function (akin to a webhook). -- NOTE: currently only accepts a single recipient at a time, the relay MTA must therefore be configured appropriately
Maintains a persistent connection to the Teller, which has the same Teller client as in Scribes; this server does not handle sending outbound messages but new emails resulting from incoming messages can can be sent with an email.Dispatch task by the Teller -- NOTE: handler functions are blocking therefore socket.smtp should not be used within this process; if processing is required the message should be passed to another process (e.g. as a teller task) or with coroutines yielded and resumed using the libuv loop in this process; bear in mind that blocking for any longer than an MTA connection timeout will cause incoming message delivery to be retried and possibly returned to sender
-- WARNING: this is not a comprehensive protocol implementation and should not be served on a public IP or obvious port, but rather the local IP accessible to the primary MTA
-- TODO: currently ignores attachments, the primary MTA should perform appropriate rejections if processing messages with attachments is undesired, or postie_size can be set

node.postie = { -- enabled with node.servers={"postie"}
	ip		= ip_address (default: "127.0.0.1")
	port		= port_number (default: 25)
	size		= max_bytes (default: 36000; false to disable)
	clients	= allowed client_list (e.g. {"127.0.0.1"}); default is nil for any
	-- for sending defaults see functions.lua
}

The normalised message table as passed to handler functions are documented in functions.lua.

--]]

-- to avoid parsing incoming messages likely to be rejected, handlers and checks can be specified with email.recipients and email.senders, addresses may also be added to email.addresses; use of these results in a default SMTP error message, if a custom email response is desired, accept the message and reply using a function in email.handlers instead
-- to define email.senders recipients or handlers, an application should use their Enabler() if moonstalk.server=="postie" then table.insert(email.senders, MyHandler) end
-- all senders and recipients functions are passed the sender address and may return true or an error string if it is NOT allowed
-- all handlers are passed a normalised message
-- handlers must return email.RECEIVED if they have accepted the message for delivery and no other handlers are to be attempted
-- IMPORTANT: senders (return path) are not the same as the message from header; you will need a dedicated sender handler for bounces as these will not necessarily come back from a known sender, and NDRs often have no sender

--# dependencies

package.path = "core/lua/?.lua;applications/?.lua;applications/moonstalk.?.lua;"..package.path

local uv = require "luv"
require "mime" -- {package="mimetypes"}
require "iconv" -- {package="lua-iconv"}
require "moonstalk/server"


-- # globals

email.senders = {} -- these handlers are called with (sender) which is the return-path address (without angle brackets), typically it matches the from address but it could be an automated system, or nil
email.addresses = {} -- these recipient addresses are permitted and will prevent the recipient handlers from being called; don't use this if you need to check both sender and recipient
email.recipients = {} -- these handlers are called with (sender,recipient)
email.bouncers = {}
email.handlers = {}
node.postie = node.postie or {}


--# server

-- TODO: Auto-Submitted or X-Loop header field, or that have a bodypart with type multipart/report

local server = uv.new_tcp()
server:bind(node.postie.ip or "127.0.0.1", node.postie.port or "25")
server:listen(128, function(err)
	local client = uv.new_tcp()
	server:accept(client)
	if email.clients and not email.clients[client:getsockname().ip] then client:write"111\r\n"; client:close() end
	local sequence=0
	local chunks,message
	local string_match = string.match
	local string_sub = string.sub
	local string_find = string.find
	client:write(email.HOST)
	client:read_start(function (err, chunk)
		-- TODO: we need a timeout, perhaps start timer that can close the client if an active timestamp hasn't changed
		local command
		if sequence ~=4 then command = string.sub(chunk or "",1,4) end
		if command=="QUIT" then
			client:write"221\r\n"; client:shutdown(); client:close()
		elseif command=="RSET" then
			client:write"250\r\n"
			message = {}
			sequence = 1
		elseif sequence==0 and command=="EHLO" then
			message.mta = string.sub(chunk,6) -- TODO: add a received header with client and MTA instead
			if not email.SIZE then client:write("250\r\n") else client:write("250\r\n"..email.SIZE.."\r\n") end
			sequence=1
		elseif sequence==0 and command=="HELO" then
			-- mta = string.sub(chunk,6)
			client:write"250\r\n"; sequence=1
		elseif sequence==1 and command=="MAIL" then -- MAIL FROM: value SIZE nnnn
			message = {}
			message.sender = string_match(string_sub(chunk,11),"<(.+)>") -- return-path, often null for auto-responses
			local disallowed
			if not message.sender then message.detected = email.BOUNCE
			else
				for _,handler in ipairs(email.senders) do
					disallowed = handler(message.sender) -- FIXME: pcall
					if disallowed then
						if disallowed ==true then
							client:write"541 sorry, you don't have permission to send to this address\r\n"
						else
							client:write("541 "..disallowed.."\r\n")
						end
						sequence = 1 -- could be another message
					end
				end
				if not disallowed and email.SIZE then
					message.size = tonumber(string_match(string.sub(chunk,11)," (%d+)")) or 0
					if message.size >node.postie.size then
						client:write"523 sorry, your message exceeds the maximum allowed size of ("..(node.postie.size/1048576).."MB)\r\n"
						sequence = 1 -- could be another message
						disallowed = true
					end
				end
			end
			if not disallowed then
				client:write"250\r\n"
				sequence=2
			end
		elseif sequence==2 and command=="RCPT" then -- RCPT TO:
			message.recipient = string_match(string_sub(chunk,10),"<(.+)>")
			if string_find(sender,"+bounce@") then
				message.detected = email.BOUNCE
			elseif not email.addresses[message.recipient] then
				for _,handler in ipairs(email.recipients) do
					disallowed = handler(message.sender,message.recipient) -- FIXME: pcall
					if disallowed then
						if disallowed ==true then
							client:write"550 sorry, we don't know this address\r\n"
						else
							client:write("550 "..disallowed.."\r\n")
						end
					end
				end
			end
			-- TODO: handle but ignore multiple recipients
			client:write"250\r\n"; sequence=3 -- We don't currently support multiple recipients
		elseif sequence==3 and command=="DATA" then
			client:write"354\r\n"; sequence=4; chunks = {size=0}
		elseif sequence==4 and chunk then
			chunks[chunks+1] = chunk
			chunks.size = chunks.size + #chunk
			if chunks.size and email.SIZE and chunks.size >node.postie.size then

			end
			if string.sub(chunk or "",-5) =="\r\n.\r\n" then
				local accepted
				message.client = client:getsockname().ip
				message.data = table.concat(chunks)
				email.Message(message)
				for _,handler in ipairs(email.handlers) do -- all handlers are attempted unless one indicates it has received it, this allows handlers to be used for both parsing messages (when first in the table) and for delivery (when later in the table); obviously the order is thus important
					if handler(message)==email.RECEIVED then accepted=true; break end -- FIXME: pcall
				end
				sequence=1 -- there might be more messages to handle
				if accepted then client:write"250\r\n" else client:write"550\r\n" end
			end
		else client:write"503\r\n"; client:close() end -- we unceremonously reject illegal sequence or unknown command
	end)
end)


--# initialisation

moonstalk.Initialise{server="postie", log="temporary/postie.log",logging=1}
require "scribe/server" -- ensures we have access to application's scribe environment functions

teller.agent = "postie"
node.smtp = node.smtp or {}
if not node.smtp.postie then print"node.smtp.postie is disabled" return end


-- FIXME: call Loaders/Starters ?

if not handlers[1] then handlers[1] = function(data) log.Notice(util.SerialiseWith(message)) end end -- TODO: or debug
if node.postie.size ~=false then email.SIZE = "250 SIZE "..(tostring(node.postie.size) or "36000").."\r\n" end
email.HOST = "220 "..(node.postie.host or node.hostname).." Moonstalk.Postie\r\n"
if node.postie.clients then email.clients=keyed(node.postie.clients) end

uv.run()


--[[ main.cf
permit_auth_destination = yes
transport_maps = hash:/etc/postfix/transport
relay_domains = hash:/etc/postfix/transport
unknown_relay_recipient_reject_code = 550
smtpd_client_restrictions = permit_mynetworks reject_unauth_destination
smtpd_proxy_filter=127.0.0.1:10025
--]]
--[[ master.cf

127.0.0.1:10026 inet n  -       n       -        -      smtpd
	-o smtpd_authorized_xforward_hosts=127.0.0.0/8
	-o smtpd_client_restrictions=
	-o smtpd_helo_restrictions=
	-o smtpd_sender_restrictions=
	-o smtpd_recipient_restrictions=permit_mynetworks,reject
	-o smtpd_data_restrictions=
	-o smtpd_junk_command_limit=100000
	-o smtpd_soft_error_limit=10000
	-o smtpd_error_sleep_time=0
	-o smtpd_proxy_filter=
	-o mynetworks=127.0.0.0/8
	-o receive_override_options=no_unknown_recipient_checks

--]]

--[[ /etc/postfix/transport
example.com    smtp:[192.168.0.15]:2525
foo.example.com  smtp:[192.168.0.16]
--]]
