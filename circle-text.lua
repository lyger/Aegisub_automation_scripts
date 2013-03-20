--[[
==README==

Circular Text

Define an origin, and this will put the text on a circular arc centered on that origin.

An origin must be defined and it must be different from the position of the line. You can't have
a circle if the radius is zero.

The x coordinate of the position tag should match the x coordinate of the origin tag for best
results. In other words, your original line should be at a right angle to the radius. Note that
these are the x coordinates in the tags, not the x coordinates on screen, which will change if
you rotate the tag.

Supports varied fonts, font sizes, font spacings, and x/y scales in the same line.

The resulting arc will be centered on the original rotation of your line.

Only works on static lines. If you want the line to move or rotate, use another macro.


]]--

script_name="Circular text"
script_description="Puts the text on a circular arc centered on the origin"
script_version="0.1"

include("karaskel.lua")

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
					posx=vid-x-line.eff_margin_r
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

--Distance between two points
local function distance(x1,y1,x2,y2)
	return math.sqrt((x2-x1)^2+(y2-y1)^2)
end

--Sign of a value
local function sign(n)
	return n/math.abs(n)
end

--Angle in degrees, given the arc length and radius
local function arc_angle(arc_length,radius)
	return arc_length/radius * 180/math.pi
end

--Main processing function
function circle_text(sub,sel)
	
	--Read in styles and meta
	local meta,styles = karaskel.collect_head(sub, false)
	
	for si,li in ipairs(sel) do
		--Read in the line
		line=sub[li]
		
		--Preprocess
		karaskel.preproc_line(sub,meta,styles,line)
		
		--Get position and origin
		px,py=get_pos(line)
		ox,oy=get_org(line)
		
		--Make sure pos and org are not the same
		if px==ox and py==oy then
			aegisub.log(1,"Error on line %d: Position and origin cannot be the same!",li)
			return
		end
		
		--Get radius
		radius=distance(px,py,ox,oy)
		
		--Remove \pos and \move
		--If your line was non-static, too bad
		line.text=line_exclude(line.text,{"pos","move"})
		
		--Make sure line starts with a tag block
		if line.text:find("^{")==nil then
			line.text="{}"..line.text
		end
		
		--Rotation direction: positive if each character adds to the angle,
		--negative if each character subtracts from the angle
		rot_dir=sign(py-oy)
		
		--Add the \pos back with recalculated position
		line.text=line.text:gsub("^{",string.format("{\\pos(%d,%d)",ox,oy+rot_dir*radius))
		
		--Get z rotation
		--Will only take the first one, because if you wanted the text to be on a circular arc,
		--why do you have more than one z rotation tag in the first place?
		_,_,zrot=line.text:find("\\frz([%-%.%d]+)")
		zrot=zrot or line.styleref.angle
		
		--Make line table
		line_table={}
		for thistag,thistext in line.text:gmatch("({[^{}]*})([^{}]*)") do
			table.insert(line_table,{tag=thistag,text=thistext})
		end
		
		--Where data on the character widths will be stored
		char_data={}
		
		--Total width of line
		cum_width=0
		
		--Stores current state of the line as style table
		current_style=deep_copy(line.styleref)
		
		--First pass to collect data on character widths
		for i,val in ipairs(line_table) do
			
			char_data[i]={}
			
			--Fix style tables to reflect override tags
			local _,_,font_name=val.tag:find("\\fn([^\\{}]+)")
			local _,_,font_size=val.tag:find("\\fs([%-%.%d]+)")
			local _,_,font_scx=val.tag:find("\\fscx([%-%.%d]+)")
			local _,_,font_scy=val.tag:find("\\fscy([%-%.%d]+)")
			local _,_,font_sp=val.tag:find("\\fsp([%-%.%d]+)")
			
			current_style.fontname=font_name or current_style.fontname
			current_style.fontsize=tonumber(font_size) or current_style.fontsize
			current_style.scale_x=tonumber(font_scx) or current_style.scale_x
			current_style.scale_y=tonumber(font_scy) or current_style.scale_y
			current_style.spacing=tonumber(font_sp) or current_style.spacing
			
			val.style=deep_copy(current_style)
			
			--Collect width data on each char
			for thischar in val.text:gmatch(".") do
				cwidth=aegisub.text_extents(val.style,thischar)
				table.insert(char_data[i],{char=thischar,width=cwidth})
			end
			
			--Increment cumulative width
			cum_width=cum_width+aegisub.text_extents(val.style,val.text)
			
		end
		
		--The angle that the rotation will begin at
		start_angle=zrot-(rot_dir*arc_angle(cum_width,radius))/2
		
		rebuilt_text=""
		cum_rot=0
		
		--Second pass to rebuild line with new tags
		for i,val in ipairs(line_table) do
		
			rebuilt_text=rebuilt_text..val.tag:gsub("\\fsp[%-%.%d]+",""):gsub("\\frz[%-%.%d]+","")
			
			for k,tchar in ipairs(char_data[i]) do
				--Character spacing should be the average of this character's width and the next one's
				--For spacing, scale width back up by the character's relevant scale_x,
				--because \fsp scales too. Also, subtract the existing font spacing
				this_spacing=0
				this_width=0
				if k~=#char_data[i] then
					this_width=(tchar.width+char_data[i][k+1].width)/2
					this_spacing=-1*(this_width*100/val.style.scale_x-val.style.spacing)
				else
					this_width=i~=#line_table and (tchar.width+char_data[i+1][1].width)/2 or 0
					this_spacing=i~=#line_table
						and -1*((tchar.width*100/val.style.scale_x 
							+ char_data[i+1][1].width*100/line_table[i+1].style.scale_x)/2
							-val.style.spacing)
						or 0
				end
				
				rebuilt_text=tchar.char==" " and rebuilt_text.." "
					or rebuilt_text..string.format("{\\frz%.3f\\fsp%.2f}%s",
						start_angle+rot_dir*cum_rot,this_spacing,tchar.char)
				
				cum_rot=cum_rot+arc_angle(this_width,radius)
			end
		end
		
		line.text=rebuilt_text:gsub("}{","")
		
		sub[li]=line
		
	end
	
end

aegisub.register_macro(script_name,script_description,circle_text)