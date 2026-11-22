-- Static checks: the TOC, the package and the files agree; every file is valid Lua 5.1 (the game's) and reads
-- only the globals it means to - a name missed as code moves between files reads as a nil global otherwise.
-- Run from the repo root: luajit tests/static_test.lua (or nvim -l), or tests/run.sh.
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local check = H.check

-- ---- TOC ---------------------------------------------------------------------------------------------------
local toc = H.read(H.root .. "/" .. H.ADDON .. ".toc")
local listed = {}
for _, file in ipairs(H.tocFiles()) do
	listed[file] = true
	local f = io.open(H.root .. "/" .. file)
	check(f ~= nil, "TOC file exists: " .. file)
	if f then f:close() end
end
for _, field in ipairs({ "Interface", "Title", "Version", "SavedVariables", "IconTexture" }) do
	check(toc:match("\n## " .. field .. ": ") or toc:match("^## " .. field .. ": "), "TOC has ## " .. field)
end
check(toc:match("## Interface: 16001"), "TOC targets WoW: Forever (Interface 16001)")
check(toc:match("## Version: @project%-version@"), "TOC version is the packager's (@project-version@)")
local icon = toc:match("## IconTexture: Interface\\AddOns\\" .. H.ADDON .. "\\([^\r\n]+)")
check(icon and io.open(H.root .. "/" .. icon:gsub("\\", "/") .. ".tga") ~= nil, "TOC icon exists")

-- Every Lua file of the addon is in the TOC (one missing from it silently does nothing in the game).
local function luaFiles()
	local out = {}
	local cmd = H.WINDOWS and ('dir /b /s "' .. H.root:gsub("/", "\\") .. '\\*.lua"') or ('find "' .. H.root .. '" -name "*.lua"')
	local p = io.popen(cmd)
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):sub(#H.root + 2)
		if not rel:match("^tests/") and not rel:match("^%.") and not rel:match("^media/") then out[#out + 1] = rel end
	end
	p:close()
	table.sort(out)
	return out
end
local files = luaFiles()
check(#files > 0, "found the addon's Lua files")
for _, file in ipairs(files) do
	check(listed[file], "listed in the TOC: " .. file)
end

-- The packager (BigWigsMods/packager) matches .pkgmeta keys exactly.
local pkgmeta = H.read(H.root .. "/.pkgmeta"):gsub("\r\n", "\n")
check(pkgmeta:match("^package%-as: " .. H.ADDON .. "\n") ~= nil, ".pkgmeta: package-as " .. H.ADDON)
check(pkgmeta:find("\n  %- tests\n") ~= nil, ".pkgmeta: the tests stay out of the package")

-- ---- syntax (the game runs Lua 5.1; LuaJIT also refuses over 200 locals or 60 upvalues, as the game does) -
local chunks = {}
for _, file in ipairs(files) do
	local chunk, err = loadfile(H.root .. "/" .. file)
	check(chunk ~= nil, "valid Lua 5.1: " .. file .. (err and (" (" .. err .. ")") or ""))
	chunks[file] = chunk
end

-- ---- the globals each file reads -----------------------------------------------------------------------------
-- The game's API, Lua's library, Blizzard's frames and functions, and the addon's saved variables: anything
-- else read as a global is a mistake (a local renamed or left in another file).
local KNOWN = {}
for name in ([[
	AuctionHouseFrame Ambiguate C_AutoComplete C_InputInterfaceStyle ChatFrameUtil ChatTypeInfo ChatFrame1EditBox
	ClearOverrideBindings CreateFrame DEFAULT_CHAT_FRAME Enum EventRegistry GAMEPAD_FACE_BOTTOM GAMEPAD_FACE_LEFT
	GAMEPAD_FACE_RIGHT GAMEPAD_FACE_TOP GAMEPAD_SHOULDER_LEFT GAMEPAD_SHOULDER_RIGHT GamepadKeyboardDB GamepadMode
	GetBindingKey GetCurrentKeyBoardFocus GetTime IsKeyDown InCombatLockdown NUM_CHAT_WINDOWS SMART_NAV_INPUT_DIRECTION
	SetOverrideBinding SetOverrideBindingClick Settings SlashCmdList SmartNavigation SmartNavigation_AddJumpNavigationOverride
	GameTooltip UIParent UISpecialFrames hooksecurefunc issecretvalue issecurevariable print strtrim tinsert _G
	error getmetatable ipairs math next pairs pcall select setmetatable string table tonumber tostring type unpack
]]):gmatch("%S+") do KNOWN[name] = true end

local jitOk, jutil = pcall(require, "jit.util")
local vmOk, vmdef = pcall(require, "jit.vmdef")
local bitOk, bit = pcall(require, "bit")
if not (jitOk and vmOk and bitOk) then
	io.write("SKIP the globals check: this Lua has no jit.util / jit.vmdef / bit (LuaJIT's)\n")
else
	-- GGET / GSET: a global read or written by name (a string constant), in a function and those inside it.
	local function opName(ins)
		local op = bit.band(ins, 0xff)
		return vmdef.bcnames:sub(op * 6 + 1, op * 6 + 6):gsub("%s+$", "")
	end
	local function globals(fn, reads, writes)
		local info = jutil.funcinfo(fn)
		for pc = 1, info.bytecodes - 1 do
			local ins = jutil.funcbc(fn, pc)
			local op = opName(ins)
			if op == "GGET" or op == "GSET" then
				local name = jutil.funck(fn, -bit.rshift(ins, 16) - 1)
				local into = op == "GGET" and reads or writes
				into[name] = into[name] or info.currentline or true
			end
		end
		for n = -1, -1000000, -1 do
			local k = jutil.funck(fn, n)
			if k == nil then break end
			if type(k) == "proto" then globals(k, reads, writes) end
		end
	end
	for _, file in ipairs(files) do
		local reads, writes = {}, {}
		if chunks[file] then globals(chunks[file], reads, writes) end
		local unknown = {}
		for name in pairs(reads) do
			if not KNOWN[name] and not writes[name] then unknown[#unknown + 1] = name end
		end
		table.sort(unknown)
		check(#unknown == 0, "reads only known globals: " .. file .. (#unknown > 0 and (" (" .. table.concat(unknown, ", ") .. ")") or ""))
	end
end

H.finish()
