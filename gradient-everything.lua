--[[
==README==

Gradient Everything

Define "key" lines, and this will gradient almost anything.

If you've used the "frame-by-frame transform" script, this behaves very similarly. The typesetter
creates lines that he wants to morph into each other, then highlights them and runs the automation.

The automation cannot calculate how to draw the \clip statements unless you give it a bounding box.
This is essentially the smallest box that will enclose your entire typeset without cutting any part
of it off. Use the rectangular clip tool in aegisub to define a bounding box on any of the lines you
want to gradient, and the automation will detect it.

As a simple example, say you want to create a line with a gradient from red to blue. First typeset
the line and make it red. Then duplicate that line and make it blue. Use the rectancular clip tool
to draw a bounding box that encloses the typeset (it doesn't have to be super tight, but keep the
margins small or the gradient might not look right). You can do this on either of the lines, it
doesn't matter.

Now highlight both lines, go to the automation menu, and select "gradient everything". Check all the
tags you wish to be affected by the gradient. In this case, you want to be sure to check the color
tags. Select whether you want the gradient to be vertical or horizontal, and pick how many pixels
per strip you prefer (the fewer pixels per strip, the smoother the gradient, the more lines, and
the more lag). Press "Gradient" and you're done.

This script uses the same preset system as frame-by-frame transform. You can save, delete, and load
preset sets of options so you don't have to check the tags you want each time. If you name a preset
"Default", it will be the preset that's loaded when you open the automation.

If you are gradienting rotations, there is something to watch out for. If you want a line to start
with \frz10 and bend into \frz350, then with default options, the "gradient everything" automation will
make the line bend 340 degrees around the circle until it gets to 350. You probably wanted it to bend
only 20 degrees, passing through 0. The solution is to check the "Rotate in shortest direction" checkbox
from the popup window. This will cause the line to always pick the rotation direction that has a total
rotation of less than 180 degrees.

Furthermore, you don't have to gradient from only one line to one other line. You are allowed to have
as many lines as you want. For example, if you define three lines, one red, one yellow, and one green,
then "gradient everything" will make it red on the left, yellow in the center, and green on the right.

As such, the order of your lines matters. If you select "horizontal", then "gradient everything" will
gradient your lines in order from left to right. If you select "vertical", then it will gradient your
lines in order from top to bottom. If you want the gradient to go the other way, then change the order
of your lines. You must select all the lines that you wish to include in the gradient.

Much like "frame-by-frame transform", all the lines you are gradienting must have the exact same text
once tags are removed.

Oh yeah, I've tested this script on about four things so far, so don't be surprised if it's buggy.


TODO: Debug, debug, and keep debugging

]]--

script_name="Gradient everything"
script_description="Define a bounding box, and this will gradient everything."
script_version="0.2.3"

include("karaskel.lua")
include("utils.lua")

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

--Set the location of the config file
local config_path=aegisub.decode_path("?user").."ge-presets.config"

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

function create_config()
	
	local config={
		--define pixels per strip
		{
			class="label",
			label="Pixels per strip:",
			x=0, y=0, width=2, height=1
		},
		{
			class="intedit",
			name="strip_pix",
			x=2, y=0, width=2, height=1,
			min=1, value=5, step=1
		},
		{
			class="dropdown",
			name="hv_select",
			x=4,y=0,width=1,height=1,
			items={"horizontal", "vertical"},
			value="horizontal"
		},
		--first the colors
		{
			class="checkbox",
			name="c",label="c",
			x=0, y=1, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="2c",label="2c",
			x=1, y=1, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="3c",label="3c",
			x=2, y=1, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="4c",label="4c",
			x=3, y=1, width=1, height=1,
			value=false
		},
		--then the alphas
		{
			class="checkbox",
			name="alpha",label="alpha",
			x=0, y=2, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="1a",label="1a",
			x=1, y=2, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="2a",label="2a",
			x=2, y=2, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="3a",label="3a",
			x=3, y=2, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="4a",label="4a",
			x=4, y=2, width=1, height=1,
			value=false
		},
		--scale
		{
			class="checkbox",
			name="fscx",label="fscx",
			x=0, y=3, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="fscy",label="fscy",
			x=1, y=3, width=1, height=1,
			value=false
		},
		--shear
		{
			class="checkbox",
			name="fax",label="fax",
			x=2, y=3, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="fay",label="fay",
			x=3, y=3, width=1, height=1,
			value=false
		},
		--rotation
		{
			class="checkbox",
			name="frx",label="frx",
			x=0, y=4, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="fry",label="fry",
			x=1, y=4, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="frz",label="frz",
			x=2, y=4, width=1, height=1,
			value=false
		},
		--border, shadow, font size, font spacing 
		{
			class="checkbox",
			name="bord",label="bord",
			x=0, y=5, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="shad",label="shad",
			x=1, y=5, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="fs",label="fs",
			x=2, y=5, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="fsp",label="fsp",
			x=3, y=5, width=1, height=1,
			value=false
		},
		--x/y bord/shad
		{
			class="checkbox",
			name="xbord",label="xbord",
			x=0, y=6, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="ybord",label="ybord",
			x=1, y=6, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="xshad",label="xshad",
			x=2, y=6, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="yshad",label="yshad",
			x=3, y=6, width=1, height=1,
			value=false
		},
		--blur
		{
			class="checkbox",
			name="blur",label="blur",
			x=0, y=7, width=1, height=1,
			value=false
		},
		{
			class="checkbox",
			name="be",label="be",
			x=1, y=7, width=1, height=1,
			value=false
		},
		--Org
		{
			class="checkbox",
			name="do_org",label="org",
			x=0,y=8,wdith=1,height=1,
			value=false
		},
		--Flip rotation
		{
			class="checkbox",
			name="flip_rot",label="Rotate in shortest direction",
			x=0,y=9,width=4,height=1,
			value=false
		},
		--Acceleration
		{
			class="label",
			label="Acceleration:",
			x=0,y=10,width=2,height=1
		},
		{
			class="floatedit",
			name="accel",
			x=2,y=10,width=2,height=1,
			value=1.0,
			hint="1 means no acceleration, >1 starts slow and ends fast, <1 starts fast and ends slow"
		}
	}
	
	return config
end

--Convert float to neatly formatted string
local function float2str(f) return string.format("%.3f",f):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end

--Creates a deep copy of the given table
local function deep_copy(source_table)
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

--Modify the line tables so they are split at the same locations
local function match_splits(line_table1,line_table2)
	local i=1
	while(i<=#line_table1) do
		text1=line_table1[i].text
		tag1=line_table1[i].tag
		text2=line_table2[i].text
		tag2=line_table2[i].tag
		--If the table1 item has longer text, break it in two based on the text of table2
		if text1:len() > text2:len() then
			_,_,newtext=text1:find(text2.."(.*)")
			for j=#line_table1,i+1,-1 do
				line_table1[j+1]=line_table1[j]
			end
			line_table1[i]={tag=tag1,text=text2}
			line_table1[i+1]={tag="{}",text=newtext}
		--If the table2 item has longer text, break it in two based on the text of table1
		elseif text1:len() < text2:len() then
			_,_,newtext=text2:find(text1.."(.*)")
			for j=#line_table2,i+1,-1 do
				line_table2[j+1]=line_table2[j]
			end
			line_table2[i]={tag=tag2,text=text1}
			line_table2[i+1]={tag="{}",text=newtext}
		end
		i=i+1
	end
	
	return line_table1,line_table2
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
	return posx,posy
end

--Returns the origin of a line
local function get_org(line)
	local _,_,orgx,orgy=line.text:find("\\org%(([%d%.%-]*),([%d%.%-]*)%)")
	if orgx==nil then
		return get_pos(line)
	end
	return orgx,orgy
end

--The main body of code that runs the frame transform
function gradient_everything(sub,sel,config)
	
	--Get meta and style info
	local meta,styles = karaskel.collect_head(sub, false)
	
	--These are the tags to transform
	transform_tags={}
	
	--Add based on config
	--(This could probably be done with a for statement, but it's not like that'll have better runtime)
	if config["c"] then table.insert(transform_tags,"c") end
	if config["2c"] then table.insert(transform_tags,"2c") end
	if config["3c"] then table.insert(transform_tags,"3c") end
	if config["4c"] then table.insert(transform_tags,"4c") end
	if config["alpha"] then table.insert(transform_tags,"alpha") end
	if config["1a"] then table.insert(transform_tags,"1a") end
	if config["2a"] then table.insert(transform_tags,"2a") end
	if config["3a"] then table.insert(transform_tags,"3a") end
	if config["4a"] then table.insert(transform_tags,"4a") end
	if config["fscx"] then table.insert(transform_tags,"fscx") end
	if config["fscy"] then table.insert(transform_tags,"fscy") end
	if config["frx"] then table.insert(transform_tags,"frx") end
	if config["fry"] then table.insert(transform_tags,"fry") end
	if config["frz"] then table.insert(transform_tags,"frz") end
	if config["bord"] then table.insert(transform_tags,"bord") end
	if config["shad"] then table.insert(transform_tags,"shad") end
	if config["fsp"] then table.insert(transform_tags,"fsp") end
	if config["fs"] then table.insert(transform_tags,"fs") end
	if config["blur"] then table.insert(transform_tags,"blur") end
	if config["be"] then table.insert(transform_tags,"be") end
	if config["fax"] then table.insert(transform_tags,"fax") end
	if config["fay"] then table.insert(transform_tags,"fay") end
	if config["xbord"] then table.insert(transform_tags,"xbord") end
	if config["ybord"] then table.insert(transform_tags,"ybord") end
	if config["xshad"] then table.insert(transform_tags,"xshad") end
	if config["yshad"] then table.insert(transform_tags,"yshad") end
		
	--Number of pixels per strip
	strip=config["strip_pix"]	
	
	--Controls whether rotations always go in direction of least rotation
	do_flip_rotation=config["flip_rot"]
	
	--Set the acceleration (default 1)
	local accel=config["accel"]
	
	--Controls whether to apply transform to or origin
	do_org=config["do_org"]
	
	--Controls vertical or horizontal
	do_vertical=true
	if config["hv_select"]=="horizontal" then do_vertical=false end
	
	--left, top, right, bottom
	clip1,clip2,clip3,clip4=nil,nil,nil,nil
	
	--Look for a clip statement in one of the lines
	for si,li in ipairs(sel) do
		this_line=sub[li]
		found,_,clip1,clip2,clip3,clip4=
			this_line.text:find("\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)")
		if found then break end
	end
	
	--Exit if none of the lines contain a rectangular clip
	if clip1==nil then
		aegisub.log("Please put a rectangular clip in one of the selected lines.")
		return
	end
	
	clip1=tonumber(clip1)
	clip2=tonumber(clip2)
	clip3=tonumber(clip3)
	clip4=tonumber(clip4)
	
	--Make sure clip1 is the left and clip3 is the right
	if clip1>clip3 then
		_temp=clip3
		clip3=clip1
		clip1=_temp
	end
	
	--Make sure clip2 is the top and clip4 is the bottom
	if clip2>clip4 then
		_temp=clip4
		clip4=clip2
		clip2=_temp
	end
	
	--The pixel dimension of the relevant direction of gradient
	span=0
	if do_vertical then span=clip4-clip2
	else span=clip3-clip1 end
	
	--Stores how many frames between each key line
	--Index 1 is how many frames between keys 1 and 2, and so on
	frames_per={}
	_temp_total=0
	for i=2,#sel,1 do
		_temp=math.ceil((i-1)/(#sel-1) * span/strip)
		frames_per[i-1]=_temp-_temp_total
		_temp_total=_temp
	end
	
	--IMPORTANT CONTROL VARIABLES
	--Must be initialized here
	--The cumulative pixel offset that indicates the start of the line
	cum_off=0
	--And the index of insertion
	ins_index=1
	
	--Store the new selection
	local new_sel={}
	
	--Master control loop
	--First cycle through all the selected "intervals" (pairs of two consecutive selected lines)
	for i=2,#sel,1 do
		--Read the first and last lines
		first_line=sub[sel[i]-1]
		last_line=sub[sel[i]]
		
		--And comment them out
		first_line.comment=true
		last_line.comment=true
		sub[sel[i]-1]=first_line
		sub[sel[i]]=last_line
		
		--Preprocess
		karaskel.preproc_line(sub,meta,styles,first_line)
		karaskel.preproc_line(sub,meta,styles,last_line)
		
		--Figure out the correct position values
		local sposx,sposy=get_pos(first_line)
		local eposx,eposy=get_pos(last_line)
		
		--Look for origin
		local sorgx,sorgy=get_org(first_line)
		local eorgx,eorgy=get_org(last_line)
		
		--Make sure each line starts with tags
		if first_line.text:find("^{")==nil then first_line.text="{}"..first_line.text end
		if last_line.text:find("^{")==nil then last_line.text="{}"..last_line.text end
		
		--Turn all \1c tags into \c tags, just for convenience
		first_line.text=first_line.text:gsub("\\1c","\\c")
		last_line.text=last_line.text:gsub("\\1c","\\c")
		
		--The tables that store the line as objects consisting of a tag and the text that follows it
		local start_table={}
		local end_table={}
		
		--Separate each line into a table of tags and text
		x=1
		for thistag,thistext in first_line.text:gmatch("({[^{}]*})([^{}]*)") do
			start_table[x]={tag=thistag,text=thistext}
			x=x+1
		end
		
		x=1
		for thistag,thistext in last_line.text:gmatch("({[^{}]*})([^{}]*)") do
			end_table[x]={tag=thistag,text=thistext}
			x=x+1
		end
		
		--Make sure both lines have the same splits
		start_table,end_table=match_splits(start_table,end_table)
		
		--Tables that store tables for each tag block, consisting of the state of all relevant tags
		--that are in the transform_tags table
		local start_state_table=make_state_table(start_table,transform_tags)
		local end_state_table=make_state_table(end_table,transform_tags)
		
		--Insert default values when not included for the state of each tag block,
		--or inherit values from previous tag block
		start_style=style_lookup(first_line)
		end_style=style_lookup(last_line)
		
		current_end_state={}
		current_start_state={}
		
		for k,sval in ipairs(start_state_table) do
			--build current state tables
			for skey,sparam in pairs(sval) do
				current_start_state[skey]=sparam
			end
			for ekey,eparam in pairs(end_state_table[k]) do
				current_end_state[ekey]=eparam
			end
			
			--check if end is missing any tags that start has
			for skey,sparam in pairs(sval) do
				if end_state_table[k][skey]==nil then
					if current_end_state[skey]==nil then
						end_state_table[k][skey]=end_style[skey]
					else
						end_state_table[k][skey]=current_end_state[skey]
					end
				end
			end
			--check if start is missing any tags that end has
			for ekey,eparam in pairs(end_state_table[k]) do
				if start_state_table[k][ekey]==nil then
					if current_start_state[ekey]==nil then
						start_state_table[k][ekey]=start_style[ekey]
					else
						start_state_table[k][ekey]=current_start_state[ekey]
					end
				end
			end
		end
		
		--Create a line table based on first_line, but without relevant tags
		local _temp_text=line_exclude(first_line.text,{unpack(transform_tags),"clip"})
		local this_table={}
		x=1
		for thistag,thistext in _temp_text:gmatch("({[^{}]*})([^{}]*)") do
			this_table[x]={tag=thistag,text=thistext}
			x=x+1
		end
		
		--Inner control loop
		--For the number of lines indicated by the frames_per table, create a gradient
		for j=1,frames_per[i-1],1 do
			--The interpolation factor for this particular line
			local factor=0
			--Failsafe because dividing by 0 is bad
			if frames_per[i-1]<2 then factor=1
			else factor=((j-1)^accel)/((frames_per[i-1]-1)^accel) end
			
			--Create this line
			this_line={}
			this_line=deep_copy(first_line)
			
			--Create the relevant clip tag
			--(as of this version, the 1 pixel overlap has been removed. Hopefully colors still look fine)
			local clip_tag="\\clip(%d,%d,%d,%d)"
			if do_vertical then clip_tag=clip_tag:format(clip1,clip2+cum_off+(j-1)*strip,clip3,clip2+cum_off+j*strip)
			else clip_tag=clip_tag:format(clip1+cum_off+(j-1)*strip,clip2,clip1+cum_off+j*strip,clip4) end
						
			--Interpolate all the relevant parameters and insert		
			rebuilt_text=""
			this_current_state={}
			
			for k,val in ipairs(this_table) do
				temp_tag=val.tag
				--Cycle through all the tag blocks and interpolate
				for ctag,param in pairs(start_state_table[k]) do
					temp_tag=temp_tag:gsub("}", function()
						local ivalue=""
						if param_type[ctag]=="alpha" then
							--aegisub.debug.out(2," interpolating "..ctag.."\n")
							ivalue=interpolate_alpha(factor,start_state_table[k][ctag],end_state_table[k][ctag])
							
						elseif param_type[ctag]=="color" then
							--aegisub.debug.out(2," interpolating "..ctag.."\n")
							ivalue=interpolate_color(factor,start_state_table[k][ctag],end_state_table[k][ctag])
							
						elseif param_type[ctag]=="number" or param_type[ctag]=="angle" then
							--aegisub.debug.out(2," interpolating "..ctag.."\n")
							nstart=tonumber(start_state_table[k][ctag])
							nend=tonumber(end_state_table[k][ctag])
							if param_type[ctag]=="angle" and do_flip_rotation then
								nstart=nstart%360
								nend=nend%360
								ndelta=nend-nstart
								if math.abs(ndelta)>180 then nstart=nstart+(ndelta*360)/math.abs(ndelta) end
							end
							nvalue=interpolate(factor,nstart,nend)
							
							if param_type[ctag]=="angle" and nvalue<0 then
								nvalue=nvalue+360
							end
							
							ivalue=float2str(nvalue)
						end
						
						--check for redundancy
						if this_current_state[ctag]~=nil and this_current_state[ctag]==ivalue then
							return "}"
						end
						this_current_state[ctag]=ivalue
						
						return "\\"..ctag..ivalue.."}"
					end)
				end
				rebuilt_text=rebuilt_text..temp_tag..val.text
			end
			
			--Set the text and uncomment
			this_line.text=rebuilt_text:gsub("{}","")
			this_line.comment=false
			
			--Forcibly add \pos
			this_line.text=line_exclude(this_line.text,{"pos"})
			this_line.text=this_line.text:gsub("^{",
					"{\\pos("..
					float2str(interpolate(factor,sposx,eposx))..","..
					float2str(interpolate(factor,sposy,eposy))..")"	
				)
			
			--Handle org transform
			if do_org then
				this_line.text=line_exclude(this_line.text,{"org"})
				this_line.text=this_line.text:gsub("^{",
						"{\\org("..
						float2str(interpolate(factor,sorgx,eorgx))..","..
						float2str(interpolate(factor,sorgy,eorgy))..")"
					)
			end
			
			--Oh yeah, and add the clip tag
			this_line.text=this_line.text:gsub("^{","{"..clip_tag)
			
			--Reinsert the line			
			sub.insert(sel[#sel]+ins_index,this_line)
			table.insert(new_sel,sel[#sel]+ins_index)
			ins_index=ins_index+1
			
		end
		
		--Increase the cumulative offset
		cum_off=cum_off+frames_per[i-1]*strip
	end
	return new_sel
end

--Opens the given file path and writes the preset tables to it
function write_presets_to_file(ppath,ptable)
	local pfile=io.open(ppath,"wb")
	pfile:write("return\n")
	for i,val in ipairs(ptable) do
		write_table(val,pfile)
		if i~=#ptable then pfile:write(",\n") end
	end
	pfile:close()
end

--Opens the given file path and reads presets from it, or returns nil if file does not exist
function open_presets_from_file(ppath)
	local pfile=io.open(ppath,"r")
	if pfile==nil then return nil end
	local return_presets,err = loadstring(pfile:read("*all"))
	if err then aegisub.log(err) return nil end
	pfile:close()
	return {return_presets()}
end

--Remove the preset with the given name from the presets table
function delete_preset(ptable,pname)
	for i,val in ipairs(ptable) do
		if val.name==pname then
			table.remove(ptable,i)
			break
		end
	end
end

--Re-run the previous application of gradient everything
function load_ge_previous(sub,sel)
	local presets=open_presets_from_file(config_path)
	if presets==nil then
		aegisub.log("Could not detect presets. Please run the gradient everything automation first.")
		return
	end
	local preset_used
	for i,val in pairs(presets) do
		if val.name=="?last" then
			preset_used=val.value
		end
	end
	if preset_used==nil then
		aegisub.log("Could not detect last used settings. Please run the gradient everything automation first.")
		return
	end
	gradient_everything(sub,sel,preset_used)
	aegisub.set_undo_point(script_name.." - repeat last")
end

function load_ge(sub,sel)

	--Create a new config file with the "horizontal all" default, if it doesn't exist
	local presets=open_presets_from_file(config_path)
	if presets==nil then
		local def_config=create_config()
		local results_all={}
		for conkey,conval in ipairs(def_config) do
			if conval.class=="checkbox" then
				results_all[conval.name]=true
			elseif conval.class=="floatedit" then
				results_all[conval.name]=1
			elseif conval.name=="strip_pix" then
				results_all[conval.name]=5
			elseif conval.name=="hv_select" then
				results_all[conval.name]="horizontal"
			end
		end
		write_presets_to_file(config_path,{{name="Horizontal all",value=results_all}})
		
		presets=open_presets_from_file(config_path)
	end
	
	--The preset that is selected on script load
	default_preset_name="No preset"
	
	--Store dropdown options
	local preset_names={"No preset"}
	for i,val in ipairs(presets) do
		if val.name~="?last" then table.insert(preset_names,val.name) end
		if val.name=="Default" then default_preset_name="Default" end
	end
	
	local buttons={"Gradient","Load preset","Preset manager","Cancel"}
	local pressed,results
	
	local config=create_config()
	
	--Add preset options to the default config
	local preset_label=
		{
			class="label",
			label="Preset:",
			x=0,y=11,width=2,height=1
		}
	local preset_dropdown=
		{
			class="dropdown",
			name="preset_select",
			x=2,y=11,width=3,height=1,
			items=preset_names,
			value=default_preset_name
		}
	table.insert(config,preset_label)
	table.insert(config,preset_dropdown)
	
	repeat
		--Load selected preset
		if pressed=="Load preset" then
			local load_this_preset={}
			for i,val in ipairs(presets) do
				if val.name==results["preset_select"] then
					load_this_preset=val.value
				end
			end
			for i,val in ipairs(config) do
				if load_this_preset[val.name]~= nil then
					val.value=load_this_preset[val.name]
				end
			end
			--If you've loaded a preset, presumably you're about to modify it, so switch to "No preset"
			preset_dropdown.value="No preset"
		--Open preset manager
		elseif pressed=="Preset manager" then
			man_pressed,results=aegisub.dialog.display(config,{"Save preset","Delete preset","Cancel"})
			if man_pressed~="Cancel" then
				--Handle deletion of a preset
				if man_pressed=="Delete preset" then
					--Do not allow the deletion of "Horizontal all" or "No preset"
					if results["preset_select"]~="No preset" and results["preset_select"]~="Horizontal all" then
						delete_preset(presets,results["preset_select"])
					end
					preset_dropdown.value="No preset"
				--Handle saving new preset
				else
					
					local is_duplicate, is_blank
					repeat
						is_duplicate, is_blank=false, false
						--Prompt for preset name
						_,temp_preset_name=aegisub.dialog.display(
								{
									{class="label",label="Enter name of new preset:",x=0,y=0,width=1,height=1},
									{class="edit",name="new_name",x=1,y=0,width=1,height=1}
								},
								{"Save"}
							)
						
						--Check if it's a duplicate name
						if temp_preset_name["new_name"]=="" then is_blank=true end
						for i,val in ipairs(preset_names) do
							if temp_preset_name["new_name"]==val then is_duplicate=true end
						end
						if is_duplicate then
							aegisub.dialog.display({{
								class="label",label="Onii-chan, it's not good to name a preset\n"..
								"the same thing as another one~",x=0,y=0,width=1,height=1
								}},{"OK"})
						end
						--Check if the name is a non-empty string
						if is_blank then
							aegisub.dialog.display({{
								class="label",label="Onii-chan, did you forget to name the preset?",
								x=0,y=0,width=1,height=1
								}},{"OK"})

						end
						--Check if it's the reserved "?last" table (I don't know why anyone would try this but)
						if temp_preset_name["new_name"]=="?last" then
							aegisub.dialog.display({{
								class="label",label="Oh my, Onii-chan, I was saving that name for\n"..
								"something special~",x=0,y=0,width=1,height=1
								}},{"OK"})
							is_duplicate=true
						end
					until not is_duplicate and not is_blank
					
					results["preset_select"]=nil
					
					--Add the new preset
					table.insert(presets,{name=temp_preset_name["new_name"],value=results})
					preset_dropdown.value=temp_preset_name["new_name"]
				end
				
				--Rewrite the config file to reflect changes in presets
				write_presets_to_file(config_path,presets)
				
				--Recreate list of preset names
				preset_names={"No preset"}
				
				--Booleans to track what preset it should default to
				local has_default=false
				local has_current=false
				for i,val in ipairs(presets) do
					if val.name~="?last" then table.insert(preset_names,val.name) end
					if val.name=="Default" then has_default=true end
					if val.name==preset_dropdown.value then has_current=true end
				end
				if has_default and not has_current then preset_dropdown.value="Default" end
				preset_dropdown.items=preset_names
			end
		end
		pressed,results=aegisub.dialog.display(config,buttons)
		--Make config reflect result values
		for i,val in ipairs(config) do
			if results[val.name]~= nil then
				val.value=results[val.name]
			end
		end
	until pressed~="Preset manager" and pressed~="Load preset"
	if pressed=="Gradient" then
		local preset_used={}
		if results["preset_select"]=="No preset" then
			preset_used=results
		else
			for i,val in pairs(presets) do
				if val.name==results["preset_select"] then
					preset_used=val.value
				end
			end
		end
		new_sel=gradient_everything(sub,sel,preset_used)
		
		--Get rid of the previous "last used"
		delete_preset(presets,"?last")
		--Add a new one
		table.insert(presets,{name="?last",value=preset_used})
		write_presets_to_file(config_path,presets)
		
		--Set undo point
		aegisub.set_undo_point(script_name)
		return new_sel
	end
	return sel
end

function validate_ge(sub,sel)
	return #sel>=2
end

--Register the gradient everything macro
aegisub.register_macro(script_name, script_description, load_ge, validate_ge)

--Register the repeat last macro
aegisub.register_macro(script_name.." - repeat last", "Repeats the last "..script_name.." operation", load_ge_previous, validate_ge)
