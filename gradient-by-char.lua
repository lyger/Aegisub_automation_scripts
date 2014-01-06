--[[
==README==

No GUI, pretty straightforward.

For example, to make a line bend in an arc and transition from blue to red, do this:

{\frz10\c&HFF0000&}This is a line of tex{\frz350\c&H0000FF&}t

Run the automation and it'll add a tag before each character to make the rotation and color
transition change smoothly across the line.

Rotations are locked to less than 180 degree rotations. If you want a bend of more than 180,
then split it up into multiple rotations of less than 180 each. This script is meant for
convenience above all, so it runs with a single button press and no time-consuming options menu.

]]--

script_name="Gradient by character"
script_description="Smoothly transforms tags across your line, by character."
script_version="1.1"

unicode = require 'aegisub.unicode'

--[[REQUIRE lib-lyger.lua OF VERSION 1.0 OR HIGHER]]--
if pcall(require,"lib-lyger") and chkver("1.0") then



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

function grad_char(sub,sel)

	local meta,styles = karaskel.collect_head(sub, false)
	
	for si,li in ipairs(sel) do
		--Read in the line
		this_line=sub[li]
		
		--Preprocess
		karaskel.preproc_line(sub,meta,styles,this_line)
		
		--Make sure line starts with tags
		if this_line.text:find("^{")==nil then this_line.text="{}"..this_line.text end
		
		--Turn all \1c tags into \c tags, just for convenience
		this_line.text=this_line.text:gsub("\\1c","\\c")
			
		--Make line table
		this_table={}
		x=1
		for thistag,thistext in this_line.text:gmatch("({[^{}]*})([^{}]*)") do
			this_table[x]={tag=thistag,text=thistext}
			x=x+1
		end
		
		if #this_table<2 then
			aegisub.log("There must be more than one tag block in the line!")
			return
		end
		
		--Transform these tags
		transform_tags={
			"c","2c","3c","4c",
			"alpha","1a","2a","3a",
			"fscx","fscy","fax","fay",
			"frx","fry","frz",
			"fs","fsp",
			"bord","shad",
			"xbord","ybord","xshad","yshad",
			"blur","be"
			}
		
		--Make state table
		this_state=make_state_table(this_table,transform_tags)
		
		--Style lookup
		this_style=style_lookup(this_line)
		
		--Running record of the state of the line
		current_state={}
		
		--Outer control loop
		for i=2,#this_table,1 do
			--Update current state
			for ctag,cval in pairs(this_state[i-1]) do
				current_state[ctag]=cval
			end
			
			--Stores state of each character, to prevent redundant tags
			char_state=deep_copy(current_state)
			
			--Local function for interpolation
			local function handle_interpolation(factor,tag,sval,eval)
				local ivalue=""
				--Handle differently depending on the type of tag
				if param_type[tag]=="alpha" then
					ivalue=interpolate_alpha(factor,sval,eval)
				elseif param_type[tag]=="color" then
					ivalue=interpolate_color(factor,sval,eval)
				elseif param_type[tag]=="angle" then
					nstart=tonumber(sval)
					nend=tonumber(eval)
					
					--Use "Rotate in shortest direction" by default
					nstart=nstart%360
					nend=nend%360
					ndelta=nend-nstart
					if math.abs(ndelta)>180 then nstart=nstart+(ndelta*360)/math.abs(ndelta) end
					
					--Interpolate
					nvalue=interpolate(factor,nstart,nend)
					if nvalue<0 then nvalue=nvalue+360 end
					
					--Convert to string
					ivalue=float2str(nvalue)
					
				elseif param_type[tag]=="number" then
					nstart=tonumber(sval)
					nend=tonumber(eval)
					
					--Interpolate and convert to string
					ivalue=float2str(interpolate(factor,nstart,nend))
				end
				return ivalue
			end
			
			--TODO: UNICODE HANDLING
			
			--Replace \N with newline character, so it's treated as one character
			local ttext=this_table[i-1].text:gsub("\\N","\n")
			
			--Rebuilt text
			local rtext=""
			
			--Skip the first character
			local first=true
			
			--Starting values
			idx=1
			total=unicode.len(ttext)
				
			for ch in unicode.chars(ttext) do
				
				if not first then
					--Interpolation factor
					factor=idx/total
					
					idx=idx+1
					
					--Do nothing if the character is a space
					if ch:find("%s")~=nil then
						rtext=rtext..ch
					else
					
						--The tags in and out of the time statement
						local non_time_tags=""
						
						--Go through all the state tags in this tag block
						for ttag,tparam in pairs(this_state[i]) do
							--Figure out the starting state of the param
							local sparam=current_state[ttag]
							if sparam==nil then sparam=this_style[ttag] end
							if type(sparam)~="number" then sparam=sparam:gsub("%)","") end--Just in case a \t tag snuck in
							
							--Prevent redundancy
							if sparam~=tparam then
								--The string version of the interpolated parameter
								local iparam=handle_interpolation(factor,ttag,sparam,tparam)
								
								if iparam~=tostring(char_state[ttag]) then
									non_time_tags=non_time_tags.."\\"..ttag..iparam
									char_state[ttag]=iparam
								end
							end
						end
					
						if non_time_tags:len() < 1 then
							--If no tags were added, do nothing
							rtext=rtext..ch
						else
							--The final tag, with a star to indicate it was added through interpolation
							rtext=rtext.."{\*"..non_time_tags.."}"..ch
						end
						
					end
				else
					rtext=rtext..ch
				end
				first=false
			end
			
			this_table[i-1].text=rtext:gsub("\n","\\N")
			
		end
		
		rebuilt_text=""
		
		for i,val in pairs(this_table) do
			rebuilt_text=rebuilt_text..val.tag..val.text
		end
		this_line.text=rebuilt_text
		sub[li]=this_line
	end
	
	aegisub.set_undo_point(script_name)
end

function remove_grad_char(sub,sel)
	for si,li in ipairs(sel) do
		this_line=sub[li]
		this_line.text=this_line.text:gsub("{%*[^{}]*}","")
		sub[li]=this_line
	end
end

--Register the macro
aegisub.register_macro(script_name,script_description,grad_char)
aegisub.register_macro(script_name.." - un-gradient","Removes gradient generated by "..script_name,remove_grad_char)




--[[HANDLING FOR lib-lyger.lua NOT FOUND CASE]]--
else
require "clipboard"
function lib_err()
	aegisub.dialog.display({{class="label",
		label="lib-lyger.lua is missing or out-of-date.\n"..
		"Please go to:\n\n"..
		"https://github.com/lyger/Aegisub_automation_scripts\n\n"..
		"and download the latest version of lib-lyger.lua.\n"..
		"(The URL will be copied to your clipboard once you click OK)",
		x=0,y=0,width=1,height=1}})
	clipboard.set("https://github.com/lyger/Aegisub_automation_scripts")
end
aegisub.register_macro(script_name,script_description,lib_err)
end