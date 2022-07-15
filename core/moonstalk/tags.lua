--[[	Moonstalk Tag Functions

Provides functionality for building optional tag structures. When assigned values their content is automatically enclosed within the desired tag, and repeated if necessary.

A tag structure (proxy table) must be delcared using : tags "html" or html = tags()
This table then handles any abritrary index (path) to set the values of the tags at that index.
Retrieval of the correctly formatted tag is supported only through the merge function.
Any depth of the structure can be retrieved, it could thus be used to build an entire html document, however this is not recommended as its performance is not ideal and sue is best restricted to optional content.

		Copyright 2010, Jacob Jay.
		Free software, under the Artistic Licence 2.0.
		http://moonstalk.org
--]]

tags = tags or {}
tagvals = {}

local function getTag (container,tag)
print ("gettag",tag)
	local content = rawget(container[tag],"content")
	if content then
		if rawget(container[tag],"seperate") then
			for i=1,#content-1 do
				table.insert(content,i*2,rawget(container[tag],"seperate"))
			end
		end
		if container[tag].open then table.insert(content,1,container[tag].open) end
		if container[tag].close then table.insert(content,#content,container[tag].close) end
		return table.concat(content)
	else
		return ""
	end
end
local function setTag (container,tag,value)
print ("settag",tag)
	if type(value) == "table" then
		-- define or replace the tag
		rawset(container,tag,value)
	else
		-- tag exists so we'll update its value
		local content = container[tag].content
		if not value or not content then container[tag].content = {} end
		if value then
			table.insert(content,value)
		else
			container[tag] = nil
		end
	end
end
local function getContainer (_,container)
print ("getcont",container)
	if type(tags[container]) == "table" then
		local output = {}
		for tag in pairs(tags[container]) do
			table.insert(output,tags[container][tag])
		end
		return table.concat(output)
	else
		return ""
	end
end
local function defineContainer (_,container,newtags)
print ("defcont",container)
	if not rawget(tags,container) then
		rawset(tags,container,{})
		-- add metamethod for setting and getting the correctly formatted tag contents
		setmetatable(tags[container], metaContainer) -- NOTE: we don't support concat
	end
	for tag,value in pairs(newtags) do
		tags[container][tag]=value
	end
end
local metaTag = {__newindex=setTag,__index=getTag}
local metaContainer = {__newindex=defineContainer,__call=getContainer}

setmetatable(tags,metaTag)

function tags(object)
	-- defines a table as of the 'tags' 'class'
	-- usage: tags "wibble" or wibble = tags()
	object = proxy(object)
	changemetatable(object,{_tags=true})
	return object
end


merge "html.head"

contents=string or table for tag with children
meta = table, an array to be concatenated as value and a map with behaviours for automatic open/close/seperate/repeat tags


tags "html" -- automaticlly provided

html.body = {onload="", bgcolor="", contents={script={contents={}}}} -- set attributes for body
html.body = {} -- declares a tag with children
html.body.script = "" -- declares an empty tag (children cannot be set as value is string)
html.body.script.open = '<script>' -- the default



--[[
-- a site or application may define its own tags in a controller
tags.head = {
	script		={open='	<script type="text/javascript">\n',seperate="\n",close='\n</script>'},
	style		={open='	<style type="text/css" media="all">\n',seperate="\n",close='\n</style>'},
	canonical	={open='	<link rel="canonical" href="',close='</link>'},
	description	={open='	<style type="text/css" media="all">\n',close=' />'},
}
tags.body = {
	script={type="append", open='	<meta name="description" content="',close='\n</script>'},
}
--]]
