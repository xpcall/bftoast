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
		assert(code.parent)
		for k, v in pairs(code.parent) do
			if v == code then
				code.parent[k] = nil
				return
			end
		end
	end

	local ctx = {
		scopeStack = {},
		push = function()
			table.insert(scopeStack, 1, {})
		end,
		pop = function()
			return table.remove(scopeStack, 1)
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
			return sm
		end,
	}

	return exc.catch(function()

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

		-- refactor variable names
		local function refactorSymbol(c, fname, tname)
			iterateCode(code, function(c, idx)

			end)
		end

		local codeSections = {}

		local function flatten(co)
			assert(co[1] == "code")
			ctx.push()
			local idx = 2
			while co[idx] do
				idx = idx + 1
				local c = co[idx]
				if c[1] == "code" then -- {"code", ...}
					table.remove(co, idx)
					for l1 = 2, #c do
						table.insert(co, idx + l1 - 2, c[l1])
					end
					idx = idx - 1
				elseif c[1] == "func" then -- {"func", symbol_name, code}
					table.insert(codeSections, )
				elseif c[1] == "define" then -- {"define", type_info, symbol_name}
					local existing = ctx.scopeStack[1][c[3]]
					if existing then
						table.insert(co, idx + 1, {"pop", c[3]})
					end
					ctx.scopeStack[1][c[3]] = c[2]
				end
			end
			for k, v in pairs(ctx.pop()) do
				table.insert(co, {"pop", k})
			end
			return co
		end

		table.insert(codeSections, flatten(code))

		return codeSections

	end, "compilerError", function(msg, c)
		local sidx = getCodeIdx(c)
		local eidx = sidx
		while sidx ~= 0 and not otxt:sub(sidx, sidx):match("[\t\r\n]") do
			sidx = sidx - 1
		end
		while eidx ~= (#otxt + 1) and otxt:sub(eidx, eidx) ~= "\n" do
			eidx = eidx + 1
		end
		return false, msg .. "\n" .. otxt:sub(sidx + 1, eidx - 1) .. "\n" .. (" "):rep(getCodeIdx(c) - sidx) .. "^"
	end)
end