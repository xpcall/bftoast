--@apidef exception
--|Exceptions API
--|Implements a proper exception system using lua errors
local exc = {}

--@apidef exception.throw
--|Throws an exception
--|Usage:
--|    exception.throw(name, ...)
function exc.throw(name, ...)
	error(
		setmetatable(
			{"exception", name = name, data = {...}},
			{__tostring = function() return name.." exception" end}
		)
	,0)
end

local function parseCatchArgs(...)
	local handlers = {...}
	local passArgs = {}
	if type(handlers[1]) == "table" then
		passArgs = handlers[1]
		table.remove(handlers, 1)
	end
	local finalFunc
	if #handlers % 2 == 1 and type(handlers[#handlers]) == "function" then
		finalFunc = handlers[#handlers]
		table.remove(handlers)
	end
	return handlers
end

function exc.catchraw(func, handlers, passArgs, finalFunc)
	local res = {xpcall(func, function(err)
		return {err, debug.traceback()}
	end, unpack(passArgs or {}))}
	if not res[1] then
		local err, tb = res[2][1], res[2][2]
		if type(err) == "string" then
			-- convert normal lua error to exception
			err = {
				"exception",
				name = "lua_error",
				data = {err, tb}
			}
		end
		local i = 1
		while handlers[i] do
			if type(handlers[i + 1]) ~= "function" then
				i = i + 1
			else
				if handlers[i] == err.name or handlers[i] == "*" then
					res[2] = {"return", {handlers[i + 1](unpack(err.data))}}
					return res
				end
				i = i + 2
			end
		end
		res[2] = {"rethrow", err}
	end
	return res
end

--@apidef exception.catch
--|Catches an exception
--|If second parameter is a table its contents are passed to func
--|Usage:
--|    exception.catch(func[, {...}], "exc1", func, "exc2", func, ...[, finally])
function exc.catch(func, ...)
	local handlers, passArgs, finalFunc = parseCatchArgs(...)
	local res = exc.catchraw(func, handlers, passArgs, finalFunc)
	if finalFunc then
		finalFunc()
	end
	if not res[1] then
		if res[2][1] == "rethrow" then
			error(res[2][2]) -- rethrow
		elseif res[2][1] == "return" then
			return unpack(res[2][2])
		end
	end
	return unpack(res, 2) -- no exceptions
end

--@apidef exception.catch
--|Runs func until an exception is thrown
--|If second parameter is a table its contents are passed to func
--|Usage:
--|    exception.untilcatch(func[, {...}], "exc1", func, "exc2", func, ...[, finally])
function exc.untilcatch(func, ...)
	local handlers, passArgs, finalFunc = parseCatchArgs(...)
	while true do
		local res, finalFunc = exc.catchraw(func, handlers, passArgs, finalFunc)
		if not res[1] then
			if res[2][1] == "rethrow" then
				error(res[2])
			end
		end
	end
	if finalFunc then
		finalFunc()
	end
end

--@apidef exception.xpcall
--|Compatibility function to allow old code to catch exceptions
--|Usage: same as xpcall
function exc.xpcall(func, cb, ...)
	return exc.catch(func, {...}, "*", function(err)
		if cb then
			return false, cb(tostring(err.name) .. " exception")
		end
	end)
end

--@apidef exception.pcall
--|Compatibility function to allow old code to catch exceptions
--|Usage: same as pcall
function exc.pcall(func, ...)
	local params = {...}
	return exc.xpcall(function()
		return func(unpack(params))
	end, function(err)
		return err
	end)
end

--@apidef exception.assert
--|Same as lua assert but throws exceptions
function exc.assert(value, name, ...)
	if not value then
		if not name then
			exc.throw("assert", {backtrace = debug.traceback(2)})
		else
			exc.throw(name, ...)
		end
	end
	return value
end

return exc