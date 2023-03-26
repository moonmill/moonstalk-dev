--[=[

Provides a generic interface to multiple backend transports including the default smtp courier, and others such as sendgrid over http.
Can be used immediately with no configuration as does not require a relay mailserver to send emails by delivery directly to recipients, however one is recommended in order to retry failures which are not currently supported.

email.Send{to="recipient@domain",subject="",body=""} -- see this function for further options
message.from or site.from or node_email.message.from must specify the sender address; use of site.from (site/settings.lua) is preferred

All addresses may be declared as either simple mailbox strings "mailbox@domain" or qualified with names e.g. "Recipient Name <mailbox@domain>".

Sending behaviour defults to async when available, thus does not return a result, but the message table is updated with an error in case it fails, and message.fail message.sent handlers may be used.
In servers that provide email.Enqueue, and where the node/messages are not provided with a server, email.Enqueue can be set as or called by a fail handler to invoke use of a queue to retry message and prevent overloading individual mail servers, e.g. for spam greylisting, this handler is responsible for managing the queue.
If sending batch emails, or attempting to send multiple seperate messages to the same server, it is preferable to use a queue, else use message.defer=false with your send loop as this dispatches only a single message at a time, but it will not return to the calling function/view until all have been dispatched.
Otherwise using the default async handling, will result in multiple messages being sent simultaneously as fast as possible during their creation, possibly resulting in thousands of coroutines and network connections which is probably quite undesireable; a very simple mitigation is to use message.defer=n with an incrementing step, which will create and execute a coroutine for each message only at the prescribed time (depending upon the timer/scheduler implementation) thus will consume resources simultaneously only in as much as execution and delays overlap.

node.email = "app" -- an application with Courier function e.g. "sendgrid"; default "smtp"
or node.email.courier = "app"
the courier app must provide a Courier() function e.g. sendgrid.Courier which denormalises the message and invokes its appropriate transport (smtp is a pseudo-app)

node.email.message = { -- default values for all messages or a specific courier with node_email[courier].message -- FIXME: apparently we're only using node.courier.default_key as it's simpler but has to be duplicated; update docs and display notice for each configured courier
	to = "email@address", -- catchall, replaces any specified recipients but only supported with logging >=4 (dev mode)
	bcc ="email@address", -- copyall, send a copy of all outgoing messages to this address
	from = "Name <email@address>", -- displayed to the user and used for replies
	sender = "email@address", -- return address for bounces and delivery problems, not to be confused with from
	headers = {name=value},
}
all keys in this table are copied to all outgoing messages; note that it is preferable to set static courier parameters in node[app] rather than copying such values to each message e.g. node.sendgrid.api_key

node_email.smtp = {
	server = "relay", -- server ip or fqdn, often simply "localhost" for the local MTA
	port=465, password="", user="", ssl={enable=true} -- additional options to authenticate with a relay server
	bind = "ip.address", -- optional and used instead of server; IP address of an available network interface, only needs to be specified if multiple interfaces are available; may be specified on messages in case seperate tenants use different mail origination IPs -- WARNING: in non-coroutine/async environments, this may result in much longer blocks with unreliable servers than using a relay with a reliable response time
	domain="name" -- used only for server greetings, defaults to hostname
	-- for postie server settings see server.lua
}


The message parsing functions are used by the postie server.lua and provide a normalised message table to its handlers, however the normalised message structure is documented here.

Message normalisation is intended for consumption of values, not for re-creation of the original message nor preserving original headers (e.g. a redirect). By default only a limited number of headers are parsed and added to the message, however all headers and original values can be obtained from message.original which is provided by metatable.__index thus not available outside this environment (i.e. in the teller). All header names are lowercase; values and attributes have case preserved.
Where a header value contains lexical tokens (key=value attributes) the header value contains the first non key-value string (an empty string if none), and additional header fields taking the form message.original['header-name:token-name']=token-value.
Values which have been folded (multiline) are unfolded to a single line and values enclosed in quotes have them removed.
Where a value has been processed or truncated the original header values is available from message.original['header-name'] instead of message['header-name']
Values for message.subject and message.body are UTF-8. Values for message.from and message.to are email addresses only, the text part may be obtained from message.original.

message = {
	-- provided by the sending MTA:
	sender = "MAIL FROM value",
	recipient = "RCPT TO value",
	mta = "HELO value",
	-- provided by the client as the envelope:
	from = "address",
	to = "address",
	subject = "",
	received = {
		""
	}
	-- body
	body = [[text/plain; charset=utf-8]],
	}
}
--]=]

-- NOTE: see settings for public namespaces that can be modified by other apps upon loading
-- NOTE: retry is attempted using the SMTP courier only in servers that engage the Queue; the Queue is persisted between restarts if the server also supports Shutdown; in all other cases and upon permanent failure with the queue failed messages are dumped to temporary/email with a timestamp and the recipient's address

if moonstalk.server =="tarantool" then return end-- FIXME:

couriers = {}
smtp_queue = util.Sync"data/smtp_queue.lua" or {} -- contains failed messages to retry with the Queue function

require "socket" -- {package="luasocket"}
_G.smtp = _G.smtp or require "socket.smtp" -- {package=false}; included with luasocket
_G.mime = _G.mime or require "mime" -- {package="mimetypes"}
_G.ltn12 = require "ltn12" -- {package=false}; included with luasocket

-- # globals

RECEIVED = "📧"
BOUNCE = "⛔️"
AUTOREPLY = "↩️"

local node_email
function Enabler()
	smtp.Courier = email.smtp_Courier -- must be assigned after loading as the namespace doesn't exist yet
	smtp.Envelope = email.smtp_Envelope
	if type(node.email)=='table' then
		node_email = copy(node.email)
		if node_email.message then
			if logging <4 then
				node_email.message.to = nil
			elseif node_email.message.to then
				if moonstalk.server=="runner" then display.error("email.Send is capturing to "..node_email.message.to,false) else log.Notice("email.Send is capturing to "..node_email.message.to) end
				node_email.message.to = email.NormaliseAddress(node_email.message.to)
			end
			node_email.message.bcc = email.NormaliseAddress(node_email.bcc)
			node_email.message.from = email.NormaliseAddress(node_email.from)
		end
		local couriers = 0; local courier
		for name in pairs(node_email) do
			if name ~="courier" and name ~="message" then
				if not node_email.courier and _G[name] and _G[name].Courier then couriers = couriers +1; courier = name end
			end
		end
		if couriers ==1 then node_email.courier = courier end -- set the default to single declared courier table
	else
		node_email = {courier=node_email}
	end
	node.email.smtp = node.email.smtp or {}
	node.email.smtp.sender = email.NormaliseAddress(node.email.smtp.sender) or "<moonstalk@"..node.hostname..">"
	node_email.courier = node_email.courier or "smtp" -- else fallback to smtp
	if not _G[node_email.courier] or not _G[node_email.courier].Courier then moonstalk.BundleError(email,{title="Invalid courier: "..node_email.courier}) end
	if moonstalk.server=="runner" and node_email.courier =="smtp" then
		if not node_email.smtp.server then display.error("Unspecified node.email.smtp.server, will default to direct dispatch from "..(node_email.smtp.bind_ip or node.hostname),false) end
		if node_email.smtp.bind_ip then
			local _,err = socket.tcp():bind(node_email.smtp.bind_ip,0)
			if err then moonstalk.BundleError(email,{title="Invalid bind_ip interface: "..err}) end
		end
		if not node.email.smtp.server then
			-- must make sure these are not specified as will interefere when opening sockets; username and password are ignored
			node.email.smtp._port = node.email.smtp._port or node.email.smtp.port
			node.email.smtp._ssl = node.email.smtp._ssl or node.email.smtp.ssl
			node.email.smtp._user = node.email.smtp.user
			node.email.smtp._password = node.email.smtp.password
			node.email.smtp.port = nil
			node.email.smtp.ssl = nil
		end
	end
	for name,app in pairs(moonstalk.applications) do
		if app.Courier then table.insert(email.couriers,name) end
	end
	for _,name in ipairs(email.couriers) do
		local app = _G[name]
		if not node_email[name] then
			node_email[name] = node_email.message
		else
			node_email[name].sender = email.NormaliseAddress(node_email[name].sender)
			if logging <4 then node_email[name].to = nil else node_email[name].to = email.NormaliseAddress(node_email[name].to) end
			node_email[name].bcc = email.NormaliseAddress(node_email[name].bcc)
			node_email[name].from = email.NormaliseAddress(node_email[name].from)
			copy(node_email.message, node_email[name], false, false)
		end
	end
	-- TODO: load app/emails and copy to sites for which app is enabled
end

function Shutdown()
	if not email.ready then return end -- don't attempt to save corrupted/unloaded/default data
	log.Debug("Saving SMTP queue")
	util.FileSave("data/smtp_queue.lua", email.smtp_queue)
end


-- # Main interface

local type=type
local string_find = string.find
local string_sub = string.sub
local string_match = string.match
local string_gmatch = string.gmatch
local string_lower = string.lower

function Send(message)
	-- {from="", to={} or "", cc={} or "", bcc={} or "", replyto="", subject="", headers={}} -- NOTE: all couriers must accept and denormalise these values
	-- message.fail = "app.FuncName" (message,retrying) end; name of an optional handler called when the message fails; the default is "email.Dump" in non-async servers whilst async servers should use "email.Enqueue" when there is no node/message.server; any explictly set fail handler should call email.Enqueue(message) itself in such servers otherwise it is responsible for handling queing and retries
	-- message.sent = "app.FuncName" (message) end; name of an optional handler called when the message completes; has no default by may be set conditionally such as to dequeue a retried message
	-- when using either of the above handlers, you will need to assign message an ID for introspection else use string.match(message.to,"<(.-)>") to get the email address as it will have been normalised
	-- supports site.from ="<email>"
	-- node_email.to ="email" can be used in dev mode to catch all outgoing messages (replaces all recipients); similarly node_email.bcc can be used to catch a copy (is added recipients)
	--- to test deliverability, you can eitehr wait for a sever response with message.defer=false, server=false (only in async servers); else use message.fail and message.sent handlers and/or a poller
	-- message.page uses scribe.Page with the given controller/view name to generate an HTML page as the message body; message.temp.key=value may be consumed in the view as ?(temp.key) in the usual manner; in addition the message itself may be modified, as message.subject = "value"; where a multipart message is desired the view should output the entire contents appropriately, and set corresponding headers -- FIXME: setfenv on the controller/view or _G?
	-- message.courier overrides the node_email.courier
	-- WARNING: the message table may be modified by couriers, and may be consumed asynchnously thus should not be reused unless you are certain it is only being consumed synchronously; use email.Send(copy(message)) if you have a message table template

	message.site = message.site or site.id -- for introspection, when sending from a scribe request we add here, otehrwise it SHOULD be added before calling Send
	-- TODO: add email.generator to be called in the courier at dispatch time and each time a retry is attempted, allowing cancellation
	-- if message.page then
	-- 	message.site = message.site or site.id
	-- 	local _site = _G.site; local _page = _G.page; local _output = _G.output; local _temp = _G.temp
	-- 	_G.site = moonstalk.sites[message.site]
	-- 	_G.temp = message.fields or {}
	-- 	scribe.Page(message.page)
	-- 	-- FIXME: handle errors
	-- 	message.html = table.concat(output)
	-- 	_G.site = _site; _G.page = _page; _G.output = output; _G.temp = _temp
	-- else
	if message.transcribe then
		local result,error = email.Transcribe(message)
		if error then message.error="Error transcribing email ‘"..(message.transcribe).."’"; return moonstalk.Error{email,title=message.error,detail=error} end
		message.body = result
	elseif message.fields then
		message.body = util.macro(message.body, message.fields)
		message.fields = nil
	end
	log.Debug(); if not message.body then message.error="No message.body for ‘"..message.subject.."’"; return log.Info(message.error) end
	log.Debug(); if not message.subject then message.error="Missing message.subject"; return log.Info(message.error) end

	-- normalisation
	local string_sub = string.sub; local string_match = string.match; local table_insert = table.insert
	message.headers = message.headers or {}
	message.rcpt = message.rcpt or {}

	-- this interface does not prepare headers, but does merge to/cc/bcc values into the rcpt table whilst normalising their values for use in headers
	local rcpt = message.rcpt
	if type(message.to) ~='table' then message.to = {message.to} end
	for i,address in ipairs(message.to) do
		if string_sub(address,-1) ==">" then
			address = string_match(address,"<.*>")
		else
			address = "<"..address..">"
			message.to[i] = address -- for Courier to construct headers
		end
		table_insert(rcpt,address)
	end
	if message.cc then
		if type(message.cc) ~='table' then message.cc = {message.cc} end
		for i,address in ipairs(message.cc) do
			if string_sub(address,-1) ==">" then
				address = string_match(address,"<.*>")
			else
				address = "<"..address..">"
				message.cc[i] = address
			end
			table_insert(rcpt,address)
		end
	end
	if message.bcc then
		if type(message.bcc) ~='table' then message.bcc = {message.bcc} end
		for i,address in ipairs(message.bcc) do
			table_insert(rcpt,string_match(address,"<.*>") or "<"..address..">")
		end
	end
	log.Debug(); if #rcpt ==0 then message.error="No message recipients for ‘"..message.subject.."’"; return log.Info(message.error) end

	message.courier = message.courier or node_email.courier
	log.Debug(); if not _G[message.courier] or not _G[message.courier].Courier then message.error="Invalid courier for message ‘"..message.subject.."’"; return log.Info(message.error) end

	local defaults = node_email[message.courier]
	if defaults then
		for key,value in pairs(defaults) do
			if message[key] == nil then message[key] = value end
		end
		log.Debug() if defaults.to then message.rcpt = {defaults.to}; message.bcc={};message.cc={} end -- capturing all messages; only used in development
		if defaults.bcc then message.bcc[#message.bcc+1] = defaults.bcc end -- monitoring all messages
		if defaults.headers then
			for name,value in pairs(defaults.headers) do
				message.headers[name] = value
			end
		end
	end

	message.from = message.from or site.from or defaults.from
	log.Debug(); if not message.from then message.error="No message.from for ‘"..message.subject.."’"; return log.Info(message.error) end
	if string_sub(message.from,-1) ~=">" then message.from = "<"..message.from..">" end

	log.Info() local log_recipient if #message.to >1 then log_recipient = #message.to.." recipients" else log_recipient = string.match(message.to[1],"<(.*)>") end
	log.Info() if message.defer==false then log.Info("Emailing '"..message.subject.."' to "..log_recipient.." via "..message.courier) else log.Info("Queuing email '"..message.subject.."' to "..log_recipient.." via "..message.courier.." in "..(message.defer or 0)) end
	-- denormalisation occurs in the courier
	return email.Dispatch(message)
end

function Dispatch(message)
	-- this default dispatcher does not support defer; servers implementing async/defer functionality, may assign a wrapper as email.Dispatch, or replace it and themselves call _G[message.courier].Courier(message); additionally such servers should enable the queue mechanism (see openresty for example)
	-- TODO: use the fail handler handler with some app to push a notification to the user (the userid has to be encoded into the return path)
	_G[message.courier].Courier(message) -- courier must set message.error, not return a state
	if message.error then
		log.Info("Email to "..message.rcpt[1].." failed: "..message.error)
		return email.Failed(message)
	elseif message.sent then
		email.Sent(message)
	end
	log.Debug("Sent email to "..message.rcpt[1])
	return true
end

function Failed(message)
	-- NOTE: retrying=true with the first message.error; retrying=nil when backoff expires and the message is dropped
	if not message.fail then
		log.Debug("unspecified message.fail")
		return nil,"unspecified message.fail"
	end
	local app,handler = string.match(message.fail, "(.-)%.(.+)")
	log.Debug() if not _G[app] or not _G[app][fail] then moonstalk.Error{email,title="Unknown message.fail",detail="handler ‘"..handler.."’ for message ‘"..message.subject.."’"}; return nil,"Unknown message.fail: "..message.fail end
	local result,err = pcall(_G[app][fail],message)
	if err then log.Notice(fail); message.error = "Error with fail handler '"..message.fail.."' on message '"..message.subject.."' "..err end
	return nil,message.error
end
function Sent(message)
	local app,sent = string.match(message.sent, "(.-)%.(.+)")
	log.Debug() if not _G[app] or not _G[app][sent] then moonstalk.Error{email,title="Unknown message.sent",detail="handler ‘"..handler.."’ for message ‘"..message.subject.."’"}; return nil,"Unknown message.sent: "..message.sent end
	local result,err = pcall(_G[app][handler],message)
	if err then log.Notice(fail); message.error = "Error with fail handler '"..message.fail.."' on message '"..message.subject.."' "..err end
end


-- # retry queuing
-- this is a slow/lazy/polite implementation and is not intended for high-perfomance nor heavy use; servers are only ever attempted with a single message, with all others waiting upon it to succeed, thus manual review is important to catch permanent errors that may be blocking other messages; however when such messages are dumped (24h) the others will then go through
-- the queue is sparse and can be persisted, eache message.enqueued is an introspective reference to its position in the queue
-- queue.errors is a table of keys corresponding the full error message, and its count
-- the queue is subdivided into tables for each server with uncleared errors; any new message sending to a server with errors is thus enqueued
-- NOTE: currently we do not allow for backup mx or changing the server -- TODO:

do local backoff = {[0]=300, [1]=1800, [2]=10800,[3]=21600, [4]=43200, [5]=64800} -- 5m 30m 3h 6h 12h 18h; after two days we give up
function Enqueue(message)
	-- only used for the first failure, thereafter is managed through Queue
	-- custom fail handlers should call this if they are handling retries themselves, note however that failhandlers can be called twice for the same message, however message.enqueued is not set until the fucntion is called, thus can be used to introspect between the first failure and (if applicable) final finalure
	if not email.Retry(message) then
		-- permanent
		return -- dispatcher will run fail handler
	end
	message.retries = message.retries or 0
	message.queue = message.queue or message.server
	email.smtp_queue[message.queue] = email.smtp_queue[message.queue] or {retry=backoff[0],errors=1,cumulated=0,count=0,messages={}} -- we don't update retry with each new message, only in the queue which has its own counter for increasing its backoff, but we start with the smallest regardless of error type
	message.enqueued = #email.smtp_queue[message.queue].messages +1
	email.smtp_queue[message.queue].messages[message.enqueued] = message
	log.Info("Enqueued email to "..message.rcpt[1])
end

local string_find = string.find
function Retry(message)
	-- whether the message should be retried based upon error
	-- TODO: return multiple classes, so that some message don't block others; we can use message.queue for this
-- 450 4.2.2 : user is overquota

	message.status_ex = string.match(message.error or "", "%d%d%d.(%d%.[%d]+%.[%d]+)")
	if message.retries and message.retries >5 then return false
	elseif message.status ==550 then
		-- this status is used for greylisting (a temporary error) as well as reporting unknown users (a permanent error) thus needs special handling
		if message.status_ex =="5.1.1" then
			-- extended status explictly identifies unknown user
			return false
		elseif message.status_ex then
			-- other errors, mostly greylisting -- TODO: identify and add common explict errors
			return true
		elseif string_find(message.error,"known",1,true) or string_find(message.error,"valid",1,true) or string_find(message.error,"no such",1,true) or string_find(message.error,"found",1,true) or string_find(message.error,"exist",1,true) or string_find(message.error,"that name",1,true) then
			-- unknown user using non-extended code
			return false
		else
			-- we assume all other errors here are some sort of greylist or blacklist issues
			return true
		end
	elseif message.status ==554
	or message.status ==521
	or message.status_ex =="4.2.2" -- over quota -- FIXME: retry later but don't hold up
	then -- explictly permanent errors
		-- TODO: > 499
		return false
	else
		-- else all other errors transient so should be retried but not as soon as greylisted ones -- TODO:
		return true
	end
end

function Queue(terminating)
	-- must be executed by a server, e.g. on a timer
	-- TODO: implement fallback relay for spam if retried >n times?
	-- OPTIMIZE: enhance timer execution with a horizon, e.g. when enqueuing a new mesasge, or removing a sent message
	-- a slow dispatcher, it waits for each message to finish before moving onto the next, this reduces load on individual servers; furthermore it doesn't retry a server if it gave an error
	if terminating then return end -- for nginx comaptability but shoudkl really be wrapped
	for mx,server in pairs(email.smtp_queue) do
		if now > server.retry then
			log.Info("Dequeuing emails for "..mx)
			for _,message in pairs(server.messages) do -- pairs because sparse array
				-- only attempt messages if they send, then backoff
				message.retries = message.retries +1
				message.defer = false -- the queue must wait
				smtp.Courier(message) -- the queue only supports smtp
				if message.error and email.Retry(message) then
					-- update the server's next retry
					server.errors = server.errors +1
					server.retry = now + (backoff[server.errors] or backoff[#backoff])
					break -- ignore any other messages until we try again
				end
				-- dequeue, either success or permanent failure
				server.cumulated = server.cumulated +server.errors
				server.errors = 0
				server.messages[message.enqueued] = nil
				if not message.error then
					message.status = nil
					email.Sent(message)
				else -- if not email.retry then
					email.Failed(message)
				end
				if not next(server.messages) then
					email.smtp_queue[mx] = nil
					break -- move onto the next server
				end
				server.retry = 0 -- try again ASAP, actually we're in a loop so this is redundant
				if sleep then -- global from server
					-- we pause here to be polite; if teh server returned any kind of error, and then starts resuming again we shouldn't be too optimistic about its limits
					log.Debug("sleeping dequeue")
					sleep(math.random(10,30))
				end
			end
		end
	end
end
end


-- # Default SMTP Courier
-- couriers are provided by applications as application.Courier and each may have its own behavious beyond the normalised values provided by email.Send

do local log=log; local util=util; local smtp; local mime -- these are required when the courier is run async e.g. with ngx.timer
local mx_cache = {} -- FIXME: needs a purge mechanism, perhaps simple use counter that just wipes it entirely
function smtp_Courier (message)
	-- if not using message.text and/or message.html we assume message.body is correctly prepared for use with this courier, which allows optimisations where the body is pre-rendered once for batch sends, instead of applying encodings on each send attempt, obviously this disallows swapping between couriers without also changing the body processing before Send is called
	-- this courier has a built-in retry queue, which may be disabled with node/message.fail = false or some other handler; non-asynchornouse servers should provide a default for this; whilst async servers SHOULD provider a timer to call email.smtp_queue
	-- TODO: implement queue with resource limit; each completition results in a check of the queue and sending the next if resources are available; strictly the defer behaviour would also add to the queue but we'd still use existing timers to invoke it; the queued and deferred items could thus be saved and restored in cases of termination
	-- default courier assigned to the smtp table by the starter
	-- server="", user="", password="";
	-- sender=""; allows to specify the return address (e.g. id+bounce@domain) otherwise it is the same as from
	-- message.text or message.html may specify a message body for which the corresponding content-type will be set; if both text and html are declared the content-type is set to multipart-alternate
	-- NOTE: if neither message.server or node.email.smtp.server then delivery is made without relay directly to the recipient domain's MX
	-- in the case of an error, message.error and (if an SMTP error) message.status are added; message.errors is an additional table of recipients {email={error=message,status=code},…}; because a specified node/message.server is usually a relay, they will generally only fail once for all recipients (e.g. due authentication), and errors for individual recipients will result in delivery reports being forwarded to the sender by teh relay, it is however possible for an error status to be return in the middle of a multiple-recipient transaction in case a limit is reached or malformed data encountered, there is however no easy status recovery from this
	mime = mime or _G.mime; smtp = smtp or _G.smtp -- unfortunate but apps may change it
	local string_match = string.match; local table_insert = table.insert
	if not message.headers.to and message.to then
		local to = {}
		for _,address in ipairs(message.to) do table_insert(to,address) end
		message.headers.to =table.concat(to,", ")
	end
	if not message.headers.cc and message.cc then
		local cc = {}
		for _,address in ipairs(message.cc) do table_insert(cc,address) end
		if not empty(cc) then message.headers.cc = table.concat(cc,", ") end
	end
	message.headers.from = message.from
	message.headers['x-mailer'] = "Moonstalk"

	if not message.headers["content-type"] then
		-- message.body = ltn12.filter.chain(mime.encode("quoted-printable"),mime.wrap("quoted-printable")) FIXME: use a proper chain with normalize() for line endings too; currently we use smtp.message to create the source
		if message.text and message.html then
			message.headers['Content-Type'] = "multipart/alternative" -- boundary is added automatically
			message.body ={
				{body=mime.wrap("quoted-printable")(mime.encode("quoted-printable")(message.text)), headers={["content-transfer-encoding"]="quoted-printable", ["content-type"] ="text/plain; charset='utf-8'"}},
				{body=mime.wrap("quoted-printable")(mime.encode("quoted-printable")(message.html)), headers={["content-transfer-encoding"]="quoted-printable", ["content-type"]="text/html; charset='utf-8'"}},
			}
		elseif message.html then
			message.headers["content-type"] ="text/html; charset='utf-8'"
			message.headers["content-transfer-encoding"] ="quoted-printable"
			message.body = mime.wrap("quoted-printable")(mime.encode("quoted-printable")(message.html))
		elseif type(message.body) ~='table' then
			message.headers["content-type"] ="text/plain; charset='utf-8'"
			message.headers["content-transfer-encoding"] ="quoted-printable"
			message.body = mime.wrap("quoted-printable")(mime.encode("quoted-printable")(message.body or message.text))
		end
	end
	message.headers.subject = mime.ew(message.subject, nil, {charset= "utf8"})
	if message.replyto then message.headers["Reply-To"] = email.NormaliseAddress(message.replyto) message.replyto=nil end

	message.from = message.sender or node_email.smtp.sender -- from in the smtp API is actually the sender (not the From header) and thus must be re-set after we consume it for the header
	local result,err
	if not message.server or message.bind_ip then -- TODO: would be preferable to use this block for all
		-- we'll attempt to deliver directly to the recipient's MX server
		-- NOTE: DNS lookups are likely to be async, however dispatch is called wrapped thus the original request will be preserved if called from one
		local failures = 0
		for _,rcpt in ipairs(message.rcpt) do
			message.rcpt = {rcpt}
			message.server = string_match(string.lower(rcpt), "@([^>]+)") -- the domain
			if not mx_cache[message.server] or mx_cache[message.server].updated < now -1800 then -- cache for 30mins
				message.server,message.error = email.ResolveMX(message.server)
				if message.server then
					mx_cache[message.server] = mx_cache[message.server] or {mx=message.server}
					mx_cache[message.server].updated = now
					if message.error then
						-- TODO: move from unresolved queue to proper queue on successful DNS attempt
					end
				else
					message.queue = "unresolved" -- a generic dns error queue
				end
			else
				message.server = mx_cache[message.server].mx
			end
			if not message.enqueued and email.smtp_queue[message.server] then
				-- backoff immediately, but not on retries
				message.error = "enqueued"
			elseif message.server then
				message.source = smtp.message(message)
				if message.bind_ip or node_email.smtp.bind_ip then
					local bind_ip = message.bind_ip or node_email.smtp.bind_ip
					log.Debug("binding SMTP to IP "..bind_ip)
					message.create = function() -- the smtp interface (through the socket.tp wrapper) uses this instead of a direct call to socket.tcp, allowing us to modify the behaviour and bind to a specific ip instead of the OS default -- FIXME:in ngx this is using luasocket thus is BLOCKING; could offload to another thread providing defer==nil https://github.com/openresty/lua-nginx-module/pull/712
						local master,err = socket.tcp()
						if err then return nil,err end
						master:settimeout(4)
						local result,err = master:bind(bind_ip,0)
						if err then log.Alert(err) end
						return master,err
					end
				end
				log.Info("Sending '"..message.subject.."' to "..message.rcpt[1].." using "..message.server)
				result,message.error = smtp.send(message)
			end
			if message.error then
				log.Debug("Send failed: "..message.error)
				message.create = nil
				message.source = nil
				message.status = tonumber(string.match(message.error,": (%d%d%d)")) -- some servers suffix with dash, others space
				message.error = string.match(message.error,"%.lua:[%d]+: (.+)") or message.error
				failures = failures+1
				message.errors = message.errors or {}
				message.errors[rcpt] = {error=message.error,status=message.status}
			end
		end
		if failures ==0 then return true end
		-- message.error = (#message.rcpt -failures).." sent, "..failures.." failed; see message.errors for each recipient" -- no longer used because we must parse the error and don't currently correctly handle multiple recipients -- TODO:
	else
		log.Info("Sending '"..message.subject.."' to "..message.rcpt[1])
		message.source = smtp.message(message)
		result,message.error = smtp.send(message) -- FIXME: how does this report individual errors with multiple recipients? resty-smtp apparently returns on the first failure
		log.Debug(result)
		log.Debug(message)
		if not message.error then return true end
		log.Debug("Send failed: "..message.error)
		message.source = nil
		message.status = tonumber(string.match(message.error,": (%d%d%d)"))
		message.error = string.match(message.error,"%.lua:[%d]+: (.+)") or message.error
	end
	-- a failure
	-- the dispatcher will run handlers
	return nil,message.error
end end


-- # Utilities

do local string_sub = string.sub
function NormaliseAddress(address)
	-- for use in headers, adds angle brackets if missing
	if not address or string_sub(address,-1) ==">" then return address else return "<"..address..">" end
end end

function Dump(message)
	-- message.failed = email.Dump
	local log_recipient
	if #message.to >1 then log_recipient = #message.to.."-recipients" else log_recipient = string.match(message.to[1],"<(.*)>") end
	util.FileSave("temporary/email/"..(message.courier or "dispatch").."_"..now.."_"..log_recipient..".lua",util.SerialiseWith(message,{truncate=false}),true)
end

function ResolveMX(domain,priority)
	-- returns highest priority mail exchange hostname beyond given priority
	-- does not work in openresty, which replaces with a native function -- OPTIMIZE: replace this with a socket-based routine
	local exchangers = {}
	for mx_priority,mx_host in string.gmatch(util.Shell("dig "..domain.." MX","*a"), "MX%s+(%d+)%s+(.-)%.\n") do
		table.insert(exchangers,{priroity=tonumber(mx_priority),host=mx_host})
	end
	util.SortArrayByKey(exchangers,"priority")
	if not exchangers[1] then return nil,"no MX found"
	elseif not priority then return exchangers[1].host
	else
		for _,exchanger in ipairs(exchangers) do
		if exchanger.priority > priority then return exchanger.host end
		end
	end
end

-- # Views

do
local email_env = {} -- this is reused, which is only possible because the assignment and rendering are sequential; re-transcribing the email later is not therefore possible
setmetatable(email_env, {__index=function(self,key) return rawget(self.message.fields,key) or rawget(self.message,key) or _G[key] end}) -- for the final lookup we must not use rawget as that disables package handling (e.g. math is not actually in the global table)
local view_env = {message={},output={}}
setmetatable(view_env, {__index=function(self,key) return rawget(self.message,key) or _G[key] end})

function Site(bundle) -- FIXME: also run on each application bundle from Enabler
	bundle.emails = bundle.emails or {}
	for _,item in ipairs(bundle.files or {}) do
		-- TODO: translations item.locales
		local name,type = string.match(item.file,"^emails/(.-)%.(.+)")
		if name and item.id then
			local view = bundle.views[item.id]
			log.Info("	Loading email: "..item.id)
			bundle.emails[name] = item
			if view.template ~=false and bundle.files['emails/template'] then view.template = "emails/template" end
			local err
			if type=="eml" then
				view.loader_email,err = loadstring(email.TranslateView(util.FileRead(item.path),view))
				setfenv(view.loader_email, email_env)
			end
			if err then log.Alert("Error in "..item.file..":"..err) end -- TODO: bundle error

			-- we wrap the original view loader to handle the message enviornment etc
			setfenv(view.loader, view_env) -- NOTE: -- FIXME: this is not restored if the file is reloaded because it is updated; perhaps preserving the env is necessary in scribe upon reload
		end
	end
end

function Transcribe(message)
	-- .lua files specify the message.body table (per smtp.body), or .html or .text view files provide the whole message body, but may also contain server tags and macros, views may also declare <? section "html" ?> to combine multiple parts of a multi-part/alternate message in a single view.
	-- the environment for the files contains the message table and can thus manipulate it, to facilitate use in macros, all its fields are however exposed as root values, e.g.: ?(name)==message.fields.name; ?(message.to)==message.to; ?(format.date(date))==_G.format.date(message.fields.date)
	-- if an emails/template file exists this will also be called after the view and must therefore include either or both of ?(message.html) and ?(message.text) macros to merge the view's corresponding content/sections, it should also declare its own sections if multipart
	email_env.message = message
	message.fields = message.fields or {}
	-- transcribe defines the html and text content of an email
	local bundle,view = string.match(message.transcribe, "(.-)%/(.+)")
	bundle = moonstalk.bundles[bundle]
	log.Info(); if not bundle or not bundle.emails then return moonstalk.Error("Invalid email ‘"..message.transcribe.."’ for ‘"..(message.subject or "unspecified subject").."’") end
	view = bundle.emails[view]
	log.Info(); if not view then return moonstalk.Error("Invalid email ‘"..message.transcribe.."’ for ‘"..(message.subject or "unspecified subject").."’") end
	-- TODO: in dev mode only NOTE: we do not use scribe.LoadView here thus content does not refresh
	local result,error = pcall(view.loader_email)
	if not result then error = "Error transcribing email '"..message.transcribe.."': "..response end
	if view.template ~=false and site.emails.template then
		result,error = pcall(site.emails.template.loader_email)
		if not result then error = "Error transcribing email template: "..response end
	end
	message.fields = nil; message.template = nil; message.transcribe = nil -- do not need to be preserved
	if error then message.error = error; return moonstalk.Error(error) end
end
end

function TranslateView(data,view)
	-- TODO: rewrite relative src and href to use site.domain
	local function outputString (s, i, f)
		s = string.sub(s, i, f or -1)
		if #s==0 then return nil end -- ignore blank values
		return [[ output[#output+1]= [=[]]..s..[[]=]; ]] -- escape the append assignment value as a long string
	end
	data = string.gsub(data, "%?(%b())", "\5%1\5") -- can't capture the contents alone, so this two-fold gsub is simplest solution; we assume that \5 is not used in the markup nor js
	data = string.gsub(data, "\5%((.-)%)\5", "<?= %1 ?>")
	-- translate these section names (text, html) to _prefixed as their tables are in the messages fields and clash with global names -- TODO: improve this as is too hacky

	local body = {"local output=output;"}
	local start = 1 -- start of untranslated part in `s'
	while true do
		local startOffset, endOffset, isExpression, code = string.find(data, "<%?[ \t]*(=?)(.-)%?>", start)
		if not startOffset then break end -- reached the end, or contains no processing directives
		table.insert(body, outputString(data, start, startOffset-1))
		if #code>0 then
		if isExpression == "=" then
			table.insert(body, "output[#output+1]=") -- nothing is added to the output if expression is nil, as required by merge
			table.insert(body, code)
			table.insert(body,";")
		else
			-- code/string block
			table.insert(body, string.format(" %s ", code))
		end
		end
		start = endOffset + 1
	end
	table.insert(body, outputString(data, start, nil))
	return table.concat(body)
end


--# Server/incoming message parsing

function Header(message,header,transform)
	-- sets the header in the message if found and returns the value, else returns nil
	local value = string.match(message.original.headers, "\n"..header..":%s*(.-)\n%S")
	if value =="" then return end
	message.original[header] = value
	value = string.gsub(value,"(\n%s+)","") -- remove folding; this entirely collapses whitespace between lines and only preserves trailing whitespace on a line
	if transform then value = transform(value) end
	message[header] = value
	return value
end

function HeaderTokens(message,header,tokens)
	-- parses a header containing lexical key=value tokens seperated by semi-colons; each found key will be set as an additional message['header:key']=value
	-- can be called on a header that has not yet been parsed, and can be provided with the value (tokens) if seperately extracted (primarily for use with content-type)
	tokens = tokens or message[header] or Header(message,header)
	local first = string_match(tokens,"(.-);")
	if not string_find(first,"=",1,true) then message[header] = first; tokens = string_sub(tokens,#first+1) end -- tokenised headers may nonetheless start with an untokenised value
	for key,value in string_gmatch(tokens,"([^=;%s]+)=?([^;]+)") do -- tokens are delimited by ; whilst key and value are delimited by = although values may themselves contain the = character
		message[header..":"..key] = value
	end
end

function Headers(message,header)
	-- parses headers when there are expected to be multiple instances of it, e.g. for Received; value is an array representing each matched header -- TODO:
end

function Address(value)
	if string.find(value,"<") then return string.match(value,"<(.+)>") end
	return value
end

do local encodings = {B="base64",Q="quoted-printable"}
function Decode(encoded)
	-- decoding and charset conversion for rfc2047 encoded words (header values); handles previously folded values (multiple encoded values to be concatenated)
	-- OPTIMIZE: ideally we'd check the original value for a linebreak before invoking the iterator
	if string.sub(value,1,2) =="=?" then
		local decoded = {}
		for charset,encoding,value in string.gmatch(encoded,"=%?(.-)%?(.)%?(.+)%?=") do
			if charset and encoding and value then
				encoded = mime.decode(encodings[encoding])(value)
				if charset ~="utf-8" and charset ~="us-ascii" then value = iconv.new("utf-8", charset)(value) end
				table.insert(decoded,value)
			end
		end
		return table.concat(decoded)
	end
	return value
end end

do local default_headers = keyed {"to","from","date","subject","content-transfer-encoding","auto-submitted","x-loop"} -- only for single-line headers, otherwise use Header()
function Message(original)
	-- expects either string message data or a table with at least {data=[[…]]}, however the table will contain other transport derived values such as sender, recipient and client when originated from the postie server
	-- returns a new message table with the ephemeral message.original subtable all values for which are non-transferable
	if not original then return end

	-- wrap in metatable
	local message = {headers={}}
	if type(original)~='table' then original={data=original} end
	setmetatable(message, {original=original, __index=function(table,key) return rawget(table,key) or getmetatable(table)[key] end}) -- false values in the message table are not supported and will return as nil or the value set in the metatable

	original.data = string_gsub(original.data,"\r","") -- use only LF not CRLF
	-- split the evelope from the content
	-- we want to avoid too many new string values so we only record the start position of the body
	original.headers, original.body = string_match(original.data,"(.-)\n\n()")
	original.headers = "\n"..original.headers.."." -- we need an initial line to match header names accurately, plus a trailing non-space value to match the last header's value
	original.headers = string_gsub(message.original.headers, "\n(%S-):(.+)",function(name,value)
		if default_headers[name] then message[name] = value end
		return string_lower(name) -- headers need to be lowercase for matching
	end)

	message.date = Date(message.date)
	message.subject = email.Decode(message.subject)
	HeaderTokens(message,"content-type") -- can contain tokens thus needs expanding

	if email.Bounced(message) then return message end -- we don't process these emails any further

	-- body charsets and encodings
	if message['content-transfer-encoding'] then
		local encoding = string_lower(message["content-transfer-encoding"])
		if encoding=="quoted-printable" or encoding=="base64" then
			message.body = mime.decode(encoding)(message.body)
		end
	end
	if message['content-type'] then
		-- should contain charset
		if message['content-type:charset'] then -- regardless of the content-type e.g. for text/plain as well as text/html
			local charset = string.upper(message['content-type:charset'])
			message['content-type:charset'] = charset
			if charset ~="UTF-8" and charset ~="US-ASCII" then message.body = iconv.new("UTF-8", charset)(message.original.body) end
		end

		elseif string_sub(message['content-type'],1,9) =="multipart" then
			message.parts = {}
			local boundary = message['content-type:boundary']
			if string.sub(boundary)=='"' then boundary = string.sub(boundary,2,-2) end -- remove quoting from boundary
			for part in string_gmatch(message.data, boundary) do
				part = {original=part}
				part.headers,part.data = string_match(part,"(.-)\n\n()")
				local count = 0
				for name,value in string_gmatch(part.headers,"") do
					part[string_lower(name)] = string_match(value,"([^;]+)")
					local tcount = 0
					for tname,tvalue in string_gmatch(value,"([^ =]+)=([^;]+)") do
						part[string_lower(name)..":"..tname] = tvalue
						tcount=tcount+1; if tcount >6 then break end
					end
					count=count+1; if count >6 then break end
				end
				table.insert(message.parts,part)
			end

			if message['content-type'] =="multipart/mixed" then
				-- find the boundary for the multipart/alternative parts
				--001a11c17f62317fe9054abb688b
				--Content-Type: multipart/alternative; boundary=001a11c17f62317fe4054abb6889

			elseif message['content-type'] =="multipart/alternative" then

			elseif message['content-type'] =="multipart/related" then
				-- has a type=text/html and its subparts must be traversed to concat all plain/html parts and extract the attachment parts?

				--boundary ==begin sequence; first part
				--boundary ==second part
				--boundary-- ==end sequence

			end
	end
	return message
end end

function Date(value)
	-- Tue, 12 Nov 2019 13:56:14 +0800
	local zone
	local time = {}
	time.day,time.month,time.year,time.hour,time.min,time.sec,zone = string_match(value,", (%d%d?) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) ?(.*)")
	time = os.time(time)
	if zone and tonumber(zone) then
		local op,hours,mins = string_match(zone,"([-+])(%d%d)(%d%d)")
		mins = (hours * 60) + mins
		if op =="+" then time = time - mins -- idiosyncratic but if the message was sent 8 hours ahead of UT we must thus bring it back (subtract) for UT
		else time = time + mins end
	-- string timezones e.g. PST don't appear to be used anymore so not supported
	end
	return time
end

function Part(message,type,boundary)
	-- extracts a part with a
end

local bouncees = keyed{ "mailer-daemon","postmaster", }
function Bounced(message)
	if message.detected ==nil then
		local sender_mailbox = string_lower(string_match(message.sender,"(.+)@"))
		if bouncees[sender_mailbox] then message.detected = email.BOUNCE
		elseif message['content-type'] =="multipart/report" then message.detected = email.BOUNCE
		elseif message['auto-submitted'] or message['x-loop'] then message.detected = email.AUTOREPLY
		end
	end
	return message.detected
end
