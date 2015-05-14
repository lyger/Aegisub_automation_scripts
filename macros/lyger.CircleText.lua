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

script_name = "Circular text"
script_description = "Puts the text on a circular arc centered on the origin."
script_version = "0.2.0"
script_author = "lyger"
script_namespace = "lyger.CircleText"

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

--[[
Tags that can have any character after the tag declaration:
\r
\fn
Otherwise, the first character after the tag declaration must be:
a number, decimal point, open parentheses, minus sign, or ampersand
]]--


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
	libLyger:set_sub(sub, sel)
	for si,li in ipairs(sel) do
		--Progress report
		aegisub.progress.task("Processing line "..si.."/"..#sel)
		aegisub.progress.set(100*si/#sel)

		--Read in the line
		line = libLyger.lines[li]

		--Get position and origin
		px, py = libLyger:get_pos(line)
		ox, oy = libLyger:get_org(line)

		--Make sure pos and org are not the same
		if px==ox and py==oy then
			aegisub.log(1,"Error on line %d: Position and origin cannot be the same!",li)
			return
		end

		--Get radius
		radius=distance(px,py,ox,oy)

		--Remove \pos and \move
		--If your line was non-static, too bad
		line.text = LibLyger.line_exclude(line.text,{"pos","move"})

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
		current_style = util.deep_copy(line.styleref)

		--First pass to collect data on character widths
		for i,val in ipairs(line_table) do

			char_data[i]={}

			--Fix style tables to reflect override tags
			local _,_,font_name=val.tag:find("\\fn([^\\{}]+)")
			local _,_,font_size=val.tag:find("\\fs([%-%.%d]+)")
			local _,_,font_scx=val.tag:find("\\fscx([%-%.%d]+)")
			local _,_,font_scy=val.tag:find("\\fscy([%-%.%d]+)")
			local _,_,font_sp=val.tag:find("\\fsp([%-%.%d]+)")
			local _,_,_bold=val.tag:find("\\b([01])")
			local _,_,_italic=val.tag:find("\\i([01])")

			current_style.fontname=font_name or current_style.fontname
			current_style.fontsize=tonumber(font_size) or current_style.fontsize
			current_style.scale_x=tonumber(font_scx) or current_style.scale_x
			current_style.scale_y=tonumber(font_scy) or current_style.scale_y
			current_style.spacing=tonumber(font_sp) or current_style.spacing
			if _bold~=nil then
				if _bold=="1" then current_style.bold=true
				else current_style.bold=false end
			end
			if _italic~=nil then
				if _italic=="1" then current_style.italic=true
				else current_style.italic=false end
			end

			val.style = util.deep_copy(current_style)

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

				rebuilt_text=rebuilt_text..string.format("{\\frz%.3f\\fsp%.2f}%s",
					(start_angle+rot_dir*cum_rot)%360,this_spacing,tchar.char)

				cum_rot=cum_rot+arc_angle(this_width,radius)
			end
		end

		--[[
		--Fuck the re library. Maybe I'll come back to this
		whitespaces=re.find(rebuilt_text,
			'(\{\\\\frz[\\d\\.\\-]+\\\\fsp[\\d\\.\\-]+\}\\S)((?:\{\\\\frz[\\d\\.\\-]+\\\\fsp[\\d\\.\\-]+\}\\s)+)')

		for j=1,#whitespaces-1,2 do
			first_tag=whitespaces[j].str
			other_tags=whitespaces[j+1].str
			aegisub.log("%s%s\n",first_tag,other_tags)
			first_space=first_tag:match("\\fsp([%d%.%-]+)")
			other_spaces=0
			total_wsp=0
			for _sp in other_tags:gmatch("\\fsp([%d%.%-]+)") do
				other_spaces=other_spaces+tonumber(_sp)
				total_wsp=total_wsp+1
			end
			total_space=tonumber(first_space)+other_spaces
			rebuilt_text=rebuilt_text:gsub(first_tag..other_tags,
				first_tag:gsub("\\fsp[%d%.%-]+",string.format("\\fsp%.2f",total_space))..string.rep(" ",total_wsp))
		end]]--

		line.text=rebuilt_text:gsub("}{","")

		sub[li]=line

	end

	aegisub.set_undo_point(script_name)

end

rec:registerMacro(circle_text)
