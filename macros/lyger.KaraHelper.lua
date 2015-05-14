--[[
README

Karaoke Helper

Does simple karaoke tasks. Adds blank padding syllables to the beginning of lines,
and also adjusts final syllable so it matches the line length.

Will add more features as ktimers suggest them to me.


]]--

script_name = "Karaoke helper"
script_description = "Miscellaneous tools for assisting in karaoke timing."
script_version = "0.2.0"
script_author = "lyger"
script_namespace = "lyger.KaraHelper"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{
		{"lyger.LibLyger", version = "2.0.0", url = "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"},
	}
}
local LibLyger = rec:requireModules()
local libLyger = LibLyger()

function make_config(styles)
	local stopts={"selected lines"}
	for i=1,styles.n,1 do
		stopts[i+1] = ("style: %q").format(styles[i].name)
	end
	local config=
	{
		--What to apply the automation on
		{
			class="label",
			label="Apply to:",
			x=0,y=0,width=1,height=1
		},
		{
			class="dropdown",
			name="sselect",items=stopts,
			x=1,y=0,width=1,height=1,
			value="selected lines"
		},
		--Match syls to line length
		{
			class="checkbox",
			name="match",label="Match syllable lengths to line length",
			x=0,y=1,width=2,height=1,
			value=true
		},
		--Add blank syl at the start
		{
			class="checkbox",
			name="leadin",label="Add start padding:",
			x=0,y=2,width=1,height=1,
			value=false
		},
		{
			class="intedit",
			name="leadindur",
			x=1,y=2,width=1,height=1,
			min=0,
			value=0
		},
		--Add blank syl at the end
		{
			class="checkbox",
			name="leadout",label="Add end padding:",
			x=0,y=3,width=1,height=1,
			value=false
		},
		{
			class="intedit",
			name="leadoutdur",
			x=1,y=3,width=1,height=1,
			min=0,
			value=0
		}
	}
	return config
end

--Match syllable and line durations
function match_durs(line)
	local ldur=line.end_time-line.start_time
	local cum_sdur=0
	for sdur in line.text:gmatch("\\[Kk][fo]?(%d+)") do
		cum_sdur=cum_sdur+tonumber(sdur)
	end
	local delta=math.floor(ldur/10)-cum_sdur
	line.text=line.text:gsub("({[^{}]*\\[Kk][fo]?)(%d+)([^{}]*}[^{}]*)$",
		function(pre,val,post)
			return ("%s%d%s"):format(pre, tonumber(val)+delta, post)
		end)
	return line
end

--Add padding at the start
function add_prepad(line,pdur)
	line.text=line.text:gsub("^({[^{}]*\\[Kk][fo]?)(%d+)",
		function(pre,val)
			return ("{\\k%d}%s%d"):format(pdur, pre, tonumber(val)-pdur)
		end)
	line.text=line.text:gsub("^{\\k(%d+)}({[^{}]*\\[Kk][fo]?)(%-?%d+)([^{}]*}{)",
		function(val1,mid,val2,post)
			return ("%s%d%s"):format(mid, tonumber(val1)+tonumber(val2), post)
		end)
	return line
end

--Add padding at the end
function add_postpad(line,pdur)
	line.text=line.text:gsub("(\\[Kk][fo]?)(%d+)([^{}]*}[^{}]*)$",
		function(pre,val,post)
			return ("%s%d%s{\\k%d}"):format(pre, tonumber(val)-pdur, post, pdur)
		end)
	line.text=line.text:gsub("(\\[Kk][fo]?)(%-?%d+)([^{}]*}){\\k(%d+)}$",
		function(pre,val1,mid,val2)
			return ("%s%d%s"):format(pre, tonumber(val1)+tonumber(val2), mid)
		end)
	return line
end

--Load config and display
function load_kh(sub,sel)
	libLyger:set_sub(sub, sel)

	-- Basic header collection, config, dialog display
	local config = make_config(libLyger.styles)
	local pressed,results=aegisub.dialog.display(config)
	if pressed=="Cancel" then aegisub.cancel() end

	--Determine how to retrieve the next line, based on the dropdown selection
	local tstyle, line_cnt, get_next = results["sselect"], #sub

	if tstyle:match("^style: ") then
		tstyle=tstyle:match("^style: \"(.+)\"$")
		get_next = function(uindex)
			for i = uindex, line_cnt do
				local line = libLyger.dialogue[uindex]
				if line.style == tstyle and (not line.comment or line.effect == "karaoke") then
					return line, i
				end
			end
		end
	else
		get_next = function(uindex)
			if uindex <= #sel then
				return libLyger.lines[sel[uindex]], uindex+1
			end
		end
	end

	--Control loop
	local line, uindex = get_next(1)
	while line do
		if results["match"] then match_durs(line) end
		if results["leadin"] then add_prepad(line, results["leadindur"]) end
		if results["leadout"] then add_postpad(line, results["leadoutdur"]) end
		sub[line.i] = line
		line, uindex = get_next(uindex)
	end

	aegisub.set_undo_point(script_name)
end

rec:registerMacro(load_kh)



