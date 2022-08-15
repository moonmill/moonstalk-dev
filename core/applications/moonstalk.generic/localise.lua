-- sets a specified languages in client.preferences, and if the referring page has a translated version, redirects to that, else the homepage
local language = request.query.language
if not vocabulary[language] then return end
request.client.preferences = request.client.preferences or {}
request.client.preferences.language = language
scribe.Cookie{name="preferences", value=json.encode(request.client.preferences), expires=now+time.year}
local address,query
if request.headers.referer then
	address,query = util.NormaliseUri(string.match(request.headers.referer, "//.-/([^?]+)(.*)"),{"/"})
	address = site.urns_exact[address]
	if address and address.vocabulary[language] then
		address = address.vocabulary[language].page_address
	else
		address = "" -- front page
	end
end
address = request.scheme.."://"..request.domain.."/"..(address or "")..(query or "")
scribe.Redirect(address)
