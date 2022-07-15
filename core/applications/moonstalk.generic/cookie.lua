-- this view simply takes a list of name value pairs presented as a query string and sets corresponding cookies with the an expiry of two months; /cookie?cookiename=cookievalue
-- you may optionally pass a redirect parameter, otherwise redirection is to the referrer or root; /cookie?cookiename=cookievalue&redirect=newView
-- TODO: only accept encrypted params to prevent possibly malicious attempts to set/overwrite cookies
page.nocache = true
for name,value in pairs(form) do
	if name~="redirect" and type(value)=="string" then scribe.Cookie{name=name,value=string.sub(value,1,60),expires=request.time+5184000} end
end
if request.form.redirect then
	 scribe.Redirect(request.form.redirect)
elseif request.referrer then
	scribe.Redirect(request.referrer)
else
	scribe.Redirect("http://"..request.domain.."/")
end
-- TODO: this is broken in Safari as it does not revalidate the destination page, therefore we must instead use an action that can be applied to any page via a GET param; OR if safari use jquery to add onclick to template that sets cookie then reloads?