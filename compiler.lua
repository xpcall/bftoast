-- This code compiles code put out by the parser
function toast.compile(code)
	-- parser supplies code indexes useful for errors
	local function getCodeIdx(code)
		while not code.idx do
			code = code.parent
			if not code then
				return 0
			end
		end
		return code.idx
	end

	local function destroy(code)
		assert(code.idx)
	end

	local ctx = {
		scopeStack = {},
		push = function()
			table.insert(scopeStack, 1, {})
		end,
		pop = function()
			table.remove(scopeStack, 1)
		end,
		getSymbol = function(s)
			for i = 1, #scopeStack do
				if scopeStack[i][s] then
					return scopeStack[i][s]
				end
			end
		end,
		requireSymbol = function(s, c)
			local sm = getSymbol(s)
			if not s then
				exc.throw("compilerError", "\"" .. s .. "\" not defined in this scope", c)
			end
		end,
	}

	local function iterateCode(c, func)
		local idx = 2
		while c[idx] do
			idx = func(c, idx) or (idx + 1)
			if c[idx][1] == "code" then
				iterateCode(c[idx], func)
			end
		end
	end

	-- helps with tracing errors
	iterateCode(code, function(c, idx)
		c[idx].parent = c
	end)

	local codeSections = {code}

	local function flatten(c)
		local idx = 1
		while c[idx] do

		end
	end
end