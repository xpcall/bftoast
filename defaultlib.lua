toast.funcs = {
	["o_copy(ref<cell>,ref<cell>)"] = function(ctx, params)
		local tmp1 = ctx.newTemp()
		return {"code",
			{"push", ctx.requireSymbol(params[1][2]), tmp1},
			{"bf", "$t[-]$b[-]$a[$b+$t+$a-]$t[$a+$t-]", {a = params[1][2], b = params[2][2], t = tmp1}},
			{"pop", tmp1},
		}
	end,
	["o_add(ref<cell>,ref<cell>)"] = function(ctx, params)
		local tmp1 = ctx.newTemp()
		return {"code",
			{"push", ctx.requireSymbol(params[1][2]), tmp1},
			{"bf", "$o[-]$t[-]$a[$o+$t+$a-]$t[$a+$t-]$b[$o+$t+$b-]$t[$b+$t-]", {a = params[1][2], b = params[2][2], t = tmp1}},
			{"pop", tmp1},
		}
	end,
}

toast.defaultlib = [[
inline func %o_copy(ref<cell> a, ref<cell> b) {
	cell t;
	@$t[-]$b[-]$a[$b+$t+$a-]$t[$a+$t-];
};

inline func cell %o_add(ref<cell> a, ref<cell> b) {
	cell t = 0;
	cell o = 0;
	@$a[$t+$o+$a-]$t[$a+$t-];
	@$b[$t+$o+$b-]$t[$b+$t-];
	return cell(o);
};

inline func cell %o_sub(ref<cell> a, ref<cell> b) {
	cell t = 0;
	cell o = 0;
	@$a[$t+$o+$a-]$t[$a+$t-];
	@$b[$t+$o-$b-]$t[$b+$t-];
	return cell(o);
};
]]