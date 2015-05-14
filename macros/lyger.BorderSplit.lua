--[[
========================
Duplicate and Blur lines
========================


==INSTRUCTIONS (SHORT VER.)==

Install by putting this script in your Aegisub program files, under "automation\autoload\"

This macro will apply to any line in the script that has "bord" in the actor field. Typeset
your bordered sign on a single line and mark it with "bord" and any relevant options (see
the long instructions, below), then go to Automation -> Duplicate and Blur.

If a blur is defined in the line, it will be used. Otherwise, the blur defined in the
"default_blur" global variable (see below) will be used. If no outline is defined in the
line, style defaults will be used.


==INSTRUCTIONS (LONG VER.)==

This macro is used to alleviate tedium from typesetting bordered lines.

Since a blur or edgeblur on a line with an outline only applies to the outline, typesetters
often have to duplicate lines and get rid of the border on one of them, so that both the
inner text and the outline can have a blur. This macro automates the process.

There are two primary modes and a couple extra options (may add more later). When you mark
a line with just "bord", the macro will use your default mode (see global variables section,
below) and no options. If you want to force a different mode, put the letter that represents
it after the "bord" keyword. If you want to use any options, add the letter after the mode.
You can only use one mode and it must come first, but options stack.

MODES:

--Mode "a" (a for alpha) sets the inner text transparent on the border line and gives the
  main line a thin outline to prevent transparent spaces in between the outline and text.
  Since the inner text is transparent on the border layer, it will not interfere with the
  color of the main text during fades or when alpha tags are involved.

--Mode "s" (s for solid) sets the inner text on the border line to be the same color as the
  border, so that blurring the main line will not create a space between the outline and inner
  text. If you use a fade or make the line semitransparent, the border color will affect the
  main text color, but this mode avoids exaggerating the font thickness.

OPTIONS:

--Option "g" (g for glow) sets the main line to default blur and the outline to whatever blur
  is defined in the line. This allows for "glowing outline" effects, with stronger blurs on
  the outline than on the main text.

--Option "d" (d for double) creates a third layer with an outline that is double the size of
  the original outline and set to the same color as the main text. This allows for doubled
  borders.

EXAMPLES:

"bord"      This will use the default mode defined below, and no options.
"borda"     This will force "a" mode, regardless of what default mode is set to.
"bordg"     This will use the default mode, as well as the "g" (glow) option.
"bordsgd"   This will force "s" mode, and use both the glow and double-border options.
"bordgs"    This probably won't work the way you want it to.
"bord a d"  Neither will this.

Repeated applications of this macro on the same script are handled in two different ways. The
original single-line typeset will always be saved as a comment. If you want to modify your
typesets by changing the original lines, then set "refactor" to "true" in the global variables.
If you want to change the resulting lines after applying the macro, then set "refactor" to
"false".

Color tags and alpha tags must be well-formed, i.e. color tags must be in &HAAAAAA&
format and alpha tags must be in &HAA& format. The macro may break if an ampersand
is missing. There is no support for xbord and ybord tags; you'll have to handle those
yourself. Changing styles in the middle of a line using \r is not supported. It might
still work, but it will likely cause unexpected side-effects. Behavior is undefined
if your line does not have a border, either in the style or in the line. It will
probably also break in other cases I haven't tested.
]]--

--[[
==TODO==

* "shad" mode.

]]--

--[[
==DEBUG==

* Restructured code to make "a" and "s" the only modes, and "g" and "d" options.
  Works so far for simple test cases, but it's fully possible that it will blow up
  for anything more complicated.
* Fixed alpha and color handling. Should be better able to handle alpha and colors
  that are not defined in-line, as well as variable alphas and colors within the
  same line. Not thoroughly tested, may still contain bugs.

]]--

script_name = "Duplicate and Blur"
script_description = "Splits a bordered line into two layers, so both text and outline have blur."
script_version = "1.1.0"
script_author = "lyger"
script_namespace = "lyger.BorderSplit"

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

--[[ ==GLOBAL VARIABLES== ]]--

-- This is what will be added to a line with no \be or \blur tag.
-- Make sure you double the slash! It's an escape character.
local default_blur = "\\blur0.6"

-- If a line is just labeled "bord", it will default to this mode.
-- Can be "a" (alpha) or "s" (solid)
local default_mode = "s"

-- If refactor is set to true, the script will save commented copies
-- of the original lines, and each time the macro is run, it will
-- delete any previously generated lines and recreate them from
-- the commented originals.
-- If set to false, it will still keep the originals but leave
-- finished lines untouched.
local refactor = false

--[[ ==END GLOBAL VARIABLES== ]]--

--Convert float to neatly formatted string
local float2str = libLyger.float2str

--[[
Tags that can have any character after the tag declaration:
\r
\fn
Otherwise, the first character after the tag declaration must be:
a number, decimal point, open parentheses, minus sign, or ampersand
]]--


--Add tags to the first code block in a line
local function give_head(text, addtags)
	if(string.find(text,"^{\\.-}")~=nil) then
		local tstart,tend,tags=string.find(text,"^{(\\.-)}")
		text=string.sub(text,1,tstart)..addtags..tags..string.sub(text,tend,string.len(text))
	else
		text="{"..addtags.."}"..text
	end
	return text
end

--Change color cto to the same color as cfrom
local function sub_colors(line, cfrom, cto)
	local text=line.text
	if(cfrom==cto) then return text end
	local sfrom=string.format("\\%dc",cfrom)
	local sto=string.format("\\%dc",cto)
	local _,_,htag=text:find("^{(\\.-)}")
	if(htag==nil or htag:find(sfrom)==nil and (htag:find("\\c&H[0-9A-Fa-f]+&")==nil or cfrom~=1)) then
		local color=""
		if cfrom==1 then color=color_from_style(line.styleref.color1)
		elseif cfrom==2 then color=color_from_style(line.styleref.color2)
		elseif cfrom==3 then color=color_from_style(line.styleref.color3)
		elseif cfrom==4 then color=color_from_style(line.styleref.color4)
		end

		local dcolor=""
		if cto==1 then dcolor=color_from_style(line.styleref.color1)
		elseif cto==2 then dcolor=color_from_style(line.styleref.color2)
		elseif cto==3 then dcolor=color_from_style(line.styleref.color3)
		elseif cto==4 then dcolor=color_from_style(line.styleref.color4)
		end

		if(color~=dcolor) then text=give_head(text,sto..color) end
	end
	if(string.find(text,sfrom)~=nil) then
		text=string.gsub(text,sfrom.."(&H%w+&)",sfrom.."%1"..sto.."%1")
	elseif(cfrom==1) and (string.find(text,"\\c&H[0-9A-Fa-f]+&")~=nil) then
		text=string.gsub(text,"\\c(&H[0-9A-Fa-f]+&)","\\c%1"..sto.."%1")
	end
	return text
end

--Change alpha ato to the same alpha as afrom
local function sub_alpha(line, afrom, ato)
	local text=line.text
	if(afrom==ato) then return text end
	local sfrom=string.format("\\%da",afrom)
	local sto=string.format("\\%da",ato)
	local _,_,htag=string.find(text,"^{(\\.-)}")
	if(htag==nil or (htag:find(sfrom)==nil and htag:find("\\alpha&H[0-9A-Fa-f]+&")==nil)) then
		local alpha=""
		if afrom==1 then alpha=alpha_from_style(line.styleref.color1)
		elseif afrom==2 then alpha=alpha_from_style(line.styleref.color2)
		elseif afrom==3 then alpha=alpha_from_style(line.styleref.color3)
		elseif afrom==4 then alpha=alpha_from_style(line.styleref.color4)
		end

		local dalpha=""
		if ato==1 then dalpha=alpha_from_style(line.styleref.color1)
		elseif ato==2 then dalpha=alpha_from_style(line.styleref.color2)
		elseif ato==3 then dalpha=alpha_from_style(line.styleref.color3)
		elseif ato==4 then dalpha=alpha_from_style(line.styleref.color4)
		end

		if(alpha~=dalpha) then text=give_head(text,sto..alpha) end
	end
	if(text:find(sfrom)~=nil) then
		text=text:gsub(sfrom.."(&H[A-Fa-f0-9]+&)",sfrom.."%1"..sto.."%1")
	end
	return text
end

--Return the alpha value for the given color
local function get_alpha(line, cnum)
	if line==nil then return "&H00&" end
	local text=line.text
	local stag=string.format("\\%da",cnum)
	local alpha=""
	if(text:find(stag)~=nil) then _,_,alpha=text:find(stag.."(&H[A-Fa-f0-9]+&)")
	elseif(text:find("\\alpha")~=nil) then _,_,alpha=text:find("\\alpha(&H[A-Fa-f0-9]+&)")
	else
		if cnum==1 then alpha=alpha_from_style(line.styleref.color1)
		elseif cnum==2 then alpha=alpha_from_style(line.styleref.color2)
		elseif cnum==3 then alpha=alpha_from_style(line.styleref.color3)
		elseif cnum==4 then alpha=alpha_from_style(line.styleref.color4)
		end
	end
	return alpha
end

--"a mode" border split
function dup_blur_a(line,line1,line2)

	--ignore anything in \t tags
	local timeless_line=LibLyger.line_exclude(line1.text,"t")

	--read in the border and blur amounts
	local _,_,border = string.find(timeless_line,"\\bord([%d%.]+)")
	local _,_,blur = string.find(timeless_line,"\\b[elur]+([%d%.]+)")
	--add a blur tag if there is none
	if blur==nil then
		_,_,blur = string.find(default_blur,"\\b[elur]+([%d%.]+)")
		line1.text=give_head(line1.text,default_blur)
		line2.text=give_head(line2.text,default_blur)
	end
	--add a bord tag if there is none
	if border==nil then
		border=line.styleref.outline
		line2.text=give_head(line2.text,"\\bord"..float2str(border))
	end

	--line1 is the top line set to main color, so remove 3c and 3a tags and make 3c the same as 1c
	line1.text=LibLyger.line_exclude(line1.text,"bord","3c","3a","shad","xshad","yshad")
	line1.text=sub_colors(line1,1,3)
	--make 3a the same as 1a
	line1.text=sub_alpha(line1,1,3)
	--double-check line1 for blur (in case g option is set)
	if line1.text:find("\\b[elur]+")==nil then
		line1.text=give_head(line1.text,default_blur)
	end
	--set border and blur to the same value
	line1.text=line1.text:gsub("(\\b[elur]+)([%d%.]+)",
		function(a,b) return a..b.."\\bord"..b end)
	--kill shadows
	if line1.styleref.shadow~=0 then line1.text=give_head(line1.text,"\\shad0") end
	--relayer
	line1.layer=line1.layer+1
	--get rid of empty t blocks
	line1.text=line1.text:gsub("\\t%([%d,]*%)","")


	--line2 is the bottom line set to border color, so remove 1c and 1a tags
	line2.text=LibLyger.line_exclude(line2.text,"c","1c","1a")
	--if the original line contained no blur, default to default_blur
	blur=tonumber(blur)
	line2.text=line2.text:gsub("\\bord([%d%.]+)",
		function(a) return "\\bord"..float2str(tonumber(a)+blur) end)
	--transform any alpha tags to 3a tags
	line2.text=line2.text:gsub("\\alpha(&H[0-9A-Fa-f]+&)","\\3a%1")
	--set 1a to transparent
	line2.text=give_head(line2.text,"\\1a&HFF&")
	--get rid of empty t blocks
	line2.text=line2.text:gsub("\\t%([%d,]*%)","")

end

--"s mode" border split
function dup_blur_s(line,line1,line2)

	--ignore anything in \t tags
	local timeless_line=LibLyger.line_exclude(line.text,"t")

	--read in the border and blur amounts
	local _,_,border = string.find(timeless_line,"\\bord([%d%.]+)")
	local _,_,blur = string.find(timeless_line,"\\b[elur]+([%d%.]+)")
	--add a bord tag if there is none
	if border==nil then
		border=line.styleref.outline
		line1.text=give_head(line1.text,"\\bord0")
		line2.text=give_head(line2.text,"\\bord"..float2str(border))
	end

	--line1 is the top line set to main color, so remove 3c and 3a tags
	line1.text=LibLyger.line_exclude(line1.text,"3c","3a","shad","xshad","yshad")
	line1.text=LibLyger.time_exclude(line1.text,"bord")
	--if there is no border by default, delete the bord tag. Otherwise, set bord tag to zero
	if line.styleref.outline==0 then
		--if the original line contained no blur, default to default_blur
		if line1.text:find("\\b[elur]+")==nil then
			line1.text=line1.text:gsub("\\bord[%d%.]+",default_blur)
		else
			line1.text=line1.text:gsub("\\bord[%d%.]+","")
		end
	else
		--if the original line contained no blur, default to default_blur
		if line1.text:find("\\b[elur]+")==nil then
			line1.text=line1.text:gsub("\\bord[%d%.]+","\\bord0"..default_blur)
		else
			line1.text=line1.text:gsub("\\bord[%d%.]+","\\bord0")
		end
	end
	--kill shadows
	if line1.styleref.shadow~=0 then line1.text=give_head(line1.text,"\\shad0") end
	--relayer
	line1.layer=line1.layer+1
	--get rid of empty t blocks
	line1.text=line1.text:gsub("\\t%([%d,]*%)","")

	--line2 is the bottom line set to border color, so remove 1c and 1a tags and make 1c the same as 3c
	line2.text=LibLyger.line_exclude(line2.text,"c","1c","1a")
	line2.text=sub_colors(line2,3,1)
	--if the original line contained no blur, default to default_blur
	if blur==nil then
		line2.text=give_head(line2.text,default_blur)
	end
	--make 1a the same as 3a
	line2.text=sub_alpha(line2,3,1)
	--get rid of empty t blocks
	line2.text=line2.text:gsub("\\t%([%d,]*%)","")

end

--handle the third line for the "d" option
function double_border(line3,mode,opts)
	--ignore anything in \t tags
	local timeless_line=LibLyger.line_exclude(line3.text,"t")

	--read in the border and blur amounts
	local _,_,border = string.find(timeless_line,"\\bord([%d%.]+)")
	local _,_,blur = string.find(timeless_line,"\\b[elur]+([%d%.]+)")
	--add a bord tag if there is none
	if border==nil then
		border=line3.styleref.outline
		line3.text=give_head(line3.text,"\\bord"..float2str(border))
	end
	--add a blur tag if there is none
	if blur==nil then
		_,_,blur=default_blur:find("\\b[elur]+([%d%.]+)")
		line3.text=give_head(line3.text,default_blur)
	end
	--extra check in case "g" option is set
	if opts:find("g")~=nil then
		_,_,blur=default_blur:find("\\b[elur]+([%d%.]+)")
	end
	blur=tonumber(blur)

	line3.text=LibLyger.line_exclude(line3.text,"3c")
	line3.text=sub_colors(line3,1,3)
	if mode=="a" then
		line3.text=LibLyger.line_exclude(line3.text,"alpha","1a")
		line3.text=line3.text:gsub("\\bord([%d%.]+)",
			function(a) return "\\bord"..float2str(tonumber(a)*2+blur) end)
		line3.text=give_head(line3.text,"\\1a&HFF&")
	elseif mode=="s" then
		line3.text=sub_alpha(line3,3,1)
		line3.text=line3.text:gsub("\\bord([%d%.]+)",
			function(a) return "\\bord"..float2str(tonumber(a)*2) end)
	end
end

--shadow split
function shad_blur(line,line1,line2)
	--ignore anything in \t tags
	local timeless_line=LibLyger.line_exclude(line.text,"t")

	--read in the border, shadow, and blur amounts
	local _,_,border = string.find(timeless_line,"\\bord([%d%.]+)")
	local _,_,blur = string.find(timeless_line,"\\b[elur]+([%d%.]+)")
	local _,_,shadow = string.find(timeless_line,"\\shad([%d%.]+)")
	local _,_,xshad = string.find(timeless_line,"\\xshad([%-%d%.]+)")
	local _,_,yshad = string.find(timeless_line,"\\yshad([%-%d%.]+)")
	if border==nil then border=line.styleref.outline end
	border=tonumber(border)
	if xshad==nil and yshad==nil then
		xshad=shadow
		yshad=shadow
	elseif yshad==nil then
		yshad="0"
	elseif xshad==nil then
		xshad="0"
	end
	xshad=tonumber(xshad)
	yshad=tonumber(yshad)

	--line1 is the top line with no shadow, so remove all shadow related tags
	line1.text=LibLyger.line_exclude(line1.text,"4c","4a","shad","xshad","yshad")
	--line1.text=LibLyger.time_exclude(line1.text,"shad","xshad","yshad")

	--make color 1 and 3 the same as color 4 for line2
	line2.text=sub_colors(line2,4,1)
	if border>0 then line2.text=sub_colors(line2,4,3) end
	--and for alpha, too
	line2.text=sub_alpha(line2,4,1)
	if border>0 then line2.text=sub_alpha(line2,4,3) end
	--now remove the shadow tags, as they're no longer needed
	line2.text=LibLyger.line_exclude(line2.text,"4c","4a","shad","xshad","yshad")
	--line2.text=LibLyger.time_exclude(line2.text,"shad","xshad","yshad")

	--THE FOLLOWING IS TEMPORARY CODE JUST SO IT'LL WORK FOR WHAT I NEED TODAY
	if line2.text:find("\\pos") == nil then
		line2.text=give_head(line2.text,string.format("\\pos(%d,%d)",line2.x,line2.y))
	end
	local _,_,shadx,shady=line2.text:find("\\pos%(([%d%.%-]+),([%d%.%-]+)%)")
	shadx=tonumber(shadx)
	shady=tonumber(shady)
	line2.text=line2.text:gsub("\\pos%([%d%.%-]+,[%d%.%-]+%)",string.format("\\pos(%d,%d)",xshad+shadx,yshad+shady))
	--relayer
	line1.layer=line1.layer+1

	--TODO:
	--Finish basics (color, alpha handling, positioning)
	--Handle modification of shadow position with \t tags -> convert \t(\shad) to \move
end

--Detect marked lines, and determine which mode to use
function dup_blur(sub, sel, act)
	libLyger:set_sub(sub)

	--cycle through script
	for _, line in ipairs(libLyger.dialogue) do
		local x = line.i
		--detect if it's marked
		if line.actor:match("^shad")~=nil and line.effect~="done" then
			--_,_,sopts=line.actor:find("bord[as]?([gd]+)")

			-- create two more copies of the line
			libLyger:preproc_lines(line)
			local line1, line2 = util.copy(line), util.copy(line)

			--apply different manipulations depending on mode
			--if bmode=="a" then dup_blur_a(line,line1,line2)
			--elseif bmode=="s" then dup_blur_s(line,line1,line2)
			--end

			--handle "g" modifier
			--if (sopts ~= nil and sopts:find("g") ~=nil) then
			--  line1.text=line1.text:gsub("\\b[elur]+[%d%.]+","")
			--end

			--split off the shadow
			shad_blur(line,line1,line2)

			--prevent it from reapplying to new lines, and comment out old line
			line1.effect='done'
			line1.comment=false
			line2.effect='done'
			line2.comment=false
			line.comment=true

			if (not refactor) then line.actor="*"..line.actor end

			--insert lines
			sub[x]=line
			sub.insert(x+1,line1)
			sub.insert(x+1,line2)

		elseif line.actor:match("^bord[as]?")~=nil and line.effect~="done" then

			--if mode is not defined, set mode to default mode
			_,_,bmode=line.actor:find("bord([as])")
			if bmode == nil then bmode=default_mode end
			_,_,bopts=line.actor:find("bord[as]?([gd]+)")

			-- create two more copies of the line
			libLyger:preproc_lines(line)
			local line1, line2, line3 = util.copy(line), util.copy(line)

			--handle "g" modifier
			if (bopts ~= nil and bopts:find("g") ~=nil) then
				line1.text=line1.text:gsub("\\b[elur]+[%d%.]+","")
			end

			if (bopts ~= nil and bopts:find("d") ~=nil) then
				line3 = util.copy(line)
				double_border(line3,bmode,bopts)
			end

			--apply different manipulations depending on mode
			if bmode=="a" then dup_blur_a(line,line1,line2)
			elseif bmode=="s" then dup_blur_s(line,line1,line2)
			end

			--prevent it from reapplying to new lines, and comment out old line
			line1.effect='done'
			line1.comment=false
			line2.effect='done'
			line2.comment=false
			line.comment=true

			if (not refactor) then line.actor="*"..line.actor end

			--make modifications if the "d" option is on
			if (bopts ~= nil and bopts:find("d") ~=nil) then
				line3.effect='done'
				line3.comment=false
				line1.layer=line1.layer+1
				line2.layer=line2.layer+1
				--kill shadows
				line2.text=LibLyger.line_exclude(line2.text,"shad","xshad","yshad")
				if line2.styleref.shadow~=0 then line2.text=give_head(line2.text,"\\shad0") end
			end

			--insert lines
			sub[x]=line
			sub.insert(x+1,line1)
			sub.insert(x+1,line2)

			--add new line if "d" option is on (wow this is inelegant)
			if (bopts ~= nil and bopts:find("d") ~=nil) then
				sub.insert(x+1,line3)
			end

		--delete lines left over from previous applications
		elseif line.actor:match("bord[asg]?")~=nil and line.effect=="done" and refactor then
			sub.delete(x)
		end
	end
	aegisub.set_undo_point("Duplicate and blur")
end

rec:registerMacro(dup_blur)