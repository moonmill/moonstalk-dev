-- sets a specified language in client.preferences, and if the referring page has a translated version, redirects to that, else the homepage
-- translated pages are site.addresses.translated[origin_address] = address_table
-- addresses that have translations have the table address.translated which contains a mapping for a traget language to a target_address
-- in the case of each address having a seperate language but a shared view these mappings are created automatically, also for view.lang.html, and a single view with a vocabulary though in this last case the mappings are redundant as site.addresses.translated[target_language] = "from_address" because the address is identical
-- obviously it's required that any translated page is associated with a translated address as well, even if the same, so that we can simply swap amongst them

page.headers['x-robots-tag'] = "none"
local language = request.query.language
if not vocabulary[language] then return end
request.client.preferences = request.client.preferences or {}
request.client.preferences.language = language
scribe.Cookie{name="preferences", value=json.encode(request.client.preferences), expires=now+time.year}

local address,query
if not language then
	-- we only set some other preference that does not change the url, such as timezone -- TODO: locale should have option to change address e.g. eu-fr ca-fr fr-fr
	return scribe.Redirect(request.headers.referer) -- return to the initiating page
elseif request.headers.referer then
	address,query = util.NormaliseUri(string.match(request.headers.referer, "//.-/([^?]+)(.*)"),{"/"}) -- we use the referrer to avoid polluting and adding overhead with the output of the initiating page on every request most of which will not invoke a translation
	local translated_address = site.urns_exact[address]
	if translated_address and translated_address.translated and translated_address.translated[language] then
		address = translated_address.translated[language]
	elseif request.query.fallback then
		address = request.query.fallback
	-- else will return to the original page which must thus have inline translations
	end
end
address = request.scheme.."://"..request.domain.."/"..(address or "")..(query or "")
scribe.Redirect(address)
