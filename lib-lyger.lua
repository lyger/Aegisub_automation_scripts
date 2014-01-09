--[[
README

Save this file to the automation\autoload directory in your Aegisub program files.

This file is a library of commonly used functions across all my automation
scripts. This way, if there are errors or updates for any of these functions,
I'll only need to update one file.

The filename is a bit vain, perhaps, but I couldn't come up with anything else.

]]

require "karaskel"
require "utils"

script_version="1.1"
--Function to check if script is up to date or not
function chkver(req)
	t_req={}
	t_this={}
	for num in req:gmatch("%d+") do
		table.insert(t_req,tonumber(num))
	end
	for num in script_version:gmatch("%d+") do
		table.insert(t_this,tonumber(num))
	end
	
	--def is returned if all digits match up until one of the version
	--numbers terminates. If the longer version number only has zeroes
	--in the remaining digits, the versions are considered equal.
	--Otherwise, the other version is out-of-date.
	lim=#t_req
	def=true
	if #t_this<#t_req then
		lim=#t_this
		for j=#t_this+1,#t_req do
			if t_req[j]~=0 then def=false end
		end
	end
	
	--This loop will only complete if all digits up to lim are equal
	for i=1,lim do
		if t_this[i]>t_req[i] then return true end
		if t_this[i]<t_req[i] then return false end
	end
	
	return def
end


--[[MODIFIED CODE FROM LUA USERS WIKI]]--
-- declare local variables
--// exportstring( string )
--// returns a "Lua" portable version of the string
local function exportstring( s )
  return string.format("%q", s)
end

--// The Save Function
function write_table(my_table,file,indent)

	if indent==nil then indent="" end
	
	local charS,charE = "   ","\n"
	
	--Opening brace of the table
	file:write(indent.."{"..charE)
	
	for key,val in pairs(my_table) do
		
		if type(key)~="number" then
			if type(key)=="string" then
				file:write(indent..charS.."["..exportstring(key).."]".."=")
			else
				file:write(indent..charS..key.."=")
			end
		else
			file:write(indent..charS)
		end
		
		local vtype=type(val)
		
		if vtype=="table" then
			file:write(charE)
			write_table(val,file,indent..charS)
			file:write(indent..charS)
		elseif vtype=="string" then
			file:write(exportstring(val))
		elseif vtype=="number" then
			file:write(tostring(val))
		elseif vtype=="boolean" then
			if val then file:write("true")
			else file:write("false") end
		end
		
		file:write(","..charE)
	end
	
	--Closing brace of the table
	file:write(indent.."}"..charE )
end

--[[END CODE FROM LUA USERS WIKI]]--

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
	["yshad"] = "number"
}

--Convert float to neatly formatted string
function float2str(f) return string.format("%.3f",f):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end

--Escapes string for use in gsub
function esc(str)
	str=str:gsub("%%","%%%%")
	str=str:gsub("%(","%%%(")
	str=str:gsub("%)","%%%)")
	str=str:gsub("%[","%%%[")
	str=str:gsub("%]","%%%]")
	str=str:gsub("%.","%%%.")
	str=str:gsub("%*","%%%*")
	str=str:gsub("%-","%%%-")
	str=str:gsub("%+","%%%+")
	str=str:gsub("%?","%%%?")
	return str
end

--[[
Tags that can have any character after the tag declaration:
\r
\fn
Otherwise, the first character after the tag declaration must be:
a number, decimal point, open parentheses, minus sign, or ampersand
]]--

--Remove listed tags from the given text
function line_exclude(text, exclude)
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
						if a:match("%)$")~=nil then
							if a:match("%b()")~=nil then
								return ""
							else
								return ")"
							end
						end
						return ""
					end
				end
			end
			return "\\"..a
		end)
	if remove_t then
		new_text=new_text:gsub("\\t%b()","")
	end
	return new_text
end

--Remove all tags except the given ones
function line_exclude_except(text, exclude)
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
			if a:match("^t")~=nil then
				return "\\"..a
			end
			if a:match("%)$")~=nil then
				if a:match("%b()")~=nil then
					return ""
				else
					return ")"
				end
			end
			return ""
		end)
	if remove_t then
		new_text=new_text:gsub("\\t%b()","")
	end
	return new_text
end

--Returns the position of a line
function get_pos(line)
	local _,_,posx,posy=line.text:find("\\pos%(([%d%.%-]*),([%d%.%-]*)%)")
	if posx==nil then
		_,_,posx,posy=line.text:find("\\move%(([%d%.%-]*),([%d%.%-]*),")
		if posx==nil then
			_,_,align_n=line.text:find("\\an([%d%.%-]+)")
			if align_n==nil then
				_,_,align_dumb=line.text:find("\\a([%d%.%-]+)")
				if align_dumb==nil then
					--If the line has no alignment tags
					posx=line.x
					posy=line.y
				else
					--If the line has the \a alignment tag
					vid_x,vid_y=aegisub.video_size()
					align_dumb=tonumber(align_dumb)
					if align_dumb>8 then
						posy=vid_y/2
					elseif align_dumb>4 then
						posy=line.eff_margin_t
					else
						posy=vid_y-line.eff_margin_b
					end
					_temp=align_dumb%4
					if _temp==1 then
						posx=line.eff_margin_l
					elseif _temp==2 then
						posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
					else
						posx=vid_x-line.eff_margin_r
					end
				end
			else
				--If the line has the \an alignment tag
				vid_x,vid_y=aegisub.video_size()
				align_n=tonumber(align_n)
				_temp=align_n%3
				if align_n>6 then
					posy=line.eff_margin_t
				elseif align_n>3 then
					posy=vid_y/2
				else
					posy=vid_y-line.eff_margin_b
				end
				if _temp==1 then
					posx=line.eff_margin_l
				elseif _temp==2 then
					posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
				else
					posx=vid_x-line.eff_margin_r
				end
			end
		end
	end
	return posx,posy
end

--Returns the origin of a line
function get_org(line)
	local _,_,orgx,orgy=line.text:find("\\org%(([%d%.%-]*),([%d%.%-]*)%)")
	if orgx==nil then
		return get_pos(line)
	end
	return orgx,orgy
end

--Returns a table of default values
function style_lookup(line)
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