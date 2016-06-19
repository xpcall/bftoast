-- This defines all the default functions
toast.funcs = {
	["o_add"] = function(ctx, params, rv)
		return {"code",
			clobbers = {params[1], params[2]}, -- compiler will automatically store a temp variable and refactor if needed
			{"seek", params[1]},
			{"bf", "[-"},
			{"seek", rv},
			{"bf", "+"},
			{"seek", params[1]},
			{"bf", "]"},
			{"use", params[1]}, -- prevent the compiler from popping inside the loop
			{"seek", params[2]},
			{"bf", "[-"},
			{"seek", rv},
			{"bf", "+"},
			{"seek", params[2]},
			{"bf", "]"},
			{"use", params[2]},
		}
	end,
	["o_copy"] = function(ctx, params, rv)
		
	end,
}