for name,table in ipairs(moonstalk.databases) do
	if table.system =="databin" then
		name = "data/"..name.."luabins"
		if lfs.attributes(name, "mode") ~="file" then
			-- create an empty database, avoiding generating an error in the Starter
			databin.Save(name, luabins.encode({}))
		end
	end
end
