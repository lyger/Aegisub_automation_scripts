--[[
README

Karaoke Helper

Does simple karaoke tasks. Adds blank padding syllables to the beginning of lines,
and also adjusts final syllable so it matches the line length.

Will add more features as ktimers suggest them to me.


]]--

script_name="Karaoke helper"
script_description="Miscellaneous tools for assisting in karaoke timing."
script_version="0.1"

include("karaskel.lua")

function make_config(styles)
	local stopts={"selected lines"}
	for i=1,styles.n,1 do
		table.insert(stopts,string.format("style: %q",styles[i].name))
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
			return pre..string.format("%d",tonumber(val)+delta)..post
		end)
	return line
end

--Add padding at the start
function add_prepad(line,pdur)
	line.text=line.text:gsub("^({[^{}]*\\[Kk][fo]?)(%d+)",
		function(pre,val)
			return string.format("{\\k%d}",pdur)..pre..string.format("%d",tonumber(val)-pdur)
		end)
	line.text=line.text:gsub("^{\\k(%d+)}({[^{}]*\\[Kk][fo]?)(%-?%d+)([^{}]*}{)",
		function(val1,mid,val2,post)
			return mid..string.format("%d",tonumber(val1)+tonumber(val2))..post
		end)
	return line
end

--Add padding at the end
function add_postpad(line,pdur)
	line.text=line.text:gsub("(\\[Kk][fo]?)(%d+)([^{}]*}[^{}]*)$",
		function(pre,val,post)
			return pre..string.format("%d",tonumber(val)-pdur)..post..string.format("{\\k%d}",pdur)
		end)
	line.text=line.text:gsub("(\\[Kk][fo]?)(%-?%d+)([^{}]*}){\\k(%d+)}$",
		function(pre,val1,mid,val2)
			return pre..string.format("%d",tonumber(val1)+tonumber(val2))..mid
		end)
	return line
end

--Load config and display
function load_kh(sub,sel)
	
	--Basic header collection, config, dialog display
	local meta,styles=karaskel.collect_head(sub,false)
	local config=make_config(styles)
	
	pressed,results=aegisub.dialog.display(config)
	
	if pressed=="Cancel" then aegisub.cancel() end
	
	--Determine how to retrieve the next line, based on the dropdown selection
	local tstyle=results["sselect"]
	
	local get_next,add_line=nil,nil
	local uindex=0
	local line=nil
	
	if tstyle:match("^style: ")~=nil then
		tstyle=tstyle:match("^style: \"(.+)\"$")
		get_next=function()
			repeat
				uindex=uindex+1
				if uindex>#sub then return 0 end
				line=sub[uindex]
			until line.style==tstyle and (line.comment==false or line.effect=="karaoke")
			return 1
		end
		
		add_line=function()
			sub[uindex]=line
		end
	else
		get_next=function()
			uindex=uindex+1
			if uindex>#sel then return 0 end
			line=sub[sel[uindex]]
			return 1
		end
		add_line=function()
			sub[sel[uindex]]=line
		end
	end
	
	--Control loop
	while get_next()>0 do
		if results["match"] then line=match_durs(line) end
		if results["leadin"] then line=add_prepad(line,results["leadindur"]) end
		if results["leadout"] then line=add_postpad(line,results["leadoutdur"]) end
		add_line()
	end
	
	aegisub.set_undo_point(script_name)
end


aegisub.register_macro(script_name,script_description,load_kh)




