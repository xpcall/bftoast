toast.defaultctx = {
	operators = {
		{"^","o_pow", "x_x"},
		{"not","o_not", "_x"},
		{"!","o_not", "_x"}.
		{"-","o_neg", "_x"],
		{"~","o_xor", "_x"},
		{"*","o_mul", "x_x"},
		{"/","o_div", "x_x"},
		{"+","o_add", "x_x"},
		{"-","o_sub", "x_x"},
		{"..","o_cat", "x_x"},
		{"<","o_lt", "x_x"},
		{">","o_gt", "x_x"},
		{"<=","o_leq", "x_x"},
		{">=","o_geq", "x_x"},
		{"!=","o_neq", "x_x"},
		{"~=","o_neq", "x_x"},
		{"==","o_eq", "x_x"},
		{"and","o_and", "x_x"},
		{"&&","o_and", "x_x"},
		{"or","o_or", "x_x"},
		{"||","o_or", "x_x"}
	},
	type_qualifiers = {
		["const"] = true,
		["final"] = true,
		["constexpr"] = true,
	},
	escapes = {
		a = "\a",
		b = "\b",
		f = "\f",
		n = "\n",
		r = "\r",
		t = "\t",
		v = "\v",
	}
}

function toast.parse(ctx, txt)
	local otxt = txt
	local function skip(n)
		txt = txt:sub(n+1)
	end

	local function skipWhitespace()
		txt = txt:gsub("^%s+", "")
	end

	local function readWord()
		skipWhitespace()
		local o = txt:match("^[%a_][%a_%d]*")
		skip(#o)
		return o
	end

	local readInline

	local readParams()
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

	local function readType()
		local otxt = txt
		local quals = {}
		while true do -- read qualifiers
			local qual = readWord()
			if not ctx.type_qualifiers[qual] then
				if isType(qual) then -- got typename
					skipWhitespace()
					local tout = {"type", qual, qualifiers = quals}
					while txt:sub(1,1) == "<" do -- read template parameters
						skip(1)
						table.insert(tparams, readParams())
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
				table.insert(quals, qual)
			end
		end
	end

	local function readConst()
		local otxt = txt
		skipWhitespace()

		-- decimal numbers
		local num = txt:match("^%-?%d+%.?%d+")
		if num then
			skip(#num)
			return {"constant", "number", tonumber(num)}
		end

		-- hexidecimal
		local num = txt:match("^%-?0x%x+%.?%x+")
		if num then
			skip(#num)
			return {"constant", "number", tonumber(num)}
		end

		-- char
		local char = txt:match("^'(.)'")
		if char then
			skip(3)
			return {"constant", "number", string.byte(char)}
		end

		-- string
		if txt:sub(1,1) == "\"" then
			skip(1)
			local str = ""
			while txt:sub(1,1) ~= "\"" do
				if txt == "" then
					txt = otxt
					error("No end of string")
				end
				local c = txt:sub(1,1)
				skip(1)
				if txt:sub(1,1) == "\\" then -- escapes
					skip(1)
					str = str .. (ctx.escapes[txt:sub(1,1)] or txt:sub(1,1))
					skip(1)
				else
					str = str .. txt:sub(1,1)
					skip(1)
				end
			end
		end

		return false
	end

	local function readInline()
		local expSections = {}
		local done = false
		local last = "none"
		while not done do
			done = true
			skipWhitespace()
			if last == "none" or last == "operator" then
				local const = readConst()
				if const then -- parse inline constants
					done = false
					table.insert(expSections, const)
					last = "const"
				elseif txt:sub(1,1) == "(" then -- parse inline parentheses
					done = false
					skip(1)
					table.insert(expSections, readInline())
					skipWhitespace()
					if txt:sub(1,1) ~= ")" then
						error("')' expected")
					end
					skip(1)
					last = "code"
				else -- parse inline variable / function call
					local varname = readWord()
					skipWhitespace()
					if txt:sub(1,1) == "(" do -- inline function call
						local fcall = {}
						while txt:sub(1,1) == "(" do -- handle multiple function calls, ex. "foo(...)(...)"
							skip(1)
							readParams()
						end
					end
				end
			else
				for k,v in pairs(ctx.operators) do
					if txt:match("^"..pescape(v[1])) then
						done = false
						table.insert(expSections, {"operator", v[1]})
						break
					end
				end
			end
		end
		if #expSections == 0 then
			return false
		end
		-- order and seperate operators
		while #expSections > 1 do
			-- this logic depends on the assumption that operators in expSections are always seperating values
			if expSections[1][1] == "operator" then -- preceeding unary operator
				local po
				for k,v in pairs(ctx.operators) do
					if v[1] == expSections[1][2] and v[3] == "_x" then
						po = k
						break
					end
				end
				if not po then
					error("Operator '" .. expSections[1][2] .. "' not unary")
				end
			else
				if #expSections == 2 then -- 
			end
		end
		return 
	end

	local function readStatement()
		
	end

	local function readCode()
		local o = {"code"}
		while true do
			local st = parseStatement()
			if not st then

				return o
			end
			table.insert(o, st)
		end
	end
end