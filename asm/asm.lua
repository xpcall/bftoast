local function compile(txt)
	local idx = 1
	local out = ""
	local erridx

	local function getLine(nidx)
		nidx = nidx or erridx or idx
		local line = 1
		for m in txt:sub(1, nidx):gmatch("\n") do
			line = line + 1
		end
		return line
	end

	local err, tb = xpcall(function()
		local function readWord()
			local o = txt:sub(idx):match("^[%a_][%a_%d]*")
			idx = idx + #o
			return o ~= "" and o
		end

		local function readNumber()
			local o =
				txt:sub(idx):match("^0x%x+") or
				txt:sub(idx):match("^%d+")
			idx = idx + #o
			return o ~= "" and tonumber(o)
		end

		local function readLine()
			local o = txt:sub(idx):match("^[^\n]*")
			idx = idx + #o
			if txt:sub(idx, idx) == "\n" then
				idx = idx + 1
			end
			return o
		end

		local function skipWhitespace()
			while txt:sub(idx, idx):match("^%s$") do
				idx = idx + 1
			end
		end

		local sections = {}
		local csection

		skipWhitespace()
		while idx <= #txt do
			local oidx = idx
			local l = readLine():gsub("//.*", ""):gsub("%s+$", ""):gsub("^%s+", "")
			if l ~= "" then
				local command, params = l:match("^(%S+)%s*(.*)$")

				local pparams = {}
				for m in params:gmatch("%S+") do
					table.insert(pparams, m)
				end

				if command:match("^@") then
					csection = command:sub(2)
					sections[command:sub(2)] = {params = pparams, code = {}};
				else
					table.insert(sections[csection].code, {
						command = command,
						params = pparams,
						idx = oidx
					})
				end

				skipWhitespace()
			end
		end

		local mainstack = {name = "^S", stack = {}, level = 1, vars = {}}
		mainstack.spacevar = {name = "^space", pos = 1, parent = mainstack}
		mainstack.vars["^S"] = mainstack
		local cstack = mainstack
		local cvar = mainstack
		local lstack

		local function getVar(name, pvar)
			local scopes = {}
			for m in name:gmatch("[^:]+") do
				table.insert(scopes, m)
			end

			local var
			while scopes[1] do
				var = scopes[1]
				local ovar = var
				table.remove(scopes, 1)

				if var == "^here" then
					pvar = pvar or cvar
					if pvar.stack then
						var = pvar.stack[#pvar.stack] or pvar.spacevar
					else
						var = pvar
					end
				elseif var == "^stack" then
					pvar = pvar or cvar
					if not pvar.stack then
						pvar = pvar.parent
					end
					var = pvar
				elseif var == "^top" then
					pvar = pvar or cstack
					if not pvar.stack then
						pvar = pvar.parent
					end
					var = pvar.stack[#pvar.stack]
				elseif var == "^up" then
					pvar = pvar or cvar
					if pvar.pos + 1 > #pvar.parent.stack then
						var = pvar.parent.spacevar
					else
						var = pvar.parent.stack[pvar.pos + 1]
					end
				elseif var == "^down" then
					pvar = pvar or cvar
					if pvar.pos <= 1 then
						var = pvar.parent
					else
						var = pvar.parent.stack[pvar.pos - 1]
					end
				elseif var == "^bottom" then
					pvar = pvar or cstack
					if not pvar.stack then
						pvar = pvar.parent
					end
					var = pvar.stack[1] or pvar
				elseif var == "^space" and pvar then
					pvar = pvar or cstack
					if not pvar.stack then
						pvar = pvar.parent
					end
					var = cvar.parent.spacevar
				elseif var == "^parent" and pvar then
					var = pvar.parent
				elseif var == "^scope" then
					var = cstack
				elseif var == "^prev" then
					var = lstack
				else
					pvar = pvar or cstack
					var = pvar.vars[var]
					if not var then
						return false, "No such var \"" .. ovar .. "\" in \"" .. name .. "\"" 
					end
				end

				pvar = var
			end

			return var
		end

		local function multiplySeek(txt, n)
			n = n or cvar.level or cvar.parent.level
			return txt:gsub("[<>]", function(t)
				return t:rep(n)
			end)
		end

		local function seek(var)
			if cvar.stack then
				cvar = cvar.stack[1] or cvar.spacevar
			end

			if cvar == var then
				return
			end

			if var.stack then
				seek(var.with)
				out = out .. multiplySeek(">", cvar.parent.level * (var.splitpos - 1))
				cvar = cstack
			end

			local toparents = {}
			local c = var
			while c.parent do
				toparents[c.parent] = true
				c = c.parent
			end

			local fromparents = {}
			local c = cvar
			while c.parent do
				fromparents[c.parent] = true
				c = c.parent
			end

			if fromparents[var.parent] then -- target is below us
				while cvar.parent ~= var.parent do
					while cvar.pos ~= 1 do
						cvar = getVar("^down")
						out = out .. multiplySeek(cvar.lseek, cvar.parent.level)
					end

					out = out .. multiplySeek("<", cvar.parent.parent.level * (cvar.parent.splitpos - 1))
					cvar = cvar.parent.with
				end
			elseif toparents[cvar.parent] then -- target is above us
				while cvar.parent ~= var.parent do
					while not cvar.split do
						out = out .. multiplySeek(cvar.rseek, cvar.parent.level)
						cvar = getVar("^up")
					end

					local tstack
					for i = 1, #cvar.split do
						if toparents[cvar.split[i]] then
							tstack = i
							break
						end
					end

					assert(tstack, "Could not find parent in " .. cvar.parent.name .. ":" .. cvar.pos .." for " .. var.name)

					out = out .. multiplySeek(">", cvar.parent.level * (tstack - 1))
					cvar = cvar.split[tstack].stack[1]
				end
			elseif assert(cvar.parent, "no cvar parent") ~= assert(var.parent, "no cvar parent") then -- target is on a different branch
				local c = cvar
				while c.parent do
					if toparents[c.parent] then -- find common branch
						break
					end
					c = c.parent
				end

				seek(c.with) -- seek down to common branch
				seek(var) -- seek up to var
			end

			if cvar ~= var and cvar.parent == var.parent then
				if cvar.pos < var.pos then
					while cvar ~= var do
						out = out .. multiplySeek(cvar.rseek, cvar.parent.level)
						cvar = getVar("^up")
					end
				else
					while cvar ~= var do
						cvar = getVar("^down")
						assert(cvar.lseek, cvar.parent.name .. ":" .. cvar.pos .. " has no lseek")
						out = out .. multiplySeek(cvar.lseek, cvar.parent.level)
					end
				end
			end
		end

		local inclstack = {}
		local incl
		function incl(section, inclparams)
			table.insert(inclstack, {section, erridx})

			local code = sections[section].code

			local function applyParams(txt)
				for i = 1, #sections[section].params do
					txt = txt:gsub("~" .. sections[section].params[i], function()
						return inclparams[i]
					end)
				end
				return txt
			end

			for i = 1, #code do
				local oline = code[i]
				local line = {params = {}, idx = oline.idx}

				line.command = applyParams(oline.command)
				for i = 1, #oline.params do
					line.params[i] = applyParams(oline.params[i])
				end

				erridx = line.idx
				if line.command == "BF" then
					local bf = applyParams(table.concat(line.params, " ")
						:gsub("`(.-)`", function(c)
							local f, err = loadstring("return " .. c)
							if not f then
								f, err = assert(loadstring(c))
							end
							return f()
						end)
						:gsub("(%b{})(%d+)", function(c, rep)
							return c:sub(2, -2):rep(tonumber(rep))
						end)
						:gsub("([%[%]<>%.,%+%-])(%d+)", function(c, rep)
							return c:rep(tonumber(rep))
						end)
					)
					local bidx = 1
					while bidx <= #bf do
						local buf = bf:sub(bidx):match("^[^$]*")
						bidx = bidx + #buf
						out = out .. multiplySeek(buf, cvar.level or cvar.parent.level)

						if bf:sub(bidx, bidx) == "$" then
							local cmd = bf:sub(bidx):match("^$([^%s%[%]<>%.,%+%-]+)")
							bidx = bidx + #cmd + 1
							if cmd:sub(1, 1) == "=" then
								cvar = assert(getVar(cmd:sub(2)))
							else
								seek(assert(getVar(cmd)))
							end
						end
					end
				elseif line.command == "X" then
					incl(line.params[1], {unpack(line.params, 2)})
				elseif line.command == "PUSHSTACK" then
					local mstack = getVar(line.params[1])

					local s = mstack.stack[#mstack.stack]
					if s and (not s.rseek or s.split) then
						error("Cannot push ontop of stack")
					end

					local val = {split = {}, parent = mstack, pos = #mstack.stack + 1}
					for i = 2, #line.params do
						if line.params[1]:match(":") then
							error("Dont use scope in stack names")
						end

						if getVar(line.params[i], mstack) then
							error("Name already exists")
						end

						local stack = {
							name = line.params[i],
							stack = {},
							parent = mstack,
							with = val,
							splitpos = i - 1,
							level = mstack.level * (#line.params - 1),
							vars = setmetatable({}, {__index = mstack.vars}),
						}

						stack.spacevar = {name = "^space", pos = 1, parent = stack}

						mstack.vars[stack.name] = stack
						table.insert(val.split, stack)
					end

					mstack.spacevar.pos = mstack.spacevar.pos + 1
					table.insert(mstack.stack, val)
				elseif line.command == "PUSH" then
					local name, lseek, rseek = line.params[1], line.params[2], line.params[3]

					local rname = name:match("([^:]+)$")
					local stack = name == rname and cstack or assert(getVar(name:sub(1, -2 - #rname)))

					local s = stack.stack[#stack.stack]
					if s and (not s.rseek or s.split) then
						error("Cannot push ontop of stack")
					end

					if getVar(name) then
						error("Name already exists")
					end

					local var = {name = rname, lseek = lseek, rseek = rseek, parent = stack, pos = #stack.stack + 1}
					table.insert(stack.stack, var)
					stack.vars[rname] = var

					stack.spacevar.pos = var.pos + 1
				elseif line.command == "SCOPE" then
					lstack = cstack
					cstack = assert(getVar(line.params[1]))
					if not cstack.stack then
						error("Not a stack")
					end
				elseif line.command == "POP" then
					for i = 1, #line.params do
						local c = line.params[i]

						local var = assert(getVar(c))

						if not var.stack and var.parent.stack[#var.parent.stack] ~= var then
							error("Not top of stack")
						elseif var.parent.stack[#var.parent.stack] ~= var.with then
							error("Not top of stack")
						end

						if var.stack then
							seek(var.with)
							cvar = #var.parent.stack == 1 and var.parent or var.parent.spacevar
							table.remove(var.parent.stack)
						else
							if cvar == var then
								cvar = #var.parent.stack == 1 and var.parent or var.parent.spacevar
							elseif cvar == var.parent.spacevar then
								seek("^down")
							end

							table.remove(var.parent.stack)
							var.parent.vars[var.name] = nil
							var.parent.spacevar.pos = var.parent.spacevar.pos - 1
						end
					end
				elseif line.command == "DEBUG" then
					print("[DEBUG] @ line " .. getLine())
					local cname = ""
					local var = cvar
					while var do
						cname =  ":" .. tostring(var.name) .. cname
						var = var.parent
					end
					print("> cvar: " .. cname:sub(2))
					print("> backtrace:")
					for i = #inclstack, 1, -1 do
						print(">     @" .. inclstack[i][1] .. " called from " .. (inclstack[i][2] and "line " .. getLine(inclstack[i][2]) or "Lua"))
					end
				else
					error("No such command \"" .. line.command .. "\"")
				end
			end
			table.remove(inclstack)
		end

		incl("_main")
	end, debug.traceback)

	if not err then
		print(tb)
		if erridx then
			idx = erridx
		end

		print("line " .. getLine(idx))
		return false
	end

	return out
end

--[[

Toast ASM

Commands:
	BF ...                           | Executes brainfuck
	X <name>[ ...]                   | Includes section
	PUSHSTACK <from> <name>[ ...]    | Initializes new stacks ontop of the specified stack
	SCOPE <name>                     | Sets current scope to stack
	PUSH <varname>[ <lseek> <rseek>] | Pushes varname to stack
	POP <name>[ ...]                 | Pops varnames (left to right)
	DEBUG                            | Prints debug information about the state at compile time

Stacks:
	Each stack has its own variable scope, it inherits variable names from its parent
	Variables are used to keep track of where things are and they are pushed ontop of eachother statically at compile-time
	These variables are not defined by type but rather how the compiler can seek over them, for example:
		PUSH foo < > // this defines foo as a single cell
		PUSH bar << >> // this defines foo as 2 cells
		PUSH walrus <<[<] >[>]> // this defines walrus as a string that is \0 prefixed and teminated

	Unseekables are variables which do not have lseek and rseek, therefore they must always be on the top of a stack
	There is currently no safety mechanism that prevents you from unintentionally expanding a dynamically sized variable that is not on the top of the stack

	A stack can have a number of children stacks using the PUSHSTACK command, these stacks act as a single unseekable variable
	The parent cannot add or remove stacks unless the old ones are popped, popping one of the stacks defined there will destruct all of them
		PUSHSTACK ^stack foo1 foo2 foo3
		PUSH foo1:bar < >
		POP foo1

	Child stacks act just like normal stacks but have output code overhead from multiplexing

	When seeking the compiler will automatically insert the code that seeks over variables and even traverse multiple children and parent stacks of different levels

Sections:
	@section_name [params ...]
		command
		...

	Parameters are inlined (gsubbed in) using "~", for example:
	@foo x
		BF $~x+
	@bar
		PUSH potato
		X foo potato

	@_main is the section that gets compiled into code

Special:
	^S      | Main stack
	^here   | Current value
	^stack  | Gets variable's stack
	^top    | Gets variable at the top of the stack
	^up     | Gets variable ontop of it
	^down   | Gets variable below it
	^bottom | Gets variable at the bottom
	^space  | Uninitialized space after ^top
	^parent | Parent stack
	^scope  | Current scope
	^prev   | Stack before the previous SCOPE

Brainfuck:
	The level aka <> multiplier is automatically applied depending on where you are seeked to

	$varname will seek to a varname
	$=varname will indicate to that compiler that we are currently pointing to varname
	<command><number> will repeat a single command n times
	{<code>}<number> will repeat code n times
	`<lua>` will execute lua code, the returned string is inserted into brainfuck code

]]

--[[
TESTING STRINGS AND MULTIPLE STACKS
@_main
	PUSH temp0 < >
	PUSH temp1 < >
	PUSHSTACK ^S foo1 foo2 foo3 foo4 foo5
	PUSHSTACK foo3 bar1 bar2 bar3
	X String.push foo3:bar2:myString
	BF $temp0[-]+72
	X String.append foo3:bar2:myString temp0
	BF $temp0[-]+105
	X String.append foo3:bar2:myString temp0
	BF $temp0[-]+79
	BF $temp1[-]+1
	X String.set foo3:bar2:myString temp1 temp0
	X String.print foo3:bar2:myString
	BF $temp0[-]+2
	X String.get foo3:bar2:myString temp0
	BF $temp0.
]]

print(compile([==============================[
@String.push str
	PUSH ~str <<<<<<[<<<] >>>[>>>]>>>
	BF $~str[-]>[-]>[-]>[-]>[-]>[-]>$=^up
@String.get str i
	BF $~i[$~str>+<$~i-] // str[0].tmp0 = i
	BF $~str>[           // while tmp0
	BF     -             // tmp0--
	BF     [->>>+<<<]    // next tmp0 = tmp0
	BF     >>>           // move to next tmp0
	BF ]                 // we are at the tmp0 of the selected char
	BF <[->+>+<<]        // tmp1,tmp0 = char
	BF >[-<+>]           // char = tmp0
	BF <[                // while char
	BF     >>            // move to tmp1
	BF     [-<<<+>>>]    // prev tmp1 = tmp1
	BF     <<<<<         // move to prev char
	BF ]>>               // we are at str[0].tmp1
	BF [-<<              // while tmp1 tmp--
	BF     $~i+$~str     // i++
	BF >>]<<             // move to str[0].char
@String.length str x
	BF $~str>>>[                  // while char
	BF     >+                     // tmp0++
	BF     [->>>+<<<]             // next tmp0 = tmp0
	BF     >>                     // move to next char
	BF ]>                         // we are at the last tmp0
	BF [->>$=^up$~x+$str:^up<<]>> // x = tmp0
@String.append str c
	BF $~str:^up                        // seek to after end of string
	BF <<<+>>>[-]>[-]>[-]>              // initialize new char to 1
	BF $~c-[-$~str:^up<<<<<<+>>>>>>$~c] // add x - 1 to char
@String.set str i x
	BF $~i[$~str>+<$~i-]   // str[0].tmp0 = i
	BF $~x[$~str>>+<<$~x-] // str[0].tmp1 = i
	BF $~str>[             // while tmp0
	BF     -               // tmp0--
	BF     [->>>+<<<]      // next tmp0 = tmp0
	BF     >[->>>+<<<]     // next tmp1 = tmp1
	BF     >>              // move to next tmp0
	BF ]                   // we are at the tmp0 of the selected char
	BF <[-]>>[-<<+>>]      // char = tmp1
	BF >[>>>]>>>$=^up      // seek to after end of string
@String.print str
	BF $~str>>>[.>>>]>>>$=~str:^up
@String.println str
	BF $~str>>>[.>>>]>>+13.-3.[-]>$=~str:^up
@String.readLine str
	X String.push ~str
	BF $~str >>>
	BF ,-13[
	BF     >[-]>[-]>
	BF     ,-13
	BF ]
	BF >,[-]>[-]<<
	BF <<<[+13<<<]
@String.equal str1 str2 x s
	BF $x[-]

	PUSH ~s:temp0 < >
	PUSH ~s:temp1 < >
	PUSH ~s:temp2 < >
	PUSH ~s:temp3 < >

	X String.length ~str1 ~s:temp0
	X String.length ~str2 ~s:temp1
	X copy ~s:temp1 ~s:temp0 ~s:temp3 // s:temp2 = s:temp0

	BF $~s:temp2[-$~s:temp1-$~s:temp2]
	X not temp1 temp2

	BF $temp1[ // if lengths are equal
		BF $~x[-]+ // x = 1
		BF $~s:temp0[ // while s:temp0
			X copy2 ~s:temp0 ~s:temp1 ~s:temp2 ~s:temp3 // s:temp1,s:temp2 = s:temp0
			BF $~s:temp0-
			X String.get ~str1 ~s:temp1
			X String.get ~str2 ~s:temp2
			BF $~s:temp2[-$~s:temp1-$~s:temp2] // s:temp1 = s:temp1 - s:temp2
			BF $~s:temp1[ // if s:temp1
				BF $~x[-] // x = 0
				BF $~s:temp0[-] // temp0 = 0
			BF $~s:temp1[-]]
		BF $~s:temp0]
	BF $temp1[-]]

	POP ~s:temp3 ~s:temp2 ~s:temp1 ~s:temp0
@lazyPrint tmp txt
	BF $~tmp`return ("~txt"):gsub(".",function(c) return "[-]" .. ("+"):rep(c:byte()) .. "." end)`
@lazyString str txt
	X String.push ~str
	BF $~str[-]>[-]>[-]>`return ("~txt"):gsub(".",function(c) return "[-]" .. ("+"):rep(c:byte()) .. ".>[-]>[-]>" end)`[-]>[-]>[-]>$=~str:^up
@copy from to temp
	BF $~temp[-]$~to[-]$~from[-$~to+$~temp+$~from]$~temp[-$~from+$~temp]
@copy2 from to1 to2 temp
	BF $~temp[-]$~to1[-]$~to2[-]$~from[-$~to1+$~to2+$~temp+$~from]$~temp[-$~from+$~temp]
@not x temp
	BF $~temp[-]+$~x[$~temp-$~x[-]]$~temp[-$~x+$~temp]
@irc_readParam to
	BF $temp1[-]+[ // while temp1 do
		X copy temp0 temp2 temp3 // temp2 = temp0
		BF $temp0+#temp0
		X String.get s0:rawLine temp2 // temp2 = s0:rawLine[temp2]
		X copy temp2 temp3 temp4 // temp3 = temp2
		BF $temp4[-]+$temp3 #-32[$temp4- // if temp3 != 32
			BF #append
			X String.append ~to temp2 // append temp2 to our string
		BF $temp3[-]]$temp4[ // else
			BF $temp1-#break // break
		BF $temp4[-]]
	BF $temp1]
@_main
	
]==============================]))

--[====[

	PUSH temp0 < >
	X lazyPrint temp0 NICK\32f^vk\r\n
	X lazyPrint temp0 USER\32brainf^vk\32~\32~\32:Brainfuck\32IRC\32bot\r\n

	PUSH temp1 < >
	PUSH temp2 < >
	PUSH temp3 < >
	PUSH temp4 < >
	PUSH continue < >
	PUSHSTACK ^S s0 s1
	BF $continue[-]+[
		X String.readLine s0:rawLine
		BF $temp0[-]+32
		BF $temp0[-]

		// temp0 is our current index in s0:rawLine
		BF $temp0[-]+2

		X String.push s0:user // ex. ping!~PixelToast@me.pxtst.com
		X irc_readParam s0:user
		X String.push s0:command // ex. PRIVMSG
		X irc_readParam s0:command

		// parse commands
		X String.println s0:user
		X String.println s0:command

		BF $temp1[-]+1
		X String.get s0:command
		BF $temp1-80
		X not temp1 temp2


		BF $temp1[-]]

	BF $continue]
]====]
