-- # Authentication
-- when valid these return a table, otherwise an error as nil,"type" or false,cluster when the request must be proxied or redirected
--[[ tracking:
		when agent-lang changes on session push high event (definate hijack)
		when ip changes on session push low event (just roaming)
		when ip-country changes on user push medium event (possible unauth login)
		when bad password <3 push low event
		when bad_password =3 push high event
		when bad_password >3 block
--]]
-- TODO: bring in line with fields used by teller version and add the schema

generic.verify_tokens = {} -- ephemeral, not replicated

function generic.SetVerifyToken(address,token,urn)
	-- urn is optional and for internal use
	urn = urn or box.space.urns:get(address)
	if not urn then return nil,'unknown' end
	if urn[db.URN.meta]~=nil and urn[db.URN.meta].merchant then
		-- TODO: if the email belongs to a merchant then find the associated user and send to that
	end
	local existing = generic.verify_tokens[address]
	if existing then
		-- prevent insertion of additional tokens, instead update the existing
		local oldtoken = existing.token
		generic.verify_tokens[oldtoken] = nil
		generic.verify_tokens[token] = generic.verify_tokens[address]
		generic.verify_tokens[address].token = token
		return true
	end
	generic.verify_tokens[token] = {token=token, created=os.time(), urn=address, user=urn[db.URN.owner]}
	generic.verify_tokens[address] = generic.verify_tokens[token]
	return true
end

function generic.Verify(query)
	-- multipurpose, used both to verify new addresses, and to peform token-based signins
	local verify = generic.verify_tokens[query.verify]
	if not verify or verify.created <(os.time()-345600) then return nil,'expired' end -- valid for 4 days only
	generic.verify_tokens[query.verify] = nil
	generic.verify_tokens[verify.urn] = nil
	local user = box.space.users:get(verify.user)
	if not user then return nil,'unassociated' end
	local user_updates = {}
	local verification -- remains nil for signins on verified addresses
	local contact = user[db.USER.contact]
	for i=1,#contact.email,3 do
		if contact.email[i] ==verify.urn and (contact.email[i+1] %2) ==0 then -- only even numbers are unverified
			verification =i -- only gets set for new unverified addresses (state==nil)
			-- change state to verified preserving the enabled state
			if contact.email[i+1] ==0 then contact.email[i+1] =1 -- unverified not enabled
			elseif contact.email[i+1] ==2 then contact.email[i+1] =3  end
			break
		end
	end
	-- TODO: validate/handle the cases where an account is hijacked, can the original user still request a signin using the old address?
	if verification then
		table.insert(user_updates,{"=",db.USER.contact,contact})
		-- we decrement for any unverified address because the unverified count was nontheless increased --TODO: all new emails must flag the unverified key, and decrement upon deletion if still unverified
		local keychain = user[db.USER.keychain]
		keychain.Unverified.count = keychain.Unverified.count -1
		if keychain.Unverified.count ==0 then keychain.Unverified=nil end -- there may be multiple urns waiting to be verified, but if the only one we can remove the key
		table.insert(user_updates,{"=",db.USER.keychain,keychain})
		-- TODO: mechanism to allow supplemental function calls such as to add data from other tables
	end
	if #user_updates >0 then box.space.users:update(verify.user, user_updates) end
	if query.user ==verify.user then return true end -- same user is already signed-in; we don't have to check the session because authentication has already been done and they were just verifying the address -- TODO: we should also signout the old session if a different user
	query.user = verify.user

	local session = generic.StartSession(query)
	session.verified = verification -- this flag is used to send an email for newly verified addresses
	return session
	-- TODO: save an event with the verification urn and time; in future this will also handle associating new users with a merchant via a verification link
end

function generic.Signin(address)
	-- doe not perform signin, but confirms a signin urn is valid, returning the passwor hash for validation in the scribe, alongside the corresponding user.id which if valid must then be passed to StartSession
	local urn = box.space.urns.index.value:get(address)
	if not urn then return nil,'unknown' end
	local account = box.space.accounts:get(urn[db.URN.owner])
	return {id=account[1], cluster=account[db.ACCOUNT.cluster], hash=account[db.ACCOUNT.password], attempts=account[db.ACCOUNT.attempts]} -- password is the stored bcrypt hash and must be verified in appserver before calling StartSession
end

function generic.StartSession(query)
	-- {user=user-id, id=session-id, type=2, realm=realm, gather={key=n,…}, ip=ip, agent="name"}
	-- session id is only specified if attempting to reuse an existing
	-- user is required thus is passed back from SignIn simply to avoid an extra urn lookup
	-- query.type=2 allows us to set an ephemeral/expiring session, the default is permanent validity; other keys such as query.gather, per CheckSession
	-- MUST be called upon the cluster to which the user is allocated, this is returned to the client during signin, and the session-id specifies to which cluster it is bound
	local user = box.space.users.index.id:get(query.user) -- returned from Signin
	local session
	if query.id then session = box.space.sessions:get(query.id) end  -- whatever the browser last had

	if session and session[2] ==user[1] then
		-- reuse existing signed-out session for same user, i.e. when they signout and back into their own browser
		log.Info"Reusing Session"
		session = box.space.sessions:update(query.id,{{"=",db.SESSION.type,1},})
		return generic.CheckSession(query,user,session)
	end
	-- generate a new ID for use by the scribe, either because it's an entirely new session (the browser had no prior token), else an existing for which the user has now changed, thus we must preserve the existing session because it's from a different user, whilst generating a new one for the new user, which applies only when a public/shared computer is used and different users signin using the same browser
	log.Info"New Session"
	_G.now = os.time() -- HACK: required for CreateID
	query.id = util.CreateID()
	session = box.space.sessions:insert(db.session{id=query.id, user=query.user, type=query.type or 1, created=os.time(), active=0, last=0, realm=query.realm, agent=query.agent, visits=1, ip=query.ip}) -- active is set as 0 so that it gets flagged as new by CheckSession which will also then set active as now; ideally we would not need to create then immediately update but this should be an infrequent event
	return generic.CheckSession(query,user,session)
end

do
local type = type
function generic.CheckSession(query,user,session)
	-- authenticates a session and returns the normalised user; valid only with sessions whose delegate is a user
	-- session is an optional internal parameter
	-- MUST be called on the cluster to which the user is allocated
	-- query.gather specifies what is to be returned from the user record either as string naming a table from fieldsets or an array of field names
	-- OPTIMIZE: in future we can tie the user to a specific node and cache the user-session in the appserver, syncing activity back to the db only occasionally rather than with every request, however currently we have a limited variety of journeys so each user doesn't generate enough hits during a session for this to be worthwhile
	-- TODO: allow passing fieldset names, e.g. request requires a pile (meta) not required elsewhere
	session = session or box.space.sessions.index.id:get(query.id)
	if not session or session[3]==0 then return nil,'unavailable'
	elseif query.realm and query.realm ~= session[6] then return nil,'notauthorised' end -- OPTIMIZE: we should track invalid realms and potentially greylist
	user = user or box.space.users:get(session[2])
	local session_new
	local session_updates,user_updates = {{"=", 4, os.time()}},{{"=", 4, os.time()}} -- active now
	if session[3]==2 and session[4] < (os.time() - 60*25) then -- ephemeral session expiry
		return nil,'expired'
	elseif session[4] < os.time()-21600 then
		log.Info("new visit")
		-- new visit (over 6h since last)
		session_new = true -- lets the scribe know to extend the cookie expiry
		table.insert(session_updates, {"=", 5, session[4]}) -- last becomes the prior active value before we update active to now
		if session[5] > user[5] then table.insert(user_updates, {"=", 5, session[4]}) end
		table.insert(session_updates, {"=", 8, session[8] +1}) -- visits
		table.insert(user_updates, {"=", 9, user[9] +1})
	end
	if query.ip and query.ip ~= session[9] then
		-- TODO: push a notification to the user on other sessions and flag for security check
		table.insert(session_updates, {"=", 9, query.ip}) -- we record only the last ip here as all others are record in events
	end

	box.space.sessions:update(query.id, session_updates) -- we don't do an assignment as the normalised user should include prior values
	box.space.users:update(user[1], user_updates)

	-- normalise the user table
	local normalised = {
		keychain = user[2],
		user = {id=user[1], active=user[4], last=user[5], nick=user[11] or user[10], cache=user[3], language=user[6], locale=user[7], timezone=user[8], visits=user[9], contact=user[14]}, -- WARNING: for efficiency these are set from their hardcoded field positions and do not use enum lookups
		session = {id=session[1], active=session[4], last=session[5], new=session_new},
	}
	if query.gather then copy(db.user(user,field_sets[query.gather] or query.gather), normalised) end

	-- TODO: mechanism for supplemental functions calls to aggregarate data

	return normalised
end
end

function generic.Signout(query)
	-- flags as inactive; we don't actually remove sessions until they're old to allow introspection such as on hijacked accounts
	-- we assume the client is addressing the correct cluster
	-- TODO: this should really also log changes of ip or agent same as checksession
	local session = box.space.sessions.index.id:get(query.id)
	if not session or (query.realm and query.realm ~= session[db.SESSION.realm]) then return end -- fail if not found, invalid or non-matching realm
	box.space.sessions:update(query.id, {{"=", db.SESSION.type, 0}, {"=", db.SESSION.active, os.time()}}) -- set signed out, and active to now
	return true
end
