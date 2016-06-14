toast = {}

dofile("objects.lua")
dofile("defaultlib.lua")
dofile("parser.lua")
dofile("compiler.lua")
dofile("debug.lua")
exc = dofile("exception.lua")

exc.catch(function()
	local potato, err = toast.parse(toast.defaultctx, [[
	int x;
	inline func potato(int y) {
		x = x + y;
	};
	potato(69);
	]])

	if not potato then
		print("Error")
		print(err)
	else
		print(cserialize(potato))
	end
end, "lua_error", function(err, bt)
	print(err .. " | " .. bt)
end)