--[[ Terminal output and formatting

The formats can be used in several manners:
	format.red "string" -- function calls always restore the default formatting
	format.red..format.whitebg.."string" -- concatention simply inserts the format beginning at that point, this is a broken example that would need to restore the default per either of the following:
	format.red..format.whitebg "string" -- restores the default as the last concatenation is a call
	format.red..format.whitebg.."string"..format.default -- restores the default explictly

Strings formatted in this manner can be output to screen using native print() or terminal.print() which provide line-wrapping. To print a single string without additional output functions nor lines you can call the formats from the terminal table directly, e.g.: terminal.red("string")
--]]

-- note that we do not require 'moonstalk/utilities' as the functions dependant upon them (print,serialise,style) are optional and the others are used in the runner before a modules check

format = import "core/moonstalk/terminal-format.lua"
local format_default = format.default

function init()
	inited = true
	rows,columns = string.match(util.Shell("stty size"),"(%d*) (%d*)") -- sh doesn't seem to export $COLUMNS
	columns = tonumber(columns) or 80
	rows = tonumber(rows) or 12
	-- TODO: check and set colour capability
end

do
local styles = { ['*']=format.bright, ['_']=format.underscore, ['#']=format.reverse, ['!']=format.erroneous}
local unstyled = "["; for style in pairs(styles) do unstyled = unstyled.."%"..style end unstyled = unstyled.."]"
function style(text,output)
	-- adds formatting using simple inline character markup, supporting nesting
	-- markup chars can be escaped with backslash to output that char itself
	output = output or print
	local formatted = {}
	local string_sub = string.sub
	local table_insert = table.insert
	local table_concat = table.concat
	local modes,opened = {},{}
	local char, prior
	for i=1,#text do
		char = string_sub(text,i,i)
		if styles[char] and prior ~="\\" then
			if not opened[char] then
				table_insert(modes,styles[char]())
				table_insert(formatted,modes[#modes])
				opened[char] = #modes
			else
				modes[opened[char]] = ""
				opened[char] = false
				table_insert(formatted,format_default())
				table_insert(formatted,table_concat(modes))
			end
		else
			table_insert(formatted,char)
		end
		prior = char
	end
	return output(table_concat(formatted))
end
function unstyle(text)
	return string.gsub(text,unstyled,"")
end
end

format.expand = {
	key_indent = "\t",
	key_open = format.dim "['",
	key_close = format.dim "']",
	numberkey_open = format.dim "[",
	numberkey_close = format.dim "]",
	longstring_open = format.dim "[[",
	longstring_close = format.dim "]]",
	table_open = format.yellow "{ ",
	table_close = format.yellow "}",
	quote = format.dim "\"",
	equals = format.yellow " = ",
	comma = format.dim ", ",
	['nil'] = format.yellow "nil",
	['true'] = format.green "true",
	['false'] = format.red "false",
	linebreak = "\n  ",
	newline = "\n  ",
}
format.flat = {
	key_indent = "",
	key_open = format.dim "['",
	key_close = format.dim "']",
	numberkey_open = format.dim "[",
	numberkey_close = format.dim "]",
	longstring_open = format.dim "[[",
	longstring_close = format.dim "]]",
	table_open = format.yellow "{ ",
	table_close = format.yellow "}",
	quote = format.dim "\"",
	equals = format.yellow " = ",
	comma = format.magenta ", ",
	['nil'] = format.yellow "nil",
	['true'] = format.green "true",
	['false'] = format.red "false",
	linebreak = format.dim "\\n", -- encode linebreaks as escaped
	newline = "",
}
function serialise(text,formatter)
	if not interactive then
		return util.Serialise(text)
	else
		formatter = formatter or format.flat
		return util.SerialiseWith(text,formatter,3)
	end
end

function print (text,newline)
	-- output text to the terminal like print but with line-wrapping; returns the number of lines output
	text = util.ResumeToCols(text) -- TODO: catch styles before linebreaks, reset, then restore after indentation
	if newline ~=false then text = text .."\n" end -- behave like print()
	io.stdout:write(text)
	io.flush()
	return pack(string.gsub(text,"\n","\n"))[2]
end

function output (text)
	io.stdout:write(text)
	io.flush()
end
local output = output

function up(rows,text)
	output("\27["..rows.."A")
	if text then output(text) end
end
function down(rows,text)
	output("\27["..rows.."B")
	if text then output(text) end
end
function back (cols,text)
	output("\27["..cols.."D")
	if text then output(text) end
end
function forward (cols,text)
	output("\27["..cols.."C")
	if text then output(text) end
end
function save_position ()
	output("\27[s")
end
function restore_position ()
	output("\27[u")
end
function reset_position ()
	output("\27[u\27[K")
end
function hide_cursor ()
	output("\27[?25l")
end
function show_cursor ()
	output("\27[?25h")
end

local this = getfenv()
for style,formatter in pairs(format) do
	if not this[style] then this[style] = function(string) output(formatter(string)) end end
end
