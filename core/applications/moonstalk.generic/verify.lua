if request.query then

if string.find(request.query,"@") then

	-- an email address in query string (to avoid static content match)
	-- TODO: use captcha/human test
	-- TODO: handle SMS
	local verify = util.CreateID()
	local session = generic.VerifyUser{ email=string.lower(request.query), verify=verify }
	if not session then
		page.data.unknown = true
	else
		local result,err = generic.Email{to=request.query, subject= macro{l.verify_subject, service=(site.name or site.domain)}, body= macro{l.verify_message, domain=(domain or site.domain), session=util.EncodeID(verify), }} -- TODO: use =task with ajax status (avoid blocking scribe whilst sending the email)
		if not result then log.Info(err) end
		-- TODO: notify the default address as well as requested
		return
	end

else

	-- a signin token
	-- this replicates functions/actions.Signin but for use with a verification token
	-- accepts an optional urn to redirect to in the form, /signin/redirectUrn/?token

	scribe.Token() -- ensure we have a session id for the new signin
	local verify = util.DecodeID(request.query)
	if not verify then scribe.Error "Verification failure" return end
	local session = generic.VerifyUser {verify=verify, token=request.client.id, ip=request.client.ip, agent=scribe.Agent().string, tenant=site.id}
	if type(session) ~="table" then scribe.Error {title="Invalid verification",detail=l.verifyfailure} return end
	generic.SetSession(session,request.client.id) -- doesn't populate client with the user, but we don't need it here because we redirect
	if not action.VerifyUser or not action.VerifyUser() then -- not extended by another applications
		if request.client.keychain.Permit and request.client.keychain.Permit.createsite then -- TODO: shift this to a SaaS application and assign it in the VerifyUser function
			scribe.Redirect ("/"..L.setup)
		elseif page.paths[2] then
			scribe.Redirect (page.paths[2])
		else
			scribe.Redirect "/my/account"
		end
	end
	return
	
end

end

scribe.Redirect (L.signinurn)
