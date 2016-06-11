toast = {}

dofile("objects.lua")
dofile("defaultlib.lua")
dofile("parser.lua")
dofile("compiler.lua")
dofile("debug.lua")

local potato = assert(toast.parse(toast.defaultctx, [[
int foo;
func potato() {
	foo = foo + 1 ^ 69;
};
]]))
print(cserialize(potato))
