--[[
README

Split at tags

Pretty self-explanatory. If you ever had a typeset with effects on each character and you wished
each character was on a separate line, you're in luck. This script splits the line into a new
line for each block of tags, with the appropriate position and appearance. For example:

{\pos(x,y)\c&H0000FF&}This {\c&H0000DD&}is {\c&H0000BB&}a {\c&H000099&}test

would get split into

{\pos(x1,y1)\c&H0000FF&}This
{\pos(x2,y2)\c&H0000DD&}is
{\pos(x3,y3)\c&H0000BB&}a
{\pos(x4,y4)\c&H000099&}test

In theory, after running this script, the appearance of the typeset will be exactly the same, but
every section will be on a different line, allowing you to work with them separately.

Doesn't support newlines (\N) and at this rate, never will. If someone teaches me about how .ass
calculates newline heights, I might write a separate script to split at newlines.


]]--

script_name="Split at tags"
script_description="Splits the line into separate lines based on tag boundaries"
script_version="0.3"

include("karaskel.lua")

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

--Creates a slightly less deep copy of the given table
local function shallow_copy(source_table)
	new_table={}
	for key,value in pairs(source_table) do
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

--Returns the position of a line
local function get_pos(line)
	local _,_,posx,posy=line.text:find("\\pos%(([%d%.%-]*),([%d%.%-]*)%)")
	if posx==nil then
		_,_,posx,posy=line.text:find("\\move%(([%d%.%-]*),([%d%.%-]*),")
		if posx==nil then
			_,_,align_n=line.text:find("\\an([%d%.%-]*)")
			if align_n==nil then
				_,_,align_dumb=line.text:find("\\a([%d%.%-]*)")
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
	return tonumber(posx),tonumber(posy)
end

--Returns the origin of a line
local function get_org(line)
	local _,_,orgx,orgy=line.text:find("\\org%(([%d%.%-]*),([%d%.%-]*)%)")
	if orgx==nil then
		return get_pos(line)
	end
	return tonumber(orgx),tonumber(orgy)
end

--Returns a table of tag-value pairs
--Supports fn but ignores r because fuck r
local function full_state_subtable(tag)
	--Store time tags in their own table, so they don't interfere
	time_tags={}
	for ttag in tag:gmatch("\\t%b()") do
		table.insert(time_tags,ttag)
	end

	--Remove time tags from the string so we don't have to deal with them
	tag=tag:gsub("\\t%b()","")

	state_subtable={}

	for t in tag:gmatch("\\[^\\{}]*") do
		ttag,tparam="",""
		if t:match("\\fn")~=nil then
			ttag,tparam=t:match("\\(fn)(.*)")
		else
			ttag,tparam=t:match("\\([1-4]?%a+)(%A.*)")
		end
		state_subtable[ttag]=tparam
	end

	--Dump the time tags back in
	if #time_tags>0 then
		state_subtable["t"]=time_tags
	end

	return state_subtable
end

local function split_tag(sub,sel)
	--Read in styles and meta
	local meta,styles = karaskel.collect_head(sub, false)

	--How far to offset the next line read
	lines_added=0

	for si,li in ipairs(sel) do

		--Progress report
		aegisub.progress.task("Processing line "..si.."/"..#sel)
		aegisub.progress.set(100*si/#sel)

		--Read in the line
		line=sub[li+lines_added]

		--Comment it out
		line.comment=true
		sub[li+lines_added]=line
		line.comment=false

		--Preprocess
		karaskel.preproc_line(sub,meta,styles,line)

		--Get position and origin
		px,py=get_pos(line)
		ox,oy=get_org(line)

		--If there are rotations in the line, then write the origin
		do_org=false

		if line.text:match("\\fr[xyz]")~=nil then do_org=true end

		--Turn all \Ns into the newline character
		--line.text=line.text:gsub("\\N","\n")

		--Make sure any newline followed by a non-newline character has a tag afterwards
		--(i.e. force breaks at newlines)
		--line.text=line.text:gsub("\n([^\n{])","\n{}%1")

		--Make line table
		line_table={}
		for thistag,thistext in line.text:gmatch("({[^{}]*})([^{}]*)") do
			table.insert(line_table,{tag=thistag,text=thistext})
		end

		--Stores current state of the line as style table
		current_style=deep_copy(line.styleref)

		--Stores the width of each section
		substr_data={}

		--Total width of the line
		cum_width=0
		--Total height of the line
		--cum_height=0
		--Stores the various cumulative widths for each linebreak
		--subs_width={}
		--subs_index=1

		--First pass to collect size data
		for i,val in ipairs(line_table) do

			--Create state subtable
			subtable=full_state_subtable(val.tag)

			--Fix style tables to reflect override tags
			current_style.fontname=subtable["fn"] or current_style.fontname
			current_style.fontsize=tonumber(subtable["fs"]) or current_style.fontsize
			current_style.scale_x=tonumber(subtable["fscx"]) or current_style.scale_x
			current_style.scale_y=tonumber(subtable["fscy"]) or current_style.scale_y
			current_style.spacing=tonumber(subtable["fsp"]) or current_style.spacing
			current_style.align=tonumber(subtable["an"]) or current_style.align
			if subtable["b"]~=nil then
				if subtable["b"]=="1" then current_style.bold=true
				else current_style.bold=false end
			end
			if subtable["i"]~=nil then
				if subtable["i"]=="1" then current_style.italic=true
				else current_style.italic=false end
			end
			if subtable["a"]~=nil then
				dumbalign=tonumber(subtable["a"])
				halign=dumbalign%4
				valign=0
				if dumbalign>8 then valign=3
				elseif dumbalign>4 then valign=6
				end
				current_style.align=valign+halign
			end

			--Store this style table
			val.style=deep_copy(current_style)

			--Get extents of the section. _sdesc is not used
			--Temporarily remove all newlines first
			swidth,sheight,_sdesc,sext=aegisub.text_extents(current_style,val.text:gsub("\n",""))

			--aegisub.log("Text: %s\n--w: %.3f\n--h: %.3f\n--d: %.3f\n--el: %.3f\n\n",
			--	val.text, swidth, sheight, _sdesc, sext)

			--Add to cumulative width
			cum_width=cum_width+swidth

			--Total height of the line
			--theight=0

			--Handle tasks for a line that has a newline
			--[[if val.text:match("\n")~=nil then
				--Add sheight for each newline, if any
				for nl in val.text:gmatch("\n") do
					theight=theight+sheight
				end

				--Add the external lead to account for the line of normal text
				--theight=theight+sext

				--Store the current cumulative width and reset it to zero
				subs_width[subs_index]=cum_width
				subs_index=subs_index+1
				cum_width=0

				--Add to cumulative height
				cum_height=cum_height+theight
			else
				theight=sheight+sext
			end]]--

			--Add data to data table
			table.insert(substr_data,
				{["width"]=swidth,["height"]=theight,["subtable"]=subtable})

		end

		--Store the last cumulative width
		--subs_width[subs_index]=cum_width

		--Add the last cumulative height
		--cum_height=cum_height+substr_data[#substr_data].height

		--Stores current state of the line as a state subtable
		current_subtable={}
		--[[current_subtable=shallow_copy(substr_data[1].subtable)
		if current_subtable["t"]~=nil then
			current_subtable["t"]=shallow_copy(substr_data[1].subtable["t"])
		end]]

		--How far to offset the x coordinate
		xoffset=0

		--How far to offset the y coordinate
		--yoffset=0

		--Newline index
		--nindex=1

		--Ways of calculating the new x position
		xpos_func={}
		--Left aligned
		xpos_func[1]=function(w)
				return px+xoffset
			end
		--Center aligned
		xpos_func[2]=function(w)
				return px-cum_width/2+xoffset+w/2
			end
		--Right aligned
		xpos_func[0]=function(w)
				return px-cum_width+xoffset+w
			end

		--Ways of calculating the new y position
		--[[ypos_func={}
		--Bottom aligned
		ypos_func[1]=function(h)
				return py-cum_height+yoffset+h
			end
		--Middle aligned
		ypos_func[2]=function(h)
				return py-cum_height/2+yoffset+w/2
			end
		--Top aligned
		ypos_func[3]=function(h)
				return py+yoffset
			end]]--

		--Second pass to generate lines
		for i,val in ipairs(line_table) do

			--Here's where the action happens
			new_line=shallow_copy(line)

			--Fix state table to reflect current state
			for tag,param in pairs(substr_data[i].subtable) do
				if tag=="t" then
					if current_subtable["t"]==nil then
						current_subtable["t"]=shallow_copy(param)
					else
						--current_subtable["t"]={unpack(current_subtable["t"]),unpack(param)}
						for _,subval in ipairs(param) do
							table.insert(current_subtable["t"],subval)
						end
					end
				else
					current_subtable[tag]=param
				end
			end

			--Figure out where the new x and y coords should be
			new_x=xpos_func[current_style.align%3](substr_data[i].width)
			--new_y=ypos_func[math.ceil(current_style.align/3)](substr_data[i].height)

			--Check if the text ends in whitespace
			wsp=val.text:gsub("\n",""):match("%s+$")

			--Modify positioning accordingly
			if wsp~=nil then
				wsp_width=aegisub.text_extents(val.style,wsp)
				if current_style.align%3==2 then new_x=new_x-wsp_width/2
				elseif current_style.align%3==0 then new_x=new_x-wsp_width end
			end

			--Increase x offset
			xoffset=xoffset+substr_data[i].width

			--Handle what happens in the line contains newlines
			--[[if val.text:match("\n")~=nil then
				--Increase index and reset x offset
				nindex=nindex+1
				xoffset=0
				--Increase y offset
				yoffset=yoffset+substr_data[i].height

				--Remove the last newline and convert back to \N
				val.text=val.text:gsub("\n$","")
				val.text=val.text:gsub("\n","\\N")
			end]]--

			--Start rebuilding text
			rebuilt_tag=string.format("{\\pos(%s,%s)}",float2str(new_x),float2str(py))

			--Add the remaining tags
			for tag,param in pairs(current_subtable) do
				if tag=="t" then
					for k,ttime in ipairs(param) do
						rebuilt_tag=rebuilt_tag:gsub("}",ttime.."}")
					end
				elseif tag~="pos" and tag~="org" then
					rebuilt_tag=rebuilt_tag:gsub("{","{\\"..tag..param)
				end
			end

			if do_org then
				rebuilt_tag=rebuilt_tag:gsub("{",string.format("{\\org(%s,%s)",float2str(ox),float2str(oy)))
			end

			new_line.text=rebuilt_tag..val.text

			--Insert the new line
			sub.insert(li+lines_added+1,new_line)
			lines_added=lines_added+1

		end

	end

	aegisub.set_undo_point(script_name)
end


aegisub.register_macro(script_name,script_description,split_tag)

