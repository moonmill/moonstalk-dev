--[[	Moonstalk MatchDomains
		This application adds support for wildcard domains declared with a single dot prefix to match any sub domain or a string.match pattern; domains = {".example.org"}
		Note that other applications must not assume all domains are valid until after starters have run.
		Must be enabled with node.curators = {"matchdomains", …}
		Declared exact-match domains always take precedence, exceptions to wildcard matches on the same domain are therefore supported (exact matches are performed before curators).
--]]

local domains_patterns = {}

function Starter() -- run per-site after all sites and applications have loaded
	for id,site in pairs(moonstalk.sites) do
		for i,domain in pairs(site.domains) do
			local pattern
			if string.sub(domain.name,1,1)=="*." then
				pattern = string.gsub(domain.name,"%.","%%.")
				pattern = "."..pattern.."$"
			elseif string.find(domain.name,"*",1,true) then
				pattern = string.gsub(domain.name,".","%.")
				pattern = string.gsub(domain.name,"*",".*")
				pattern = domain.name
			end
			if pattern then
				-- add to our curator's index
				domains_patterns[pattern] = site
				-- remove from the moonstalk domains
				moonstalk.domains[domain.name] = nil
			end
		end
	end
	if util.ArrayContains(node.curators,"matchdomains") then
		log.Info(#domains_patterns.." wildcard domains enabled")
	elseif #domains_patterns >0 then
		log.Alert(#domains_patterns.." wildcard domains disabled")
	end
end

local string_match = string.match
local pairs = pairs
function Curator() -- run upon each request if no core API domain matches, and no prior-specified curator has provided a site
	-- OPTIMIZE: if there's lots of domains_patterns, we could instead use a tree lookup after splitting the domain upon its periods
	if domains_patterns then
		for pattern,site in pairs(domains_patterns) do
			if string_match(request.domain,pattern) then
				log.Info("Matched domain for site "..site.id.." with pattern: "..pattern)
				return site
			end
		end
	end
end
