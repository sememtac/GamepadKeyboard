-- Test harness: checks, the addon's files in TOC order, and running a suite.
local H = {}

local WINDOWS = package.config:sub(1, 1) == "\\"
local here = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local root = here:match("^(.-)/?tests/lib/harness%.lua$") or ""
if not root:match("^/") and not root:match("^%a:/") then -- relative: make it absolute
	local p = io.popen(WINDOWS and "cd" or "pwd")
	local cwd = p:read("*l"):gsub("\\", "/")
	p:close()
	root = (root == "" or root == ".") and cwd or (cwd .. "/" .. root:gsub("^%./", ""))
end
H.root = root
H.WINDOWS = WINDOWS
H.libDir = H.root .. "/tests/lib"
H.ADDON = "GamepadKeyboard"

local failures, passes = 0, 0
local quiet = os.getenv("GC_TESTS_QUIET") == "1"

function H.check(cond, msg)
	if cond then
		passes = passes + 1
		if not quiet then io.write("PASS ", msg, "\n") end
	else
		failures = failures + 1
		io.write("FAIL ", msg, "\n")
	end
	return cond
end

function H.finish()
	if H.addonLoaded then
		local leaks = H.unexpectedGlobals()
		H.check(#leaks == 0, "the addon created no stray globals (" .. table.concat(leaks, ", ") .. ")")
	end
	io.write(failures == 0 and ("ALL PASSED (" .. passes .. ")\n") or (failures .. " FAILURE(S), " .. passes .. " passed\n"))
	os.exit(failures == 0 and 0 or 1)
end

function H.read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- The addon's Lua files, in the order the TOC loads them.
function H.tocFiles()
	local files = {}
	for line in H.read(H.root .. "/" .. H.ADDON .. ".toc"):gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and not line:match("^#") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
end

-- Globals the addon may create, by name: its saved variables, named frames and slash commands. (A name, not a
-- prefix: once the addon is several files, any of them could leak a GamepadKeyboardSomething unseen.)
local ALLOWED_GLOBALS = {
	GamepadKeyboardDB = true, SLASH_GAMEPADKEYBOARD1 = true, SLASH_GAMEPADKEYBOARD2 = true,
	GamepadKeyboardFrame = true, GamepadKeyboardAButton = true, GamepadKeyboardDelKey = true,
	GamepadKeyboardSpaceKey = true, GamepadKeyboardCursorLeft = true, GamepadKeyboardCursorRight = true,
}
H.addonGlobals = {} -- name -> file, for every new global the addon's code created

-- Whether a chunk's source (debug.getinfo's `source`) is one of the addon's files: anywhere under the repo,
-- not in tests/ (slashes either way, "@" or not).
function H.isAddonSource(source)
	source = tostring(source or ""):gsub("^@", ""):gsub("\\", "/")
	return source:sub(1, #H.root) == H.root and not source:find("/tests/", #H.root, true)
end

-- The source of the code that called the function asking (`level` as debug.getinfo's, from the asker's
-- caller), past C functions in between - pcall(box.SetText, box, s) is still the addon's call.
function H.callerSource(level)
	level = level + 1
	while true do
		local info = debug.getinfo(level, "Sl")
		if not info then return nil end
		if info.source ~= "=[C]" then return info.source, info.currentline end
		level = level + 1
	end
end

-- Whether any of the calls under way (from the asker's caller up) is the addon's code: a call made from a
-- hook the addon put on a function (hooksecurefunc) is the addon's, though the hook's wrapper calls it.
function H.addonInStack(level)
	level = level + 1
	while true do
		local info = debug.getinfo(level, "S")
		if not info then return false end
		if H.isAddonSource(info.source) then return true end
		level = level + 1
	end
end

-- A short name for an addon file ("Keyboard/Chat.lua"), for messages.
function H.shortName(source)
	return (tostring(source or ""):gsub("^@", ""):gsub("\\", "/"):sub(#H.root + 2))
end

-- Records new globals made by the addon's files (not by the test or the mocks).
local tracking = false
local function trackGlobals()
	if tracking then return end
	tracking = true
	local root = H.root
	setmetatable(_G, { __newindex = function(t, k, v)
		local info = debug.getinfo(2, "S")
		if info and H.isAddonSource(info.source) then
			H.addonGlobals[k] = H.shortName(info.source)
		end
		rawset(t, k, v)
	end })
end

function H.unexpectedGlobals()
	local found = {}
	for name, file in pairs(H.addonGlobals) do
		if not ALLOWED_GLOBALS[name] then found[#found + 1] = tostring(name) .. " (" .. file .. ")" end
	end
	table.sort(found)
	return found
end

-- Runs the TOC's files (those `filter` accepts) with the addon's private table, as the game does.
function H.loadAddon(ns, filter)
	trackGlobals()
	H.addonLoaded = true
	local loaded = {}
	for _, file in ipairs(H.tocFiles()) do
		if file:match("%.lua$") and (not filter or filter(file)) then
			local chunk = assert(loadfile(H.root .. "/" .. file))
			chunk(H.ADDON, ns)
			loaded[#loaded + 1] = file
		end
	end
	return loaded
end

return H
