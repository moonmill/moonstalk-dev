if request.client.id and page.view =="generic/signin" then
	-- an edge case of having just signed in from the signin address
	scribe.Redirect ( request.query_string or "/my/account" )
elseif request.form.id then
	request.form.email = request.form.id
	page.focusfield = "password"
elseif page.data.error =="invalid" then
	page.focusfield = "password"
	request.form.password = nil
elseif request.form.email and not request.form.password then
	page.focusfield = "password"
else
	page.focusfield = "email"
end
