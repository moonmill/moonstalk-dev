--[[ Moonstalk Generic Database functions ]]--
-- TODO: this needs to be an authication app, with the other fucntionality probably moved to kit

tasks = {}

local digits = digits
local persist = persist
local pairs = pairs
local ipairs = ipairs

function Signin(query)
	-- this supports both A. non-comparible hashing such (e.g. bcrypt) for which no password is passed and instead we return the stored hash for verification with a subsequent seperate call to SetSession if that was successful; and B. reproduciable hashing mechanism (e.g. sha-2) which if the provided hashed password matches the one stored in the db, enables the session to be started immediately
	local authuser,ident
	if string.find(query.login,'@',1,true) then -- an email; -- NOTE: must use plain match otherwise LPEG match syntax in username would be a security risk
		authuser = emails_user[query.login]
		log.Info "email login"
		if not authuser then return "unknown" end
		local email = util.ParentKeyValue(authuser.emails,"address",query.login)
		if email and email.verify then return "unverified" end -- TODO: this should be a keychain to enable signup to multiple tenants
	elseif type(query.login) == number then -- a telephone number; the client must normalise as a number, removing spaces and standardising the prefix
		authuser = telephones_user[number]
		log.Info "tel login"
	else -- is it a username?
		authuser = urns_user[query.login]
		log.Info "urn login"
	end

	if not authuser then
		return "unknown"
	elseif (authuser.session_attempts or 0) > 4 then
		return "disabled"
	elseif not query.password then -- e.g. bcrypt
		return {hash=authuser.password,id=authuser.id}
	elseif query.password == authuser.password then -- e.g. sha-2
		return generic.StartSession(query,authuser)
	else -- a user but invalid password or requires a client-side verification
		-- we don't persist attempts
		if authuser.session_attempts then
			authuser.session_attempts = authuser.session_attempts+1
		else
			authuser.session_attempts = 1
		end
		return "invalid"
	end
end

function VerifyUser(query)
	-- to flag for verification provide query.email and a query.verify ID to be used as the verification token
	-- to verify provide token (from prior call) as query.verify and query.token as the token for the new signin session (e.g. set as the cookie for the user); returns user on success
	-- verification sessions are not persisted, thus expire when the db is restarted
	if query.email then
		-- flag an email for validation
		local authuser = emails_user[query.email]
		if not authuser then return end
		for i,email in ipairs(authuser.emails) do
			if email.address ==query.email then
				if email.verify then
					-- remove the old one; avoid polluting the db in case of multiple requests
					sessions_user[email.verify] = nil
				end
				email.verify = query.verify
				sessions_user[email.verify] = authuser -- these are lost on db restart
				persist("users["..digits(authuser.id).."].emails.["..i.."].verify", email.verify)
				log.Info("Assigned verification token to "..email.address)
				return true
			end
		end
	else
		-- unflag for verification and signin
		local authuser = session_user[query.verify]
		if not authuser then return end
		sessions_user[query.verify] = nil
		authuser.password = nil -- this is a hint that the user must set their password as the old one was forgotten
		for i,email in ipairs(authuser.emails) do
			if email.verify ==query.verify then
				email.verify = nil
				persist("users["..digits(authuser.id).."].emails.["..i.."].verify",nil)
				log.Info("Verified "..email.address)
				delegate("VerifiedUserSessionDelegate",authuser,query.token) -- allows apps to
				return StartSession(query,authuser) -- sets the new token as provided in the query
			end
		end
	end
end

-- TODO: cleanup unused sessions
function NewUserDelegate (authuser)
	if sessions[authuser.id] then
		for token,session in pairs(sessions[authuser.id]) do
			AuthUserSessionEvent(authuser,token,session)
		end
	end
end

function NewUserSessionEvent(authuser,token,session)
	-- invoked only on sucessful new signin e.g. new device -- TODO: could probably be invoked on every signin
	sessions[authuser.id][token] = session -- persistence
	persist("sessions["..digits(authuser.id).."]["..digits(token).."]", session)
	delegate("NewUserSessionDelegate",authuser,token,session)
	AuthUserSessionEvent(authuser,token,session) -- index
end

function AuthUserSessionEvent(authuser,token,session)
	-- user and token are required; activates or expires sessions -- TODO: expiry really needs a task rather than on startup
	-- invoked on startup for each user
	session = session or sessions[authuser.id][token]
	local remove
	if not session then
		return
	elseif session.expire and session.expire <now then
		-- remove expired sessions
		remove = true
	elseif session.expire ~=false and session.active and session.active <(now-10368000) then
		-- remove old sessions (that have not been signed out or have been inactive for over 120 days), except those flagged as permanent (expire=false)
		remove = true
	elseif session.active then
		-- enable sessions in-use
		sessions_user[token] = authuser
	end
	if remove then
		DeleteUserSessionEvent(nil,authuser,token)
	else
		delegate("AuthUserSessionDelegate",authuser,token,session)
	end
end
function DeauthUserSessionEvent(userid,authuser,token)
	-- does not remove the session so that it may be reused, e.g. upon signout
	authuser = authuser or users[userid]
	log.Info ("Expiring session: "..digits(token))
	delegate("DeauthUserSessionDelegate",authuser,token)
	sessions_user[token] = nil
end
function DeleteUserSessionEvent(userid,authuser,token)
	-- removes the session entirely e.g. if old
	authuser = authuser or users[userid]
	log.Info ("Deleting session: "..digits(token))
	DeauthUserSessionEvent(nil,authuser,token) -- we must also expire the session
	delegate("DeleteUserSessionDelegate",authuser,token)
	sessions[authuser.id][token] = nil
	save("user["..digits(authuser.id).."]["..digits(token).."]", nil)
end

local function GetSession(site,authuser,session)
	local response = {}
	response.user = util.TablePieces(authuser,userSessionPieces)
	response.session = session
	if authuser.settings then response.settings = authuser.settings[site] end
	if authuser.keychains then response.keychain = authuser.keychains[site] end
	return response
end

function StartSession(query,authuser)
	-- this function performs the actual assignments for a signin {ip=ip,id=userid,token=token}, or just setting a session token {token=token,id=userid,application=namespace}; non-signin sessions (e.g. for feeds, or APIs) should declare an application attribute
	-- NOTE: query.token is actually a decoded ID
	-- NOTE: applications that don't want sessions auto-expired must add a managed attribute with their name to the session, and should then take responsibility for maintaining that session; in the case of needing many sessions, the application should probably not store its sessions in user.sessions
	authuser = authuser or users[query.id]
	if not authuser then return "invalid" end
	sessions[authuser.id] = sessions[authuser.id] or {}
	-- save token
	local session
	if not sessions_user[query.token] then
		-- new session
		-- we have a maximum number of sessions and before adding must remove either an expired session, or the least recently used
		-- long-validity sessions (e.g. RSS tokens) may set expire=false, and they only expire after a defined period of non-use
		local remove
		local oldest = 9999999999999
		for token,session in pairs(sessions[authuser.id]) do
			-- TODO: if large, cleaning up sessions could be delegated to a task
			if (session.expire and session.expire < now) then
				-- remove expired session
				remove = true
				break
			elseif (session.expire ==false and session.active +15552000 < now) then -- TODO: should be configurable
				-- remove expired long-validity session when unused for 6 months
				remove = true
				break
			elseif not session.managed and session.expire ==nil and session.active < now -(time.day*7) and session.active < oldest then
				-- remove least recently used session, but ignore sessions used in last week
				remove = true
				oldest = session.active
			end
			if remove then
				DeleteUserSessionEvent(nil,authuser,token)
				break
			end
		end
		session = {ip=query.ip, created=now, last=0, active=now, visits=1, agent=query.agent} -- the new session template
		log.Info("Adding session: "..digits(query.token))
		save("sessions["..digits(authuser.id).."]["..digits(query.token).."]", session)
		-- TODO: store common IP locations and warn if new
		-- update the indexes for the new token
		NewUserSessionEvent(authuser,query.token,session)
	else
		-- reusing an existing session (cookie is not deleted upon signout)
		log.Info("Reusing session: "..digits(query.token))
		session = sessions[authuser.id][query.token]
		session.expire = nil -- set when signing out
		if session.last > (authuser.last or 0) then
			authuser.last = session.last
			persist("users["..digits(authuser.id).."].last",authuser.last)
		end
		session.active = now
		session.lastip = session.ip -- we can compare request.client.ip and user.session.ip to see changes during a session, as this only gets persisted with session updates
		session.ip = query.ip
		session.visits = (session.visits or 0)+1
		save("sessions["..digits(authuser.id).."]["..digits(query.token).."]", session)
		-- update the indexes for the reactivated token
		AuthUserSessionEvent(authuser,query.token,session)
	end
	if authuser.session_attempts then -- TODO: this should be propogated to a homepage or notification and retain details of the client attempting the failed login, and only then be removed
		authuser.session_attempts = nil
		persist("users["..digits(authuser.id).."].session_attempts",nil) -- just in case it got persisted at some point
	end
	return GetSession(query.tenant,authuser,session)
end

function CheckSession(tenant, token, ip)
	local authuser = sessions_user[token]
	if not authuser then return "invalid" end
	-- the following required values may not have been defined yet
	local session = sessions[authuser.id][token]
	if session.expire and session.active < (now - time.minute*25) then
		return "expired"
	elseif session.active < now-21600 then
		-- new visit (over 6h since last)
		session.new = true -- flag to extend token expiry in scribe
		session.last = session.active
		persist("sessions["..digits(authuser.id).."]["..digits(token).."].last",session.last)
		if session.last > (authuser.last or 0) then
			authuser.last = session.last
			persist("users["..digits(authuser.id).."].last",authuser.last)
		end
		session.visits = (session.visits or 0)+1
		persist("sessions["..digits(authuser.id).."]["..digits(token).."].visits",session.visits)
		session.ip = ip
		persist("sessions["..digits(authuser.id).."]["..digits(token).."].ip",session.ip)
		persist("sessions["..digits(authuser.id).."]["..digits(token).."].active",now) -- we save this only with new visits so that last active is more reliable after a db restart
	end
	user.active = now
	session.active = now -- we don't persist this as in apps we only need last active
	-- TODO: when supporting multiple sessions, check the ip/browser profile and store if different (use an array of ips and timestamps per cookie); should be trimmed to a max number
	return GetSession(tenant,authuser,session)
end

function EndSession(token,delete)
	local authuser = sessions_user[token]
	if authuser then
		if delete then
			DeleteUserSessionEvent(nil,authuser,token)
		else
			-- we may reuse the session in future as the browser cookie is not removed (preserves first use and visits etc.)
			DeauthUserSessionEvent(nil,authuser,token)
			local session = sessions[authuser.id][token]
			session.last = now
			save("sessions["..digits(authuser.id).."]["..digits(token).."].last", session.last)
			session.expire = now+(time.day*14) -- when we'll remove its record if not reused
			save("sessions["..digits(authuser.id).."]["..digits(token).."].expire", session.expire) -- we'll keep a record of this session for 14 days
			session.active = nil -- prevents re-activation
			save("sessions["..digits(authuser.id).."]["..digits(token).."].active", session.active)
			log.Info"Session ended"
		end
		return true
	end
end

function UserAccount(userid)
	-- used by generic/account to display keychains with an identifying domain/urn (instead of tenant id)
	local person = users[userid]
	if not person then return end
	person = util.TablePieces(person,userAccountPieces)
	local keychain = {}
	for site,keys in pairs(person.keychains or {}) do
		keychain[site]={ keys=keys, }
		if tenants and tenants[site] and tenants[site].site then
			-- a virtual site
			keychain[site].name = tenants[site].site.name
			if tenants[site] then -- support for tenant app where tenant ID must not be revealed and should be replaced by one of:
				if tenants[site].site.domains then -- custom domains
					keychain[site].domain = tenants[site].site.domains[1].name
				elseif node.tenant.subdomain then -- default subdomain
					keychain[site].domain = tenants[site].site.urn.."."..node.tenant.subdomain
				end
			-- else consumer can display the site id (usually default site.domain)
			end
		else -- a folder, which the db doesn't know about
			keychain[site].name = site
		end
	end
	return person
end

function KeychainLocksFilter(_,item,criteria)
	-- a filter match handler, accepts keychain attribute in criteria with user id, and only matches if the item has no locks or a lock matching a key
	if not item.locks or ( users[criteria.keychain].keychains[criteria.tenant] and util.AnyKeysExist(item.locks, users[criteria.keychain].keychains[criteria.tenant]) ) then return item end
end
