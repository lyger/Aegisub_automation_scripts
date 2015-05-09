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

script_name = "Gradient by character"
script_description = "Smoothly transforms tags across your line, by character."
script_version = "1.2.1"
script_author = "lyger"
script_namespace = "lyger.GradientByChar"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
    feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
    {
    	{"lyger.libLyger", version = "1.1.0", url = "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"},
    	"aegisub.util", "aegisub.re"
	}
}
local LibLyger, util, re = rec:requireModules()
local libLyger = LibLyger()

function grad_char(sub,sel)
	libLyger:set_sub(sub, sel)

	for si,li in ipairs(sel) do
		--Read in the line
		this_line=libLyger.lines[li]

		--Make sure line starts with tags
		if this_line.text:find("^{")==nil then this_line.text="{}"..this_line.text end

		--Turn all \1c tags into \c tags, just for convenience
		this_line.text=this_line.text:gsub("\\1c","\\c")

		--Make line table
		this_table={}
		x=1
		for thistag,thistext in this_line.text:gsub("}","}\t"):gmatch("({[^{}]*})([^{}]*)") do
			this_table[x]={tag=thistag,text=thistext:gsub("\t","")}
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
		this_state = LibLyger.make_state_table(this_table,transform_tags)

		--Style lookup
		this_style = libLyger:style_lookup(this_line)

		--Running record of the state of the line
		current_state={}

		--Outer control loop
		for i=2,#this_table,1 do
			--Update current state
			for ctag,cval in pairs(this_state[i-1]) do
				current_state[ctag]=cval
			end

			--Stores state of each character, to prevent redundant tags
			char_state=util.deep_copy(current_state)

			--Local function for interpolation
			local function handle_interpolation(factor,tag,sval,eval)
				local param_type, ivalue = libLyger.param_type, ""
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
					ivalue=libLyger.float2str(nvalue)

				elseif param_type[tag]=="number" then
					nstart=tonumber(sval)
					nend=tonumber(eval)

					--Interpolate and convert to string
					ivalue=libLyger.float2str(interpolate(factor,nstart,nend))
				end
				return ivalue
			end

			--Replace \N with newline character, so it's treated as one character
			local ttext=this_table[i-1].text:gsub("\\N","\n")

			if ttext:len()>0 then

				--Rebuilt text
				local rtext=""

				--Skip the first character
				local first=true

				--Starting values
				idx=1

				matches=re.find(ttext,'\\X')

				total=#matches

				for _,match in ipairs(matches) do

					ch=match.str

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
								rtext=rtext.."{*"..non_time_tags.."}"..ch
							end

						end
					else
						rtext=rtext..ch
					end
					first=false
				end

				--Put \N back in
				this_table[i-1].text=rtext:gsub("\n","\\N")

			end

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

-- Register the macro
rec:registerMacros{
    {"Apply Gradient", script_description, grad_char},
    {"Remove Gradient", "Removes gradient generated by #{script_name}", remove_grad_char}
}
