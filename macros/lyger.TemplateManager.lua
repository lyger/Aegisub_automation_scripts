--[[
TEMPLATE MANAGER

Allows the creation, management, and use of robust typesetting templates
that can be applied to subtitle scripts.

The "template manager" automation itself does not change the subtitles
file at all. Instead, template groups created using template manager will
be registered as new macros in Aegisub's automations menu, and will
become available after reloading automation scripts. This is to allow
templates to be hotkeyed.

The template manager interface and the use of templates should be relatively
intuitive. Templates are applied to "base lines", which determine how the
generated lines are timed and, optionally, some other parameters.

Template lines can have four kinds of timing:

Absolute - The start and end times are relative to the first frame of the video.
Relative (start) - The start and end times are relative to the start of the
	base line(s).
Relative (end) - The start and end times are relative to the end of the base
	line(s).
Relative (both) - The start time is relative to the start and the end to the
	end of the base line(s).

Because this script is intended for typesetting, all times are in frames. As
such, make sure you have a video loaded when working with template manager.

Templates also allow variables and basic expressions. Variables are identified
by a single dollar sign at the beginning of the variable.

These variables allow the template to behave differently depending on the base
line that it is applied to. The most common reason you may need this is when
the colors, font, etc. of a frequently-occurring typeset are the same, but the
text is different. In this case, you can use the $text variable to automatically
insert the text from the base line into the template.

The value of override tags can also be read from the base line. The variables for
most tags are simply the name of the tag, preceded by a dollar sign. For example,
to get the z rotation value, use the variable $frz.

There are some special variables that don't follow this rule. They are as follows:

$x, $y
	The coordinates in \pos()
$x1, $y1, $x2, $y2, $movet1, $movet2
	The six parameters of \move(), the last two being the time parameters
$orgx, $orgy
	The coordinates in \org()
$clipx1, $clipy1, $clipx2, $clipy2
	The four parameters of rectangular \(i)clip()
$vclip
	The shape in a vector \(i)clip()
$fad1, $fad2
	The parameters of \fad()
$dur
	Duration of the line, in milliseconds
$$
	The dollar sign character

Simple Lua expressions can also be used. Expressions must be surrounded by
backticks (`). You can do arithmetic as well as string manipulation. For example,
to make the y scaling exactly half the x scaling, you might write:

{\fscx$fscx\fscy`$fscx*0.5`}

The expression `$fscx*0.5` will calculate half of the x scale value and insert it
into the line.

To do string manipulation, be aware that $text is not a variable in the strictest
sense, but simply a token for the string replacer. To use it as a variable in
expressions, you must surround it with quotes.

Template line 1: `("$text"):match("^(.+:)")`
Template line 2: `("$text"):match(":%s?(.+)$$")`

When the above two example templates are applied to the base line:

Episode 4: A New Hope

the template will generate the following:

Episode 4:
A New Hope

Thus allowing the two parts of the title to be treated separately. Note that the
dollar sign in the Lua pattern must be doubled, since the dollar sign is otherwise
interpreted as the start of a variable. Similarly, if you ever want to use a
literal backtick, for whatever reason, type ``.



APPENDIX: Important changes from version 1

First off, the syntax for variables and expressions outlined above is completely
different from what it was in version 1, because I realized my choice of symbols
was, to put it simply, stupid. Not only is the new syntax easier to type, it
allows the special characters to be escaped in case you actually need them.

It's worth noting that version 1 of template manager had a rather confusing way
of handling base lines with multiple override tag blocks. This feature has been
removed entirely. Template manager only looks at the first override tag block
and the first section of text in your base line, and discards anything after
that. For example, if your base line is:

{\fs80}Never {\c&H0000FF&}gonna give {\r}you up

then the $text variable would only hold "Never ". It is assumed that if you are
going to use a template, there is no reason for your base line to be this
complicated.

It's also worth mentioning that nothing you do in template manager is final until
you press the "save" button. The changes are only written to file when you press
"save", and you won't be warned if you quit Aegisub with an unsaved template
(it's actually not possible for me to make the macro do this). The plus side is,
if you mess up and accidentally delete a template, you can always use the "revert
to last save" action (unfortunately, if you accidentally delete the entire
template group, it's gone forever).



TODO:

-Possibly add a settings/configuration menu, though idk what it would do
 other than adjust number of lines per page.
-Button to copy template folder path to clipboard? To make sharing templates
 easier.

]]

script_name = "Template Manager"
script_description = "Manage typsetting templates."
script_version = "2.1.0"
script_author = "lyger"
script_namespace = "lyger.TemplateManager"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{
		{"l0.ASSFoundation.Common", version = "0.2.0", url = "https://github.com/TypesettingTools/ASSFoundation",
		 feed = "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
		"aegisub.util", "karaskel"
	}
}
local Common, util = rec:requireModules()

-- The path to the template manager directory
local tmpath = aegisub.decode_path("?user/tempman/")

-- Variables for next menu to execute and the parameters to pass to it
local next_menu
local menu_params = function() return nil end

-- Variables for subtitles and selected lines
local sub, sel

-- List of template groups, metadata, template data,
-- name of current template group and template
local tglist, meta, data, ctg, ctemp = {}, {}, {}

-- Current page and lines per page
local page, LPP = 1, 5

-- Last used templates and last action
local last_temps, last_action = {}

-- Styles
local styles

--Because convenience
local ttdict = {
	["a"]="Absolute",
	["rs"]="Relative (start)",
	["re"]="Relative (end)",
	["rb"]="Relative (both)",
	["Absolute"]="a",
	["Relative (start)"]="rs",
	["Relative (end)"]="re",
	["Relative (both)"]="rb"
}

--Thank you stackoverflow
--http://stackoverflow.com/questions/11401890/case-insensitive-lua-pattern-matching
local function cip(pattern)

  -- find an optional '%' (group 1) followed by any character (group 2)
  local p = pattern:gsub("(%%?)(.)", function(percent, letter)

	if percent ~= "" or not letter:match("%a") then
	  -- if the '%' matched, or `letter` is not a letter, return "as is"
	  return percent .. letter
	else
	  -- else, return a case-insensitive character class of the matched letter
	  return string.format("[%s%s]", letter:lower(), letter:upper())
	end

  end)

  return p
end

--Make an alert popup
local function alert(msg)
	aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",label=msg}},
		{"OK"},{ok="OK"})
end

--Find the next number to name a default name
local function next_n(tb,str)
	local maxn=0
	for _,t in ipairs(tb) do
		local n=t:match(str.." (%d+)$")
		if n then
			n=tonumber(n)
			if n>maxn then maxn=n end
		end
	end

	return maxn+1
end

--Sees if an item exists in a table
local function isdupe(tb,item)
	for _,i in pairs(tb) do
		if i==item then return true end
	end
	return false
end

--Converts old .tm format into new .tm2 syntax
local function convert_to_tm2(oname)
	local ofile=io.open(tmpath..oname..".tm","r")
	local nfile=io.open(tmpath..oname..".tm2","w")

	nfile:write("META\n")
	nfile:write("\tname:"..oname.."\n")
	nfile:write("\tversion:"..script_version.."\n")

	nfile:write("DATA\n")

	local otline=ofile:read("*line")

	repeat
		if otline:match("^\t") then
			local function nvar(a) return "$"..a:lower() end
			--Escape new special characters
			otline=otline:gsub("%$","$$")
			otline=otline:gsub("`","``")

			--Take care of custom variables
			otline=otline:gsub(cip("%%text%%"),"$text")
			otline=otline:gsub(cip("%%(movet[12])%%"),nvar)
			otline=otline:gsub(cip("%%(clip").."[xXyY][12])%%",nvar)
			otline=otline:gsub("%%([xXyY][12]?)%%",nvar)
			otline=otline:gsub(cip("%%(org").."[xXyY])%%",nvar)
			otline=otline:gsub(cip("%%vclip%%"),"$vclip")
			otline=otline:gsub(cip("%%(fad[12])%%"),nvar)

			--Take care of other tags
			otline=otline:gsub("%%([1-4]?[aAbBcCfFiIkKmMoOpPqQrRtsSTuU]%a*)%%",
				nvar)

			--Take care of expressions
			otline=otline:gsub("`","``"):gsub("(%b!!)",function(a)
				return a:gsub("^!","`"):gsub("!$","`") end)
		end
		nfile:write(otline.."\n")
		otline=ofile:read("*line")
	until not otline

	nfile:close()
	ofile:close()

	if psep=="\\" then os.execute("del \""..tmpath..oname..".tm\"")
	else os.execute("rm \""..tmpath..oname..".tm\"") end
end

--Creates a function to register as a macro
local function make_template(tname)
	return function(sub,sel)
		--Make sure a video is loaded
		if not aegisub.project_properties().video_file == "" then
			alert("Please load a video")
			aegisub.cancel()
		end

		_,styles=karaskel.collect_head(sub,false)
		load_tg(tname)

		local stnames={}
		for _,st in ipairs(styles) do table.insert(stnames,st.name) end

		local tmlist=table.keys(data)
		table.sort(tmlist)

		if #tmlist<1 then aegisub.cancel() end --Because fuck you

		local dconf=
		{
			{x=0,y=0,width=1,height=1,class="label",label="Select template:"},
			{x=0,y=1,width=1,height=1,class="dropdown",name="temp_select",
				items=tmlist,value=last_temps[tname] or tmlist[1]}
		}

		local prs,results=aegisub.dialog.display(dconf,{"Apply","Cancel"},{ok="Apply",cancel="Cancel"})

		if prs~="Apply" then aegisub.cancel() end --Because f--oh wait.

		last_temps[tname]=results["temp_select"]

		--Create a new pointer to the relevant data for convenience
		local tdata=data[results["temp_select"]]

		local lines_added=0

		local new_sel={}

		--Style not found
		local stnf={}

		--For all lines in selection
		for i,li in ipairs(sel) do

			local cline=sub[li+lines_added]

			--For simplicity, and because why would you use templates
			--on anything more complicated? only look at the first tag
			--and text block
			if not cline.text:match("^{") then cline.text="{}"..cline.text end
			local ctag,ctext=cline.text:match("^(%b{})([^{]*)")

			cline.comment=true

			local cstart=aegisub.frame_from_ms(cline.start_time)
			local cend=aegisub.frame_from_ms(cline.end_time)

			local sublines_added=0

			--For every line in the given template
			for _,tline in ipairs(tdata) do

				local nline=table.copy(cline)

				nline.comment=false

				--Parse template
				local l,tt,st,ed,sty,ln=parse(tline)

				--Set line layer and style
				nline.layer=l
				nline.style=sty

				--Warn when style not found
				if not stnf[sty] and not isdupe(stnames,sty) then
					alert("WARNING: Style not found: "..sty)
					stnf[sty]=true
				end

				--Set time based on timing type
				local bstart,bend=0,0
				if tt=="rb" then bstart,bend=cstart,cend
				elseif tt=="rs" then bstart,bend=cstart,cstart
				elseif tt=="re" then bstart,bend=cend,cend end

				nline.start_time=aegisub.ms_from_frame(bstart+st)
				nline.end_time=aegisub.ms_from_frame(bend+ed)

				local nldur=nline.end_time-nline.start_time

				--Aliases for common expressions
				local sf=string.format
				local nm="[%-%d%.]+"
				local nmc="[%-%d%.]+,"

				--Replace text
				ln=ln:gsub(cip("%$text"),ctext)
				--Replace escaped dollar signs
				ln=ln:gsub("%$%$","@DOLLAR")
				--Replace tags
				ln=ln:gsub("%$([1-4]?%a+[12]?)",
					function(tg)
						tg=tg:lower()

						local param=nil

						if tg:match("^fn") or tg:match("^r") then
							param=ctag:match("\\"..tg.."([^\\}]+)")
						elseif tg:match("^a$") then
							param=ctag:match("\\a(%d%d?)")
						elseif tg:match("^fs$") then
							param=ctag:match("\\fs([%d%.]+)")
						elseif tg:match("^x$") then
							param=ctag:match("\\pos%(([%-%d%.]+)")
						elseif tg:match("^y$") then
							param=ctag:match("\\pos%("..sf("%s(%s)",nmc,nm))
						elseif tg:match("^x1") then
							param=ctag:match("\\move%("..sf("(%s)",nm))
						elseif tg:match("^y1") then
							param=ctag:match("\\move%("..sf("%s(%s)",nmc,nm))
						elseif tg:match("^x2") then
							param=ctag:match("\\move%("..nmc:rep(2)..sf("(%s)",nm))
						elseif tg:match("^y2") then
							param=ctag:match("\\move%("..nmc:rep(3)..sf("(%s)",nm))
						elseif tg:match("^movet1") then
							param=ctag:match("\\move%("..nmc:rep(4)..sf("(%s)",nm))
						elseif tg:match("^movet2") then
							param=ctag:match("\\move%("..nmc:rep(5)..sf("(%s)",nm))
						elseif tg:match("^clipx1") then
							param=ctag:match("\\i?clip%(([%-%d%.]+)")
						elseif tg:match("^clipy1") then
							param=ctag:match("\\i?clip%("..sf("%s(%s)",nmc,nm))
						elseif tg:match("^clipx2") then
							param=ctag:match("\\i?clip%("..nmc:rep(2)..sf("(%s)",nm))
						elseif tg:match("^clipy2") then
							param=ctag:match("\\i?clip%("..nmc:rep(3)..sf("(%s)",nm))
						elseif tg:match("^orgx") then
							param=ctag:match("\\org%(([%-%d%.]+)")
						elseif tg:match("^orgy") then
							param=ctag:match("\\org%("..sf("%s(%s)",nmc,nm))
						elseif tg:match("^fad1") then
							param=ctag:match("\\fad%(([%-%d%.]+)")
						elseif tg:match("^fad2") then
							param=ctag:match("\\fad%("..sf("%s(%s)",nmc,nm))
						elseif tg:match("^vclip") then
							param=ctag:match("\\i?clip%(([^%)]*m[^%)]+)%)")
						elseif tg:match("^dur$") then
							param=tostring(nldur)
						else
							param=ctag:match("\\"..tg.."([^\\}]+)")
						end

						--If param not found, delete this tag
						param=param or "@DELETE"

						return param

					end)

				--Move statements without the time parameters are an exception
				ln=ln:gsub("\\move%(("..nmc:rep(3)..nm.."),@DELETE,@DELETE%)",
					"\\move(%1)")
				--Otherwise delete tags that are not found
				ln=ln:gsub("\\[^\\}]+@DELETE[^\\}]*","")

				--Put back escaped dollar signs
				ln=ln:gsub("@DOLLAR","$")

				--Now evaluate expressoins
				ln=ln:gsub("(%b``)",function(expr)
						if expr=="``" then return expr end
						expr=expr:gsub("^`",""):gsub("`$","")
						local com,err=loadstring("return "..expr)
						if err then aegisub.log(err) return end
						return com()
					end):gsub("``","`")

				--Add the line
				nline.text=ln:gsub("{}","")
				sub.insert(li+lines_added+sublines_added+1,nline)
				table.insert(new_sel,li+lines_added+sublines_added+1)
				sublines_added=sublines_added+1

			end

			sub[li+lines_added]=cline
			lines_added=lines_added+sublines_added

		end

		aegisub.set_undo_point(tname)
		return new_sel

	end
end

--Function to scan and reload templates
local function load_list()
	--The index of templates
	local tmfile=io.open(tmpath.."index.txt","r")

	tglist = {}

	--If the file exists, register macros
	if tmfile then

		local tmname=tmfile:read("*line")
		while tmname do
			--Disabled templates are prefixed with a hash
			if not tmname:match("^#") then
				aegisub.register_macro(tmname,"Automatically generated template.",
					make_template(tmname))
			end
			tmname=tmname:gsub("^#(.*)","%1 (DISABLED)")

			table.insert(tglist,tmname)
			tmname=tmfile:read("*line")
		end

		--Close file
		tmfile:close()
	else
		tmfile=io.open(tmpath.."index.txt","w")
		if tmfile then tmfile:close()
		else
			os.execute("mkdir \""..tmpath.."\"")
		end
	end
end

--And save template index
function save_list()
	local idxfile=io.open(tmpath.."index.txt","w")

	for _,tname in ipairs(tglist) do
		tname=tname:gsub("^(.+) %(DISABLED%)$","#%1")
		idxfile:write(tname.."\n")
	end

	idxfile:close()
end

--Load template group from file
function load_tg(tfname)

	if not tfname then tfname=ctg end

	if not tfname then
		alert("Error - no template group selected.")
		return
	end

	local tgfile=io.open(tmpath..tfname..".tm2","r")

	--Reset data and meta
	data={}
	meta={}

	if not tgfile then
		--Check if template not found due to being old version
		tgfile=io.open(tmpath..tfname..".tm","r")
		--If still not found then return
		if not tgfile then return end
		--Otherwise convert
		tgfile:close()
		convert_to_tm2(tfname)
		tgfile=io.open(tmpath..tfname..".tm2","r")
	end

	local tline=nil

	repeat
		tline=tgfile:read("*line")
	until tline:match("^META")

	repeat
		tline=tgfile:read("*line")
		if tline:match("^\t") then
			mname,mval=tline:match("^\t([^:]+):(.+)$")
			meta[mname]=mval
		end
	until tline:match("^DATA")

	local ctname=""

	while tline do

		if tline:match("^[^\t]+:$") then
			ctname=tline:match("(.+):$")

			data[ctname]={}
		end

		if tline:match("^\t") then
			table.insert(data[ctname],tline)
		end

		tline=tgfile:read("*line")

	end

	tgfile:close()

end

--Save current template group
function save_tg()
	if not ctg then return end

	local tgfile=io.open(tmpath..ctg..".tm2","w")

	tgfile:write("META\n")

	for mname,mval in pairs(meta) do
		tgfile:write(("\t%s:%s\n"):format(mname,tostring(mval)))
	end

	tgfile:write("DATA\n")

	for tname,tdata in pairs(data) do
		tgfile:write(tname..":\n")

		for _,ldata in ipairs(tdata) do
			tgfile:write(ldata.."\n")
		end

	end

	tgfile:close()

end

--Parse a raw template line
function parse(tmp)
	--layer,timetype,start,end,style,line
	local l,tt,st,ed,sty,ln=tmp:match("(%d+),([ra][seb]?),(%-?%d+),(%-?%d+),([^,]+),(.*)$")
	l=tonumber(l)
	st=tonumber(st)
	ed=tonumber(ed)
	ln=ln or ""
	return l,tt,st,ed,sty,ln
end

--And format it
function tfmt(l,tt,st,ed,sty,ln)
	if tt:len()>2 then tt=ttdict[tt] end
	return string.format("\t%d,%s,%d,%d,%s,%s",l,tt,st,ed,sty,ln)
end

--Fill rows in config from data
function fill_rows(conf,idx1,idx2)

	local stnames={}
	for _,st in ipairs(styles) do table.insert(stnames,st.name) end

	--For convenience
	local function ins(ctrl)
		table.insert(conf,ctrl)
		return
	end

	--List of not found styles
	local stnf={}

	for i=idx1,idx2 do
		local by= (i-idx1)*3+1

		local l,tt,st,ed,sty,ln = parse(data[ctemp][i])

		if not isdupe(stnames,sty) then
			if not stnf[sty] then
				alert("WARNING: Style not found: "..sty)
				stnf[sty]=true
			end
			sty=nil
		end

		ins({x=0,y=by,width=1,height=2,class="checkbox",name="select_"..i,value=false})

		ins({x=1,y=by,width=1,height=1,class="label",label="Layer"})
		ins({x=1,y=by+1,width=1,height=1,class="intedit",name="layer_"..i,value=l,min=0})

		ins({x=2,y=by,width=1,height=1,class="label",label="Style:"})
		ins({x=3,y=by,width=1,height=1,class="dropdown",name="style_"..i,items=stnames,value=sty})

		ins({x=2,y=by+1,width=1,height=1,class="label",label="Timing:"})
		ins({x=3,y=by+1,width=1,height=1,class="dropdown",name="timetype_"..i,items=
			{ttdict.a,ttdict.rs,ttdict.re,ttdict.rb},
			value=ttdict[tt]})

		ins({x=4,y=by,width=1,height=1,class="label",label="Start:"})
		ins({x=5,y=by,width=1,height=1,class="intedit",name="start_"..i,value=st})
		ins({x=4,y=by+1,width=1,height=1,class="label",label="End:"})
		ins({x=5,y=by+1,width=1,height=1,class="intedit",name="end_"..i,value=ed})

		ins({x=6,y=by,width=40,height=2,class="textbox",name="line_"..i,value=ln})
	end

	--Return the next empty row
	return (idx2-idx1+1)*3+1

end

--Modify the current template group
function mod_temp()
	--List of templates
	local tlist=table.keys(data)
	table.sort(tlist)

	--Correct page number
	local maxpage=ctemp~=nil and math.ceil(#data[ctemp]/LPP) or 0
	if page>maxpage then page=maxpage end
	if page<1 then page=1 end

	--Returns a dialog config containing a template selector
	local function tselector()
		return
		{
			{x=0,y=0,width=4,height=1,class="dropdown",name="temp_select",items=tlist,
				value=ctemp},
			{x=6,y=0,width=1,height=1,class="label",label=("Page %d/%d"):format(page,maxpage)}
		}
	end

	local conf = tselector()

	--Figure out which lines are visible on this page
	local idx1=(page-1)*LPP+1
	local idx2=0
	if ctemp then idx2=page*LPP<#data[ctemp] and page*LPP or #data[ctemp] end

	local opts={"New template","Main","Quit"}
	local opts_ids={cancel="Quit"}
	if #tlist>0 then
		table.insert(opts,1,"Load")
		if ctemp then
			table.insert(opts,1,"Save")
			table.insert(opts,4,"Delete template")
			table.insert(opts,5,"Action")
			opts_ids.ok="Save"

			nextrow=fill_rows(conf,idx1,idx2)

			table.insert(conf,{x=4,y=nextrow,width=1,height=1,class="label",label="Action:"})
			table.insert(conf,{x=5,y=nextrow,width=1,height=1,class="dropdown",name="action",
				items={"New line","Delete selected","Duplicate selected","Modify selected",
				"Import from subtitles","Jump to page","Revert to last save"}
				,value=last_action})

			if page>1 then table.insert(opts,"<--") end
			if page<maxpage then table.insert(opts,"-->") end

		end
	end

	--Display dialog
	local pr, rs = aegisub.dialog.display(conf,opts,opts_ids)

	local slct={}

	--Update data
	if ctemp then
		for i=idx1,idx2 do
			--The old style, in case a new style was not found
			local oldsty=select(5,parse(data[ctemp][i]))
			--l,tt,st,ed,sty,ln
			data[ctemp][i]=tfmt(rs["layer_"..i],rs["timetype_"..i],
				rs["start_"..i],rs["end_"..i],
				#rs["style_"..i]>1 and rs["style_"..i] or oldsty,rs["line_"..i])
			if rs["select_"..i] then table.insert(slct,i) end
		end
	end

	--Handle button press
	--Save and load
	if pr=="Save" then
		save_tg()

	elseif pr=="Load" then
		ctemp=rs["temp_select"]

	--New and delete
	elseif pr=="New template" then
		local nname=""

		repeat

			local npressed,nresults=aegisub.dialog.display(
				{
					{x=0,y=0,width=7,height=1,class="label",label="Enter template name:"},
					{x=0,y=1,width=7,height=1,class="edit",name="tname",
						value="Template "..next_n(table.keys(data),"Template")}
				},{"Save","Cancel"},{ok="Save",cancel="Cancel"})

			nname=nresults["tname"]

			if npressed=="Cancel" then return end

		until (not data[nname] and #nname>0)

		data[nname]={tfmt(0,"rb",0,0,"Default","")}
		ctemp=nname

	elseif pr=="Delete template" then
		if rs["temp_select"] then
			local dtemp=rs["temp_select"]
			data[dtemp]=nil
			if dtemp==ctemp then ctemp=nil end
		else
			data[ctemp]=nil
			ctemp=nil
		end
	--Actions
	elseif pr=="Action" then
		act=rs["action"]
		last_action=act
		if act=="New line" then
			table.insert(data[ctemp],tfmt(0,"rb",0,0,"Default",""))
		elseif act=="Delete selected" then
			for j=#slct,1,-1 do
				table.remove(data[ctemp],slct[j])
			end
			--Disallow deleting all lines
			if #data[ctemp]<1 then
				table.insert(data[ctemp],tfmt(0,"rb",0,0,"Default","")) end
		elseif act=="Duplicate selected" then
			for _,j in pairs(slct) do
				table.insert(data[ctemp],data[ctemp][j])
			end
		elseif act=="Modify selected" then
			--Return if no lines selected
			if #slct<1 then return end

			local stnames={"No change"}
			for _,st in ipairs(styles) do table.insert(stnames,st.name) end

			local modconf={
				{x=0,y=0,width=1,height=1,class="label",label="Layer change:"},
				{x=0,y=1,width=1,height=1,class="intedit",name="dlayer",value=0},
				{x=1,y=0,width=1,height=1,class="label",label="Style:"},
				{x=2,y=0,width=1,height=1,class="dropdown",name="dstyle",items=stnames,value="No change"},
				{x=1,y=1,width=1,height=1,class="label",label="Timing:"},
				{x=2,y=1,width=1,height=1,class="dropdown",name="dtiming",items=
					{"No change",ttdict.a,ttdict.rs,ttdict.re,ttdict.rb},value="No change"},
				{x=3,y=0,width=1,height=1,class="label",label="Start change:"},
				{x=4,y=0,width=1,height=1,class="intedit",name="dstart",value=0},
				{x=3,y=1,width=1,height=1,class="label",label="End change:"},
				{x=4,y=1,width=1,height=1,class="intedit",name="dend",value=0},
				{x=0,y=2,width=5,height=1,class="label",label="Find (supports Lua patterns):"},
				{x=0,y=3,width=5,height=1,class="edit",name="dfind",value=""},
				{x=0,y=4,width=5,height=1,class="label",label="Replace:"},
				{x=0,y=5,width=5,height=1,class="edit",name="drep",value=""}
			}

			local mpr,mrs=aegisub.dialog.display(modconf,{"Go","Cancel"},{ok="Go"})

			if mpr=="Cancel" then return end

			local dl,dsty,dtt,dst,ded,dfind,drep=
				mrs.dlayer,mrs.dstyle,mrs.dtiming,mrs.dstart,mrs.dend,mrs.dfind,mrs.drep

			for _,j in ipairs(slct) do
				local cl,ctt,cst,ced,csty,cln=parse(data[ctemp][j])
				cl=cl+dl
				if cl<0 then cl=0 end
				if dtt~="No change" then ctt=dtt end
				if dsty~="No change" then csty=dsty end
				cst=cst+dst
				ced=ced+ded
				cln=cln:gsub(dfind,drep)
				data[ctemp][j]=tfmt(cl,ctt,cst,ced,csty,cln)
			end

		elseif act=="Import from subtitles" then
			if not sel or #sel<1 then aegisub.cancel() end --Because fuck you

			--Make sure a video is loaded
			if not aegisub.frame_from_ms(1) then
				aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
					label="Please load a video."}},{"OK"})
				aegisub.cancel()
			end

			local _,lsresults=aegisub.dialog.display(
				{
					{x=0,y=0,width=5,height=1,class="label",label="Load times as:"},
					{x=0,y=1,width=5,height=1,class="dropdown",name="tt_select",items=
						{ttdict.a,ttdict.rb,ttdict.rs,ttdict.re},
						value=ttdict.rb},
					{x=0,y=2,width=5,height=1,class="checkbox",name="keep_text",
						label="Preserve line text",value=false},
					{x=0,y=3,width=5,height=1,class="label",label="Convert tags to variables:"},
					{x=0,y=4,width=5,height=2,class="textbox",name="convert_tags",
					hint="Comma separated list of tags to convert to variables"}
				},{"OK"})

			local ttype=ttdict[lsresults["tt_select"]]
			local keep_text=lsresults["keep_text"]
			local taglist=lsresults["convert_tags"]

			if not taglist:match(",$") then taglist=taglist.."," end
			taglist=taglist:gsub("%s",""):lower()
			tagtb={}
			for tg in taglist:gmatch("([^,]+),") do
				table.insert(tagtb,tg)
			end

			--Get data on first line timing
			local bline=sub[sel[1]]
			local bstart=aegisub.frame_from_ms(bline.start_time)
			local bend=aegisub.frame_from_ms(bline.end_time)

			for i,li in ipairs(sel) do
				local cline=sub[li]

				local cstart=aegisub.frame_from_ms(cline.start_time)
				local cend=aegisub.frame_from_ms(cline.end_time)
				local ctext=cline.text

				if ttype=="rb" then
					cstart=cstart-bstart
					cend=cend-bend
				elseif ttype=="rs" then
					cstart=cstart-bstart
					cend=cend-bstart
				elseif ttype=="re" then
					cstart=cstart-bend
					cend=cend-bend
				end

				if not keep_text then
					if not cline.text:match("^{") then
						cline.text="{}"..cline.text
					end
					cline.text=cline.text:gsub("(%b{})[^{]+","%1%$text")
					cline.text=cline.text:gsub("^{}","")
				end

				for _,tg in ipairs(tagtb) do
					cline.text=cline.text:gsub("\\"..tg.."([^\\}]+)",
						function(param)
							if tg=="pos" then return "\\pos($x,$y)"
							elseif tg=="clip" or tg=="iclip" then
								if param:match("m") then return "\\"..tg.."($vclip)"
								else return "\\"..tg.."($clipx1,$clipy1,$clipx2,$clipy2)" end
							elseif tg=="org" then return "\\org($orgx,$orgy)"
							elseif tg=="move" then return "\\move($x1,$y1,$x2,$y2,$movet1,$movet2)"
							elseif tg=="fad" then return "\\fad($fad1,$fad2)"
							end
							return "\\"..tg.."$"..tg
						end)
				end

				data[ctemp][i]=tfmt(cline.layer,ttype,cstart,cend,cline.style,cline.text)

			end
		elseif act=="Jump to page" then
			_,pgrs=aegisub.dialog.display({{x=0,y=0,width=1,height=1,
				class="intedit",name="pageto",value=page,min=1,max=maxpage}},{"Go"},{ok="Go"})
			page=pgrs.pageto
		elseif act=="Revert to last save" then
			load_tg()
		end

	--Return to main
	elseif pr=="Main" then
		next_menu=main_menu

	--Page handling
	elseif pr=="<--" then
		page=page-1
	elseif pr=="-->" then
		page=page+1

	--Quit
	else
		aegisub.cancel()
	end

end

--New template group menu
function new_tg()
	local conf =
	{
		{x=0,y=0,width=7,height=1,class="label",label="Enter template group name:"},
		{x=0,y=1,width=7,height=1,class="edit",name="tname",
			value="Template group "..next_n(tglist,"Template group")}
	}

	local nname=""

	repeat

		local pressed,results=aegisub.dialog.display(conf,{"Save","Cancel"},{ok="Save",cancel="Cancel"})

		if pressed~="Save" then
			next_menu=main_menu
			return
		end

		nname=results["tname"]

	until not isdupe(tglist,nname) and #nname>0

	ctg=nname

	meta.name=ctg
	meta.version=script_version
	data={}

	table.insert(tglist,nname)

	save_list()
	save_tg()
	next_menu=main_menu
end

--Displays main menu
function main_menu()

	load_list()

	table.sort(tglist)

	if not ctg and #tglist>0 then
		ctg=tglist[1]
	end

	local dconfig=
	{
		{x=0,y=0,width=1,height=1,class="label",label="Template group:"},
		{x=1,y=0,width=1,height=1,class="dropdown",name="tgroup",items=tglist,value=ctg}
	}

	local options={"New template group","Import","Quit"}
	local option_ids={cancel="Quit"}

	if #tglist>0 then
		table.insert(options,2,"Modify")
		table.insert(options,3,"Disable/Enable")
		table.insert(options,4,"Delete")
		option_ids.ok="Modify"
	end

	--Display dialog
	local pressed,results=aegisub.dialog.display(dconfig,options,option_ids)

	ctg=results["tgroup"]

	if not ctg then aegisub.cancel() end --Because fuck you

	--Set next menu
	next_menu=main_menu

	--Open different menus depending on input
	if pressed=="New template group" then next_menu=new_tg
	--Modify
	elseif pressed=="Modify" then
		--Creates data, even if it's empty
		load_tg()
		ctemp=nil
		next_menu=mod_temp

	--Disable/Enable
	elseif pressed=="Disable/Enable" then
		local didx=0
		for i,tgname in ipairs(tglist) do
			if tgname==ctg then
				didx=i
				break
			end
		end
		if tglist[didx]:match(" %(DISABLED%)$") then
			tglist[didx]=tglist[didx]:gsub(" %(DISABLED%)$","")
		else
			tglist[didx]=tglist[didx].." (DISABLED)"
		end
		ctg=tglist[1]
		save_list()

	--Import
	elseif pressed=="Import" then

		local itemp=aegisub.dialog.open("Select template","","",".tm2 and .tm files|*.tm2;*.tm",false,true)
		if not itemp then return end
		local itempname=itemp:match(psep.."([^"..psep.."]+)%.tm2?$")

		--Copy file
		if psep=="\\" then os.execute("copy \""..itemp.."\" \""..tmpath.."\" /Y")
		else os.execute("cp \""..itemp.."\" \""..tmpath.."\"") end

		--Insert name
		if not isdupe(tglist,itempname) then table.insert(tglist,itempname) end
		save_list()

		--Update if necessary
		if itemp:match("%.tm$") then convert_to_tm2(itempname) end

	--Delete
	elseif pressed=="Delete" then
		local didx=0
		for i,tgname in ipairs(tglist) do
			if tgname==ctg then
				didx=i
				break
			end
		end
		table.remove(tglist,didx)

		if psep=="\\" then os.execute("del \""..tmpath..ctg..".tm2\"")
		else os.execute("rm \""..tmpath..ctg..".tm2\"") end

		if #tglist>0 then ctg=tglist[1] end
		save_list()

	--Quit
	else aegisub.cancel() end

end



--Main execution function
function tempman(_sub,_sel)

	--Set global sub and sel variables
	sub=_sub
	sel=_sel

	--Collect styles
	_,styles=karaskel.collect_head(sub,false)

	--Execute next menu until cancel
	while true do
		next_menu(menu_params())
	end
end

--Set next menu to main menu to start with
next_menu=main_menu

--Load existing templates
load_list()

--Register
rec:registerMacro(tempman)