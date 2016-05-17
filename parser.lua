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
		while not done do
			done = true
			skipWhitespace()
			local const = readConst()
			if const then
				done = false
				table.insert(expSections, const)
			elseif txt:sub(1,1) == "(" then
				done = false
				skip(1)
				table.insert(expSections, readInline())
				skipWhitespace()
				if txt:sub(1,1) ~= ")" then
					error("')' expected")
				end
				skip(1)
			else
				for k,v in pairs(ctx.operators) do
					if txt:match("^"..pescape(k)) then
						done = false
						table.insert(expSections, {"operator", k})
						break
					end
				end
			end
		end
		if #expSections == 0 then
			return false
		end
		-- order operators
		local idx = 1
		while expSections[idx] do
			local c = expSections[idx]
			local prev = expSections[idx - 1]
			local nxt = expSections[idx + 1]
			if c[1] == "operator" then
				if ctx.operators[c[2]][2] == "_x"
			end
			idx = idx + 1
		end

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