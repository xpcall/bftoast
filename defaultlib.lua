toast.funcs = {
	["readline"] = function(ctx, params)
		assert(#params == 0, "Invalid number of params")
		local tmp1 = ctx.newTemp()
		return {"code",
			{"push", "string",tmp1},
			{"seek", tmp1},
			{"bf", ">,-10[>,-10]<[+10<]"},
		}
	end,
	["print"] = function(ctx,params)
		assert(#params == 1, "Invalid number of params")
		if params[1][2] == "string" then
			return {"code",
				{"seek", params[1][3]},
				{"bf", ">[,>]"},
				{"seeked", "s_right"},
			}
		else if toast.getTypeString(params[1]) == "array<int<1>>" then
			return {"code",
				{"seek", params[1][3]},
				{"bf", ">[>.>>]>"},
				{"seeked", "s_right"},
			}
		end
	end
}