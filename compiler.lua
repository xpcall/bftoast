-- This code compiles code put out by the parser
function toast.compile(code, otxt)
	-- parser supplies code indexes useful for errors
	local function getCodeIdx(code)
		if not code then
			return 0
		end
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

	local ctx
	ctx = {
		scopeStack = {},

		push = function()
			table.insert(ctx.scopeStack, 1, {})
		end,

		pop = function()
			return table.remove(ctx.scopeStack, 1)
		end,

		getSymbol = function(s)
			for i = 1, #ctx.scopeStack do
				if ctx.scopeStack[i][s] then
					return ctx.scopeStack[i][s]
				end
			end
		end,

		requireSymbol = function(s, c)
			local sm = ctx.getSymbol(s)
			if not sm then
				print(debug.traceback())
				exc.throw("compilerError", "\"" .. s .. "\" not defined in this scope", c)
			end
			return sm
		end,

		tempNum = -1,

		newTemp = function(txt)
			ctx.tempNum = ctx.tempNum + 1
			return "tmp" .. ctx.tempNum
		end,
	}

	return exc.catch(function()
		local function iterateCode(c, func)
			local idx = 2
			while c[idx] do
				idx = func(c, idx) or (idx + 1)
				if c[idx] and c[idx][1] == "code" then
					iterateCode(c[idx], func)
				end
			end
		end

		-- helps with tracing errors
		iterateCode(code, function(c, idx)
			c[idx].parent = c
		end)

		-- refactor variable names
		local function refactorSymbol(code, fname, tname)
			iterateCode(code, function(c, idx)
				if c[1] == "push" and c[3] == fname then -- {"push", type_info, symbol_name}
					c[3] = tname
				end
				-- incomplete
			end)
		end

		local function findMatchingFunc(name, args)


		end

		local codeSections = {}

		-- this function converts all the sub blocks of code (function parameters, etc) into flat code chunks
		local flatten
		function flatten(co)
			assert(co[1] == "code")

			if not co.inline then
				ctx.push()
			end
			local idx = 2

			local function declobber(x)
				if x[1] == "code" then
					if x.clobbers then
						for i = 1, #x.clobbers do
							local c = ctx.requireSymbol(x.clobbers[i])
							ctx.scopeStack[1][ctx.newTemp()] = c[2]
						end
					end-- incomplete (refactor)
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

			local resolveArgs
			function resolveArgs(t) -- resolves code/ilcall to references
				local o = {}
				local ocode = {"code", inline = true}
				for k, v in pairs(t) do
					local cv = v
					if cv[1] == "ilcall" then
						local regs, rcode = resolveArgs(v[3])
						table.insert(ocode, rcode)
						local vret = ctx.newTemp()
						cv = nil
						local cfunc
						for i = 1, #ctx.scopeStack do
							local cstack = ctx.scopeStack[i]
							for k, v in pairs(cstack) do
								if v.type[2] == "func" and v.name == name and #v.type.tparams == #regs then
									local match = true
									for j = 1, #v.tparams[1] do
										if toast.typeSignature(v.tparams[1][j]) ~= toast.typeSignature(requireSymbol(regs[j][2]).type) then
											match = false
											break
										end
									end

									if match then
										assert(v.section, "Undefined function")
										table.insert(ocode, {"push", v.type.tparams[2][1], vret})
										for j = 1, #vret do
											if v.tparams[1][j][2] == "ref" then
												table.insert(ocode, {"push", v.tparams[1][j].tparams[1][1]}, codeSections[v.section].params[j], alias = regs[j][2])
											else
												table.insert(ocode, {"push", v.tparams[1][j].tparams[1][1]}, codeSections[v.section].params[j])
												table.insert(ocode, {"call", "o_copy"})
											end
										end
										cv = {"reference", vret}
									end
								end
							end
						end
						table.insert(ocode, {"call", v[2], regs, {cv}})
					end

					if cv[1] == "code" then
						local t = ctx.newTemp()
						cv.returnVarname = t
						local cc = flatten(cv)
						for i = 2, #cc do
							table.insert(ocode, cc[i])
						end
						table.insert(o, {"reference", t})
					elseif cv[1] == "constant" then
						local t = ctx.newTemp()
						assert(cv[2] == "number")
						table.insert(ocode, {"bf", "$t[-]+" .. cv[3], {t = t}})
						table.insert(o, {"reference", t})
					elseif cv[1] == "reference" then
						table.insert(o, cv)
					else
						print(debug.traceback())
						exc.throw("compilerError", "cannot resolve type " .. tostring(cv[1] or cv), cv)
					end
				end

				return o, ocode
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

				elseif c[1] == "bf" and false then -- {"bf", codes, aliases}
					table.remove(co, idx)
					local aliases = c[3] or {}
					local nstat = 0
					local ccode = c[2]
					local bcode = ""
					while #ccode > 0 do
						local vname = ccode:match("^$[%a_][%w_]*")
						if vname then
							if #bcode > 0 then
								table.insert(co, idx + nstat, {"bf", bcode})
								nstat = nstat + 1
								bcode = ""
							end
							
							table.insert(co, idx + nstat, {"seek", aliases[vname:sub(2)] or vname:sub(2)})
							nstat = nstat + 1
							ccode = ccode:sub(#vname + 1)
						else
							bcode = bcode .. ccode:sub(1, 1)
							ccode = ccode:sub(2)
						end
					end

					if #bcode > 0 then
						table.insert(co, idx + nstat, {"bf", bcode})
						nstat = nstat + 1
					end

					idx = idx + nstat - 1

				elseif c[1] == "func" then -- {"func", symbol_name, qualifiers, arglist, rettype, code}

				elseif c[1] == "push" then -- {"push", type_info, symbol_name}
					local existing = ctx.scopeStack[1][c[3]]
					if existing then
						error("exists " .. c[3])
						table.insert(co, idx, {"pop", c[3]})
						idx = idx + 1
					end
					ctx.scopeStack[1][c[3]] = c[2]

				elseif c[1] == "pop" then -- {"pop", symbol_name}
					assert(ctx.scopeStack[1][c[2]], c[2])
					ctx.scopeStack[1][c[2]] = nil

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
					table.insert(co,idx, {"ilcall", "o_copy", {c[2], c[3]}})
					idx = idx - 1

				elseif c[1] == "ilcall" then -- {"ilcall", funcname, {...}}
					table.remove(co, idx)
					local params, pcode = resolveArgs({c})
					merge(pcode)
					idx = idx - 1
				elseif c[1] == "call" then -- {"call", funcname, {...params}, {...returns}}
					-- c[3] and c[4] must only contain references
					local stlfunc = assert(toast.funcs[c[2]], c[2])
					table.remove(co, idx)
					merge(assert(stlfunc(ctx, c[3], c[4]), c[2]))
					idx = idx - 1
				end -- missing a bunch more 
				idx = idx + 1
			end

			if not co.inline then
				for k, v in pairs(ctx.pop()) do
					if v[1] == "type" then
						table.insert(co, {"pop", k})
					end
				end
			end
			return co
		end

		table.insert(codeSections, flatten(code))

		print(cserialize(codeSections[1]))

		do return "done" end

		-- assumption: every item in codeSections is flat

		-- stack managment

		--[=[local mainSec = codeSections[1] -- right now we only care about the main chunk
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

		return mainSec]=]

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
