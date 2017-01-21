toast = {}

dofile("objects.lua")
dofile("defaultlib.lua")
dofile("parser.lua")
dofile("compiler.lua")
dofile("debug.lua")
exc = dofile("exception.lua")

exc.catch(function()
	local source = toast.defaultlib .. [[
	cell x;
	x = 2;
	x = x + 69 + 2;
	]]
	local potato, err = toast.parse(toast.defaultctx, source)

	if not potato then
		print("Error")
		print(err)
	else
		print(cserialize(potato))
		local walrus, err = assert(toast.compile(potato, source))
		print(cserialize(walrus))
	end
end, "lua_error", function(err, bt)
	print(err .. " | " .. bt)
end)