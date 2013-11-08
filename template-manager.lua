--[[

Template Manager

Mostly self-explanatory. If you want to read variables from the line
you are applying the template to, then in most cases just surround the
name of the tag in percent signs. For example, to use the z rotation
from the line, type:

\frz%FRZ%

Some special values have different variable names:

\pos:
	%X% and %Y%
\org:
	%ORGX% and %ORGY%
\move:
	%X1%, %Y1%, %X2%, and %Y2% for the position
	%MOVET1% and %MOVET2% for the time parameters
\clip (rectangular):
	%CLIPX1%, %CLIPY1%, %CLIPX2%, and %CLIPY2%
\clip (vector):
	%VCLIP%
\fad:
	%FAD1% and %FAD2%

Also the actual text of the line is %TEXT%, so if you don't have a %TEXT%
in your template, it will ignore the line text (useful in certain cases,
e.g. a masking layer).

Concerning timing:

All times are in frames, since this is a typesetting script.

Absolute means the frame numbers are relative to the start of the video.
Relative (both) means the start is relative to the start of the line
	and the end is relative to the end of the line that the template is
	being applied to.
Relative (start) means both the start and end time are relative to the
	start of the line that the template is being applied to.
Relative (end) means... well you get the idea.

]]

script_name="Template Manager"
script_description="Manage typesetting templates."
script_version="Beta 1.0"

require 'karaskel'
require 'utils'

--Determine the path separator
psep=aegisub.decode_path('?data'):match('/') and '/' or '\\'

--The path to the template manager directory
tmpath=aegisub.decode_path("?user")..psep.."tempman"..psep

--Table of templates
templates={}

--Currently selected template group
ctg=nil

--And the table its data is stored in
ctg_data=nil

--Last used menu
last_menu=nil

--Last used templates
last_temps={}

--Styles
styles=nil

--Because convenience
ttdict=
{
	["a"]="Absolute",
	["rs"]="Relative (start)",
	["re"]="Relative (end)",
	["rb"]="Relative (both)",
	["Absolute"]="a",
	["Relative (start)"]="rs",
	["Relative (end)"]="re",
	["Relative (both)"]="rb"
}

--Function to scan and reload templates
function load_tm()
	--The index of templates
	local tmfile=io.open(tmpath.."index.txt","rb")
	
	templates={}
	
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
			
			table.insert(templates,tmname)
			tmname=tmfile:read("*line")
		end
		
		--Close file
		tmfile:close()
	else
		tmfile=io.open(tmpath.."index.txt","wb")
		if tmfile then tmfile:close()
		else
			os.execute("mkdir \""..tmpath.."\"")
		end
	end
end

--And save template index
function save_tm()
	local idxfile=io.open(tmpath.."index.txt","wb")
	
	for _,tname in ipairs(templates) do
		tname=tname:gsub("^(.+) %(DISABLED%)$","#%1")
		idxfile:write(tname.."\n")
	end
	
	idxfile:close()
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
	return string.format("\t%d,%s,%d,%d,%s,%s",l,ttdict[tt],st,ed,sty,ln)
end

--Save current template group
function save_ctg()
	if not ctg then return end
	
	local tgfile=io.open(tmpath..ctg..".tm","wb")
	
	for tname,tdata in pairs(ctg_data) do
		tgfile:write(tname..":\n")
		
		for _,ldata in ipairs(tdata) do
			tgfile:write(ldata.."\n")
		end
		
	end
	
	tgfile:close()
	
end

--Load template from file
function load_temp(tfname)
	
	if not tfname then tfname=ctg end
	
	if not tfname then
		aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
			label="Error - no template group selected."}},{"OK"})
		return
	end
	
	local tgfile=io.open(tmpath..tfname..".tm","rb")
	
	ctg_data={}
	
	if not tgfile then return end
	
	local tline=tgfile:read("*line")
	
	local ctname=""
	
	while tline do
		
		if tline:match("^[^\t]+:$") then 
			ctname=tline:match("(.+):$")
		
			ctg_data[ctname]={}
		end
		
		if tline:match("^\t") then
			table.insert(ctg_data[ctname],tline)
		end
		
		tline=tgfile:read("*line")
		
	end
	
	tgfile:close()
	
end

--Creates a function to register as a macro
function make_template(tname)
	
	return
	function(sub,sel)
		_,styles=karaskel.collect_head(sub,false)
		load_temp(tname)
		
		local tmlist={}
		for k in pairs(ctg_data) do
			table.insert(tmlist,k)
		end
		
		if #tmlist<1 then aegisub.cancel() end --Because fuck you
		
		local dconf=
		{
			{x=0,y=1,width=1,height=1,class="label",label="Select template:"},
			{x=0,y=1,width=1,height=1,class="dropdown",name="temp_select",
				items=tmlist,value=last_temps[tname] or tmlist[1]}
		}
		
		local pressed,results=aegisub.dialog.display(dconf,{"Apply","Cancel"})
		
		if pressed~="Apply" then aegisub.cancel() end --Because f--oh wait.
		
		last_temps[tname]=results["temp_select"]
		
		--Create a new pointer to the relevant data for convenience
		local tdata=ctg_data[results["temp_select"]]
		
		local lines_added=0
		
		local new_sel={}
		
		--For all lines in selection
		for i,li in ipairs(sel) do
			
			local function make_line_table(ltext)
				local ntable={}
				if ltext:match("^{")==nil then
					ltext="{}"..ltext
				end
				ltext=ltext:gsub("}","}\t")
				local j=1
				for thistag,thistext in ltext:gmatch("({[^{}]*})([^{}]*)") do
					ntable[j]={tag=thistag:gsub("\\1c","\\c"),text=thistext:gsub("^\t","")}
					j=j+1
				end
				return ntable
			end
			
			local cline=sub[li+lines_added]
			
			--Break the line into a table
			local cl_table=make_line_table(cline.text)
			
			
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
				
				--Set time based on timing type
				local bstart,bend=0,0
				if tt=="rb" then bstart,bend=cstart,cend
				elseif tt=="rs" then bstart,bend=cstart,cstart
				elseif tt=="re" then bstart,bend=cend,cend end
				
				nline.start_time=aegisub.ms_from_frame(bstart+st)
				nline.end_time=aegisub.ms_from_frame(bend+ed)
				
				local tl_table=make_line_table(ln)
				
				local rbtext=""
				
				local k=1
				
				local state={}
				
				while k<=#tl_table do
					
					local ctag=cl_table[(k<#cl_table) and k or #cl_table].tag
					local ttag=tl_table[k].tag
					local ctext=cl_table[(k<#cl_table) and k or #cl_table].text
					local ttext=tl_table[k].text
					
					local function replacer(txt)
						txt=txt:gsub("%%([^%%]+)%%",
							function(tg)
								tg=tg:lower()
								
								local param=nil
								
								if tg=="fn" or tg=="r" then
									param=ctag:match("\\"..tg.."([^\\}]+)")
								elseif tg=="a" then
									param=ctag:match("\\a(%d%d?)")
								elseif tg=="fs" then
									param=ctag:match("\\fs([%d%.]+)")
								elseif tg=="x" then
									param=ctag:match("\\pos%(([%-%d%.]+)")
								elseif tg=="y" then
									param=ctag:match("\\pos%([%-%d%.]+,([%-%d%.]+)")
								elseif tg=="x1" then
									param=ctag:match("\\move%(([%-%d%.]+)")
								elseif tg=="y1" then
									param=ctag:match("\\move%([%-%d%.]+,([%-%d%.]+)")
								elseif tg=="x2" then
									param=ctag:match("\\move%("..("[%-%d%.]+,"):rep(2).."([%-%d%.]+)")
								elseif tg=="y2" then
									param=ctag:match("\\move%("..("[%-%d%.]+,"):rep(3).."([%-%d%.]+)")
								elseif tg=="movet1" then
									param=ctag:match("\\move%("..("[%-%d%.]+,"):rep(4).."([%-%d%.]+)")
								elseif tg=="movet2" then
									param=ctag:match("\\move%("..("[%-%d%.]+,"):rep(5).."([%-%d%.]+)")
								elseif tg=="clipx1" then
									param=ctag:match("\\clip%(([%-%d%.]+)")
								elseif tg=="y1" then
									param=ctag:match("\\clip%([%-%d%.]+,([%-%d%.]+)")
								elseif tg=="x2" then
									param=ctag:match("\\clip%("..("[%-%d%.]+,"):rep(2).."([%-%d%.]+)")
								elseif tg=="y2" then
									param=ctag:match("\\clip%("..("[%-%d%.]+,"):rep(3).."([%-%d%.]+)")
								elseif tg=="orgx" then
									param=ctag:match("\\org%(([%-%d%.]+)")
								elseif tg=="orgy" then
									param=ctag:match("\\org%([%-%d%.]+,([%-%d%.]+)")
								elseif tg=="fad1" then
									param=ctag:match("\\fad%(([%-%d%.]+)")
								elseif tg=="fad2" then
									param=ctag:match("\\fad%([%-%d%.]+,([%-%d%.]+)")
								elseif tg=="vclip" then
									param=ctag:match("\\clip%(([^%)]+)%)")
								elseif tg=="text" then
									param=ctext
								else
									param=ctag:match("\\"..tg.."([^\\}]+)")
								end
								
								--If param not found, read from state, and update state
								param=param or state[tg]
								state[tg]=param or state[tg]
								--If param still not found, delete this tag
								param=param or "%%DELETE%%"
								
								return param
								
							end)
						
						return txt:gsub("\\[^\\}]+%%DELETE%%[^\\}]*([\\}])","%1")
					end
					
					rbtext=rbtext..replacer(ttag)..replacer(ttext)
					
					k=k+1
				end
				
				--Now evaluate expressoins
				rbtext=rbtext:gsub("!([^!]+)!",function(expr)
						local com,err=loadstring("return "..expr)
						if err then aegisub.log(err) return end
						return com()
					end)
			
				--Add the line
				nline.text=rbtext:gsub("{}","")
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

--Find the next number to name a default name
function next_n(tb,str)
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
function isdupe(tb,item)
	for _,i in pairs(tb) do
		if i==item then return true end
	end
	return false
end

--Create a line template edit row in row n
function tedit_row(n)
	
	local stnames={}
	for _,st in ipairs(styles) do
		table.insert(stnames,st.name)
	end
	
	return
		{x=0,y=n*3-2,width=1,height=1,class="label",label="Layer"},
		{x=0,y=n*3-1,width=1,height=1,class="intedit",name="layer_"..n,value=0,min=0},
		
		{x=1,y=n*3-2,width=1,height=1,class="label",label="Style:"},
		{x=2,y=n*3-2,width=1,height=1,class="dropdown",name="style_"..n,items=stnames,value="Default"},
		{x=1,y=n*3-1,width=1,height=1,class="label",label="Timing:"},
		{x=2,y=n*3-1,width=1,height=1,class="dropdown",name="timetype_"..n,items=
			{ttdict.a,ttdict.rs,ttdict.re,ttdict.rb},
			value=ttdict.rb},
		
		{x=3,y=n*3-2,width=1,height=1,class="label",label="Start:"},
		{x=4,y=n*3-2,width=1,height=1,class="intedit",name="start_"..n,value=0},
		{x=3,y=n*3-1,width=1,height=1,class="label",label="End:"},
		{x=4,y=n*3-1,width=1,height=1,class="intedit",name="end_"..n,value=0},
		
		{x=5,y=n*3-2,width=40,height=2,class="textbox",name="line_"..n}
end

--Fill the edit row with existing data
function fill_row(n,l,tt,st,ed,sty,ln)
	lab1,ledit,lab2,styedit,lab3,ttedit,lab4,stedit,lab5,ededit,lnedit=
		tedit_row(n)
	
	if #tt<3 then tt=ttdict[tt] end
	
	ledit.value=l
	styedit.value=sty
	ttedit.value=tt
	stedit.value=st
	ededit.value=ed
	lnedit.value=ln
	
	return lab1,ledit,lab2,styedit,lab3,ttedit,lab4,stedit,lab5,ededit,lnedit
end

--New template menu
function new_temp(sub,sel,conf)
	if not conf then
		conf=
		{
			{x=0,y=0,width=7,height=1,class="label",label="Enter template group name:"},
			{x=0,y=1,width=7,height=1,class="edit",name="tname",
				value="Template group "..next_n(templates,"Template group")}
		}
	end
	
	local nname=""
	
	repeat
		
		local pressed,results=aegisub.dialog.display(conf,{"Save"})
		
		if pressed~="Save" then aegisub.cancel() end --Because fuck you
	
		nname=results["tname"]
		
	until not isdupe(templates,nname) and #nname>0
	
	ctg=nname
	
	table.insert(templates,nname)
	
	save_tm()
	
	main_menu()
end

--Modify template menu
function mod_temp(sub,sel,conf)
	--Creats ctg_data, even if it's empty
	load_temp()
	
	local titems={}
	
	--Returns a dialog config containing a template selector
	local function tselector()
		titems={}
		for tname in pairs(ctg_data) do
			table.insert(titems,tname)
		end
		return
		{
			{x=0,y=0,width=5,height=1,class="dropdown",name="temp_select",items=titems,
				value=titems[1] or nil}
		}
	end
	
	local rows=0
	
	if not conf then
		conf=tselector()
	else
		rows=tonumber(conf[#conf].name:match("_(%d+)")) or 0 --Hacky as fuuuuuuuck
		titems=conf[1].items
	end
	
	local opts={"New template","Main","Quit"}
	
	--Make sure ctg_data has data
	local has_temps=false
	for _ in pairs(ctg_data) do
		has_temps=true
		break
	end
	
	if ctg_data and has_temps then
		table.insert(opts,1,"Save")
		table.insert(opts,2,"Load")
		table.insert(opts,3,"Load selected lines")
		table.insert(opts,4,"New line")
		table.insert(opts,6,"Delete template")
	end
	
	local pressed,results=aegisub.dialog.display(conf,opts)
	
	--Compile results into a table
	local tline_data={}
	
	for k,v in pairs(results) do
		local param,n=k:match("(%a+)_(%d+)")
		if n then
			n=tonumber(n)
			if not tline_data[n] then tline_data[n]={} end
			tline_data[n][param]=tonumber(v) or v
		end
	end
	
	--Update conf to match results
	local function update_conf(stemp)
		
		conf=tselector()
		
		stemp=stemp or conf[1].items[1]
		
		conf[1].value=stemp
		
		ctg_data[stemp]={}
		
		for i,v in ipairs(tline_data) do
			table.insert(ctg_data[stemp],
				tfmt(v.layer,v.timetype,v.start,v["end"],v.style,v.line))
			for _,ctrl in ipairs(
				{fill_row(i,v.layer,v.timetype,v.start,v["end"],v.style,v.line)}) do
				
				table.insert(conf,ctrl)
			end
		end
	end
	
	--Set last menu
	last_menu=function(sub,sel) mod_temp(sub,sel,conf) end
	
	--Name of selected template
	local stemp=results["temp_select"]
	
	--New template routine
	if pressed=="New template" then
	
		local nname=""
		
		repeat
			
			local _,nresults=aegisub.dialog.display(
				{
					{x=0,y=0,width=7,height=1,class="label",label="Enter template name:"},
					{x=0,y=1,width=7,height=1,class="edit",name="tname",
						value="Template "..next_n(titems,"Template")}
				},{"Save"})
			
			nname=nresults["tname"]
			
		until not ctg_data[nname] and #nname>0
		
		ctg_data[nname]={}
		
		conf=tselector()
		
		conf[1].value=nname
		
		for _,ctrl in ipairs({tedit_row(1)}) do
			table.insert(conf,ctrl)
		end
		
		save_ctg()
		
		return mod_temp(sub,sel,conf)
	
	--Delete routine
	elseif pressed=="Delete template" then
		
		if stemp then
			ctg_data[stemp]=nil
			
			save_ctg()
		end
		
		return mod_temp(sub,sel)
	
	--Save routine
	elseif pressed=="Save" then
		
		update_conf(results["temp_select"])
		
		save_ctg()
		
		return mod_temp(sub,sel,conf)
	
	--Load template routine
	elseif pressed=="Load" then
		
		conf=tselector()
		
		if stemp then
			conf[1].value=stemp
			for i,tline in ipairs(ctg_data[stemp]) do
				for _,ctrl in ipairs({fill_row(i,parse(tline))}) do
					table.insert(conf,ctrl)
				end
			end
		end
		
		return mod_temp(sub,sel,conf)
	
	--Load from selected routine
	elseif pressed=="Load selected lines" then
		
		if not sel or #sel<1 then aegisub.cancel() end --Because fuck you
		
		local _,lsresults=aegisub.dialog.display(
			{
				{x=0,y=0,width=1,height=1,class="label",label="Load times as:"},
				{x=0,y=1,width=1,height=1,class="dropdown",name="tt_select",items=
					{ttdict.a,ttdict.rb,ttdict.rs,ttdict.re},
					value=ttdict.rb},
				{x=0,y=2,width=1,height=1,class="checkbox",name="keep_text",
					label="Preserve line text",value=false}
			},{"OK"})
		
		local ttype=ttdict[lsresults["tt_select"]]
		local keep_text=lsresults["keep_text"]
		
		--Get data on first line timing
		local bline=sub[sel[1]]
		local bstart=aegisub.frame_from_ms(bline.start_time)
		local bend=aegisub.frame_from_ms(bline.end_time)
		
		conf=tselector()
		if stemp then conf[1].value=stemp end
		
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
				cline.text=cline.text:gsub("(%b{})[^{]+","%1%%TEXT%%")
				cline.text=cline.text:gsub("^{}","")
			end
			
			for _,ctrl in ipairs(
				{fill_row(i,cline.layer,ttype,cstart,cend,cline.style,cline.text)}) do
				table.insert(conf,ctrl)
			end
			
		end
			
		return mod_temp(sub,sel,conf)
	
	--New line routine
	elseif pressed=="New line" then
	
		update_conf()
		if stemp then
			conf[1].value=stemp
		end
		
		for _,ctrl in ipairs({tedit_row(rows+1)}) do
			table.insert(conf,ctrl)
		end
		
		return mod_temp(sub,sel,conf)
		
	--Return to main menu
	elseif pressed=="Main" then
		main_menu(sub,sel)
	
	--Quit
	else
		aegisub.cancel()
	end
end

--Main menu
function main_menu(sub,sel)
	
	if not ctg and #templates>0 then
		ctg=templates[1]
	end
	
	local dconfig=
	{
		{x=0,y=0,width=1,height=1,class="label",label="Template group:"},
		{x=1,y=0,width=1,height=1,class="dropdown",name="tgroup",items=templates,value=ctg}
	}
	
	local options={"New template group","Quit"}
	
	if #templates>0 then
		table.insert(options,2,"Modify")
		table.insert(options,3,"Disable/Enable")
		table.insert(options,4,"Delete")
	end
	
	--Display dialog
	local pressed,results=aegisub.dialog.display(dconfig,options)
		
	ctg=results["tgroup"]
	
	if not ctg then aegisub.cancel() end --Because fuck you
	
	--Set last menu
	last_menu=main_menu
	
	--Open different menus depending on input
	if pressed=="New template group" then new_temp(sub,sel)
	elseif pressed=="Modify" then mod_temp(sub,sel)
	
	--Disable/Enable
	elseif pressed=="Disable/Enable" then
		local didx=0
		for i,tgname in ipairs(templates) do
			if tgname==ctg then
				didx=i
				break
			end
		end
		if templates[didx]:match(" %(DISABLED%)$") then
			templates[didx]=templates[didx]:gsub(" %(DISABLED%)$","")
		else
			templates[didx]=templates[didx].." (DISABLED)"
		end
		ctg=templates[1]
		save_tm()
		return main_menu()
		
	--Delete
	elseif pressed=="Delete" then
		local didx=0
		for i,tgname in ipairs(templates) do
			if tgname==ctg then
				didx=i
				break
			end
		end
		table.remove(templates,didx)
		
		if psep=="\\" then os.execute("del \""..tmpath..ctg..".tm\"")
		else os.execute("rm \""..tmpath..ctg..".tm\"") end
		
		if #templates>0 then ctg=templates[1] end
		save_tm()
		return main_menu()
	
	--Quit
	else aegisub.cancel() end
	
end

--Last used menu
last_menu=main_menu

--Main execution function
function tempman(sub,sel)
	_,styles=karaskel.collect_head(sub,false)
	last_menu(sub,sel)
end

--Load current templates
load_tm()

--Register
aegisub.register_macro(script_name,script_description,tempman)