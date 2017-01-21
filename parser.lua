-- Parser output documentation
-- toast.parse(ctx, txt)
--     returns the main block of code
--     ctx holds configurable stuff like operators, qualifiers, and string escapes (see toast.defaultctx)
-- {"code", ...}
--     an array of statement blocks
-- {"constant", type, value}
--     constant types:
--         number
--         string
--         type
-- {"reference", name}
--     reference to variable
-- {"ilcall", funcname, {...}}
--     inline function call
--     third argument is a list of function parameters
-- {"push", type, varname}
--     declares a variable name
-- {"assign", expression, expression}
--     assignes a reference to 
-- {"func", varname, arglist, rettype, code}
--     function
-- {"while", varname, code}
--     simple while loop

toast.defaultctx = {
	operators = { -- later this will just be filled by funcs.lua
		{"^",  "o_pow", "x_x"},
		{"not","o_not", "_x"},
		{"!",  "o_not", "_x"},
		{"-",  "o_neg", "_x"},
		{"~",  "o_xor", "_x"},
		{"*",  "o_mul", "x_x"},
		{"/",  "o_div", "x_x"},
		{"+",  "o_add", "x_x"},
		{"-",  "o_sub", "x_x"},
		{"..", "o_cat", "x_x"},
		{"<",  "o_lt",  "x_x"},
		{">",  "o_gt",  "x_x"},
		{"<=", "o_leq", "x_x"},
		{">=", "o_geq", "x_x"},
		{"!=", "o_neq", "x_x"},
		{"~=", "o_neq", "x_x"},
		{"==", "o_eq",  "x_x"},
		{"and","o_and", "x_x"},
		{"&&", "o_and", "x_x"},
		{"or", "o_or",  "x_x"},
		{"||", "o_or",  "x_x"}
	},
	type_qualifiers = {
		["const"] = true,
		["final"] = true,
		["constexpr"] = true,
		["replace"] = true,
	},
	func_qualifiers = {
		["inline"] = true,
	},
	escapes = {
		a = "\a",
		b = "\b",
		f = "\f",
		n = "\n",
		r = "\r",
		t = "\t",
		v = "\v",
	},
	types = {
		["ref"] = true,
		["cell"] = true,
		["int"] = true,
		["long"] = true,
	},
}

function toast.typeSignature(t)
	if t[1] == "type" then
		local o = ""
		for i = 1, #t.quals do
			o = o .. t.quals[i] .. " "
		end
		o = o .. t[2]
		for i = 1, #t.tparams do
			o = o .. "<"
			for j = 1, #t.params[i] do
				o = o .. toast.typeSignature(t)
				if j ~= #t.params[i] then
					o = o .. ","
				end
			end
			o = o .. ">"
		end
	elseif t[1] == "constant" then
		if t[2] == "number" then
			return tostring(t[3])
		elseif t[2] == "string" then
			return (("%q"):format(t[3]):gsub("\\\n", "\\n"))
		else
			error("cannot serialize constant " .. t[2])
		end
	else
		error("cannot serialize " .. t[1])
	end
end

-- lua pattern escaper
local function pescape(txt)
	local o=txt:gsub("[%.%[%]%(%)%%%*%+%-%?%^%$]","%%%1"):gsub("%z","%%z")
	return o
end

local table_merge
function table_merge(a, b)
	for k,v in pairs(b) do
		if type(a[k]) == "table" then
			table_merge(a[k], v)
		else
			a[k] = v
		end
	end
	return a
end

function toast.parse(ctx, txt)
	local otxt = txt

	local function getIdx()
		return #otxt - #txt
	end

	-- adds code index for debugging
	local function addIdx(t)
		t.idx = getIdx()
		return t
	end

	local types = {ctx.types} -- we have to keep track of type names in the parser

	local function isType(tpe)
		for l1 = 1, #types do
			if types[l1][tpe] then
				return true
			end
		end
		return false
	end

	-- in the lua implementation i am being lazy and using string.sub instead of indexes
	-- for noticably better performance it would be better to store the index you are in the source string
 	local function skip(n)
		txt = txt:sub(n+1)
	end

	local function skipWhitespace()
		txt = txt:gsub("^%s+", "")
	end

	local function readWord()
		skipWhitespace()
		local o = txt:match("^[%%%a_][%a_%d]*") -- expand pattern to support more characters in variable names
		if not o then
			return false
		end
		skip(#o)
		return o
	end

	local readInline

	local function readParams() -- reads function and template parameters delimiated by commas
		local o = {}
		while true do
			local param = readInline()
			if not param then
				return o
			end
			table.insert(o, param)
			skipWhitespace()
			if txt:sub(1,1) ~= "," then
				return o
			end
			skip(1)
		end
	end

	-- reads types including their qualifiers and template parameters
	local function readType()
		local otxt = txt
		local quals = {}
		while true do -- read qualifiers
			local qual = readWord()
			if not ctx.type_qualifiers[qual] then
				if isType(qual) then -- got typename
					skipWhitespace()
					local tout = addIdx({"type", qual, quals = quals, tparams = {}})
					while txt:sub(1,1) == "<" do -- read template parameters
						skip(1)
						table.insert(tout.tparams, readParams())
						skipWhitespace()
						if txt:sub(1,1) ~= ">" then
							error("'>' expected")
						end
						skip(1)
						skipWhitespace()
					end
					return tout
				else
					txt = otxt
					return false
				end
			else
				quals[qual] = true
			end
		end
	end

	-- reads constants like 69, "potato", etc return false and restores source otherwise
	local function readConst()
		local otxt = txt
		skipWhitespace()

		-- decimal numbers
		local num = txt:match("^%-?%d+%.?%d*")
		if num then
			skip(#num)
			return addIdx({"constant", "number", tonumber(num)})
		end

		-- hexidecimal
		local num = txt:match("^%-?0x%x+%.?%x+")
		if num then
			skip(#num)
			return addIdx({"constant", "number", tonumber(num)})
		end

		-- char
		local char = txt:match("^'(.)'")
		if char then
			skip(3)
			return addIdx({"constant", "number", string.byte(char)})
		end

		-- string
		if txt:sub(1,1) == "\"" then
			skip(1)
			local str = ""
			while txt:sub(1,1) ~= "\"" do -- \ handling
				if txt == "" then
					txt = otxt
					exc.throw("parserError", "End of string expected")
				end
				local c = txt:sub(1,1)
				skip(1)
				if c == "\\" then -- escapes
					str = str .. (ctx.escapes[txt:sub(1,1)] or txt:sub(1,1))
					skip(1)
				else
					str = str .. c
				end
			end
			skip(1)
			return addIdx({"constant", "string", str})
		end

		return false
	end

	local function getOperator(ctx, opname, optype)
		for k,v in pairs(ctx.operators) do
			if v[1] == opname and v[3] == optype then
				return k
			end
		end
	end

	-- reads inline statements, does operator ordering, etc
	function readInline()
		local otxt = txt
		local expSections = {}
		local done = false 
		local last = "none"
		while not done do
			done = true
			skipWhitespace()
			local prev = expSections[#expSections]
			if txt:sub(1,1) == "(" then -- parse inline parentheses
				if last ~= "none" and last ~= "operator" then
					skip(1)
					local params = readParams()
					skipWhitespace()
					if txt:sub(1,1) ~= ")" then
						exc.throw("parserError", "\")\" Expected")
					end
					skip(1)
					done = false
					if prev[1] == "reference" then
						table.remove(expSections)
						table.insert(expSections, addIdx({"ilcall", prev[2], params}))
					else
						table.remove(expSections)
						table.insert(expSections, addIdx({"ilcall", "s_callptr", {prev}}))
					end
				else
					done = false
					skip(1)
					table.insert(expSections, readInline())
					skipWhitespace()
					if txt:sub(1,1) ~= ")" then
						exc.throw("parserError", "\")\" Expected")
					end
					skip(1)
					last = "code"
				end
			else -- parse inline variable / function call
				local varname = readWord()
				skipWhitespace()

				local op
				for k = 1, #ctx.operators do -- operators
					local v = ctx.operators[k]
					if (prev or {"operator"})[1] == "operator" or
						v[3] ~= "_x" then -- make sure unary operators dont get placed after an expression
						if varname and varname == v[1] or (not varname and txt:match("^"..pescape(v[1]))) then
							skip(#v[1])
							done = false
							op = true
							table.insert(expSections, {"operator", k})
							break
						end
					end
				end

				if not op and not varname then
					local const = readConst()
					if const then -- parse inline constants
						done = false
						table.insert(expSections, const)
						last = "const"
					end
				elseif not op and varname then -- variable name
					if isType(varname) then
						done = false
						table.insert(expSections, readType())
					else
						done = false
						table.insert(expSections, {"reference", "u_"..varname})
						last = "reference"
					end
				end
			end
		end

		if #expSections == 0 then
			txt = otxt
			return false
		end
		local o = {}
		local expq = {{expSections, o}}
		while #expq > 0 do -- resolve order of operations
			local c = expq[#expq][1]
			local co = expq[#expq][2]
			table.remove(expq)
			local maxn = 0
			local maxi = 0
			for k,v in pairs(c) do
				if v[1] == "operator" then
					if v[2] > maxn then
						maxn = v[2]
						maxi = k
					end
				end
			end
			if maxn ~= 0 then
				if ctx.operators[maxn][3] == "_x" then -- stuff like (-x)
					local r = {}
					for l1 = maxi + 1, #c do
						table.insert(r, c[l1])
					end
					table.insert(expq, r)
					for l1 = 1, #c do
						c[l1] = nil
					end
					c[1] = "ilcall"
					c[2] = ctx.operators[maxn][2]
					c[3] = {r}
				elseif ctx.operators[maxn][3] == "x_x" then -- stuff like (x + y)
					co[1] = "ilcall"
					co[2] = ctx.operators[maxn][2]
					co[3] = {{}, {}}
					local l = {}
					for l1 = 1, maxi - 1 do
						table.insert(l, c[l1])
					end
					local r = {}
					for l1 = maxi + 1, #c do
						table.insert(r, c[l1])
					end
					table.insert(expq, {l, co[3][1]})
					table.insert(expq, {r, co[3][2]})
				end
			elseif #c == 1 then -- no operators
				table_merge(co, c[1])
			else
				exc.throw("parserError", "Invalid expression")
			end
		end
		return o
	end

	local readStatement
	local readCode

	local function readFunction()
		local otxt = txt

		-- read function qualifiers
		local quals = {}
		skipWhitespace()
		local cn = true
		while cn do
			cn = false
			for k, v in pairs(ctx.func_qualifiers) do
				if k == txt:sub(1, #k) then
					quals[k] = true
					skip(#k)
					skipWhitespace()
					cn = true
					break
				end
			end
		end

		skipWhitespace()
		local rt = readType()
		
		local word = readWord()
		if word ~= "func" then
			if not next(quals) then
				txt = otxt
				return false
			end
			exc.throw("parserError", "\"func\" Expected")
		end

		-- read function name
		skipWhitespace()
		local funcname = readWord()
		if not funcname then
			exc.throw("parserError", "Function name expected")
		end

		skipWhitespace()
		if txt:sub(1,1) ~= "(" then
			exc.throw("parserError", "\"(\" Expected")
		end
		skip(1)

		-- read function args
		local argl = {}
		while true do
			local tpe = readType()
			if not tpe then
				break
			end
			local arname = readWord()
			if not arname then
				exc.throw("parserError", "Argument name expected")
			end
			table.insert(argl, {tpe, arname:sub(1, 1) == "%" and arname:sub(2) or "u_" .. arname})
			skipWhitespace()
			if txt:sub(1,1) ~= "," then
				break
			end
			skip(1)
		end

		skipWhitespace()
		if txt:sub(1,1) ~= ")" then
			exc.throw("parserError", "\")\" Expected")
		end
		skip(1)

		local typeinfo = {"type", "func", quals = quals, tparams = {argl, next(rt) and rt}}

		skipWhitespace()
		if txt:sub(1, 1) == ";" then -- decleration
			skip(1)
			return addsIdx({"push", typeinfo, funcname:sub(1, 1) == "%" and funcname:sub(2) or "u_" .. funcname})
		end

		local st = assert(readStatement())
		
		-- push is inserted later by compiler.lua
		return addIdx({"func", funcname:sub(1, 1) == "%" and funcname:sub(2) or "u_" .. funcname, quals, argl, rt, st})
	end

	-- read statements, always ends with semicolons
	function readStatement()
		local func = readFunction()
		if func then
			skipWhitespace()
			if txt:sub(1,1) ~= ";" then
				exc.throw("parserError", "\";\" Expected")
			end
			skip(1)
			return func
		end

		skipWhitespace()
		if txt:sub(1,1) == "{" then
			skip(1)
			local code = readCode()
			skipWhitespace()
			if txt:sub(1,1) ~= "}" then
				exc.throw("parserError", "\"}\" Expected")
			end
			skip(1)
			return code
		end

		local otxt = txt
		local w = readWord()
		if w == "while" then
			skipWhitespace()
			if txt:sub(1,1) ~= "(" then
				exc.throw("parserError", "\"(\" Expected")
			end
			skip(1)

			local cond = readInline()

			skipWhitespace()
			if txt:sub(1,1) ~= ")" then
				exc.throw("parserError", "\")\" Expected")
			end
			skip(1)

			local st = readStatement()
			if txt:sub(1,1) ~= ";" then
				exc.throw("parserError", "\";\" Expected")
			end

			return addIdx({"while", cond, st})

		elseif ctx.type_qualifiers[v] or isType(w) then
			txt = otxt
			local tpe = readType()
			skipWhitespace()
			local varname = readWord()
			skipWhitespace()
			if txt:sub(1,1) == ";" then -- decleration
				skip(1)
				return {"push", tpe, varname:sub(1, 1) == "%" and varname:sub(2) or "u_" .. varname}
			elseif txt:sub(1,1) == "=" then -- decleration + assignment
				skip(1)
				local il2 = readInline()
				if not il2 then
					exc.throw("parserError", "Statement expected")
				end
				if txt:sub(1,1) ~= ";" then
					exc.throw("parserError", "\";\" Expected")
				end
				skip(1)
				return {"code",
					{"push", tpe, varname:sub(1, 1) == "%" and varname:sub(2) or "u_" .. varname},
					{"assign", {"reference", varname:sub(1, 1) == "%" and varname:sub(2) or "u_" .. varname}, il2},
				}
			else
				exc.throw("parserError", "\")\" Expected")
			end
		else
			txt = otxt
		end

		local il = readInline() -- inline statements like function calls
		if il then
			skipWhitespace()
			if txt:sub(1,1) == "=" then -- assignment
				skip(1)
				local il2 = readInline()
				if not il2 then
					exc.throw("parserError", "Statement expected")
				end
				if txt:sub(1,1) ~= ";" then
					exc.throw("parserError", "\";\" Expected")
				end
				skip(1)
				return {"assign", il, il2}
			elseif txt:sub(1,1) ~= ";" then
				exc.throw("parserError", "\";\" Expected")
			end

			if il[1] == "reference" or il[1] == "constant" then
				exc.throw("parserError", "Statement with no effect")
			end

			skip(1)
			return il
		end
		return false, "No statement"
	end

	-- reads a block of code
	function readCode()
		local o = {"code"}
		while true do
			local st, err = readStatement()
			if not st then
				if #o == 1 then
					exc.throw("parserError", "Statement expected")
				end
				return o
			end
			table.insert(o, st)
		end
	end

	return exc.catch(function()
		local code = readCode()
		skipWhitespace()
		if #txt > 0 then
			exc.throw("parserError", "Incomplete statement")
		end
		return code
	end, "parserError", function(msg)
		local sidx = #otxt - #txt
		local eidx = #otxt - #txt
		while sidx ~= 0 and not otxt:sub(sidx, sidx):match("[\t\r\n]") do
			sidx = sidx - 1
		end
		while eidx ~= (#otxt + 1) and otxt:sub(eidx, eidx) ~= "\n" do
			eidx = eidx + 1
		end
		return false, msg .. "\n" .. otxt:sub(sidx + 1, eidx - 1) .. "\n" .. (" "):rep((#otxt - #txt) - sidx) .. "^"
	end)
end