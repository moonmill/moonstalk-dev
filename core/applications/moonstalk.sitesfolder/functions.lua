-- Moonstalk Sitesfolder
-- This application loads bundles from the sites folder as sites

function Gather(path)
	local sites = moonstalk.GetBundles(path)
	for _,site in ipairs(sites) do
		copy(scribe.default_site, site, false, true)
		moonstalk.ReadBundle(site)
		site.domain = site.domain or site.id -- name may get replaced by settings but is the default domain from the folder name
	end
	return sites
end

function Sites(path)
	-- normalise each site
	local sites = sitesfolder.Gather("sites")
	-- we also support sites in app bundles
	for _,application in pairs(moonstalk.applications) do
		if application.files["sites/"] then append(sitesfolder.Gather(application.path.."/sites"), sites) end
	end
	return sites
end
