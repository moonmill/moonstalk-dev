if request.form.action.UpdateUser then
	-- we assume that any signed-in user is authorised to update their record (any user with just a sign-in ID, such as email or mobile, is capable of being signed-in, as they reset/generate their own credentials)
	-- WARNING: accepting password changes without validating the prior password allows a signed-in account to be hijacked by anyone whether with access to the physical device, or the ability to capture the authentication token; however requring password validation or reset by email also requires implementation of validation for primary email address changes, which introduces support overhead for users whom no longer have access to their primary account; improving the security for user accounts is therefore left as an exercise for implementation in an application that replaces (or disables) this generic interface per its own policies
	local record = teller.FetchRecord("users"..varkey(user.id))
	if request.form.email and (not record.emails[1] or (record.emails[1] and request.form.email~=record.emails[1].address)) then
		if lookup("emails_user"..varkey(request.form.email)) then
			page.data.email = L.idused
		else
			record.emails[1] = {address=request.form.email,created=now}
		end
	end
	if request.form.telephone and (not record.telephones[1] or (record.telephones[1] and request.form.telephone~=record.telephones[1].number)) then
		if lookup("telephones_user"..varkey(request.form.telephone)) then
			page.data.telephone = L.idused
		else
			record.telephones[1] = {number=request.form.telephone,created=now}
		end
	end
	if request.form.password then
		record.password = generic.Password(request.form.password)
	end
	if request.form.avatar then
		if people.SaveAvatar(request.form.avatar, util.EncodeID(user.id)) then -- TODO: get the size from a node setting
			user.avatar = true
			record.avatar = true
		else
			scribe.Error[[Couldn't process uploaded avatar image]] -- TODO: proper error propagation
			return
		end
	elseif request.form.generate_avatar then
		if people.GenerateDefaultAvatar(util.EncodeID(user.id)) then
			user.avatar = true
			record.avatar = true
		else
			scribe.Error[[Couldn't generate avatar]] -- TODO: proper error propagation
			return
		end
	end
	record.name = request.form.name
	record.nickname = request.form.nickname
	_G.user.name = record.name
	_G.user.nickname = record.nickname

	if locales[request.form.locale] then
		_G.user.locale = request.form.locale
		record.locale = request.form.locale
	end
	if moonstalk.timezones[request.form.timezone] then
		_G.user.timezone = request.form.timezone
		record.timezone = request.form.timezone
	end
	if terms.languages[request.form.language] then
		_G.user.language = request.form.language
		record.language = request.form.language
	end
	moonstalk.Environment(client,site) -- we need to update the environment, this will update client and set locale and vocabularies

	if empty(page.data) then
		record:Save()
		people.NewUserEvent(user.id)
	end
end

temp.user = teller.Run ("generic.UserAccount",user.id)
for _,key in pairs(temp.user.keychains) do
	if key.name == "localhost" then key.name = node.hostname break end
end
-- this does not supported federated accounts, and will only show keychains for the user on the nodes of this cluster

scribe.Extensions ("generic/account")
