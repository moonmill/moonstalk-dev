-- expects daemon on to be used in the confuguration
-- data/configuration/host.cert and data/configuration/host.key will enable global ssl (all domains)
-- nginx configuration can be overloaded with the following files
-- data/configuration/nginx.conf for directives in the root
-- TODO: data/configuration/nginx-server.conf for directives in the server block
-- expects the readlink command to be available for dev installs if apps are symlinked to a shared install

--[[ TODO: add support for ca certs else http.Request with https requires ssl_verify=false
linux: /etc/ssl/certs/ca-certificates.crt
or curl https://curl.haxx.se/ca/cacert.pem > cacert.pem
and in conf:
lua_ssl_verify_depth 2;
lua_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.pem;
--]]

node.scribe = node.scribe or {}

elevator.servers.openresty	= "openresty"
elevator.servers.nginx 		= "openresty"
elevator.servers.http		= "openresty"
elevator.servers.web		= "openresty"
elevator.servers.pages		= "openresty"
elevator.servers.scribe		= "openresty"
local log_errors = keyed{"emerg","crit","error","alert"}
-- SIGQUIT

-- TODO: support reload/refresh -s HUP
elevator.functions.openresty = function ()
	display.status("OpenResty"," (Web)")
	terminal.save_position()
	if not run.status and not elevator.config.rootuser then
		display.error("Root priveleges required: use sudo")
		return
	elseif not node.scribe.server=="openresty" then
		terminal.red("disabled (using "..node.scribe.server..")")
		return
	end
	local pid = util.FindPID("openresty")
	if run.status then
		if pid then
			terminal.green "running"
		else
			terminal.yellow "not running"
		end
		return
	end
	if run.restart and not pid then
		terminal.yellow "not running"
		return
	end
	if run.stop and not run.restart then
		if pid then
			os.execute("/bin/kill -s QUIT "..pid) -- TODO: cheeck for shutdown
			terminal.green "terminating…"
			if not run.start then
				return
			else
				os.execute("sleep 1")
			end
		elseif not run.start then
			terminal.yellow "not running"
			return
		end
	elseif run.start and not run.stop and not run.restart and pid then
		terminal.yellow "already running"
		return
	end

	-- stop exits above, the following is for start and restart only
	terminal.reset_position(); terminal.output("configuring…")

	-- nginx conf include directives are relative to the specified conf file which we keep in temporary, thus we must unfortunately create a link to the defaults and configuration directories so that include can reference files in them
	-- we need to copy the initial conf to our temporary directory, where we then create a node-specific nginx-node.conf
	if not util.FileExists"temporary/nginx/moonstalk.conf" then -- TODO: use a version check
		local installdir = "core/applications/moonstalk.openresty"
		local installdir = util.Shell("readlink "..installdir) or (moonstalk.root.."/core/applications/moonstalk.openresty") -- nginx will only follow one symlink, thus we must resolve the actual path in case the app is a symlink
		util.Shell("mkdir temporary/nginx")
		util.Shell("ln -s "..installdir.."/defaults "..moonstalk.root.."/temporary/nginx/")
		util.Shell("ln -s "..moonstalk.root.."/data/configuration temporary/nginx/data")
	end

	-- the following only applies to update, start and restart, for which we rewrite the conf file before invocation
	local configs = {[0]="production", [1]="production", [2]="production", [3]="production", [4]="development", [5]="debug"} -- NOTE: not to be confused with node.environment as logging/server/environment profiles can be mixed
	local file,err = io.open("core/applications/moonstalk.openresty/defaults/"..configs[node.logging]..".conf")
	if not file then terminal.reset_position() terminal.red "failed" display.error(err) return end
	local data = file:read("*a"); file:close()
	-- change root directives
	data = string.gsub(data, "worker_processes auto", "worker_processes "..node.scribe.instances)
	local overrides,err = io.open("data/configuration/nginx.conf")
	if overrides then
		data = string.gsub(data, "http {\n", "http {\n"..overrides:read("*a"))
		overrides:close()
	end

	-- prepare the directives to insert into http
	-- we do not use init_worker_by_lua_file because many APIs are not available within it, and the check for initialisation with the request handler (server.lua) is extremely lightweight
	local conf = {"", -- TODO: overrides file for http and servers
	"  resolver "..table.concat(moonstalk.resolvers," ").." ipv6=off;", -- TODO: local=on
	"  include defaults/mime.conf;",
	"  lua_shared_dict moonstalk 64k;",
	"  lua_transform_underscores_in_response_headers off;",
	"  client_body_temp_path temporary/nginx/client-body;",
--	"  fastcgi_temp_path /dev/null;",
	}

	for name,site in pairs(moonstalk.sites) do
		table.insert(conf, "  server {")
		local domains = {}
		for _,domain in ipairs(site.domains) do -- TODO: handle ASCII (Punycode) conversion for internationalised domains
			if string.sub(domain.name,1,1) =="*" then
				table.insert(domains, domain.name) -- already a valid declaration
			elseif not string.find(domain.name,"*",1,true) then -- wildcarded domains do not get declared as will be handled by default_site and caught by the matchdomains curator
				table.insert(domains, domain.name)
			end
		end
		table.insert(conf,"    server_name "..table.concat(domains," ")..";") -- NOTE: we don't declare redirected domains here, their use should be infrequent that handling in Lua is okay, otherwise they should be hardcoded or this should build a seperate server block for them and use nginx redirection directives
		if util.FileExists("/etc/letsencrypt/live/"..site.domain.."/fullchain.pem") then
			table.insert(conf,"    ssl_certificate /etc/letsencrypt/live/"..site.domain.."/fullchain.pem;")
			table.insert(conf,"    ssl_certificate_key /etc/letsencrypt/live/"..site.domain.."/privkey.pem;")
			table.insert(conf,"    listen 443 ssl;")
		elseif util.FileExists(site.path.."/private/ssl/public.pem") then
			table.insert(conf,"    ssl_certificate "..moonstalk.root.."/"..site.path.."/private/ssl/public.pem;")
			table.insert(conf,"    ssl_certificate_key "..moonstalk.root.."/"..site.path.."/private/ssl/private.pem;")
			table.insert(conf,"    listen 443 ssl;")
		end
		table.insert(conf,"    root "..site.path.."/;")
		if site.id ~="localhost" then
			table.insert(conf,"    listen 80;")
		else
			table.insert(conf,"    listen 80 default_server;")
		end
		table.insert(conf, "    include defaults/server.conf;")
		-- insert a custom config, this can take precedence over moonstalk's directives
		-- this conf can be used such as to declare: add_header Content-Security-Policy "default-src 'self'"
		if site.files['private/nginx.conf'] then
			table.insert(conf, "    include ../../"..site.path.."/private/nginx.conf;") -- relative to temporary/nginx
		end
		table.insert(conf, "    location ^~ /.well-known/ {root "..site.path.."/;}") -- slightly more efficient than invoking the file regex
		table.insert(conf, "    location ^~ /public/ {root "..site.path.."/;}") -- slightly more efficient than invoking the file regex
		-- the following is a backwards/end match for a period at position -3 or -4, thus long extensions are NOT matched and would require a dedicated location directive
		-- if these prefix matches do not work, we invoke regexp:
		-- firstly we block all requests ending with .lua to prevent source code beign served
		table.insert(conf, [[    location ~ \.lua$ {return 404;} # disable access to source of controllers, unfortunately has to invoke regex for every (following) non-static request]])
		-- secondly we match files with a 2-5 letter extension (other than Lua which has already been caught)
		table.insert(conf, [[    location ~ "\.\w{2,5}$" {root ]]..site.path..[[/;} # matches all root assets (with extensions) on site domains but invokes regex to do so]])
		-- finally we handle everything else with moonstalk, this is actually a prefix match so it will match every request, but the longest is used is another prefix matches, or if no regex matches this is thus the longest prefix
		-- first call initialises Moonstalk; this is an extremely lightweight check of initialisation to perform with each request without using the only slightly more expensive require mechanism
		table.insert(conf, "    location / {content_by_lua_file "..openresty.path.."/"..ifthen(node.dev,"server-debug.lua","server.lua")..";}")
		-- TODO: check addresses for any with max_file_size and declare seperate locations for them with client_max_body_size 10m and client_body_buffer_size then reduce the defaults for these in server.conf
		table.insert(conf,"  }") -- close server
	end
	table.insert(conf,"}") -- close http as will be replaced by gsub
	file = io.open("temporary/nginx/moonstalk.conf","w+")
	if not file then terminal.reset_position() terminal.red "failed" display.error(err) return end


	local appconf = {}
	for _,bundle in pairs(moonstalk.applications) do
		-- catch requests prefixed with app names
		if bundle.files['public/'] then
			-- only enable for applications with public folders
			table.insert(appconf, [[location ^~ /]]..bundle.file..[[/public/ {alias ]]..bundle.path..[[/public/;}
]])
		end
		if bundle.files['private/nginx-servers.conf'] then
			table.insert(appconf, "include "..bundle.path.."/private/nginx-servers.conf")
		end
		if bundle.files['private/nginx-http.conf'] then
			table.insert(conf, "include "..bundle.path.."/private/nginx-http.conf")
		end
	end

	data = string.gsub(data,"\n}",table.concat(conf,"\n"))
	file:write(data); file:close()

	file,err = io.open("temporary/nginx/applications.conf","w+")
	if not file then terminal.reset_position() terminal.red "failed" display.error(err) return end
	file:write(
		"# the following match assets for applications, efficiently using a prefix match, thus application assets are prefered\n",
		"# all locations prefixed ^~ will not cause regexs to be checked; the longest such match is used otherwise regexs are checked\n",
		table.concat(appconf)
	)
	file:close()

	-- by default errors are sent to stderr, however our configs use the error.log if successfully loaded, nonehteless we must check in case there are any config errors
	-- the following commands reset the log before launch
	terminal.reset_position()
	if run.restart then
		terminal.output("relaunching…")
		file = io.popen("openresty -c temporary/nginx/moonstalk.conf -p . -s reload &>temporary/nginx/error.log")
	elseif run.start then
		terminal.output("launching…")
		file = io.popen("openresty -c temporary/nginx/moonstalk.conf -p . &>temporary/nginx/error.log")
	end
	--[=[  -- FIXME: this only reports the error log on the next run, which isn't helpful
	for line in file:lines() do
		if not string.find(line,"could not open error log",1,true) -- the log error is unimportant as simply an attempt to set the deafult log from the server/default installed configuration which we don't touch
		and not string.find(line,"signal process started",1,true) -- on restart
		then
			table.insert(message,line)
		end
	end --]=]
	file:close()
	terminal.reset_position()
	if (run.start or run.restart) then
		-- success but we check the error log for the worker processes if we're in dev mode
		terminal.output("checking…")
		if run.restart then os.execute"sleep 1" end -- FIXME: repeatedly check the log for shutdown as it could take a while and we only want to send our test request to the restarted server, not the one still shutting down
		local response,err = http.Request{url="http://127.0.0.1/",timeout=3000}
		log.Notice(response)
		if err or (response.status ~=200 and response.status ~=404) then
			terminal.reset_position()
			terminal.red "error"
			if err then
				display.error("Unable to connect to webserver. "..err)
			else
				display.error("Webserver responded with status "..response.status..". Check the server or logs for details.")
			end
			elevator.exit = 1
			return
		end
		os.execute"sleep 1"
		local count = 0
		for line in io.linesbackward("temporary/moonstalk.log") do -- FIXME: not working
			count = count +1
log.Alert(line)
			if count > 100 or string.find(line,"] Initialising",1,true) then break end
			local class = string.match(line,"%[(.)%]")
			if class =='‼︎' then -- alert
				err = string.match(line,"%] (.+)")
				display.error(err, nil,"yellow",true)
			elseif class =='✻' and not string.find(line,"] Started",1,true) then -- priority
				err = string.match(line,"%] (.+)")
				display.error(err, nil,"yellow",true)
			end
		end
		for line in io.lines("temporary/nginx/error.log") do
			local class = string.match(line," %[(.-)%]")
			if class =='warn' then
				err = "openresty: "..( string.match(line,"%] (.+)") or line )
				display.error(err, nil,"yellow",true)
			elseif log_errors[class] then
				err = "openresty: "..( string.match(line,"[Ll]ua .-:(.+)") or string.match(line,"%].-:(.+)",1,true) )
				display.error(err, nil,nil,true)
			end
		end
		terminal.reset_position()
	end
	if not err then
		pid = util.FindPID("nginx")
		if pid then
			if run.restart then
				terminal.green "relaunched"
			else
				terminal.green "launched"
			end
		else
			terminal.red "failed"
		end
	end
end
