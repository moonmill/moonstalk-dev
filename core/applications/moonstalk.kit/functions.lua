-- Moonstalk Kit
-- Provides useful functions and procedures in the form of an optional application
-- To enable use: applications = {"kit"} in settings
-- NOTE: Static pages are also processed by editors, adding a slight overhead, reducing capcity by up to 15% (i.e. from 2800rps to 2400rps), but with negligable additional overhead on dynamic pages

local table_insert = table.insert
local util_TablePath = util.TablePath
local string_match = string.match
local string_gmatch = string.gmatch
local string_find = string.find
local string_sub = string.sub
local string_gsub = string.gsub
local table_concat = table.concat
local ipairs = ipairs

_G.captcha = _G.captcha or {} -- namespace

function captcha.Generate()
	local operator
	local base = 10
	if math.random(2) == 1 then operator = '+' else operator = '−' end
	local number = math.random(10)
	local salt = math.random(10000) -- we add this to the number to ensure the encrypted string appears random
	write(L.captcha_question.." ")
	write(base.." "..operator.." "..number.. " = ")
	tag.input({name="captcha", size=4, id="captcha" })
	write([[<input type="hidden" name="_captchaop" value="]])
	local token_op = util.Encrypt (operator)
	write(token_op)
	write([["/><input type="hidden" name="_captchanum" value="]])
	local token_num = util.Encrypt (number + salt)
	write(token_num)
	write([["/><input type="hidden" name="_captchasalt" value="]])
	write(salt)
	write([["/>]])
end

function captcha.Validate(captcha)
	local operator = util.Decrypt(request.form._captchaop)
	local number = util.Decrypt(request.form._captchanum) - request.form._captchasalt -- math to subtract the random salt coercises it to a number
	local result
	if operator == '+' then result = 10 + number else result = 10 - number end

	if tonumber(request.form[captcha or 'captcha']) == result then -- form input is a string, must be a number to compare with result number
 			return true
	else
		_G.page.data[captcha or 'captcha'] = L.this_is_wrong
	end
end

_G.tag = _G.tag or {} -- namespace
-- when using tag.* functions with a concordance always specify the value as the concordance value
-- name="wibble" concordance.wibble and request.form.wibble are all considered associated values; therefore no root key amongst these should be the same if the values are unassociated
-- NOTE: concordance will not save 0-indexed form values (i.e. input name="field.0")

function TableItems(attributes)
--[[

Outputs the items of a named concordance or table, for display in a view, prepared for add/remove/reorder functionality using jQuery, and returns the submitted tables in the request.form. Submitted changes to these tables from a form is intended for use with concordances only, other use may require specific additional manipulation of the form values, specifically additions in hashmaps (to support assignments of key). Use with a concordance merges values with an existing record thus enabling the output into a view of only the values to be changed.

CALL:
TableItems{items=table,item=function}; items is a table to be iterated or the name of a concordance table, and item is a function that outputs an HTML container (e.g. <LI>) for each item; additional attributes as shown below

VIEW:
<? local function items(index,item) ?>
	<li class="item">
		<label>Item ?(index)</label><? tag.input{name="record.array."..index..".key"} ?>
	</li>
<? end kit.TableItems{…} ?>

ATTRIBUTES:
	hashmap = true, must be specified if the table is not an array but a hashmap -- WARNING: failure to specify this will result in corrupt data
	name = the id of the list, or if items is unspecified, the name of a concordance field which contains the items
	add = false to disable new items -- TODO: specify maximum number
	remove = false to disable removing items
	reorder = false to disable reordering items
	class any custom classes for the OL
	items = a table of items
	item = function to write HTML for each item instead of the default (which only handles an array of strings)
	template = HTML for adding new items if not handled by the item handler function; for use with hashmaps, this must have an input present with name="key" and a value representing the key-name for that item in the hashmap
--]]
-- TODO: support adding with hashmaps
	if not attributes.items then
		local namespace = string_match(attributes.name or "", "([^%[%.]*)")
		if namespace and temp.concordances and temp.concordances[namespace] then
			attributes.items = util_TablePath(temp.concordances, attributes.name)
			attributes.concordance = true
			if not attributes.hashmap then write [[<input type="hidden" name="]] write(attributes.name) write[[._array" value="1"/>]] end -- this is required to ensure concordance compatibility by forcing an item 0 to be present
		end
	end
	attributes.name = attributes.name or "table"
	attributes.cssid = string.gsub(attributes.name,"%.","_")
	local iterator = pairs
	if not attributes.hashmap then
		write [[<ol id="]]
		iterator = ipairs
	else
		if attributes.add ~=false and not attributes.template then scribe.Error"TableItems requires template to add items to a hashmap." end
		write [[<ul id="]]
	end
	write(attributes.cssid) write[[" class="items]]
	if attributes.class then write" " write(attributes.class) end
	if not attributes.hashmap then
		write " array"
		if attributes.reorder ~=false then write" sortable" end
	end
	if attributes.add ~=false then write" add" end
	if attributes.remove ~=false then write" remove"; _G.page.javascript.removeTitle = L.removeitem end
	write[[">]]
	if not attributes.item then
		local item_handler
		if not attributes.hashmap then
			item_handler = function (index,item) write[[<li class="item">]] tag.input{name=attributes.name.."."..index} write[[</li>]] end
		else
			item_handler = function (index,item) write[[<li class="item">]] write(L.index) write" " tag.input{name=attributes.name..".index"} write[[</li>]] end
		end
		attributes.item = item_handler
	end
	for index,item in iterator(attributes.items or {}) do
		scribe.Cut()
		attributes.item(index,item)
		if not attributes.hashmap and attributes.concordance and type(item) =="table" then
			write( string.gsub(scribe.Paste(), ">", table.concat({[[><input type="hidden" name="]],attributes.name,".",index,"._origin",[[" value="]],index,[["/>]]}), 1) )
		else
			write(scribe.Paste())
		end
	end
	if attributes.template then write(attributes.template) elseif attributes.add ~=false then
		scribe.Cut()
		attributes.item(0,{})
		write( string.gsub(scribe.Paste(), "<li", [[<li style="display:none" id="template" class="component" ]], 1) )
	end
	if attributes.add ==false then
		-- we output a 'none' item that should be shown if there are no items
		write[[<li id="none" class="component"]]
		if #attributes.items >0 then write[[ style="display:none"]] end
		write[[><i>]] write(L.noitems) write[[</i></li>]]
	end
	if attributes.add ~=false then
		write[[<li id="add" class="component"><a onclick="moonstalk_Kit.addFormTableItem('#]] write(attributes.cssid) write[[')" title="]] write(L.additem) write[[">]] write(L[attributes.add or "additem"]) write[[</a></li>]] -- TODO: javascript to put insertion point in first text input
	end
	if not attributes.hashmap then write [[</ol>]] else write [[</ul>]] end
	kit.Script ("/moonstalk.kit/jquery.js","/moonstalk.kit/jquery-ui.js","/moonstalk.kit/kit.js","moonstalk_Kit.enableFormTable('#"..attributes.cssid.."')")
end
function FileItems(attributes)
	-- similar to TableItems, but for an array of files; takes additional attributes:
	-- preview = "_m.jpg" to enable image preview using the designated suffix to construct a URL with item.file
	-- title = true to display title field
	-- uploaded data is in a request.form.uploads[name] array as it must be processed before references to it are subsequently combined with existing data
	if not attributes.items then
		local namespace = string_match(attributes.name or "", "([^%[%.]*)")
		if namespace and temp.concordances and temp.concordances[namespace] then
			attributes.items = util_TablePath(temp.concordances, attributes.name)
			attributes.concordance = true
			write [[<input type="hidden" name="]] write(attributes.name) write[[._array" value="1"/>]] -- this is required to ensure concordance compatibility by forcing an item 0 to be present
		end
	end
	attributes.name = attributes.name or "files"
	attributes.cssid = string.gsub(attributes.name,"%.","_")
	write [[<ol id="]] write(attributes.cssid) write[[" class="files array]]
			if attributes.class then write" " write(attributes.class) end
			if attributes.reorder ~=false then write" sortable" end
			if attributes.add ~=false then write" add" end
			if attributes.remove ~=false then write" remove"; _G.page.javascript.removeTitle = L.removeitem end
		write[[">]]
	attributes.accept = attributes.accept or "image/*"
	attributes.li = attributes.li or function(index,item)
		write[[<li class="item array">]]
		if attributes.preview then write[[<div id="preview"><img src="/tenants/]] write(site.token) write[[/media/]] write(item.token) write(attributes.preview or ".jpg") write[[" id="preview"/></div>]] end
		write[[<div id="options">]]
		if attributes.title then write[[<input type="text" name="]] write(attributes.name) write"." write(index) write[[.title" value="]] write(item.title) write[["/>]]
		end
		if index ==0 then write[[<input name="]] write(attributes.name) write"." write(index) write[[.upload" type="file" accept="]] write(attributes.accept) write[[" class="add" style="display:none"/>]] end
		write[[</div></li>]]
	end
	for index,item in ipairs(attributes.items or {}) do
		scribe.Cut()
		attributes.li(index,item)
		if attributes.concordance and type(item) =="table" then
			write( string.gsub(scribe.Paste(), ">", table.concat({[[><input type="hidden" name="]],attributes.name,".",index,"._origin",[[" value="]],index,[["/>]]}), 1) )
		else
			write(scribe.Paste())
		end
	end
	if attributes.template then write(attributes.template) elseif attributes.add ~=false then
		scribe.Cut()
		attributes.li(0,{})
		write( string.gsub(scribe.Paste(), "<li", [[<li style="display:none" id="template" class="component" ]], 1) )
		-- TODO: insert the delete a tag to the template!
	end
	if attributes.add ~=false then write [[<li id="add" class="component">]] write(L[attributes.add or "additem"]) write[[:<br><input name="]] write(attributes.name) write[[.0.upload" type="file" onchange="newFileItem(event)"/></li>]] end
	write [[</ol>]]
	kit.Script ("/moonstalk.kit/jquery.js","/moonstalk.kit/jquery-ui.js","/moonstalk.kit/kit.js","moonstalk_Kit.enableFormTable('#"..attributes.cssid.."')")
end

function ConvertImage(file,variants)
	-- file is a file object from form.files, else {file=path, name=name}
	-- variants is an array of command strings, each of which represents a variant to be generated and saved, as a shell command; the command string should includes macros for ?(original) which is the full path of a file and ?(variant) as a path suffix of the file to be saved (which following this macro should be suffixed with a unique identifier to distinguish each from the other saved variants)
	-- variants.prefix = "path" added to the modified path for saved filed; is relative within the moonstalk folder e.g. "applications/name/public/"; defaults to site/public/images
	-- on success returns the file object with file.id and file.token if not disabled
	-- variants.tokens = false to disable creating a file.token at the end of the modified path, instead file.name will be used (not advisable with uploads)
	local info,err = util.Shell(sys.prefix..[[gm identify -format "%m %w %h" ]]..file.file)
	if not info or string.sub(info,1,12)=="gm identify:" then return nil,"Unknown format "..(err or info) end
	log.Debug("Processing "..info)
	file.width,file.height = string.match(info,".+ (%d+) (%d+)")

	-- save variants
	variants = variants or { -- by default we create a medium version at reasonable quality, and a smaller square cropped version which is compressed and intended for a smaller display size (e.g. 160), such that its resolution better utilises high density screens
		[[gm convert ?(original) -resize 1200^ -colorspace rgb +profile '*' -unsharp 1.0X0.7+0.8+0.01 -quality 80% ?(variant)_m.jpg]],
		[[gm convert ?(original) -resize 320^ -gravity center -extent 320x320 -colorspace rgb +profile '*' -unsharp 1.0X0.7+0.8+0.01 -quality 55% ?(variant)_s.jpg]],
	}
	if variants.tokens ~=false then file.id = file.id or util.CreateID(); file.token = file.token or util.EncodeID(file.id) end
	if not variants.prefix then variants.prefix = site.path.."public/images/"..(file.token or file.name) end
	local result,err
	for i,command in ipairs(variants) do
		command = string.gsub(command, "%?%((%w+)%)", {original=file.file, variant=variants.prefix})
		result,err = util.Shell(sys.prefix..command)
		if err then log.Notice("Command "..i.." failed : "..err) return nil,err end
		log.Info(result)
	end
	-- TODO: store combined files sizes (i.e. disk usage)
	return file
end

function DeleteTemporaryFile(name)
	-- WARNING: this removes all variant files whose name starts with the name
	-- NOTE: does not check if any matching items exist
	if not tenant_token or not name then return nil,"Invalid RemoveFile parameters" end
	if type(name)=="number" then name = util.EncodeID(name) end -- will only work if the same node secret is being used
	if directory then name = directory.."/"..name end
	os.execute("rm -f public/tenants/"..tenant_token.."/"..name.."*")
	log.Info("Deleted files "..name.."* from tenant "..tenant_token)
end

function DeleteFiles(tenant_token,name,directory)
	-- WARNING: this removes all variant files whose name starts with the name
	-- NOTE: does not check if any matching items exist
	if not tenant_token or not name then return nil,"Invalid RemoveFile parameters" end
	if type(name)=="number" then name = util.EncodeID(name) end -- will only work if the same node secret is being used
	if directory then name = directory.."/"..name end
	os.execute("rm -f public/tenants/"..tenant_token.."/"..name.."*")
	log.Info("Deleted files "..name.."* from tenant "..tenant_token)
end

function ArrayUploads(name,directory)
	-- handles changes in a FileItems or MediaItems array to save its uploads, update the corresponding items with an id and token, and delete the files of items that have bene removed; returns a table of new uploads that may be iterated
	-- should only be called after a concordance :Finalise()
	-- directory is an optional tenant subdirectory by which files may be grouped (e.g. media)
	-- returns an array of new files, to be processed/moved/removed; each file items has a temporary key that should be removed once processed, along with the file; files are typically preserved in data/tenants/[directory/]token[_variant][.extension] thus their path need not be stored, and is instead generated on demand

	if directory then
		local result,err = util.Shell("mkdir -p data/tenants/"..site.token.."/"..directory)
		if err then log.Alert(err) return nil,err end
	end
	local record
	local concordance = string_match(name or "", "([^%[%.]*)")
	if concordance and temp.concordances and temp.concordances[concordance] then
		record = temp.concordances[concordance]
		name = string.match(name, ".*%.(.*)") -- trim off the concordance name
	else
		scribe.Error"Invalid concordance name"
		return
	end
	local files = util.TablePath(record, name)
	local new = {}
	local existing = {}
	for index,file in ipairs(files or {}) do
		if file.upload then
			file.name = file.upload.name
			file.id = util.CreateID()
			file.created = now
			file.size = file.upload.size
			file.token = util.EncodeID(file.id)
			log.Info("Saving upload "..file.name.." with id "..digits(file.id).." token "..file.token)
			-- save original to temporary location for processing, we only ever use this directory as it is easier to cleanup failed uploads from this common location, than it would in a directory amongst existing files; the file should be moved or removed by the function that calls this one according to its own validation criteria
			file.temporary = "temporary/upload/"..site.token.."_"..file.token -- must save using a unique name as we could be handling simultaneous uploads of similarly named files
			if util.FileSave(file.temporary,file.upload.contents) then
				table.insert(new,file)
			else
				log.Info("Failed to save upload "..index..": "..err)
				table.remove(files, index) -- delete incomplete item from the record entirely
				-- TODO: propagate to view / FileItems
			end
			file.upload = nil -- remove the upload data
		else
			existing[file.id] = true
		end
	end
	-- delete removed files
	for _,file in ipairs(util.TablePath(record._original, name) or {}) do
		if not existing[file.id] then DeleteFile(site.token,file.id,directory) end
	end
	return new
end

function tag.Error(name,message,reset_value)
	-- invokes an immediate validation error for the given tag name; may be used after calling tag.Validate
	if message ==true then message = nil end
	page.data[name] = page.data[name] or {name} -- allows us to add an error for a non-validated tag
	local validation = page.data[name]
	validation.server_message = message
	validation.validated = false
	if reset_value then
		validation[2] =nil
		validation.value =nil
		request.form[validation[1]] =nil
		-- TablePath(form, validation[1]) ??
	end
	tag.ValidateTag(validation)
	_G.page.validated = false
end

do local function ValidationItem(validation)
	_G.page.data[validation[1]] = validation
	if validation.groups then keyed(validation.groups) end
	if validation.origin then
		-- get the value from the origin table
		validation[2] = util_TablePath(validation.origin, string_match(validation[1],"[^%.]+%.(.+)"))
	end
	if validation.denormalise then
		log.Debug("Denormalising "..validation[1].." "..tostring(validation[2]).." -> "..tostring(validation.denormalise(validation[2])))
		validation[2] = validation.denormalise(validation[2]) -- TODO: use .value so we can preserve the original
	end
end
function tag.Validation (validation,validate)
	-- assign validation parameters to a named tag, or a default array of tags in their displayed order; these validation parameters are used when calling tag.Validate which further defines corresponding (conditional) markup for output with tag.* functions
	-- accepts a single table parameter with a complete or partial tag validation configuration attributes
	-- previously defined tags may have their attributes changed by subsequent calls with new or changed attributes (albeit at the cost of iterating all other tags)
	-- supported classes are the names of icons in kit/icons, e.g. "error", "warn", "unknown", "valid", "none"; display should be modified with CSS as the output is standardised markup
	--[[
{
	"namespace.fieldname", -- namespace optional
	"original value", -- propagates to tag value and manifest; requires namespace; replaced by denormalise
	validate = "Function", -- the name of a function from the validate.* table to be run both server and client-side upon user-input see validate.*; if none is specified validation is considered to have failed and the corresponding class will be displayed; if a corresponding jsvalidate.Name table is declared, the javascript validation will use its values instead
	postvalidate = function, -- an optional function that will be run server-side only if validation succeeds; this function may return a failure message (will be replaced client-side if further validation occurs), or true
	normalise = "Function" or true, -- if true the form value is replaced with the result of the validation function when succesful; should only be used with validation functions that return values suitable for both consumption from the form and display/use in the rendered form; may be specified as a function name from the validate table the result of which is set to the value .returned for consumption as a manifest
	optional = true, -- does not invoke an error if there is no value
	preserve = false; set to true to replace nil values (from forms) with the origin value; should not be set on any value that may be removed (i.e. becomes nil), most useful with checkboxes that toggle values, but also when set conditionally on a larger validation set than a form itself returns
	message = "string", -- a message to show if validation fails
	groups = {"name",…} -- a list of names, upon which the supplementary manifest functions operate
	to set classes call tag.ValidationDefaults
}
	]]--
	-- the page._validation table is a private array used for recursing the tags during validation in their declared order, and focusing the first failed field
	-- each tag is also assigned to the page.data table by name, and may be used to directly change tag validation instead of calling this function again; the page.data table is replicated in the client-side javascript environment
	-- when used with an original value page.data["user.name"].changed can be used to determine if the value has been changed by the form input
	-- .validated_class indicates the state of the field by class name
	-- .validated (as boolean) indicates if the field validated or not
	_G.page._validation_markup = page._validation_markup or {} -- always populate as required by tag functions -- TODO: remove as no longer required with css classes
	if validation.valid==true then validation.valid = "valid" end
	_G.page._validation =  _G.page._validation or {}
	if type(validation[1]) =="table" then
		-- multiple tags
		for _,tag in ipairs(validation) do
			if not _G.page.data[validation[1]] then
				table.insert(_G.page._validation, tag)
				ValidationItem(tag)
			else
				copy(validation,_G.page.data[validation[1]],true)
				ValidationItem(_G.page.data[validation[1]])
			end
		end
	elseif _G.page.data[validation[1]] then
		-- update tag
		copy(validation,_G.page.data[validation[1]],true)
		ValidationItem(_G.page.data[validation[1]])
	else
		table_insert(_G.page._validation,validation)
		ValidationItem(validation)
	end
	if validate then return tag.Validate() end
end end

function tag.ValidationDefaults(defaults)
	-- default = "class", -- an optional class to be shown if no validate function is provided, or if there is no value; default is "none" (a class value that will not actually be used in js); not to be confused with tag.Validate{default="class"}
	-- error = "class", -- an optional class to be shown when validation fails; if neither class nor error are specified the default "error" class is used
	-- valid = "class", -- shown when validation succeeds; defaults to "valid"
	-- defaults.valid="class" default is none on get and "valid" on post to enable the validation icon for successfully validated fields
	-- defaults.error="class" default is "error"
	-- defaults.default="class" default is none, used only on GET, and may thus be set to "warn" to show all required fields before input is made
	if _G.page.data._validation_default then return _G.page.data._validation_default end
	defaults = defaults or {}
	_G.page.data._validation_default = defaults
	_G.page.javascript._validation_default = defaults -- must not use class="" which is for conditional static validation, so we set the defaults for interactive validation before those conditionals
	page.javascript._validation_default.error = defaults.error or "error"
	page.javascript._validation_default.valid = defaults.valid or "valid"
	defaults.default = defaults.default or ""
	if request.get then
		defaults.valid = defaults.valid or ""
		defaults.error = defaults.default or ""
	else
		defaults.valid = defaults.valid or "valid"
		defaults.error = defaults.error or "error"
	end
	return defaults
end
function tag.Validate(options)
	-- returns state of validation as well as compiling markup for rendering with tag.* functions to provide user feedback
	-- validation parameters are configured with tag.Validation or passed as options (cannot also be used with following options)
	-- options.field ="name" allows checking of a single field
	-- options.group allows checking of only subsets of tag fields with a correspondingly declared validation.groups={"group"}
	-- options.reset = true if running a second time
	request.form.validated = request.form.validated or {} -- where we put normalised validation return values
	options = options or {}
	if options[1] then tag.Validation(options) end -- can be a single tag or an array
	if not _G.page._validation then return true end -- no validation declared
	local tag_ValidateTag = tag.ValidateTag
	if options.field then
		local validation = _G.page.data[options.field]
		validation.validated = tag_ValidateTag(validation,options.reset)
		return
	end
	local page_validated = true
	for _,validation in ipairs(_G.page._validation) do
		if not options.group or (validation.groups and validation.groups[options.group]) then
			validation.validated = tag_ValidateTag(validation,options.reset)
			if not validation.validated then
				_G.page.focusfield = page.focusfield or validation[1]
				page_validated = false
			end
		end
	end
	_G.page.validated = page_validated
	return page_validated
end

do local function Invalid(group,grouping)
	local matched = 0
	local max = #page._validation
	local grouped = {}
	return function()
		for i=matched+1,max,1 do
			local tag = page._validation[i]
			if not tag.validated and (not tag.groups or not group or tag.groups[group]) then
				if grouping~=false and tag.invalid then
					if not grouped[tag.invalid] then
						grouped[tag.invalid] = true
						matched = i
						return tag.invalid,tag
					end
				else
					matched = i
					return tag[1],tag
				end
			end
		end
	end
end
function tag.Invalid(group,grouping,concat)
	-- an iterator that returns name,validation for all the unvalidated tag validation tables
	-- or if concat is given returns all the field names concatendated in a string, or nil if none; field names must be declared in a vocabulary in the form ["field:namespace.name"] = "Display name"
	-- group if specified only evaluates tags having validation.groups={"name"}
	-- validation may be supplemented with invalid="name" and only one unique instance of that name will be returned, or may simply be used to provide an alternate return name (if unique); this behaviour can be disabled with grouping=false
	if not concat then return Invalid(group,grouping) end
	local fields = {}
	for field in Invalid(group,grouping) do table.insert(fields,l["field:"..field]) end
	if #fields ==0 then return end
	return table.concat(fields,concat)
end end

postvalidate={}
do local postvalidate = postvalidate
function tag.ValidateTag(validation,reset)
	-- constructs markup for the tag, and adds a .valid attribute to its validation table allowing per-field conditions e.g. if not page.data["namespace.field"].valid then …
	-- set validation.validated =nil to force re-check
	-- individual direct tag validation with this method is discouraged in favour of tag.Validate{"name", …}
	local defaults = page.data._validation_default or tag.ValidationDefaults()
	local validated = validation.validated -- preserves tag.Error
	local message
	local class = defaults.valid -- default is valid
	if validation.value==nil or reset then -- declared value takes precedence always
		if temp.concordances then
			local namespace = string_match(validation[1], "([^%[%.]*)")
			validation.value = util_TablePath(temp.concordances, validation[1])
		elseif request.get then
			validation.value = validation[2]
		elseif request.form[validation[1]] then -- post
			validation.value = request.form[validation[1]]
		else -- post but namespaced; also if request.form[name] is nil
			validation.value = util_TablePath(form, validation[1])
			if validation.value ==nil and validation.preserve then validation.value = validation[2] end
		end
	end

	if validated ==nil or reset then
		if validation.validate then
			-- a validation function was specified
			log.Info(); if not validate[validation.validate] then return scribe.Error{title="Unknown validate function", detail=validation.validate} end
			validated = validate[validation.validate](validation.value, validation.arg)
			if validated ==validate.invalid and validation.optional~=true then
				validated = false
				class = defaults.error
			else
				if validation.value ==nil and validation.optional then class = "" end -- optional fields should not show any class
				if validated ~=validate.invalid then
					request.form.validated[validation[1]] = validated -- always assign normalised value to this table
					if validation.normalise then validation.returned = validated end -- only assign normalised value to return result if normalise is true -- TODO: if validation.normalise~=false; normalise should be the default behaviour
				end
				validated = true
				if validation.postvalidate then
					-- an optional supplementary validate function to run server-side; is replaced with the validation class before it reaches JS
					-- typically used to perform persistence or lookup checks, optionally returning a string that becomes an error message
					validated = validation.postvalidate(value)
					if type(validated) =="string" then
						validation.server_message = validated
						validated = false
						class = defaults.error
					end
				end
			end
		elseif validation.value==nil then -- this is not first so as to allow validation functions to set defaults
			if validation.optional then
				validated = true
				class = ""
			else
				class = defaults.error
			end
		else
			validated = true
		end
	end
	if class =="error" then message = validation.server_message or validation.message end
	log.Debug("Validate "..validation[1].." "..tostring(validated).." "..tostring(class))

	if request.post then
		local value = validation.value
		if not validation.normalise then
			value = validation.value
		elseif validation.normalise ~=true then -- was normalised for display as well
			validation.returned = validate[validation.normalise](validation.value)
			value = validation.returned
			request.form.validated[validation[1]] = validation.returned
		else
			value = validation.returned
		end
		if value ~=validation[2] then
			validation.changed = true
		end
	end

	validation.validated_class = class -- consumed during tag construction and enabled

	local markup = {}
	if class and class~="" then -- TODO: remove as will henceforth be provided by CSS exclusively
		table_insert(markup, [[<img class="validation ]])
		table_insert(markup, class)
		table_insert(markup, [[" src="/moonstalk.kit/public/icons/]])
		table_insert(markup, class)
		table_insert(markup, [[.gif">]])
	end
	if message then -- TODO: eventually this could be replaced with JS using elem.setCustomValidity but currently this means unreliable invocation and stepping through fields before submission
		table_insert(markup, [[<strong>]])
		table_insert(markup, message)
		table_insert(markup, [[</strong>]])
	end
	_G.page._validation_markup[validation[1]] = table.concat(markup) -- consumed by the tag.* functions in the view
	return validated
end end


-- # Manifests
-- sets the denormalised display value of form fields (using tag functions), validates them, and provides normalised values from form input (either only those changed, or all); used in place of individual tag.Validation calls
-- see Validation for usage
-- supports field names that contain multiple distinct namespaces
-- original values used for default display should be assigned as DenormaliseHandler(record.field) and this value will be compared with request.form.namespace.field to determine if it has changed
-- when normalise is set to true the validate handler's result is used as the form value, both for return and display as a denormalised value, otherwise if validate is successful the specified denormalise handler is run and the return value set by that, leaving the form value unchanged (in case it needs to be redisplayed)
-- use page.validated to check status
function tag.Manifest(group,all)
	-- updates and returns tables of normalised and validated input that have changed
	-- fields are declared with tag.Validation using the following supplementary attributes
	-- origin table is always updated and if destination is a table that will be updated
	-- if destination is not false, values will also be returned in a table per their name namespace
	-- by default returns only changed values, but if all=true will return all fields

	-- {{"namespace.field", "original value", … }, …}; only the first manifest's declaration is used
	-- {{"namespace.field", origin=table, … }, …}; origin value will be retreived from the namespace_table (and assigned on return if destination is not false or someother table)
	-- {{"namespace.field", origin=table, destination=table, … }, …}; destination may be false to disable inclusion of this field
	-- {{"namespace.field", origin=table, destination="subtable", … }, …}; the changes table will include the entire origin[subtable] value merged with the updated validated value
	-- .denormalise=function; the value will be given to and set as the result of this function
	-- all other attributes as per kit.Validation
	-- may need to call tag.ValidationDefaults

	local changes = {}
	local util_TablePathAssign = util.TablePathAssign
	for _,validation in ipairs(page._validation) do
		if validation.groups and validation.groups[group] and (all or validation.changed) then
			local value = validation.value
			if validation.normalise then value = validation.returned end
			if validation.origin then util_TablePathAssign(validation.origin, string_match(validation[1], "[^%.]+%.(.*)"), value) end -- merge the validated value with the original value
			if type(validation.destination) =='table' then
				util_TablePathAssign(validation.destination, string_match(validation[1], "[^%.]+%.(.*)"), value) -- assign the value to the destination table
			elseif validation.destination ==nil then
				util_TablePathAssign(changes, validation[1], value) -- add only the value to changes
			elseif validation.destination then
				-- add the value and its parent subtable to changes
				local namespace = string_match(validation[1], "([^%.]+)")
				changes[namespace] = changes[namespace] or {}
				util_TablePathAssign(changes[namespace],validation.destination,validation.origin[validation.destination]) -- the value has already been merged
			end
		end
	end
	return changes
end


-- # form tag functions
-- these take a simple value=value that is always used, or if value=nil the value will be derived from a the declared tag.Validation or kit.Manifesto value, else form field

do local function AssignTagValue(attributes)
	-- Validate may be run conditionally (e.g. only on post) so if used to set values we may nontheless need to get values assigned by Validation
	-- tag attributes may specify initial="value" which will always be used on GET if not namespaced
	-- attributes.default is always used (GET and POST) when no value is given
	if attributes.value then return end -- set directly in tag
	local namespace = string_match(attributes.name or "", "([^%[%.]*)")
	local namespaced = string_find(attributes.name or "", ".", 1, true)
	if not namespaced and request.post then
		-- simple behaviour, gets from form
		attributes.value = request.form[attributes.name]
	elseif not namespaced then -- GET
		-- simple behaviour, uses initial
		attributes.value = attributes.initial
		attributes.initial = nil
	-- else namespaced
	elseif temp.concordances and temp.concordances[namespace] then
		attributes.value = util_TablePath(temp.concordances, attributes.name)
	elseif request.get and _G.page.data[attributes.name] then
		-- set by validation origin; only valid with a namespace
		if _G.page.data[attributes.name].value ==nil then
			attributes.value = _G.page.data[attributes.name][2]
		else
			attributes.value =_G.page.data[attributes.name].value
		end
	else
		-- simple behaviour but namespaced
		attributes.value = util_TablePath(form,attributes.name)
	end
	if attributes.value == nil then attributes.value = attributes.default; attributes.default = nil end
end

function tag.hidden (attributes,value)
	-- accepts a single param for name
	-- only required for values that *may* be changed by JS
	if type(attributes)~="table" then attributes={name=attributes,value=value} end
	AssignTagValue(attributes)
	write [[<input type="hidden"]]
	for key,value in pairs(attributes) do
		write [[ ]]
		write(key)
		write [[="]]
		write(value)
		write [["]]
	end
	write [[/>]]
end

-- TODO: add required attributed if not optional
-- NOTE: pattern attributes if desired are expected to be set manually in a view's tag declaration
function tag.input (attributes,value)
	-- if validation is specified will set focusfield (via moonstalk_kit.js) in case of error
	-- default type is text
	if type(attributes)~="table" then attributes={name=attributes, value=value} end
	AssignTagValue(attributes)
	local validation
	if page.data[attributes.name] then -- TODO: remove validation class from inputs as covered by span wrapper? can then do away with concatenation
		attributes.class = table.concat{attributes.class or "", " ", page.data[attributes.name].validated_class}
		validation = page._validation_markup[attributes.name]
	end
	attributes.type = attributes.type or "text"
	write [[<span class="input ]] write(attributes.class) attributes.class=nil write[[" id="]] write(attributes.name) write[["><input ]]
	for key,value in pairs(attributes) do
		write [[ ]]
		write(key)
		write [[="]]
		write(value)
		write [["]]
	end
	write [[/>]]
	write(validation)
	write[[</span>]]
end

function tag.date (attributes,value)
	-- date inputs are submitted by browsers with the format "YYYY-MM-DD" if supported, else user-input text, thus should use an appropriate validation routine to convert this as needed ue.g. validate.Date
	if type(attributes)~="table" then attributes={name=attributes, value=value} end
	AssignTagValue(attributes)

	local validation
	if page.data[attributes.name] then
		attributes.class = table.concat{attributes.class or "", " ", page.data[attributes.name].validated_class}
		validation = page._validation_markup[attributes.name]
	end

	write [[<span class="input ]] write(attributes.class) attributes.class=nil write[[" id="]] write(attributes.name) write[["><input type="date"]]
	for key,value in pairs(attributes) do
		write [[ ]]
		write(key)
		write [[="]]
		write(value)
		write [["]]
	end
	write [[/>]]
	write(validation)
	write[[</span>]]
end

function tag.file (attributes)
	if type(attributes)~="table" then attributes={name=attributes} end

	local validation
	if page.data[attributes.name] then
		attributes.class = table.concat{attributes.class or "", " ", page.data[attributes.name].validated_class}
		validation = page._validation_markup[attributes.name]
	end

	write [[<span class="input ]] write(attributes.class) write[[" id="]] write(attributes.name) write[["><input type="file" name="]] write(attributes.name) write[[">]]
	write(validation)
	write[[</span>]]
end

function tag.text (attributes,value)
	-- TODO: support validation images, would require a pre-defined validation requirements table (e.g. in the controller), and if present would display the image and load the javascript
	-- transaprently denormalises lines from LF to CRLF; normalise may need to be used if stored as LF
	if type(attributes)~="table" then attributes={name=attributes} end
	AssignTagValue(attributes)
	value = value or attributes.value
	attributes.value = nil
	local line = string.find(value or "","\n",1,true); if line and not string.sub(value,line-1,line-1) =="\r" then value = string.gsub(value,"\n","\r\n") end

	local validation
	if page.data[attributes.name] then
		attributes.class = table.concat{attributes.class or "", " ", page.data[attributes.name].validated_class}
		validation = page._validation_markup[attributes.name]
	end

	-- TODO: add support for javascript validation
	write [[<span class="input ]] write(attributes.class) attributes.class=nil write[[" id="]] write(attributes.name) write[["><textarea]]
	for key,value in pairs(attributes) do
		write [[ ]]
		write(key)
		write [[="]]
		write(value)
		write [["]]
	end
	write [[>]]
	write (value)
	write [[</textarea>]]
	write(validation)
	write[[</span>]]
end

function tag.select (attributes)
	-- name = "",
	-- selected = value,
	-- preserve = false, -- if the value or selected are not present in one of the option items, a new item will be added to preserve the value (default is true)
	-- unspecified = true or "localisedstring", -- this will insert an extra item labelled with the given localised string (or "") and having a nil value
	-- insert = items, -- will not be sorted; a divider is added after -- WARNING: will be modified only if unspecified=true
	-- options = items or table; table is assuemd to be an array of labels the value is either the position or label (when values=false), use pairs=true and values="keyname" for more complex tables; -- WARNING: will be modified if sort is used unless insert or append are also specified
	-- sort = true (using item.value) or "keyname" (using item[keyname]); -- WARNING: modifies the options table if sort is used; should be copied before use (typically at startup not with every request) if the original order of that table is to be maintained
	-- append = items, -- will not be sorted; will not be modified; a divider is added before
	-- localise = false, -- if true or nil, individual option items may specfy false to disable; else if false disables for all option items except those that declare it as true -- WARNING: modifies the options table when localise=true
	-- values = "keyname" or false, -- the key name inside the each option table for the option value, or false to use the label; also disables localisation
	-- labels = "keyname", -- the key name inside the each option table for the label value (or localised string name)
	-- pairs = true, -- use the pairs iterator on the options instead of ipairs
	-- html = [[html]], -- a chunk of html options markup to be inserted at the end of the above options (if any); this allows caching of commonly used chunks as a single string avoiding iteration, and is used by tag.Countries; all other options may still be used and the chunk will be modified with a selected value

	-- items are specified as an array of {value="",label="",localise=false} where label is a localised string unless localise=false; if neither values nor labels are specified and options is an array, it is considered an array of items
	-- if an options table is provided, an unmatched value will be added at the bottom having only the label of the value
	-- WARNING: if sort and localise are both specifed for an options table, every option will have a "_localised" key added, for non-ephemeral tables the value of which will change with every request
	-- NOTE: some combinations of attributes can cause multiple iterations of the tables and regeneration of new tables, therefore when higher performance is desired, it is preferable to generate and cache the options table and pass it without enabling the more expensive behaviours (sort, localise, insert, append)
	-- NOTE: if values are numbers, they will be formatted using digits() which handles whole numbers only (i.e. it assumes they are internal IDs, which should ideally be encoded)
	-- TODO: label and value function handlers / validation
	AssignTagValue(attributes)
	local selected = attributes.selected or attributes.value -- else matches with unspecified or first value=""
	attributes.selected = nil; attributes.value = nil
	local insert = attributes.insert -- first items in menu; an items array
	local append = attributes.append -- last items in menu; an items array
	local html_chunk = attributes.html; attributes.html = nil
	attributes.insert = nil; attributes.append = nil
	local items -- items in menu; an items array or table whose behaviour is defined by labelkey and and valuekey such as created with options()
	if attributes.options and attributes.options.options then
		if not attributes.sort then
			items = attributes.options.ordered
		else
			items = attributes.options.options
		end
	else
		items = attributes.options
	end
	attributes.options = nil

	local sort = attributes.sort; attributes.sort = nil
	local preserve = attributes.preserve; attributes.preserve = nil
	local localise = attributes.localise; attributes.localise = nil
	local table_insert = table.insert
	if attributes.unspecified then
		insert = insert or {}
		if attributes.unspecified ==true then attributes.unspecified = "unspecified" end
		table_insert(insert, 1, {label=attributes.unspecified, value="", localise=true})
		attributes.unspecified = nil
	end
	local options
	-- build the items
	if not attributes.pairs and not (attributes.values or attributes.labels) and items[1] and type(items[1]) =="table" then
		-- an items array
		if sort then
			if localise ~=false and sort==true then
				-- add the localised value so we can sort with it
				local L = L
				for _,item in ipairs(items) do
					if item.localise ~=false then
						item._localised = L[item.label]
					else
						item._localised = item.label
					end
				end
				if sort ==true then sort = "_localised" end
			end
			util.SortArrayByKey(items,sort)
		end
		if insert or append then
			-- we'll need to change the array
			options = insert or {}
			if insert then table_insert(options,{label="—", value=[[" disabled="disabled]], localise=false}) end
			for _,item in ipairs(items) do table_insert(options,item) end
			if append then
				table_insert(options,{label="—", value=[[" disabled="disabled]], localise=false})
				for _,item in ipairs(append or{}) do table_insert(options,item) end
			end
		else
			-- unchanged
			options = items
		end
	else
		-- table needs converting to an items array
		local valuekey = attributes.values -- defaults to key of item in items
		attributes.values = nil
		if valuekey then localise = false end
		local labelkey = attributes.labels -- defaults to value of item in items
		attributes.labels = nil
		options = {}
		local iterator
		if attributes.pairs then -- pairs=true must be specified if not an array as we can't detect an empty array otherwise
			attributes.pairs = nil
			iterator = pairs
		else
			iterator = ipairs
		end
		local L = L
		for key,value in iterator(items) do
			local option = {}
			if valuekey then
				option.value = value[valuekey]
			elseif valuekey ~=false then
				option.value = key
			end
			if labelkey then
				option.label = value[labelkey]
			else
				option.label = value
			end
			table_insert(options,option)
		end
		if sort then
			if sort ==true then sort = "label" end
			util.SortArrayByKey(options,sort)
		end
		if insert then -- must preserve the order of these, but also insert at beginning after items have been sorted
			for i=1,#insert do table_insert(options, i, insert[i]) end
			table_insert(options, #insert+1, {label="—", value=[[" disabled="disabled]], localise=false})
		end
		if append then
			table_insert(options, {label="—", value=[[" disabled="disabled]], localise=false})
			for _,item in ipairs(append) do table_insert(options,item) end
		end
	end

	local validation
	if page.data[attributes.name] then
		attributes.class = table.concat{attributes.class or "", " ", page.data[attributes.name].validated_class}
		validation = page._validation_markup[attributes.name]
	end
	write [[<span class="input ]] write(attributes.class) attributes.class=nil write[[" id="]] write(attributes.name) write[["><select]]
	for key,value in pairs(attributes) do
		write [[ ]]
		write(key)
		write [[="]]
		write(value)
		write [["]]
	end
	write[[ size="1">]]
	local L=L; local tonumber=tonumber; local digits=digits; local write=write
	for _,option in ipairs(options) do
		if tonumber(option.value) then option.value = digits(option.value) selected = digits(selected) end -- this will only preserve whole numbers up to 16 digits
		write[[<option]] if option.value then write[[ value="]] write(option.value) write[["]] end
		if option.value ==selected or option.label ==selected then
			write[[ selected="selected"]]
			selected = true -- only want to select first instance, in case it appears multiple times
		end
		write[[>]]
		if option.localise ==true or (localise ~=false and option.localise ~=false) then
			if sort then
				write(option._localised)
			else
				write(L[option.label])
			end
		else
			write(option.label)
		end
		write[[</option>]]
	end
	if selected~=true and html_chunk then
		local found
		html_chunk,found = string.gsub(attributes.html, attributes.value..[["]], attributes.value..[[" selected="selected"]], 1) -- if the value does not match it will simply be added as an additional option unless preserve=false
		if found >0 then selected = true end
	end
	if selected~=nil and selected~=true and preserve~=false then
		-- edge case for when we have a value no longer in the popup
		write[[<option value="]] write(selected) write[[" selected="selected">]] write(selected) write[[</option>]]
		log.Notice("Unmatched value '"..tostring(selected).."' in select '"..attributes.name.."' at "..request.url)
	end
	write(html_chunk) -- usually empty
	write[[</select>]]
	write(validation)
	write[[</span>]]
end

function tag.checkbox (attributes)
	-- a falsy values result in not checked; a truthy value will cause it to be checked; use either attributes.checked=true or false to override this, or attributes.default=true to check by default if value and checked are not specified
	-- to invert the behaviour requires both denormalisation and normalisation using validation={validate="Checkbox", arg={checked=nil,unchecked=true}, normalise=true,optional=true}
	-- request.form.checkbox_name always returns 1 when checked or nil when unchecked unless attributes.invert=true; use custom logic or validation to preserve/assign values for persistence e.g. validate.Checkbox and arg={checked=false,unchecked=true or "value"} normalise=true and request.form.validated.checkbox_name
	if type(attributes)~="table" then attributes={name=attributes} end
	AssignTagValue(attributes)
	if attributes.checked or attributes.value or (attributes.default and attributes.checked==nil and attributes.value==nil) then
		attributes.checked ="checked"
	else
		attributes.checked =nil -- to handle attributes.checked==false
	end
	attributes.value = "1"
	attributes.default = nil
	attributes.invert = nil

	local validation
	if page.data[attributes.name] then
		attributes.class = table.concat{attributes.class or "", " ", page.data[attributes.name].validated_class}
		validation = page._validation_markup[attributes.name]
	end

	write [[<span class="input ]] write(attributes.class) attributes.class=nil write[[" id="]] write(attributes.name) write[["><input type="checkbox"]]
	for key,value in pairs(attributes) do
		write [[ ]]
		write(key)
		write [[="]]
		write(value)
		write [["]]
	end
	write[[></span>]]
	write(validation)
end


do local html_options =[[
<option value="af" data-alternative-spellings="AF Afghanistan">افغانستان</option>
<option value="ax" data-alternative-spellings="AX Aaland Aland">Åland Islands</option>
<option value="al" data-alternative-spellings="AL Albania">Shqipëria</option>
<option value="dz" data-alternative-spellings="DZ Algeria">الجزائر</option>
<option value="as" data-alternative-spellings="AS">American Samoa</option>
<option value="ad" data-alternative-spellings="AD Andore">Andorra</option>
<option value="ao" data-alternative-spellings="AO">Angola</option>
<option value="ai" data-alternative-spellings="AI">Anguilla</option>
<option value="aq" data-alternative-spellings="AQ">Antarctica</option>
<option value="ag" data-alternative-spellings="AG">Antigua And Barbuda</option>
<option value="ar" data-alternative-spellings="AR">Argentina</option>
<option value="am" data-alternative-spellings="AM Armenia">Հայաստան</option>
<option value="aw" data-alternative-spellings="AW">Aruba</option>
<option value="au" data-alternative-spellings="AU">Australia</option>
<option value="at" data-alternative-spellings="AT Austria Osterreich Oesterreich">Österreich</option>
<option value="az" data-alternative-spellings="AZ Azerbaijan">Azərbaycan</option>
<option value="bs" data-alternative-spellings="BS">Bahamas</option>
<option value="bh" data-alternative-spellings="BH Bahrain">البحرين</option>
<option value="bd" data-alternative-spellings="BD Bangladesh">বাংলাদেশ</option>
<option value="bb" data-alternative-spellings="BB">Barbados</option>
<option value="by" data-alternative-spellings="BY Belarus">Беларусь</option>
<option value="be" data-alternative-spellings="BE Belgium Belgie Belgien">België / Belgique</option>
<option value="bz" data-alternative-spellings="BZ">Belize</option>
<option value="bj" data-alternative-spellings="BJ">Benin</option>
<option value="bm" data-alternative-spellings="BM">Bermuda</option>
<option value="bt" data-alternative-spellings="BT Bhutan">भूटान</option>
<option value="bo" data-alternative-spellings="BO Buliwya Wuliwya Volívia">Bolivia</option>
<option value="bq" data-alternative-spellings="BQ">Bonaire, Sint Eustatius and Saba</option>
<option value="ba" data-alternative-spellings="BA BiH Bosnia Bosna Hercegovina Herzegovina">Босна и Херцеговина</option>
<option value="bw" data-alternative-spellings="BW">Botswana</option>
<option value="bv" data-alternative-spellings="BV">Bouvet Island</option>
<option value="br" data-alternative-spellings="BR Brazil">Brasil</option>
<option value="io" data-alternative-spellings="IO">British Indian Ocean Territory</option>
<option value="bn" data-alternative-spellings="BN">Brunei Darussalam</option>
<option value="bg" data-alternative-spellings="BG Bulgaria Bălgarija Bulgariya">България</option>
<option value="bf" data-alternative-spellings="BF">Burkina Faso</option>
<option value="bi" data-alternative-spellings="BI">Burundi</option>
<option value="kh" data-alternative-spellings="KH Cambodia Kampuchea">កម្ពុជា</option>
<option value="cm" data-alternative-spellings="CM">Cameroon</option>
<option value="ca" data-alternative-spellings="CA">Canada</option>
<option value="cv" data-alternative-spellings="CV Cabo">Cape Verde</option>
<option value="ky" data-alternative-spellings="KY">Cayman Islands</option>
<option value="cf" data-alternative-spellings="CF Ködörösêse kodoro">Central African Republic</option>
<option value="td" data-alternative-spellings="TD Chad Tchad Tšād">تشاد‎</option>
<option value="cl" data-alternative-spellings="CL">Chile</option>
<option value="cn" data-alternative-spellings="CN Zhongguo Zhonghua Peoples Republic China">中国</option>
<option value="cx" data-alternative-spellings="CX">Christmas Island</option>
<option value="cc" data-alternative-spellings="CC">Cocos (Keeling) Islands</option>
<option value="co" data-alternative-spellings="CO">Colombia</option>
<option value="km" data-alternative-spellings="KM Comoros Juzur Qamar">جزر القمر</option>
<option value="cg" data-alternative-spellings="CG Kongo">République démocratique du Congo (Kinshasa)</option>
<option value="cd" data-alternative-spellings="CD Repubilika Kongo">République du Congo (Brazzaville)</option>
<option value="ck" data-alternative-spellings="CK">Cook Islands</option>
<option value="cr" data-alternative-spellings="CR">Costa Rica</option>
<option value="ci" data-alternative-spellings="CI Cote dIvoire">Côte d'Ivoire</option>
<option value="hr" data-alternative-spellings="HR Croatia">Hrvatska</option>
<option value="cu" data-alternative-spellings="CU">Cuba</option>
<option value="cw" data-alternative-spellings="CW Curacao">Curaçao</option>
<option value="cy" data-alternative-spellings="CY Cyprus">Κύπρος / Kýpros / Kıbrıs</option>
<option value="cz" data-alternative-spellings="CZ Česká Ceska Czech">Česko</option>
<option value="dk" data-alternative-spellings="DK Denmark">Danmark</option>
<option value="dj" data-alternative-spellings="DJ Djibouti Jabuuti Gabuuti">جيبوتي‎</option>
<option value="dm" data-alternative-spellings="DM Dominique">Dominica</option>
<option value="do" data-alternative-spellings="DO Dominican Republic">República Dominicana</option>
<option value="ec" data-alternative-spellings="EC">Ecuador</option>
<option value="eg" data-alternative-spellings="EG Misr Masr Egypt">مصر</option>
<option value="sv" data-alternative-spellings="SV">El Salvador</option>
<option value="gq" data-alternative-spellings="GQ Equatorial">Guinea Ecuatorial</option>
<option value="er" data-alternative-spellings="ER Eritrea Iritriya Ertra">إرتريا / ኤርትራ</option>
<option value="ee" data-alternative-spellings="EE Estonia">Eesti</option>
<option value="et" data-alternative-spellings="ET Ityop'ia">ኢትዮጵያ / Ethiopia</option>
<option value="fk" data-alternative-spellings="FK Malvinas">Falkland Islands</option>
<option value="fo" data-alternative-spellings="FO Faroe">Føroyar / Færøerne</option>
<option value="fj" data-alternative-spellings="FJ">Viti / Fiji / फ़िजी</option>
<option value="fi" data-alternative-spellings="FI Finland">Suomi</option>
<option value="fr" data-alternative-spellings="FR France">République Française</option>
<option value="gf" data-alternative-spellings="GF French Guiana">Guyane</option>
<option value="pf" data-alternative-spellings="PF French Polynesia">Polynésie Française</option>
<option value="tf" data-alternative-spellings="TF">French Southern Territories</option>
<option value="ga" data-alternative-spellings="GA Gabon">République Gabonaise</option>
<option value="gm" data-alternative-spellings="GM">The Gambia</option>
<option value="ge" data-alternative-spellings="GE Georgia">საქართველო</option>
<option value="de" data-alternative-spellings="DE Germany Bundesrepublik">Deutschland</option>
<option value="gh" data-alternative-spellings="GH Gaana Gana">Ghana</option>
<option value="gi" data-alternative-spellings="GI">Gibraltar</option>
<option value="gr" data-alternative-spellings="GR Greece">Ελλάδα</option>
<option value="gl" data-alternative-spellings="GL Greenland Grønland">Kalaallit Nunaat</option>
<option value="gd" data-alternative-spellings="GD">Grenada</option>
<option value="gp" data-alternative-spellings="GP">Guadeloupe</option>
<option value="gu" data-alternative-spellings="GU">Guåhån / Guam</option>
<option value="gt" data-alternative-spellings="GT">Guatemala</option>
<option value="gg" data-alternative-spellings="GG">Guernsey</option>
<option value="gn" data-alternative-spellings="GN Guinea Gine">Guinée</option>
<option value="gw" data-alternative-spellings="GW Guinea Bissau">Guiné-Bissau</option>
<option value="gy" data-alternative-spellings="GY">Guyana</option>
<option value="ht" data-alternative-spellings="HT Haiti Ayiti">Haïti</option>
<option value="hm" data-alternative-spellings="HM">Heard Island and McDonald Islands</option>
<option value="va" data-alternative-spellings="VA">Holy See</option>
<option value="hn" data-alternative-spellings="HN">Honduras</option>
<option value="hk" data-alternative-spellings="HK">香港 / Hong Kong</option>
<option value="hu" data-alternative-spellings="HU Hungary">Magyarország</option>
<option value="is" data-alternative-spellings="IS Iceland">Ísland</option>
<option value="in" data-alternative-spellings="IN Hindustan Bharat Bhārat" data-relevancy-booster="2">भारत / India</option>
<option value="id" data-alternative-spellings="ID">Indonesia</option>
<option value="ir" data-alternative-spellings="IR Iran Īrān">ایران</option>
<option value="iq" data-alternative-spellings="IQ Iraq">العراق‎</option>
<option value="ie" data-alternative-spellings="IE Ireland" data-relevancy-booster="1">Éire</option>
<option value="im" data-alternative-spellings="IM">Isle of Man</option>
<option value="il" data-alternative-spellings="IL Israel Yisrael">ישראל / إسرائيل</option>
<option value="it" data-alternative-spellings="IT Italy" data-relevancy-booster="1">Italia</option>
<option value="jm" data-alternative-spellings="JM">Jamaica</option>
<option value="jp" data-alternative-spellings="JP Nippon Nihon Japan">日本</option>
<option value="je" data-alternative-spellings="JE">Jersey</option>
<option value="jo" data-alternative-spellings="JO Jordan Urdun">الأردن</option>
<option value="kz" data-alternative-spellings="KZ Kazakhstan Казахстан">Қазақстан</option>
<option value="ke" data-alternative-spellings="KE">Kenya</option>
<option value="ki" data-alternative-spellings="KI">Kiribati</option>
<option value="kp" data-alternative-spellings="KP North Korea Republic Chosŏn Bukchosŏn">조선</option>
<option value="kr" data-alternative-spellings="KR South Korea Republic Namhan Hanguk">한국</option>
<option value="xk" data-alternative-spellings="XK Kosovo Косово">Kosova</option>
<option value="kw" data-alternative-spellings="KW Kuwait">الكويت</option>
<option value="kg" data-alternative-spellings="KG Kyrgyzstan Kirgizija">Кыргызстан</option>
<option value="la" data-alternative-spellings="LA Laos">ປະເທດລາວ</option>
<option value="lv" data-alternative-spellings="LV Latvia">Latvija</option>
<option value="lb" data-alternative-spellings="LB Lebanon Liban Lubnān">لبنان</option>
<option value="ls" data-alternative-spellings="LS">Lesotho</option>
<option value="lr" data-alternative-spellings="LR">Liberia</option>
<option value="ly" data-alternative-spellings="LY Libya">ليبيا</option>
<option value="li" data-alternative-spellings="LI">Liechtenstein</option>
<option value="lt" data-alternative-spellings="LT Lithuania">Lietuva</option>
<option value="lu" data-alternative-spellings="LU Luxembourg">Lëtzebuerg</option>
<option value="mo" data-alternative-spellings="MO Macao">澳門 / Macau</option>
<option value="mk" data-alternative-spellings="MK Macedonia Makedonija">Македонија</option>
<option value="mg" data-alternative-spellings="MG Madagascar">Madagasikara</option>
<option value="mw" data-alternative-spellings="MW Malawi">Malaŵi</option>
<option value="my" data-alternative-spellings="MY">马来西亚 / Malaysia</option>
<option value="mv" data-alternative-spellings="MV Dhivehi Raajje">Maldives</option>
<option value="ml" data-alternative-spellings="ML">Mali</option>
<option value="mt" data-alternative-spellings="MT">Malta</option>
<option value="mh" data-alternative-spellings="MH Marshall">Aorōkin M̧ajeļ</option>
<option value="mq" data-alternative-spellings="MQ">Martinique</option>
<option value="mr" data-alternative-spellings="MR Mauritania">الموريتانية / Muritan / Agawec</option>
<option value="mu" data-alternative-spellings="MU Maurice Moris">Mauritius</option>
<option value="yt" data-alternative-spellings="YT">Mayotte</option>
<option value="mx" data-alternative-spellings="MX Mexico">México</option>
<option value="fm" data-alternative-spellings="FM Federated States">Micronesia</option>
<option value="md" data-alternative-spellings="MD">Moldova</option>
<option value="mc" data-alternative-spellings="MC">Monaco</option>
<option value="mn" data-alternative-spellings="MN Mongolia Mongol">Mongγol Uls / Монгол улс</option>
<option value="me" data-alternative-spellings="ME Montenegro">Crna Gora</option>
<option value="ms" data-alternative-spellings="MS">Montserrat</option>
<option value="ma" data-alternative-spellings="MA Morocco Amerruk Elmeɣrib">المغرب / Maroc</option>
<option value="mz" data-alternative-spellings="MZ Mozambique">Moçambique</option>
<option value="mm" data-alternative-spellings="MM Myanmar Burma">မြန်မာ</option>
<option value="na" data-alternative-spellings="NA Namibia">Namibië</option>
<option value="nr" data-alternative-spellings="NR Naoero">Nauru</option>
<option value="np" data-alternative-spellings="NP Nepal">नेपाल</option>
<option value="nl" data-alternative-spellings="NL Holland Netherlands">Nederland</option>
<option value="nc" data-alternative-spellings="NC New Caledonia">Nouvelle-Calédonie</option>
<option value="nz" data-alternative-spellings="NZ Aotearoa">New Zealand</option>
<option value="ni" data-alternative-spellings="NI">Nicaragua</option>
<option value="ne" data-alternative-spellings="NE Nijar">Niger</option>
<option value="ng" data-alternative-spellings="NG Naigeria Nijeriya">Nigeria</option>
<option value="nu" data-alternative-spellings="NU">Niue</option>
<option value="nf" data-alternative-spellings="NF Norfolk">Norf'k Ailen</option>
<option value="mp" data-alternative-spellings="MP Northern Mariana">Notte Mariånas</option>
<option value="no" data-alternative-spellings="NO Norway Noreg">Norge</option>
<option value="om" data-alternative-spellings="OM Uman Oman">عمان</option>
<option value="pk" data-alternative-spellings="PK">پاکستان / Pakistan</option>
<option value="pw" data-alternative-spellings="PW Palau">Belau</option>
<option value="ps" data-alternative-spellings="PS Palestine">فلسطين</option>
<option value="pa" data-alternative-spellings="PA">Panamá</option>
<option value="pg" data-alternative-spellings="PG">Papua New Guinea</option>
<option value="py" data-alternative-spellings="PY">Paraguay</option>
<option value="pe" data-alternative-spellings="PE Peru">Perú</option>
<option value="ph" data-alternative-spellings="PH Philippines">Pilipinas</option>
<option value="pn" data-alternative-spellings="PN">Pitcairn Islands</option>
<option value="pl" data-alternative-spellings="PL Poland">Polska</option>
<option value="pt" data-alternative-spellings="PT">Portugual</option>
<option value="pr" data-alternative-spellings="PR">Puerto Rico</option>
<option value="qa" data-alternative-spellings="QA Qatar">قطر</option>
<option value="re" data-alternative-spellings="RE Reunion">Réunion</option>
<option value="ro" data-alternative-spellings="RO Romania Rumania Roumania">România</option>
<option value="ru" data-alternative-spellings="RU Rossiya Российская Russia">Россия</option>
<option value="rw" data-alternative-spellings="RW">Rwanda</option>
<option value="bl" data-alternative-spellings="BL St. Barthelemy">Saint Barthélemy</option>
<option value="sh" data-alternative-spellings="SH St.">Saint Helena, Ascension and Tristan da Cunha</option>
<option value="kn" data-alternative-spellings="KN St.">Saint Kitts and Nevis</option>
<option value="lc" data-alternative-spellings="LC St.">Saint Lucia</option>
<option value="mf" data-alternative-spellings="MF St.">Saint-Martin (French)</option>
<option value="pm" data-alternative-spellings="PM St.">Saint-Pierre et Miquelon</option>
<option value="vc" data-alternative-spellings="VC St.">Saint Vincent and the Grenadines</option>
<option value="ws" data-alternative-spellings="WS">Samoa</option>
<option value="sm" data-alternative-spellings="SM RSM Repubblica">San Marino</option>
<option value="st" data-alternative-spellings="ST Sao Tome">São Tomé e Príncipe</option>
<option value="sa" data-alternative-spellings="SA Saudi Arabia">السعودية</option>
<option value="sn" data-alternative-spellings="SN Senegal">Sénégal</option>
<option value="rs" data-alternative-spellings="RS Serbia Srbija">Србија</option>
<option value="sc" data-alternative-spellings="SC Sesel">Seychelles</option>
<option value="sl" data-alternative-spellings="SL">Sierra Leone</option>
<option value="sg" data-alternative-spellings="SG Singapore">சிங்கப்பூர் / குடியரசு / 新加坡共和国</option>
<option value="sx" data-alternative-spellings="SX">Sint Maarten (Dutch)</option>
<option value="sk" data-alternative-spellings="SK">Slovensko</option>
<option value="si" data-alternative-spellings="SI Slovenia">Slovenija</option>
<option value="sb" data-alternative-spellings="SB">Solomon Islands</option>
<option value="so" data-alternative-spellings="SO Somalia Soomaaliya">الصومال</option>
<option value="za" data-alternative-spellings="ZA RSA Suid Afrika">South Africa</option>
<option value="gs" data-alternative-spellings="GS">South Georgia and the South Sandwich Islands</option>
<option value="ss" data-alternative-spellings="SS Kusini Thudän">South Sudan</option>
<option value="es" data-alternative-spellings="ES Spain">España</option>
<option value="lk" data-alternative-spellings="LK Ceylon srilan">ශ්‍රී ලංකා / இலங்கை</option>
<option value="sd" data-alternative-spellings="SD Sudan">السودان</option>
<option value="sr" data-alternative-spellings="SR Sarnam Sranang">Suriname</option>
<option value="sj" data-alternative-spellings="SJ">Svalbard and Jan Mayen</option>
<option value="sz" data-alternative-spellings="SZ Swaziland eSwatini">Eswatini</option>
<option value="se" data-alternative-spellings="SE Sweden">Sverige</option>
<option value="ch" data-alternative-spellings="CH Swiss Switze Svizra">Schweiz / Suisse / Svizzera</option>
<option value="sy" data-alternative-spellings="SY Syria">سورية</option>
<option value="tw" data-alternative-spellings="TW Taiwan">台灣</option>
<option value="tj" data-alternative-spellings="TJ Tajiki Toçiki">Тоҷикистон</option>
<option value="tz" data-alternative-spellings="TZ">Tanzania</option>
<option value="th" data-alternative-spellings="TH Thailand Prath Thai">ประเทศไทย</option>
<option value="tl" data-alternative-spellings="TL">Timor-Leste</option>
<option value="tg" data-alternative-spellings="TG">Togolese</option>
<option value="tk" data-alternative-spellings="TK">Tokelau</option>
<option value="to" data-alternative-spellings="TO">Tonga</option>
<option value="tt" data-alternative-spellings="TT">Trinidad and Tobago</option>
<option value="tn" data-alternative-spellings="TN Tunes تونس">Tunisie / تونس</option>
<option value="tr" data-alternative-spellings="TR Turkey Turkiy">Türkiye</option>
<option value="tm" data-alternative-spellings="TM Turkme">Türkmenistan</option>
<option value="tc" data-alternative-spellings="TC">Turks and Caicos Islands</option>
<option value="tv" data-alternative-spellings="TV">Tuvalu</option>
<option value="ug" data-alternative-spellings="UG">Uganda</option>
<option value="ua" data-alternative-spellings="UA Ukrayina Ukraine">Україна</option>
<option value="ae" data-alternative-spellings="AE UAE United Arab Emirates">الإمارات</option>
<option value="gb" data-alternative-spellings="GB Great Britain England UK Wales Scotlan Northern Ireland" data-relevancy-booster="2">United Kingdom</option>
<option value="us" data-alternative-spellings="US USA United States America" data-relevancy-booster="2">United States</option>
<option value="um" data-alternative-spellings="UM">United States Minor Outlying Islands</option>
<option value="uy" data-alternative-spellings="UY">Uruguay</option>
<option value="uz" data-alternative-spellings="UZ Uzbekistan O'zbek">Oʻzbekiston / Ўзбекистон</option>
<option value="vu" data-alternative-spellings="VU">Vanuatu</option>
<option value="ve" data-alternative-spellings="VE">Venezuela</option>
<option value="vn" data-alternative-spellings="VN Vietnam">Việt Nam</option>
<option value="vg" data-alternative-spellings="VG">British Virgin Islands</option>
<option value="vi" data-alternative-spellings="VI US">U.S. Virgin Islands, U.S.</option>
<option value="wf" data-alternative-spellings="WF">Wallis-et-Futuna</option>
<option value="eh" data-alternative-spellings="EH Western Sahara">لصحراء الغربية</option>
<option value="ye" data-alternative-spellings="YE Yemen">اليمن</option>
<option value="zm" data-alternative-spellings="ZM">Zambia</option>
<option value="zw" data-alternative-spellings="ZW">Zimbabwe</option>
]] -- alt spelling country code must be upper case to avoid match for replace -- TODO: move to an html file
function tag.Countries(attributes,selected)
	-- outputs a countries selector (with names in each country's language, *not* the user's), plus the user's geoip derived country as the default selection at the top of the list, and if different also the site's locale country
	-- not to be used for setting as locale or language, as this lists countries currently with undefined locales and languages -- TODO: add missing locales
	-- uses progressive enhancement based upon https://baymard.com/labs/country-selector to convert the select menu into an auto-complete field
	-- ("name", selected); selected might be specified as the country associated with the user's locale if previously set such as with a cookie in which case, detect=false should also be used to disable the automatic country detection and insertion
	-- {name="name", detect=false, selected=value, unspecified=, …} and other attributes per tag.select
	-- if not using detect and a valid selected or form value are not provided, unspecified=true should be used to preserve the unspecified (nil) value on submission
	-- NOTE: the geo app must be enabled to use geoip deriviation
	if type(attributes) ~='table' then attributes = {name=attributes, selected=selected} end
	AssignTagValue(attributes)
	-- attributes.options = attributes.options or terms.countries -- now using hardcoded list -- TODO: generate with Starter when locales are fully populated with countries (using locale=false)
	attributes.html = attributes.html or html_options
	if attributes.unspecified ==nil then attributes.unspecified = "pleaseselect" end
	attributes.localise = false
	attributes.name = attributes.name or "country"
	kit.Script("moonstalk.kit/jquery.js","moonstalk.kit/jquery-ui.min.js","moonstalk.kit/jquery.select-to-autocomplete.js", [[$('select[name=]]..attributes.name..[[]').selectToAutocomplete({'copy-attributes-to-text-field': false, autoFocus:false, placeholder:"]]..l.specifycountry..[["})]])
	if attributes.value then
		attributes.html = string.gsub(attributes.html, attributes.value..[["]], attributes.value..[["  selected="selected"]]) -- if the value does not match it will simply be added as an additional option unless preserve=false
	elseif request.method =="get" and attributes.detect ~=false then
		if request.client.place and request.client.place.country_code then
			-- this is a country thus we attempt to select the option not insert
			-- table_insert(attributes.insert, {value=request.client.place.country_code, label=vocabulary.en["country_"..request.client.place.country_code]})
			attributes.html = string.gsub(attributes.html, request.client.place.country_code..[["]], request.client.place.country_code..[["  selected="selected"]])
		end
		if not request.client.place or request.client.place.country_code ~=site.locale and #site.locale ==2 then
			attributes.insert = attributes.insert or {}
			table_insert(attributes.insert, {value=site.locale, label=l["country_"..site.locale]})
		end
	end
	attributes.detect = nil
	tag.select(attributes)
end end

function tag.time(datetime,default)
	-- outputs an HTML 5 time tag with UTC reftime attribute, and interprets this client-side adding a localised relative value (provided by kit.js via kit.Editor); outputs a default display value (in site localtime) which depending upon client side re-rendering time may be undesireable in which case an alternate default may be provided such as simpyl an empty string thus resulting in the text growing once rewritten client-side
	return table.concat{[[<time datetime="]], os.date("!%F %T",datetime), [[">]], default or format.Date(datetime,"short"), [[</time>]]}
end
end


function Head(tag)
	_G.page._kit_head = page._kit_head or {} -- we use the page table rather than a local as it gets reset with each request
	table_insert(page._kit_head,tag)
end

function reader(data,view)
	-- parses and changes views upon loading
	local change,count = {},0
	if view.type =="html" and logging < 4 then
		-- minimise size (a little) by removing tabs and single-line comments (also effectively makes html comment tags private without needing Lua long-comment syntax)
		data = string.gsub(data,"\t","")
		data = string.gsub(data,"<!%-%-[^\n]-%-%->","")
	end
	if node.base and view.type =="html" then -- node.base = "/directory/" -- TODO; support app.base
		-- we change relative attribute paths to use the specified base; must not change src beginning with http or / so we have to check each match
		-- a src that starts ] is actually the beginning of an embedded write and must be ignored i.e. src="?(myvar)"
		for src in string.gmatch(data, [[src="([^%]/].-)"]]) do
			if string.sub(src,1,4) ~="http" then
				change[src] = [[="]]..node.base..src..[["]]
				count = count + 1
			end
		end
		for link in string.gmatch(data, [[<link(.-)>]]) do
			if string.find(link,"stylesheet",1,true) then
				link = string.match(link, [[href="([^%]/].-)"]])
				if link and string.sub(link,1,4) ~="http" then
					change[link] = [[="]]..node.base..link..[["]]
					count = count + 1
				end
			end
		end
		if count >0 then
			data = string.sub(data, [[="([^%]/].-)"]], change)
			log.Info("  changed base of "..count.." relative paths")
		end
	end
	return data
end

function Editor ()
	if page.type ~="html" then return end
	-- # Meta tags
	if not page.title and page.vocabulary then page.title = page.vocabulary[page.language or client.language].title end

	-- # Scripts
	-- the following scripts are loaded before all others, but in reverse order so that the last of these is actually first
	local script = {'<script>\n'}

	-- # JavaScript Environment
	-- TODO: this should be suppressed for AJAX requests (using a POST param or address.ajax=true)

	table_insert(script, "var client=")
	table_insert(script, json.encode{
		locale = request.client.locale,
		language = request.client.language,
	})
	table_insert(script, '\n')

	if user and user.javascript then
		table_insert(script, "var user=")
		table_insert(script, json.encode(user.javascript))
		table_insert(script, '\n')
	else
		-- we always declare this to avoid the need to use if(window.user) due to otherwise being undefined
		table_insert(script, "var user=null\n")
	end

	if page.javascript then
		table_insert(script, "var page=")
		local page_js = page.javascript
		page_js.flags = {}
		if _G.page._validation then
			local jsflags=page_js.flags; local copyfields=util.copyfields
			for _,validation in ipairs(_G.page._validation) do
				local jsval =  copyfields(validation,nil,"1","validate","arg","optional","default","error","valid") -- we don't copy validated_class as we generally want the status to be updated from default
				if jsvalidate[validation.validate] then copy(jsvalidate[validation.validate],jsval,true,false) end
				jsflags[validation[1]] = jsval
			end
		end
		page_js.validated = page.validated
		page_js.focusfield = page.focusfield
		table_insert(script, json.encode(page_js))
		table_insert(script, '\n')
	end
	-- # Conditional JavaScript

	if page.javascript_loader then
		-- enable async loader using minified version of below function
		local funcs = page.javascript_loader.funcs
		page.javascript_loader.funcs=nil; page.javascript_loader.count=nil
		table_insert(script,"var loader=")
		table_insert(script,json.encode(page.javascript_loader))
		table_insert(script,"\n")
		for i=0,#funcs do -- must be named with a zero-based index for client side js
			table_insert(script,"loader["..(i))
			table_insert(script,"]=()=>{"..funcs[i])
			table_insert(script,"}\n")
		end
		table_insert(script,[=[for(let e in loader.s){let o=document.createElement("script");o.onload=(()=>{loader.Check(e)}),o.src=e,document.head.appendChild(o)}loader.Check=function(e){loader.s[e].forEach(e=>{let o=loader.c[e];o[0]++,o[0]==o[1]&&loader[e]()})};]=])

		--[=[this function simply iterates all associated chains (loader.c) by their array position for a given script src (loader.s) that has finished loading, checking the count of scripts loaded for that chain, running the handler if all are loaded; this is both efficient and fairly compact minified
		script.onload=function(){loader.Check(src)}

			var loader = {c:{{scripts_loaded,script_count},…},s={src={chain_id,…}}}

			for(let src in loader.s){
				let script=document.createElement('script')
				script.onload=()=>{
						loader[src.match(/([^\.\/]+)[^/]+$/)[1]]=true // DISABLED: allows introspection
						loader.Check(src)
				}
				script.src=src
				document.head.appendChild(script)
			}
			loader.Check=function(src){
				loader.s[src].forEach(id=>{
					let chain = loader.c[id]
					chain[0]++; if(chain[0]==chain[1]){loader[id]()}
				})
			}

		--]=]

	end
	if script[2] then
		table_insert(script, '\n</script></head>')
		_G.output = string_gsub(_G.output, [[</head>]], table.concat(script), 1)
	end

	-- # Head
	if page._kit_head and page._kit_head[1] then
		local head = {}
		for _,tag in ipairs(page._kit_head) do
			table_insert(head,tag)
			table_insert(head,"\n")
		end
		table_insert(head,"</head>")
		_G.output = string_gsub(_G.output, [[</head>]], table_concat(head), 1)
	end

end

do local vocab_js = {fr="fr",en="en"} -- TODO: this is a hack to select one of the hardcoded vocab files we have, and must be replaced when we support dynamic js vocabularies
function VocabPath() return "/moonstalk.kit/public/vocab."..( vocab_js[page.language] or 'en' )..".js" end
end
function Script(...)
	-- facilitates use of javascript dependancies in pages; call for each javascript chain to be created, or for any standalone javacsript to be included in the chain
	-- initial arguments are the paths or URLs to javascript files
	-- the final argument MUST be inline code (as a string) such as a call to a function, that will be executed once all its dependant files in the initial arguments have loaded
	-- files are generally loaded starting with the first declared by any call to this function, and limited by the browser's max connections per host [e.g. 6]
	-- NOTE: browsers will generally process async script tags before those using this loader, therefore to avoid this and include an arbitrary file in the loader sequence, it is not necessary to have a chain, and can be used for a single file e.g. kit.Script("path/to/file.js","return"); return in this case assumes the file instantiates itself using inline code, rather than requiring a function call
	-- WARNING: javascript files cannot be dependant upon each other with inline code that references functions of other files in the chain; they should be modular and standalone with only the final function call being dependant; each file is run once it has been downloaded by the browser asynchronously; should synchronous loads be required due to having inline code they should be declared using script tags manually to employ the browser's default synchonous blocking behaviour
	-- NOTE: to assign a var in javascript simply assign a value to page.javascript.varname and access it client-side as page.varname; HOWEVER if the value is not dynamic, it is preferable to statically add it in a script tag to reduce server processing
	-- NOTE: if loading json data, it is advisable to start this with an inline script declared at the top thus commencing before scripts declared by this function, increasing the liklihood of timely completion
	-- NOTE: if the final function for a chain needs to call dependent functions defined inline in the page, be sure to place the script tag that defines them early in the HTML, else when cached the chain may execute before the inline functions become defined (e.g. if the script tag is at the body end)
	-- NOTE: when using this function, the variable loader is a reserved name in the global scope
	-- instantiated by a compact client-side async script loader function that will be included; see Editor for implementation
	-- DISABLED: loader[file] provides a map for introspection using a regexp on the original src for just the filename part preceeeding any extension e.g. /path/to/filename.min.js can be checked as if(loader.filename)
	-- whilst the size of the loader chains declaration and script is not entirely insignificant, given the size of several static script tags inline, it is sufficiently insignificant to not be notable in most circumstances
	-- this function is most beneficial where a variety of pages use some but not all scripts having moderate or larger sizes or must be selected dynamically; where sizes are smaller it is preferable to package them together into a single file
	-- script packagaing/concatenation should be automated or performed manually per page and site requirements; if you have two libraries that are needed before a script on every page, it makes sense to combine them and manually add a script tag for that with its dependant invocation, though worth noting that if the scripts are on different domains and of moderate or larger size, they should load faster using this function, similarly if some larger libraries are used on some pages and not others, it is more desireable to only load those required for that page, in which case this function is beneficial
	-- if a vocabularly file is required, it may be included using kit.VocabPath() as one of the arguments if it should match the user or browser dervived preferences, else may of course be manually specified
	-- if you absolutely must dynamically create a script tag use kit.Head[[<script>…</script>]]
	-- chains are deconsructed into loader.s for each source file and the chains that depend upon it, plus loader.c for giving the final functions for each chain
	page.javascript_loader = page.javascript_loader or {count=-1,funcs={},s={},c={}} -- chain id count must start from 0 for clientside js compatability
	local config = page.javascript_loader
	config.count = config.count +1
	local chain = pack(...)
	local length = #chain -1 -- exclude the function
	config.c[config.count+1] = {0,length} -- [loaded,target] to be matched before running the function; position must start from 1 in Lua to be 0 in JS, else the encoder will make a dictionary instead of an array
	config.funcs[config.count] = chain[length+1]
	for i=1,length do
		local src = chain[i]
		local chains = config.s[src]
		if not chains then
			chains = {} -- [chain_id,…]
			config.s[src] = chains
		end
		table_insert(chains, config.count)
	end
end
function EnableJS(library)
	-- this is a convenience function to enable client-side kit features; options may be declared in page.javascript
	-- library should be a full path or URL to jquery, else defaults to the bundled cash.js which is lightweight dropin for jQuery using the MIT licence https://github.com/fabiospampinato/cash
	kit.Script(library or "/moonstalk.kit/public/cash.js","/moonstalk.kit/public/kit.js", kit.VocabPath(), "moonstalk_Kit.Initialise()") -- TODO: namespace the js functions
end

-- # Concordance functionality

local function ConcordanceClerkHandler(record)
	-- this copies values from changes (form input) to the record using change formatting handlers, and sets finalised if the save validation handlers all pass
	local metaindex = getmetatable(record).__index
	local valid = true
	if metaindex._validated ==true and metaindex.finalise then
			log.Info "  Clerk: cleaning validated record for finalise"
			-- remove empty tables; this is necessary to at least remove unused namespace declarations before saving, but is also a convenience to avoid managing empty tables manually
			local function clear(table)
				for key,value in pairs(table) do
					if type(value)=="table" then
						clear(value)
						if not next(value) then table[key] = nil end
					end
				end
			end
			clear(record)
	elseif metaindex._validated ~=nil then
		log.Info "  Clerk: aready validated "
		valid = metaindex._validated
	elseif record.finalise then
		metaindex._validated = false
		log.Info("  Handling changes for concordance '"..record._concordance.."'")
		local env = {[record._concordance]=record, changes=record._changes}
		setmetatable(env, {__index=_G})
		local util_TablePath = util.TablePath
		local util_TablePathAssign = util.TablePathAssign
		local table_insert = table.insert
		local table_remove = table.remove
		local type = type
		-- handle deletions, and array[0]
		local string_find = string.find
		local string_match = string.match
		local concordance = record._concordance
		local position = #record._concordance

		-- copy form input to record; we do deletions and handlers next
		copy(record._changes, record)
		--util.CopyReplaceArrays(record._changes, record) -- the copy function does a recursive merge, but we must replace arrays to avoid reordered array items from different positions being merged

		-- tidy up the form input that was copied to remove empty string values (explicit deletions), and record them for later reapplication in reset arrays
		-- NOTE: this actually breaks the ability to use an input other than the form, therefore this is form specific handling
		local deleted = {}
		local root
		for namespace,value in pairs(request.post) do
			if value =="" then
				namespace = util.StringNamespace(string.match(namespace,"^.-%.(.*)")) -- drop the name prefix
				util_TablePathAssign(record,namespace,nil)
				util_TablePathAssign(deleted,namespace,true)
			end
		end
		log.Info("Deletions from input:")
		log.Info(deleted)

		-- meld arrays based on original locations
		-- clear all arrays in the record (any table having a key 1) so they can be correctly repopulated with updated data (merging as performed by the prior copy command wouldn't work in the case of reordering and deletions)
		local function clear(subtable)
			for key,value in pairs(subtable) do
				if type(value) =="table" then
					if value[1] then
						subtable[key] = {}
					else
						-- recurse
						clear(value)
					end
				end
			end
		end
		clear(record)
		-- now we look for arrays from the input (form) to repopulate the record with
		local namespace
		local function populate(changed,original,deleted,namespace)
			-- this is a recursive function that looks for array items in the input (any table with the key ._array), then if it contains non-table values, replaces the entire array in the original, or if containing table-items, deletes items no longer in the input (which must include at least an _origin key) from the original and merges the contents of modified ones with the original (also adding new items)
			for key,value in pairs(changed) do
				if type(value) =="table" then
					table_insert(namespace,key)
					if value._array then
						value._array = nil  -- an array table from input is given this private flag to identify its behaviour and must be removed
						value[0] = nil -- remove the zero-index item which is only a placeholder
						if not value[1] then -- an empty array
							-- delete the empty table; this wasn't done by clear() because it still had a an _array flag and 0-item
							util_TablePathAssign(record,namespace,nil)
						else -- not an empty array
							if type(value[1]) ~="table" then
								-- an array of non-table values; simply replace entirely to ensure correct ordering
								util_TablePathAssign(record,namespace,value)
							else
								-- an array of table items, we iterate them and merge with its original if existing
								for index,item in ipairs(value) do
									if item._origin then
										-- an item that previously existed, thus we must merge it with its original which is defined by the _origin key from input
										table_insert(namespace,tonumber(item._origin))
										item._origin = nil -- must remove this private flag
										local original = util_TablePath(record._original,namespace)
										-- we must however also remove explicit deletions from the original so as not to copy them into the new item
										local function delete(these,outof) if not these or not outof then return end for name,this in pairs(these) do if this==true then outof[name] = nil else delete(these[name],outof[name]) end end end
										delete(util_TablePath(deleted,{key,index}),original)
										copy(original, item, false, true) -- preserve original unchanged values by copying from the original into the input item, and without replacing the changed values
										table_remove(namespace,#namespace)
									-- else a new item to assign, no manipulation required
									end
									table_insert(namespace,index)
									util_TablePathAssign(record,namespace,item)
									table_remove(namespace,#namespace)
								end
							end
						end
					else
						-- recurse this table to check if there's a deeper array
						populate(value, original[key], deleted, namespace)
					end
					table_remove(namespace,#namespace)
				end
			end
		end
		populate(record._changes, record._original, deleted, {})
		-- run form-input handlers; these assign their values directly to record, allowing direct replacement of those even if already changed from input, unless a second error parameter (either a string message, or true) is returned which causes validation to fail (per tag.Error)
		local pcall = pcall
		local value,result
		local tag_ValidateTag = tag.ValidateTag
		local function RunHandlers(namespace,handlers)
			env.original = util_TablePath(record._original, namespace)
			env.changed = util_TablePath(record._changes, namespace)
			value = env.changed
			for _,Change_Handler in ipairs(handlers) do
				log.Info("  Running handler ".._.." for "..namespace.." with value "..tostring(value))
				if Change_Handler ==tag_ValidateTag then
					result,err = tag_ValidateTag(handlers.arg) -- validation only, does not provide value manipulation
					if not result then
						valid = false
						tag.Error(record._concordance.."."..namespace)
						log.Info("Change validation failed for "..record._concordance.."."..namespace)
						break
					end
				else
					if Change_Handler ~=tonumber then setfenv(Change_Handler,env) end
					result,value,err = pcall(Change_Handler, value, handlers.arg or handlers.default)
					if not result then
						valid = false
						scribe.Error{title="Error calling change handler for "..record._concordance.."."..namespace, detail=string.match(value,".*:(.*)")}
						return
					elseif err then
						valid = false
						tag.Error(record._concordance.."."..namespace, err)
						log.Info("Change handler failed for "..record._concordance.."."..namespace)
						break
					else
						-- success so update the value
						util_TablePathAssign(env.record,namespace,value)
					end
				end
			end
			if not handlers[1] and not value then
				util_TablePathAssign(env.record,namespace,handlers.default) -- we only use the default it it was not given to a handler
			end
			return true
		end
		for namespace,handlers in pairs(record._change_handlers) do
			if string.sub(namespace,-1) =="*" then
				namespace = util.StringNamespace(string.sub(namespace,1,-3))
				for name,value in pairs(util_TablePath(record._changes, namespace) or {}) do
					table.insert(namespace,name)
					if not RunHandlers(util.NamespaceString(namespace),handlers) then return end -- a handler is broken, abandon to error page
					table.remove(namespace,#namespace)
				end
			else
				RunHandlers(namespace,handlers)
			end
		end
		metaindex._validated = valid
	end
	if record._deferfinalise ==true then
		-- the operation must be cancelled as it has been deferred (e.g. for delete confirmation, or because we're only doing a validation check); other handlers will run and record.finalised is set to false
		log.Info("  Clerk: finalisation deferred")
		return false
	end
	log.Info("  Clerk: validated "..tostring(valid))
	return valid
-- else we do nothing post-finalisation as view_handlers are run from ViewConcordance
end

local function FinaliseConcordance(record,criteria)
	-- TODO: handle criteria
	-- this causes the ConcordanceClerkHandler and any other clerk handlers to be run, and if finalised the record operation to be carried out (by teller.Clerk)
	-- this is either automatically run upon concordance creation, or manually afterwards (e.g. after formatter assignments) by calling record:Finalise()
	if request.form.token then
		-- finalisation is only required if we have an authenticated action
		criteria = criteria or {}
		local metaindex = getmetatable(record).__index
		if metaindex._clerks[1] ~= ConcordanceClerkHandler then
			table.insert(metaindex._clerks, 1, ConcordanceClerkHandler)
		end
		if criteria.namespace then
			copy(criteria.namespace,record,false,true)
			copy(criteria.namespace,metaindex._changes,false,true)
			copy(criteria.namespace,metaindex._original,false,true)
		end
		criteria.operation = metaindex.operation
		log.Info("  Finalising concordance for "..metaindex.operation.." with "..#record._clerks.." clerks")
		teller.FinaliseClerk(record,criteria) -- true if no clerk failed (i.e. validation succeeded)
		if metaindex.finalised and metaindex.operation == "delete" then metaindex.operation = "deleted" end
		return metaindex.finalised
	else
		tag.Validate() -- support generic tag validation upon creation
		return nil
	end
end
local function ValidateConcordance(record,criteria)
	if page.error then return end
	local metaindex = getmetatable(record).__index
	metaindex._deferfinalise = true -- flag for our clerk handler to prevent record operation from completing as we're only validating (running the change handlers)
	FinaliseConcordance(record,criteria)
	metaindex._deferfinalise = nil -- with next call we will want to complete the operation
	return metaindex._validated
end

local function AssignConcordanceHandler(handlers, name, handler)
	if empty(handler) then return end
	handlers[name] = handlers[name] or {}
	for _,value in ipairs(handler) do
		if type(value) =="function" then
			table.insert(handlers[name], value)
		elseif type(value) =="table" then
			handlers[name].arg = value
		else
			handlers[name].default = value
		end
	end
end
local function AssignConcordanceViewHandler(record, name, ...)
	AssignConcordanceHandler(record._view_handlers, name, arg)
end
local function AssignConcordanceChangeHandler(record, name, ...)
	if type(arg[1]) =="table" then
		-- use tag Validation
		local name = record._concordance .."."..name
		table_insert(arg[1],1,name)
		tag.Validation(arg[1])
		arg = {tag.ValidateTag, arg[1]}
	end
	AssignConcordanceHandler(record._change_handlers, name, arg)
end

local function ViewConcordance(name)
	-- called before attempting to use any concordance value in a view; performs a merge of changes and original using view_formatters
	-- returns the concordance used in a controller so that it may be used in a view without specifically knowing where it was assigned; should be assigned to a suitably named local
	name = name or "record"
	local record = temp.concordances[name]
	-- action is the flag used in a form that changes the intent from prepare to finalise for the CRUD operation upon submission of the user input; consumed in kit.Clerk and then teller.Clerk
	local metaindex = getmetatable(record).__index
	if metaindex.operation =="create" then
		metaindex.action = "create_record"
		metaindex.action_token = util.Encrypt(now+user.id)
	elseif metaindex.operation =="update" then
		metaindex.action = "update_record"
		metaindex.action_token = util.EncodeID(record.id)
	elseif metaindex.operation =="delete" then
		metaindex.action = "delete_record"
		metaindex.action_token = util.EncodeID(record.id)
	end
	log.Info("Preparing concordance '"..name.."' for view with action "..metaindex.action)
	-- apply display handlers
	local util_TablePathAssign = util.TablePathAssign
	local value
	local function RunHandlers(namespace,handlers)
		value = util_TablePath(record,namespace)
		for _,View_Handler in ipairs(handlers) do
			log.Info("  Running handler ".._.." for "..namespace.." with value "..util.Serialise(value))
			value = View_Handler(value or handlers.default)
		end
		if not handlers[1] and not value then value = handlers.default end -- we only use the default if it was not given to a handler
		util_TablePathAssign(record,namespace,value)
	end
	for namespace,handlers in pairs(record._view_handlers) do
		if string.sub(namespace,-1) =="*" then
			namespace = util.StringNamespace(string.sub(namespace,1,-3))
			for name,value in pairs(util_TablePath(record, namespace) or {}) do
				table.insert(namespace,name)
				RunHandlers(util.NamespaceString(namespace),handlers)
				table.remove(namespace,#namespace)
			end
		else
			RunHandlers(namespace,handlers)
		end
	end
	return record
end

function Concordance(criteria)
	-- encapsulates teller.Clerk's record functionality (whilst also handling deletions) but enhances the record as a 'concordance' table handling the merging of original values and changed values; typically used with user input from a form that is to be updated in a record, with optional value manipulation and validation
	-- input is *merged* with the original record, unless A. the input is an empty string "" in which case it is removed from the original (an explicit deletion) or B. it is an array of tables in which case the each array item is merged and the array itself will be updated for removals -- TODO: add a complete=true criteria that also deletes such values that are missing from input, or C. an array of non-table values which is replaced in its entirety
	-- WARNING: arrays MUST be identified in form input by the presence of a array._array=1 field and each existing item in an array that is a table MUST have a corresponding arrayname.n._origin field with its value being the item's original position; this is done automatically by the TableItems and FileItems functions; failure to include these in a form used with a concordance will result in data being mixed up across the array table items if they are reordered or removed; note also that mixed arrays (containing both table and non-table values) are not supported
	-- the returned concordance record functions the same as a teller.Clerk record but with additional properties and an additional :Finalise method that should be used in place of either :Save or :Delete
	-- no operation is carried out until :Finalise is called on the returned record
	-- to output values in a view the view must contain <? local concordance = kit.Concordance() ?>
	-- does not support * as a key name, as this is a wildcard indicator
	-- handlers are given an environment with original, changed, [name] (the record), changes (i.e. request.form[name]), and passed value which is the result of the prior handler or changes[path] or default
	-- handlers always return a new value to be used (either in the record after a change, or in the view; change handlers may optionally pass a second message or true param to invoke an error; note that most generic functions do not do this if there is invalid input and thus the user will not be informed if their input is invalid, only the validate.* functions currently handle these scenarios -- TODO: this will be fixed using a complete namespace table
	-- NOTE: the existence of a table in _original does not indicate its prior existence, as in the Teller, empty tables are ignored, therefore always use empty() for checks

	if type(criteria) ~="table" then return ViewConcordance(criteria) end

	local finalise = true
	if criteria.finalise ~=true then finalise = false end -- inverted behaviour compared to Clerk which does not finalise by default
	criteria.finalise = false -- for the Clerk call; we call :Finalise() later
	local record = teller.Clerk(criteria)
	if not record then return end

	local meta = getmetatable(record)
	local metaindex = meta.__index
	metaindex._concordance = criteria.name or metaindex._concordance or "record" -- the name of this concordance
	log.Info("Creating concordance '"..metaindex._concordance.."'")
	-- ascertain and define the record operation based on form action
	if request.form.token then
		-- we only carry out actions with a valid token to mitigate some possible hijacking or bad refreshes
		if request.form.action.delete_record then
			if util.DecodeID(request.form.token) ==record.id then
				metaindex.operation = "delete"
				finalise = true
			else
				scribe.Error{title="Invalid concordance action token"}
			end
		elseif request.form.action.update_record then
			if util.DecodeID(request.form.token) ==record.id then
				metaindex.operation = "update"
			else
				scribe.Error{title="Invalid concordance action token"}
			end
		elseif request.form.action.create_record then
			if now+7200 > util.Decrypt(request.form.token)-user.id then -- 2h to submit (nothing is lost as the view will simply return to create)
				metaindex.operation = "create"
			else
				-- TODO: report error if timeout/failed
				log.Notice "Concordance action token expired"
			end
		else
			request.form.token = nil -- cancels finalisation
		end
	elseif request.form.action.delete_record or request.query==L.delete_record then
		metaindex.operation = "delete"
		scribe.Abandon "manager/admin-delete" -- this can be changed by a clerk also using scribe.Abandon
		metaindex._deferfinalise = true -- this is a flag to the ClerkHandler to cancel the record operation for now
	-- all other cases will use teller.Clerk, defaulting to a non-finalised operation
	end

	metaindex._changes = criteria.form or request.form[metaindex._concordance] -- input if any
	metaindex._original = metaindex._original or {} -- record for comparisons, not used by create
	metaindex._view_handlers = {}
	metaindex._change_handlers = {}
	metaindex.View = AssignConcordanceViewHandler
	metaindex.Change = AssignConcordanceChangeHandler
	metaindex.Validated = ValidateConcordance
	metaindex.Finalise = FinaliseConcordance -- replace teller's
	if criteria.namespace then
		copy(criteria.namespace,record,false,true)
		copy(criteria.namespace,metaindex._changes,false,true)
		copy(criteria.namespace,metaindex._original,false,true)
	end

	if finalise then
		FinaliseConcordance(record)
	end

	_G.temp.concordances = temp.concordances or {}
	_G.temp.concordances[metaindex._concordance] = record -- temporary storage for later assignment in a view by ViewConcordance()
	return record
end

-- # Validate functions
_G.validate = {invalid="\0"}
_G.jsvalidate = {}
-- when used with a concordance:Change definition these functions must be called  using required.* or optional.* and not directly, else they may be called directly considering that their return values vary
-- these validation functions receive whatever value was received (which may be nil, a number or a string) plus the supplementary validation arguments, and return their validated value (which may be nil or false) or validate.invalid to generate a validation error; if validation.normalise is specified the returned value will be made available for persistence as .returned but will not propogate back to the form
-- if kit.jsvalidate.ValidateFunc is declared as a table, it's contents will be used instead of the declared validation options client side
function validate.Checkbox(value,arg)
	-- must use validation.optional=true
	-- arg=nil; returns true/nil; default is nil
	-- arg={checked=1,unchecked=0}; returns 1 or 0
	-- NOTE: cannot use false as a value because this indicates validation failure
	if not arg and value then return true
	elseif not arg and not value then return nil
	elseif value then
		return arg.checked
	else
		return arg.unchecked
	end
end
function validate.HTML(value)
	-- this does some HTML cleanup
	-- TODO: make safe (remove js, rel, hijacks etc.)
	-- TODO: remove empty tags
	value = string.gsub(value,[[ class="Apple%-[^-]-%-span"]],"") -- this apparently redundant class is added to rich text editor fields in webkit browsers
	return value or validate.invalid
end
function validate.Lua(value)
	value = loadstring("return "..value)
	setfenv(value, {}) -- sandboxed
	return value() or validate.invalid
end
function validate.LuaTable(value)
	value = loadstring("return "..value)
	setfenv(value, {}) -- sandboxed
	value = value()
	if type(value) =="table" then return value or validate.invalid end
end

do local terms_e164 = terms.e164
function validate.TelephoneCountry(value)
	-- check if a given number has a country prefix and returns that and the country code
	-- value must be string
	local match = terms_e164[string_sub(value,1,2)]
	if match then return match.code, match[1] end
	match = terms_e164[string_sub(value,1,4)]
	if match then return match.code, match[1] end
	match = terms_e164[string_sub(value,1,3)]
	if match then return match.code, match[1] end
	match = terms_e164[string_sub(value,1,1)]
	if match then return match.code, match[1] end
	return validate.invalid
end end

function validate.Telephone(value,arg)
	-- TODO: normalised value is e164.number as a string and is clearly identifed by the period versus user-input which might be +number
	-- will not work in countries where only one period is used in formatting a number
	-- denormalisation is simple as the country-dot prefix can be removed and replaced with the local trunk access code (e.g. 0) or prefixed with + and the period replaced with a half-space without needing to identify the country code which has a variable length (1–3)
	-- TODO: arg.allow and arg.disallow (e164 codes)
	-- does not accept country prefix without +; numbers with + will be normalised to arg.locale.e164 or locale.e164
	-- also see util.NormaliseTel which stores and accepts a non-delimited number with a default country code
	if not value then return validate.invalid end
	value = tostring(value)

	local country
	if string_sub(value,1,1) =="+" then
		value = string_sub(value,2)
		country = validate.TelephoneCountry(value)
		if country==validate.invalid then return country end
		value = string_sub(value,#country+1)
	else
		local periods = string_gmatch(value,"%.")
		if periods() and not periods() then -- only 1
			local potential_value
			country,potential_value = string_match(value,"([%d]+)%.(.+)")
			if terms.e164[country] then
				value = potential_value
			else return validate.invalid end -- we're assuming a single period with an unknown country code is an invalid format
		-- else has multiple periods
		end
	end
	value = string.gsub(value,"%D","") -- remove all non-digit and formatting except those allowed
	if not country and string_sub(value,1,2) =="00" then
		value = string_sub(value,3)
		country = validate.TelephoneCountry(value)
		if not country then return validate.invalid end
		value = string_sub(value,#country+1)
	elseif not country and string_sub(value,1,1) =="0" then -- TODO: only if locale has trunk access code
		value = string_sub(value,2)
	end
	if #value >16 then return validate.invalid end -- TODO lookup min length from country prefix, currently only has cell lengths
	-- TODO: denormalise function that removes the country prefix and adds national trunk access code (e.g. 0) if same locale, else simply +; also local number formatting e.g. groups of two digits in france, three digit code plus dashes in NA
	local arg_locale = locale
	if arg and arg.locale then arg_locale = arg.locale end
	return (country or arg_locale.e164).."."..value
end
validate.Mobile = validate.Telephone -- TODO: use mobile prefix if available
jsvalidate.Telephone = {validate="Length",arg={min=8}}-- TODO: as js with allowed country prefixes

-- # Validation handlers
-- the following may be used generically but are intended for use when assigned with tag.Validation{validate="Length",arg=4} or concordance:Change("field",{validate="Length",arg=4}) and should have correspondingly named javascript functions for client-side validation
-- returns validate.invalid if not validated otherwise the validated/normalised/coerced value (which may be nil)
-- to check for an invalid result you must use: if validate.Type(value) ~= validate.invalid
-- when assigned with concordance:Change these functions have no access to the changed and original values
function validate.Date(value,arg)
	-- returns a YYYYMMDD date string; expects either a YYYY-MM-DD formatted date from a date input, or a free-text user-input date string; for which the arg.locale=(string id) hint or _G.locale is used to determine how to parse user-input values
	-- TODO: support min/max dates
	if not value then return validate.invalid end
	value = tostring(value) -- unlikely but may have been transformed to a number
	local year,month,day = string.match(value,("^(%d%d%d%d)-(%d%d)-(%d%d)$"))
	if year and month and day then return year..month..day end
	arg = arg or {}
	local date,guessed = util.GetDate(value, locales[arg.locale] or _G.locale, true)
	if not date or #tostring(date.year)~=4 or guessed then return validate.invalid end
	return date.year..util.Pad(date.month,2,"0")..util.Pad(date.day,2,"0")
end
function validate.Number(value,arg)
	-- arg.min and/or arg.max = number;
	-- arg.decimals = number; default=2; max decimal places (if any)
	-- TODO: arg.localise = true; default=false; true allows thousand seperator; the default behaviour is to accept either period or comma for decimals
	-- does not assume
	if not value then return validate.invalid
	elseif not arg then arg = {} end
	arg.decimals = arg.decimals or 2
	value = tostring(value)
	if arg.localise ==true then
		value = util.GetNumber(value) -- uses locale to parse decimals
		if not value then return validate.invalid end
	end
	local int,sep,dec = string.match(value,"([%d]+)()[,%.]?([%d]*)")
	if dec=="" and sep == #value +1 then value = tonumber(int) -- no sep, decimals are always optional
	elseif dec and sep == #value -arg.decimals then value = tonumber(int.."."..dec)
	else return validate.invalid end
	if (arg.min and value <arg.min) or (arg.max and value >arg.max) then return validate.invalid end
	return value
end
function validate.Digits(value,arg)
	-- extracts valid digits from the value ignoring all other characters, but assuming the extra characters account for less than 60% the number of digits (i.e. 12-34-56 is okay, but 1-2-3-4 is not); accepts arg.min and arg.max for length (not value)
	-- returns a string to preserve leading zeros
	arg = arg or {}
	if not value then return validate.invalid end
	local digits = {}
	for digit in string.gmatch(tostring(value),"%d+") do table.insert(digits,digit) end
	digits = table.concat(digits)
	if (#tostring(value) -#digits >(#digits/100*(arg.ratio or 60)))
	or (arg.max and #digits >arg.max)
	or (arg.min and #digits <arg.min)
	then return validate.invalid end
	return digits
end
function validate.Length(value, arg)
	-- arg.number={min=1,max=99} or arg.number=true will also validate that the value is a number which is beneficial for validating zero-padded values that can't be evaluated just by value but must be validated as both numbers and by length
	-- lines=false to reject, ="; " to replace (empty string also) or =true to normalise from CRLF
	if not value then return validate.invalid end
	arg = arg or {min=1}
	if arg.number then
		if arg.number ==true then arg.number=nil end
		if not validate.Number(value, arg.number) then return validate.invalid end
	end
	value = tostring(value)
	if arg.lines then
		if arg.lines ==true then value=string.gsub(value,"\r\n","\n") -- normalise
		elseif arg.lines ==false and string.find(value,"\r",1,true) then return validate.invalid
		else value = string.gsub(value,"\r\n",arg.lines)
		end
	end
	if #value <arg.min or (arg.max and #value >arg.max) then return validate.invalid end
	return value
end
function validate.Option(value,options)
	-- requires the value to be an enum in an options table
	-- typically used with tag.select, however will not include insert and append values!
	if not options then scribe.Error"Missing options for validate.Option"; return validate.invalid
	elseif not value or not options[value] then return validate.invalid end
	return value
end
jsvalidate.Option ={validate="Length",arg={min=1,max=20}} -- the arg table is not appropriate for json
function validate.Email(value)
	if not value or #value > 64 then return validate.invalid end
	return string_match(string.lower(value), "([^%s]+@..+%.[%w%.]+)") or validate.invalid -- can't be too strict with email matches even a single emoji is a valid domain
end
function validate.IBAN(iban,arg)
	-- arg.countries = an optional keyed table of country_codes (two char lower case)
	-- arg.country = single country_code
	if not iban then return validate.invalid end
	iban = string.upper(iban:gsub("%s","")) -- remove spaces
	local country = string.lower(string.sub(iban,1,2))
	if arg then
		if arg.country then arg.countries = {[string.lower(arg.country)]=true} end
		if arg.countries and not arg.countries[country] then return validate.invalid end
	end
	local country = locales[country]
	if not country or not country.iban or #iban~=country.iban.length or iban:match("[^%d%u]") then return validate.invalid end
	local mod=0
	local rotated=iban:sub(5)..iban:sub(1,4)
	for c in rotated:gmatch(".") do
		mod=(mod..tonumber(c,36)) % 97
	end
	if mod~=1 then return validate.invalid end
	return iban
end
jsvalidate.IBAN = {validate="Length",arg={min=12}}-- TODO: as js with allowed country prefixes
function validate.Twitter(url)
	-- accepts any of URL, domain+path, @username or username
	if not url then return validate.invalid end
	if string.find(url,"twitter.com/",1,true) then
		url = string.match(request.form.twitter,"twitter%.com/(%w)/?")
	elseif string.sub(url,1,1)=="@" then
		url = string.sub(request.form.twitter,2)
	end
	if string.match(url,"[^%a%d_]") then return validate.invalid end -- only letters, numbers and underscore allowed
	return url
end
jsvalidate.Twitter = {validate="Length",arg={min=4}}
function validate.URLPath(url,arg)
	-- returns only the path component of a URL, domain+path or path alone
	-- arg may specify domain to aid parsing, however it is not required to be present and if not found will still validate
	if not url then return validate.invalid end
	if string.find(url,"//",1,true) then url = string.match(url,"//([^%?#]+)") end
	if arg and arg.domain and string.find(url,arg.domain,1,true) then url = string.match(url,arg.domain.."/([^%?#]+)") end
	if string.sub(url,1,1) =="/" then url = string.sub(url,2) end
	if arg and arg.component and string.find(url,"/",1,true) then return util.split(url or "","/")[arg.component] end
	return url
end
jsvalidate.URLPath = {validate="Length",arg={min=4}}
function validate.CountryCode(value)
	if not value or not #value==2 or not locales[value] then return validate.invalid end
	return value
end

function validate.File(upload,arg)
	-- TODO:
	return validate.invalid
end


-- # Concordance change validate wrappers
-- TODO: when namespace table/whitelist is implemented these can just be used as flags, i.e. optional=true or required=true
_G.optional = {} -- this table wraps all validate.* functions to make them optional and is typically used when providing the function as a concordance change handler; invokes an error if a value is provided but the validate function returns no value, preserving the original value
setmetatable(optional,{__call= function(_,validator,value)
	if not value then return end
	local newvalue,err = validate[validator](value)
	if err or not newvalue then return value, err or true end
	return newvalue
end})
_G.required = {} -- this table wraps all validate.* functions to make them required when used as a concordance change handler; those functions may return an optional error message as a second parameter; by default all validate handlers return their values only if validated, therefore they act as required and do not need to be called through this table if not used with a concordance
setmetatable(required,{__call= function(_,validator,value)
	if not value then return nil, true end
	local newvalue,err = validate[validator](value)
	if err or not newvalue then return value,err or true end
	return newvalue
end})
