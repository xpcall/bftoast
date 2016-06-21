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

		newTemp = function(txt)
			txt = txt or "tmp"
			local i = 0
			while getSymbol(txt..i) do
				i = i + 1
			end
			return txt..i
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
				if c[1] == "define" and c[3] == fname then -- {"define", type_info, symbol_name}
					c[3] = tname
				end
				-- incomplete
			end)
		end

		local codeSections = {}

		-- this function converts all the sub blocks of code (function parameters, etc) into flat code chunks
		local function flatten(co)
			assert(co[1] == "code")

			ctx.push()
			local idx = 2

			local function declobber(x)
				if x[1] == "code" then
					if x.clobbers then
						for i = 1, #x.clobbers do
							local c = x.clobbers[i]
						end
					end
				end
			end

			local function merge(x)
				if x[1] == "code" then
					for l1 = 2, #x do
						table.insert(co, idx + l1 - 2, x[l1])
					end
				else
					table.insert(co, idx, x)
				end
			end

			while co[idx] do
				local c = co[idx]
				if c[1] == "code" then -- {"code", ...}
					table.remove(co, idx)
					flatten(c)
					for l1 = 2, #c do
						table.insert(co, idx + l1 - 2, c[l1])
					end
					idx = idx - 1

				elseif c[1] == "func" then -- {"func", symbol_name, qualifiers, arglist, code}
					table.insert(codeSections, c[5])
					ctx.push()
					for k, v in pairs(c[4]) do
						ctx.scopeStack[1][v[2]] = {"reference", v}
					end
					flatten(c[5])
					for k, v in pairs(ctx.pop()) do
						table.insert(c[5], {"pop", k})
					end
					table.remove(co, idx)
					ctx.scopeStack[1][c[2]] = {"funcptr", qualifiers, arglist, #codeSections}

				elseif c[1] == "define" then -- {"define", type_info, symbol_name}
					local existing = ctx.scopeStack[1][c[3]]
					if existing then
						table.insert(co, idx + 1, {"pop", c[3]})
					end
					ctx.scopeStack[1][c[3]] = c[2]

				elseif c[1] == "return" then -- {"return", ...}
					if not co.returnVarname then -- TODO: allow inline function calls to not be assigned
						exc.throw("compilerError", "cannot return", c)
					end
					table.remove(co, idx)
					
					table.insert(co,idx, {"assign", {"reference", co.returnVarname}, })
					idx = idx - 1

				elseif c[1] == "assign" then -- {"assign", expression, expression}
					exc.assert(c[2][1] == "reference", "compilerError", "Complex references unsuported atm", c)
					table.remove(co, idx)
					table.insert(co,idx, {"ilcall", "o_copy", {c[2], c[3]})
					idx = idx - 1

				elseif c[1] == "ilcall" then -- {"ilcall", funcname, {...}}
					local func = ctx.requireSymbol(c[2])

					ctx.push()
					local arglist = {}
					for k, v in pairs(c[3]) do
						if v[1] == "code" then
							local t = ctx.newTemp()
							v.returnVarname = t
							merge(flatten(v))
							table.insert(arglist, {"reference", t})
						else
							table.insert(arglist, v)
						end
					end
					
					if func.builtin then
						func[3](ctx, arglist, )
					elseif func[2].inline then
						table.remove(co, idx)
						idx = idx - 1

						merge(func[4])

						-- incomplete
					else
						exc.throw("compilerError", "Tasks unsuported atm", c)
					end

					for k, v in pairs(ctx.pop()) do
						table.insert(co, {"pop", k})
					end

				end -- missing a bunch more 
				idx = idx + 1
			end
			for k, v in pairs(ctx.pop()) do
				table.insert(co, {"pop", k})
			end
			return co
		end

		table.insert(codeSections, flatten(code))

		print(cserialize(codeSections[1]))

		-- assumption: every item in codeSections is flat

		-- stack managment

		local mainSec = codeSections[1] -- right now we only care about the main chunk
		local stack = {} -- todo: substacks
		local used = {}
		local meta = {}
		local cstackpos = 1
		local i = 1

		local function codeMerge(c)
			for j = 1, #c do
				table.insert(mainSec, i + j - 1, c[j])
			end
			i = i - 1
		end

		while mainSec[i] do
			local c = mainSec[i]
			if c[1] == "push" then -- {"push", type, varname, meta}
				table.insert(stack, c[2])
				used[c[2]] = #stack
				meta[c[2]] = c

			elseif c[1] == "pop" then -- {"pop", name}
				used[c[2]] = nil
				while not used[stack[#stack]] do
					if cstackpos > #stack then
						local obj = meta[stack[#stack]]
						if obj.static_size then
							table.insert(mainSec, i, {"bf", ("<"):rep(obj.static_size)})
						else
							table.insert(mainSec, i, {"bf", obj.func.seekLeft(ctx, obj)})
						end
						i = i - 1

					end
					meta[c[2]] = nil
					table.remove(stack)
				end

			elseif c[1] == "seek" then -- {"seek", name}
				while cstackpos ~= used[c[2]] do
					local obj = meta[stack[cstackpos]]
					if cstackpos > used[c[2]] then
						table.insert(mainSec, i, {"bf", obj.static_size and ("<"):rep(obj.static_size) or obj.func.seekLeft(ctx, obj)})
						cstackpos = cstackpos - 1
					else
						table.insert(mainSec, i, {"bf", obj.static_size and (">"):rep(obj.static_size) or obj.func.seekRight(ctx, obj)})
						cstackpos = cstackpos + 1
					end
				end
			end

			i = i + 1
		end

		return mainSec

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
