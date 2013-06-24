--[[
==README==

Layer Increment

Basic utility that will make selected lines have increasing or decreasing layer numbers.

]]

script_name="Layer increment"
script_description="Makes increasing or decreasing layer numbers"
script_version="1.0"

config={
	{
		class="dropdown", name="updown",
		items={"Count up","Count down"},
		x=0,y=0,width=2,height=1,
		value="Count up"
	},
	{
		class="label",label="Interval",
		x=0,y=1,width=1,height=1
	},
	{
		class="intedit",name="int",
		x=1,y=1,width=1,height=1,
		min=1,value=1
	}
}

function layer_inc(sub,sel)
	pressed,results=aegisub.dialog.display(config,{"Go","Cancel"})
	
	min_layer=0
	
	for _,li in ipairs(sel) do
		line=sub[li]
		if line.layer>min_layer then min_layer=line.layer end
	end
	
	start_layer=min_layer
	factor=1
	interval=results["int"]
	
	if results["updown"]=="Count down" then
		start_layer=min_layer+(#sel-1)*interval
		factor=-1
	end
	
	for j,li in ipairs(sel) do
		line=sub[li]
		line.layer=start_layer+(j-1)*factor*interval
		sub[li]=line
	end
	
	return sel
end

aegisub.register_macro(script_name,script_description,layer_inc)





