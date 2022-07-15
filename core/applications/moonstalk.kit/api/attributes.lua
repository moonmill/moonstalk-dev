if not page.paths[3] or empty(form) then write [[{"error":true,"message":"Missing parameters"}]] return end

local methods = {}
methods["localegeohash"] = function ()
	if not locales[request.form.locale] then return {error=true,message="Unknown locale"} end
	return {value=locales[request.form.locale].geohash}
end

if methods[page.paths[3]] then
	write(json.encode( methods[page.paths[3]]() ))
else
	write [[{"error":true,"message":"Unknown method"}]]
end
page.type = "json"
