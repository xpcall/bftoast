-- This defines all the default types implementations
toast.objects = {
	["cell"] = {
		["init"] = function(ctx, meta, templ)
			meta.static_size = 1
			return {"code",
				{"seek", meta[1]},
				{"bf", "[-]"},
			}
		end,
		["movemulti"] = function(ctx, meta, meta2s)
			local code = {"code"}
			for k,v in pairs(meta2s) do
				table.insert(code, {"seek", v[1]})
				table.insert(code, {"bf", "[-]"})
			end
			table.insert(code, {"seek", meta[1]})
			table.insert(code, {"bf", "[-"})
			for k,v in pairs(meta2s) do
				table.insert(code, {"seek", v[1]})
				table.insert(code, {"bf", "+"})
			end
			table.insert(code, {"seek", meta[1]})
			table.insert(code, {"bf", "]"})
			return code
		end,
		["move"] = function(ctx, meta, meta2)
			return toast.objects.int.movemulti(meta,{meta2})
		end,
		["copymulti"] = function(ctx, meta, meta2s)
			local tmp1 = ctx.newTemp()
			return {"code",
				{"push", "int", tmp1},
				toast.objects.int.move(ctx, meta, {tmp1,}),
				toast.objects.int.movemulti(ctx, {tmp1}, meta2s),
			}
		end,
		["copy"] = function(ctx, meta, meta2)
			return toast.objects.int.copymulti(meta, {meta2s})
		end,
	},

	["int"] = {
		["init"] = function(ctx, meta, templ)
			meta.static_size = 1 -- when bigger ints are supported this will be set higher
			return {"code",
				{"seek", meta[1]},
				{"bf", "[-]>[-]>[-]>[-]<<<"},
				{"seeked", "right"},
			}
		end,

		["move"] = function(ctx, meta, meta2)
			return toast.objects.int.movemulti(meta,{meta2})
		end,
		["copymulti"] = function(ctx, meta, meta2s)
			local tmp1 = ctx.newTemp()
			return {"code",
				{"push", "int", tmp1},
				toast.objects.int.move(ctx, meta, {tmp1,}),
				toast.objects.int.movemulti(ctx, {tmp1}, meta2s),
			}
		end,
		["copy"] = function(ctx, meta, meta2)
			return toast.objects.int.copymulti(meta, {meta2s})
		end,
	},

	-- simple string, text is surrounded in 0s so it can be seeked over
	["string"] = {
		["init"] = function(ctx, meta, templ)
			meta.dynamic = true
			return {"code",
				{"seek", name},
				{"bf", "[-]>[-]<"}
			}
		end,
		["seekleft"] = function(meta)
			return "<[<]"
		end,
		["seekright"] = function(meta)
			return ">[>]>"
		end,
	},

	-- internal structure
	-- 0 item[index, data, temp0, temp1] ... 0
	["array"] = {
		["init"] = function(ctx, meta, templ)
			meta.dynamic = true
			return {"code",
				{"bf", "[-]>[-]<"}
			}
		end,
		["seekleft"] = function(ctx,meta)
			return "<<[<<<]"
		end,
		["seekright"] = function(ctx,meta)
			return ">[>>>]>"
		end,
		["index"] = function(ctx, meta, meta2, meta3) -- this, index, output
			return {"code", clobbers = {meta2},
				{"seek", meta[2]},
			}
		end,
		["newindex"] = function(ctx, meta, meta2)
			-- TODO
		end,
	}
}