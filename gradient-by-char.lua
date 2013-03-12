--[[
==README==

No GUI, pretty straightforward.

For example, to make a line bend in an arc and transition from blue to red, do this:

{\frz10\c&HFF0000&}This is a line of tex{\frz350\c&H0000FF&}t

Run the automation and it'll add a tag before each character to make the rotation and color
transition change smoothly across the line.

Rotations are locked to less than 180 degree rotations. If you want a bend of more than 180,
then split it up into multiple rotations of less than 180 each. This script is meant for
convenience above all, so it runs with a single button press and no time-consuming options menu.

]]--

script_name="Gradient by character"
script_description="Smoothly transforms tags across your line, by character."
script_version="0.1"

include("karaskel.lua")
include("utils.lua")

--Lookup table for the nature of each kind of parameter
param_type={
	["alpha"] = "alpha",
	["1a"] = "alpha",
	["2a"] = "alpha",
	["3a"] = "alpha",
	["4a"] = "alpha",
	["c"] = "color",
	["1c"] = "color",
	["2c"] = "color",
	["3c"] = "color",
	["4c"] = "color",
	["fscx"] = "number",
	["fscy"] = "number",
	["frz"] = "angle",
	["frx"] = "angle",
	["fry"] = "angle",
	["shad"] = "number",
	["bord"] = "number",
	["fsp"] = "number",
	["fs"] = "number",
	["fax"] = "number",
	["fay"] = "number",
	["blur"] = "number",
	["be"] = "number",
	["xbord"] = "number",
	["ybord"] = "number",
	["xshad"] = "number",
	["yshad"] = "number",
	["t"] = "time"
}

--Convert float to neatly formatted string
local function float2str(f) return string.format("%.3f",f):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end

--Creates a deep copy of the given table
local function deep_copy(source_table)
	new_table={}
	for key,value in pairs(source_table) do
		--Let's hope the recursion doesn't break things
		if type(value)=="table" then value=deep_copy(value) end
		new_table[key]=value
	end
	return new_table
end

--[[
Tags that can have any character after the tag declaration:
\r
\fn
Otherwise, the first character after the tag declaration must be:
a number, decimal point, open parentheses, minus sign, or ampersand
]]--

--Remove listed tags from the given text
local function line_exclude(text, exclude)
	remove_t=false
	local new_text=text:gsub("\\([^\\{}]*)",
		function(a)
			if a:find("^r")~=nil then
				for i,val in ipairs(exclude) do
					if val=="r" then return "" end
				end
			elseif a:find("^fn")~=nil then
				for i,val in ipairs(exclude) do
					if val=="fn" then return "" end
				end
			else
				_,_,tag=a:find("^([1-4]?%a+)")
				for i,val in ipairs(exclude) do
					if val==tag then
						--Hacky exception handling for \t statements
						if val=="t" then
							remove_t=true
							return "\\"..a
						end
						return ""
					end
				end
			end
			return "\\"..a
		end)
	if remove_t then
		text=text:gsub("\\t%b()","")
	end
	return new_text
end

--Remove all tags except the given ones
local function line_exclude_except(text, exclude)
	remove_t=true
	local new_text=text:gsub("\\([^\\{}]*)",
		function(a)
			if a:find("^r")~=nil then
				for i,val in ipairs(exclude) do
					if val=="r" then return "\\"..a end
				end
			elseif a:find("^fn")~=nil then
				for i,val in ipairs(exclude) do
					if val=="fn" then return "\\"..a end
				end
			else
				_,_,tag=a:find("^([1-4]?%a+)")
				for i,val in ipairs(exclude) do
					if val==tag then
						if val=="t" then
							remove_t=false
						end
						return "\\"..a
					end
				end
			end
			return ""
		end)
	if remove_t then
		text=text:gsub("\\t%b()","")
	end
	return new_text
end

--Remove listed tags from any \t functions in the text
local function time_exclude(text,exclude)
	text=text:gsub("(\\t%b())",
		function(a)
			b=a
			for y=1,#exclude,1 do
				if(string.find(a,"\\"..exclude[y])~=nil) then
					if exclude[y]=="clip" then
						b=b:gsub("\\"..exclude[y].."%b()","")
					else
						b=b:gsub("\\"..exclude[y].."[^\\%)]*","")
					end
				end
			end
			return b
		end
		)
	--get rid of empty blocks
	text=text:gsub("\\t%([%-%.%d,]*%)","")
	return text
end

--Returns a table of default values
local function style_lookup(line)
	local style_table={
		["alpha"] = "&H00&",
		["1a"] = alpha_from_style(line.styleref.color1),
		["2a"] = alpha_from_style(line.styleref.color2),
		["3a"] = alpha_from_style(line.styleref.color3),
		["4a"] = alpha_from_style(line.styleref.color4),
		["c"] = color_from_style(line.styleref.color1),
		["1c"] = color_from_style(line.styleref.color1),
		["2c"] = color_from_style(line.styleref.color2),
		["3c"] = color_from_style(line.styleref.color3),
		["4c"] = color_from_style(line.styleref.color4),
		["fscx"] = line.styleref.scale_x,
		["fscy"] = line.styleref.scale_y,
		["frz"] = line.styleref.angle,
		["frx"] = 0,
		["fry"] = 0,
		["shad"] = line.styleref.shadow,
		["bord"] = line.styleref.outline,
		["fsp"] = line.styleref.spacing,
		["fs"] = line.styleref.fontsize,
		["fax"] = 0,
		["fay"] = 0,
		["xbord"] =  line.styleref.outline,
		["ybord"] = line.styleref.outline,
		["xshad"] = line.styleref.shadow,
		["yshad"] = line.styleref.shadow,
		["blur"] = 0,
		["be"] = 0
	}
	return style_table
end

--Returns a state table, restricted by the tags given in "tag_table"
--WILL NOT WORK FOR \fn AND \r
local function make_state_table(line_table,tag_table)
	local this_state_table={}
	for i,val in ipairs(line_table) do
		temp_line_table={}
		pstate=line_exclude_except(val.tag,tag_table)
		for j,ctag in ipairs(tag_table) do
			--param MUST start in a non-alpha character, because ctag will never be \r or \fn
			--If it is, you fucked up
			_,_,param=pstate:find("\\"..ctag.."(%A[^\\{}]*)")
			if param~=nil then
				temp_line_table[ctag]=param
			end
		end
		this_state_table[i]=temp_line_table
	end
	return this_state_table
end

function grad_char(sub,sel)

	local meta,styles = karaskel.collect_head(sub, false)
	
	for si,li in ipairs(sel) do
		--Read in the line
		this_line=sub[li]
		
		--Preprocess
		karaskel.preproc_line(sub,meta,styles,this_line)
		
		--Make sure line starts with tags
		if this_line.text:find("^{")==nil then this_line.text="{}"..this_line.text end
		
		--Turn all \1c tags into \c tags, just for convenience
		this_line.text=this_line.text:gsub("\\1c","\\c")
			
		--Make line table
		this_table={}
		x=1
		for thistag,thistext in this_line.text:gmatch("({[^{}]*})([^{}]*)") do
			this_table[x]={tag=thistag,text=thistext}
			x=x+1
		end
		
		if #this_table<2 then
			aegisub.log("There must be more than one tag block in the line!")
			return
		end
		
		--Transform these tags
		transform_tags={
			"c","2c","3c","4c",
			"alpha","1a","2a","3a",
			"fscx","fscy","fax","fay",
			"frx","fry","frz",
			"fs","fsp",
			"bord","shad",
			"xbord","ybord","xshad","yshad",
			"blur","be"
			}
		
		--Make state table
		this_state=make_state_table(this_table,transform_tags)
		
		--Style lookup
		this_style=style_lookup(this_line)
		
		--Running record of the state of the line
		current_state={}
		
		--Outer control loop
		for i=2,#this_table,1 do
			--Update current state
			for ctag,cval in pairs(this_state[i-1]) do
				current_state[ctag]=cval
			end
			
			--Local function for interpolation
			local function handle_interpolation(factor,tag,sval,eval)
				local ivalue=""
				--Handle differently depending on the type of tag
				if param_type[tag]=="alpha" then
					ivalue=interpolate_alpha(factor,sval,eval)
				elseif param_type[tag]=="color" then
					ivalue=interpolate_color(factor,sval,eval)
				elseif param_type[tag]=="angle" then
					nstart=tonumber(sval)
					nend=tonumber(eval)
					
					--Use "Rotate in shortest direction" by default
					nstart=nstart%360
					nend=nend%360
					ndelta=nend-nstart
					if math.abs(ndelta)>180 then nstart=nstart+(ndelta*360)/math.abs(ndelta) end
					
					--Interpolate
					nvalue=interpolate(factor,nstart,nend)
					if nvalue<0 then nvalue=nvalue+360 end
					
					--Convert to string
					ivalue=float2str(nvalue)
					
				elseif param_type[tag]=="number" then
					nstart=tonumber(sval)
					nend=tonumber(eval)
					
					--Interpolate and convert to string
					ivalue=float2str(interpolate(factor,nstart,nend))
				end
				return ivalue
			end
			
			--Add a new tag in front of all the nonspace characters except the first
			this_table[i-1].text=this_table[i-1].text:gsub("(.)(.*)", function(c,a)
				idx=1				
				total=string.len(a)+1
				
				return c..a:gsub("(.)", function(b)
					--Interpolation factor
					factor=idx/total
					
					idx=idx+1
					
					if b:find("%s")~=nil then return b end
					
					--The tags in and out of the time statement
					local non_time_tags=""
					
					--Go through all the state tags in this tag block
					for ttag,tparam in pairs(this_state[i]) do
						--Figure out the starting state of the param
						local sparam=current_state[ttag]
						if sparam==nil then sparam=this_style[ttag] end
						sparam=sparam:gsub("%)","")--Just in case a \t tag snuck in
						
						--The string version of the interpolated parameter
						local iparam=handle_interpolation(factor,ttag,sparam,tparam)
						
						non_time_tags=non_time_tags.."\\"..ttag..iparam
					end
					
					--The final tag, with a star to indicate it was added through interpolation
					return "{\*"..non_time_tags.."}"..b
				end)
			end)
		end
		
		rebuilt_text=""
		
		for i,val in pairs(this_table) do
			rebuilt_text=rebuilt_text..val.tag..val.text
		end
		this_line.text=rebuilt_text
		sub[li]=this_line
	end
	
	aegisub.set_undo_point(script_name)
end

function remove_grad_char(sub,sel)
	for si,li in ipairs(sel) do
		this_line=sub[li]
		this_line.text=this_line.text:gsub("{%*[^{}]*}","")
		sub[li]=this_line
	end
end

--Register the macro
aegisub.register_macro(script_name,script_description,grad_char)
aegisub.register_macro(script_name.." - un-gradient","Removes gradient generated by "..script_name,remove_grad_char)