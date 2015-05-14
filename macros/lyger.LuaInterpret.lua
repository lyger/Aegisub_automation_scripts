--[[
==README==

Lua Interpreter

This allows you to run Lua code on-the-fly on an .ass file. The code will
be applied to all the selected lines. A simple API is provided to make
modifying line properties more efficient.

Calling it a "Lua interpreter" may be a misnomer, but I can't think of
anything better at the moment.

The code the user inputs is run for each "section" of text, as marked by
the override blocks. A "section" of text is defined as the part of the
line that has all the same properties. For example, this line:

Never gonna {\fs200}give {\alpha&H55&}you up

has three sections. The first section is "Never gonna " and contains all
default properties. The second section is "{\fs200}give ". All text in
this section has font size 200, and default properties otherwise. The
third and last section is "{\alpha&H55&}you up", which has font size 200,
an alpha of 55 hex, and default properties otherwise.

Any code you input into the interpreter will thus run once for each of
these three sections, changing the properties as appropriate.

Functions are as follows:

modify(tag, method)
mod(tag,method)
	Modify tag using method. tag is a string that indicates the override
	tag (property) that you want to modify. method is a function that
	dictates how the modification is done. For example, to double the
	font size, do:

	modify("fs",multiply(2))

	mod is an alias for modify, which you can use to save typing.

modify_line(property, method)
modln(propery,method)
	Works like modify(), but acts on line properties, not override tags.
	For example, to modify the layer of a line:

	modify_line("layer",add(1))

	For a list of line properties that can be modified, see:
	http://docs.aegisub.org/3.0/Automation/Lua/Modules/karaskel.lua/#index12h3

add(...)
	Returns a function that will add the given values. Can have multiple
	parameters. For example, to expand a rectangular clip by 10 pixels on
	all sides, assuming the first two coordinates represent top left and
	the last two coordinates represent bottom right, do:

	modify("clip",add(-10,-10,10,10))

	This will add -10, -10, 10, and 10, in that order, to the four
	parameters of \clip. There is no subtract() function; simply add a
	negative number to subtract.

multiply(...)
mul(...)
	Works like add(). There is no divide() function. Simply multiply by
	a decimal or a fraction. Example:

	modify("fscx",multiply(0.5))

replace(x)
rep(x)
	Returns a function that returns x. When used inside modify(), this
	will effectively replace the original parameter of the tag with x.

	modify("fn",replace("Comic Sans MS"))

append(x)
app(x)
	Returns a function that appends x to the parameter. For example:

	modify_line("actor",append(" the great"))

	I'm not sure why I wrote this function either. Completeness' sake,
	perhaps.

get(tag)
	Returns the parameter of the tag. If the tag has multiple parameters,
	they are returned as a table. Example:

	main_color=get("c")

remove(...)
rem(...)
	Removes all the tags listed. Example:

	remove("bord","shad")

select()
	Adds the current line to the final selection. If this function is
	never used, the original selection will be returned.

duplicate()
	DO NOT USE UNLESS YOU KNOW WHAT YOU ARE DOING. This will insert a
	copy of the current line after the current line. Beware of recursion!
	If you do not put some sort of if statement around duplicate(), then
	your first line will be duplicated, then the duplicate will be
	duplicated, then the duplicate of the duplicate will be duplicated,
	and you end up in an infinite loop. I suggest you use the function
	like this:

	if i%2==1 then
		duplicate()

		--Code to run on the original line

	else

		--Code to run on the duplicate line

	end

	Note that "once per line" functions such as duplicate() are run at
	the end of the rest of the execution, but before changes are saved.
	In other words, duplicate() will always create a line that looks like
	your current line did originally, before you modified it at all.

You also have access to all functions in utils.lua and karaskel.lua, such
as functions for doing math on alpha and color values. I may eventually
write alpha and color handling into the already complex modify function,
but for now, code such as modify("alpha",add(50)) will not work.



Global variables are as follows:

i
	This is the index within your selection. In other words, when the
	code is being run on the first line, i will have the value 1. When
	the code is being run on the third line, i will have the value 3.
	In the code example under duplicate() above, i will be odd for all
	of the original lines and even for all of the duplicates, thus
	the check "i%2==1" is made.

li
	This is the line number of the current line.

j
	This is the number (counting from 1) of the section that the code is
	currently looking at.

state
	This is a table containing the current state of the line, indexed by
	tag name. For example, to find out what the current x scaling is, use:

	state["fscx"]

	This table automatically updates when your code modifies properties
	of the line. To see the state of the untouched line, use the variable
	dstate (for default state).

pos
	This is a table (or object) with two fields: x and y. Use pos.x to
	access the x coordinate and pos.y to access the y coordinate. The
	coordinates are guaranteed to match the line's position on screen,
	even if no position is defined in-line. You can perform arithmetic
	on this object, but it may not behave the way you want it to. You
	are advised to use modify("pos",...) instead.

org
	Like pos, but for the origin.

flags
	A global table for values you want to store outside of the loop. Most
	other variables will change or be reset once the the script starts to
	run on the next line. It's empty by default.

]]

script_name = "Lua Interpreter"
script_description = "Run Lua code on the fly."
script_version = "1.3.0"
script_author = "lyger"
script_namespace = "lyger.LuaInterpret"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{
		{"lyger.LibLyger", version = "2.0.0", url = "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"},
		"aegisub.util"
	}
}

local LibLyger, util = rec:requireModules()
local libLyger = LibLyger()
local f2s, esc = LibLyger.float2str, LibLyger.esc

--Set the location of the config file
local config_pre=aegisub.decode_path("?user")
local config_name="luaint-presets.config"
local psep=config_pre:match("\\") and "\\" or "/"

--Old config path, to allow old data to be copied over to the proper location
local old_config_path=config_pre..config_name
--Proper config path
local config_path=config_pre..psep..config_name


local textbox, dialog_conf = {}, {}

--Lookup table for once-per-line tags
local opl= {
	["pos"]=true,
	["org"]=true,
	["move"]=true,
	["a"]=true,
	["an"]=true,
	["fad"]=true,
	["clip"]=true
}

--Remake the configuration defaults
local function make_conf()
	textbox={class="textbox",name="code",x=0,y=1,width=40,height=6}
	dialog_conf=
	{
		{class="label",label="Enter code below:",x=0,y=0,width=40,height=1},
		textbox
	}
end


--Returns a function that adds by each number
function add(...) -- exposed to script
	local x = table.pack(...)
	return function(...)
		local y, z = table.pack(...), {}
		for i=1, #y do
			y[i]=tonumber(y[i]) or 0
			x[i]=tonumber(x[i]) or 0
			z[i]=y[i]+x[i]
		end
		return unpack(z)
	end
end

--Returns a function that multiplies by each number
function multiply(...) -- exposed to script
	local x = table.pack(...)
	return function(...)
		local y, z = table.pack(...), {}
		for i=1, #y do
			y[i]=tonumber(y[i]) or 0
			x[i]=tonumber(x[i]) or 0
			z[i]=y[i]*x[i]
		end
		return unpack(z)
	end
end

--Returns a function that replaces with x
function replace(...) -- exposed to script
	local args = table.pack(...)
	return function() return unpack(args) end
end

--Returns a function that appends x
function append(x) -- exposed to script
	return function(y) return y..x end
end

--Write presets table to file
local function table_to_file(path,wtable)
	local wfile=io.open(path,"wb")
	wfile:write("return\n")
	LibLyger.write_table(wtable,wfile,"    ")
	wfile:close()
end

--Read presets table from file
local function table_from_file(path)
	local lfile=io.open(path,"r")
	if not lfile then return end
	local return_presets,err = loadstring(lfile:read("*all"))
	if err then
		aegisub.log(err)
		return
	end
	lfile:close()
	return return_presets()
end


function lua_interpret(sub,sel)
	make_conf()
	libLyger:set_sub(sub, sel)

	--Copies old data over in the case of first run after upgrade
	local oldpresets=table_from_file(old_config_path)
	if oldpresets then
		table_to_file(config_path,oldpresets)
	end

	--Load presets or create if none
	local presets = table_from_file(config_path)
	if not presets then
		presets={["Example - Duplicate and Blur"] = [[
	if i%2 == 1 then
		duplicate()
		modify("bord", replace(0))
		if state.blur == 0 then modify("blur", replace(0.6)) end
		modify_line("layer",add(1))
		remove("3c", "3a", "shad")
	else
		modify("c", replace(get("3c")))
		modify("1a", replace(get("3a")))
		if state.blur == 0 then modify("blur", replace(0.6)) end
	end]]}

		table_to_file(config_path,presets)
	end

	--Components of the dialog
	local preselector = {
			class="dropdown",items={},
			name="pre_sel",
			x=0,y=7,width=20,height=1
		}
	local prenamer = {
			class="edit",
			name="new_prename",
			x=20,y=7,width=20,height=1
		}

	dialog_conf[3], dialog_conf[4] = preselector, prenamer

	local function make_name_list()
		preselector.items = {}
		local maxnew, p = 0, 1
		for k,_ in pairs(presets) do
			preselector.items[p], p = k, p+1
			num=k:match("New preset (%d+)")
			num=tonumber(num) or 0
			maxnew = math.max(num, maxnew)
		end
		table.sort(preselector.items)
		prenamer.value=string.format("New preset %d",maxnew+1)
	end

	make_name_list()

	--Show GUI
	local pressed, results
	repeat
		pressed,results=aegisub.dialog.display(dialog_conf,
			{"Run","Load","Save","Delete","Cancel"})

		if pressed=="Cancel" then aegisub.cancel() end
		if pressed=="Load" then
			textbox.value=presets[results["pre_sel"]]
			preselector.value=results["pre_sel"]
		end
		if pressed=="Save" then
			textbox.value=results["code"]
			if presets[results["new_prename"]]~=nil then
				aegisub.dialog.display({{class="label",label="Name already in use!",x=0,y=0,width=1,height=1}})
			else
				presets[results["new_prename"]]=results["code"]
				table_to_file(config_path,presets)
				make_name_list()
			end
		end
		if pressed=="Delete" then
			presets[results["pre_sel"]]=nil
			make_name_list()
			table_to_file(config_path,presets)
			preselector.value=nil
		end

	until pressed=="Run"

	local command, new_sel = results["code"], {}

	--Run for all lines in selection. Hard limit of 9001 just in case
	i, flags = 1, {} -- exposed to script
	while i<=#sel and #sel<=9001 do
		local li=sel[i]
		local line, line_table = libLyger.lines[li], {}

		aegisub.progress.set(100*i/#sel)

		--Alias maxi to the size of the selection
		maxi = #sel -- exposed to script
		--Break the line into a table

		if not line.text:match("^{") then
			line.text="{}"..line.text
		end
		line.text=line.text:gsub("}","}\t")
		local j = 1
		for thistag,thistext in line.text:gmatch("({[^{}]*})([^{}]*)") do
			line_table[j]={tag=thistag:gsub("\\1c","\\c"),text=thistext:gsub("^\t","")}
			j=j+1
		end
		line.text=line.text:gsub("}\t","}")

		--These functions are run at the end, at most once per line
		local tasklist = {}

		--Function to select line
		local function _select()
			tasklist[#tasklist+1] = function()
				new_sel[#new_sel+1] = li
				selected = true  -- exposed to script
			end
		end

		--Function to duplicate lines
		local function _duplicate()
			table.insert(tasklist,1,function()
				table.insert(sel,i+1,li+1)
				libLyger:insert_line(util.copy(line), li+1)
				for x = i+2, #sel do
					sel[x] = sel[x]+1
				end

				for x = 1, #new_sel do
					if new_sel[x] > li+1 then
						new_sel[x] = new_sel[x] + 1
					end
				end

				duplicated = true -- exposed to script
				flags["duplicate"]=true
			end)
		end

		--Function to modify line properties
		local function _modify_line(prop,func)
			table.insert(tasklist, function()
				line[prop]=func(line[prop])
			end)
		end

		--Create state table
		local state_table = {}
		for j,a in ipairs(line_table) do
			state_table[j]={}
			for b in a.tag:gmatch("(\\[^\\}]*)") do
				if b:match("\\fs%d") then
					state_table[j]["fs"]=b:match("\\fs([%d%.]+)")
					state_table[j]["fs"]=tonumber(state_table[j]["fs"])
				elseif b:match("\\fn") then
					state_table[j]["fn"]=b:match("\\fn([^\\}]*)")
				elseif b:match("\\r") then
					state_table[j]["r"]=b:match("\\r([^\\}]*)")
				else
					local tag, param = b:match("\\([1-4]?%a+)(%A[^\\}]*)")
					state_table[j][tag] = tonumber(param) or param
				end
			end
		end

		--Create default state and current state
		state = libLyger:style_lookup(line) -- exposed to script
		dstate = util.copy(state) -- exposed to script

		--Define position and origin objects
		pos, org = {}, {} -- exposed to script
		pos.x,pos.y=libLyger:get_pos(line)
		org.x,org.y=libLyger:get_org(line)

		--Now cycle through all tag-text pairs
		for j,a in ipairs(line_table) do
			local fenv = getfenv(1)
			fenv.j=j
			fenv.line=line
			fenv.flags=flags
			fenv.maxj=#line_table

			--Wrappers for the once-per-line functions
			fenv.duplicate = function()
				if j==1 then _duplicate() end
			end
			fenv.select = function()
				if j==1 then _select() end
			end
			fenv.modify_line = function(prop,func)
				if j==1 then _modify_line(prop,func) end
			end

			local first = j==1

			--Define variables
			text, tag = a.text, a.tag -- exposed to script

			--Update state
			for tag, param in pairs(state_table[j]) do
				state[tag]= param
				dstate[tag]= param
			end

			--Get the parameter of the given tag
			fenv.get = function(b)
				local param = tostring(dstate[b])
				if param:match("%b()") then
					local c = {}
					for d in param:gmatch("[^%(%),]+") do
						c[#c+1] = d
					end
					return unpack(c)
				end
				return param
			end

			--Modify the given tag
			fenv.modify = function(b,func)
				--Make sure once-per-lines are only modified once
				if opl[b] and j~=1 then return end

				local c, d = {get(b)}
				if #c==1 then c=c[1] end
				if type(c)=="table" then
					local e, h, f = {func(unpack(c))}, {"("}, ""
					--If modifying pos or org, store values in relevant objects
					if b=="pos" then pos.x,pos.y=unpack(e) end
					if b=="org" then org.x,org.y=unpack(e) end
					d = {"("}
					for i, g in ipairs(e) do
						d[2*i], d[2*i+1] = f, g
						h[2*i], h[2*i+1] = f, c[i]
						f = ","
					end
					d[#d+1], h[#h+1] = ")", ")"
					c, d = table.concat(h), table.concat(d)
				else
					d=func(c)
					if tonumber(d) then
						d = f2s(tonumber(d))
					end
				end
				--Prevent redundancy
				if state[b]~=d then
					local mod_tag, num = "\\"..b..esc(d)
					tag, num = tag:gsub("\\"..b..esc(c), mod_tag)
					if num<1 and not opl[b] then insert(mod_tag) end
					state[b]=d
				end
			end

			--Remove the given tags
			fenv.remove = function(...)
				tag = LibLyger.line_exclude(tag, table.pack(...))
			end

			--Insert the given tag at the end
			fenv.insert = function(b)
				tag=tag:gsub("}$",b.."}")
			end

			--Select every
			fenv.isel = function(n)
				if i%n==1 then select() end
			end

			--Aliases for common functions
			fenv.mod=modify
			fenv.mul=multiply
			fenv.rep=replace
			fenv.app=append
			fenv.modln=modify_line
			fenv.rem=fenv.remove

			--Run the user's code
			local com, err = loadstring(command)

			if err then
				aegisub.log(err)
				aegisub.cancel()
			end

			setfenv(com, fenv)()

			a.text=text
			a.tag=tag
		end

		for _,task in ipairs(tasklist) do
			task()
		end

		--Rebuild
		local rebuilt_text = {}
		for r, a in ipairs(line_table) do
			rebuilt_text[r*2-1], rebuilt_text[r*2] = a.tag, a.text
		end
		line.text = table.concat(rebuilt_text):gsub("{}","")

		--Update position and org
		local px, py = libLyger:get_pos(line)
		if px ~= pos.x or py ~= pos.y then
			local ptag = string.format("\\pos(%s,%s)", f2s(pos.x), f2s(pos.y))
			local num
			line.text, num = line.text:gsub("\\pos%b()", esc(ptag))
			if num < 1 then
				line.text = line.text:gsub("{", "{"..esc(ptag), 1)
			end
		end
		local ox, oy = libLyger:get_org(line)
		if ox ~= org.x or oy ~= org.y then
			local otag = string.format("\\org(%s,%s)", f2s(org.x), f2s(org.y))
			local num
			line.text, num = line.text:gsub("\\org%b()", esc(otag))
			if num < 1 and (ox ~= pos.x or oy ~= pos.y) then
				line.text = line.text:gsub("{", "{"..esc(otag), 1) end
		end

		--Reinsert
		sub[li]=line

		--Increment
		i=i+1
	end

	aegisub.set_undo_point(script_name)

	--Return new selection or old selection
	if #new_sel>0 then return new_sel end
	return sel

end

rec:registerMacro(lua_interpret)