if user and page.view =="generic/signin" then
	-- an edge case of having just signed in from the signin address
	scribe.Redirect ( request.query_string or "/my/account" )
elseif request.query.id and page.view =="generic/signin" then
	-- provide a pre-filled signin link
	request.form.email = request.query.id
	page.focusfield = "password"
elseif request.error =="invalid" then
	request.form.password = nil
	page.focusfield = "password"
	page.reminder = true
	page.error_message = l.signin_invalid
elseif request.error =="disabled" then
	request.form.password = nil
	page.reminder = true
	page.error_message = l.signin_disabled
elseif request.error =="unknown" then
	request.form.email = nil
	page.error_message = l.signin_unknown
elseif request.error =="unverified" then
	reminder = true
	page.error_message = l.signin_unverified
elseif request.error ~="signedout" then
	-- signedout gets no special treatment, no other errors should be displayed but are shown in case of development issues
	page.error_message = request.error
elseif request.form.email and not request.form.password then
	page.focusfield = "password"
else
	page.focusfield = "email"
end
