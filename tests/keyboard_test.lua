-- Gamepad Keyboard tests. Run from the repo root: luajit tests/keyboard_test.lua (or nvim -l).
-- The focus manager and the chat box follow Blizzard's code (FrameControlsManager.lua, ChatFrameEditBox.lua,
-- FloatingChatFrame.lua). Every chat send function is poisoned: the keyboard must never call one.
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local W = dofile(lib .. "widgets.lua")
local check = H.check

-- ---- a small game world -------------------------------------------------------------------------------
local world = { combat = false, printed = {}, party = false, raid = false, instance = false, guild = false }
W.install({ inCombat = function() return world.combat end })
function InCombatLockdown() return world.combat end
function print(s) world.printed[#world.printed + 1] = s end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function tinsert(t, v) table.insert(t, v) end
UISpecialFrames, SlashCmdList = {}, {}
UIParent = W.CreateFrame("Frame", "UIParent"); UIParent.height = 1000
GAMEPAD_FACE_BOTTOM, GAMEPAD_FACE_RIGHT = "PAD1", "PAD2"
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
local style = 1
C_InputInterfaceStyle = { GetCurrentStyle = function() return style end }
function GetCurrentKeyBoardFocus() return W.focused end
function hooksecurefunc(t, k, fn)
	if type(t) == "string" then t, k, fn = _G, t, k end
	local orig = assert(t[k], "hooksecurefunc: no " .. tostring(k))
	t[k] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
NUM_CHAT_WINDOWS = 1
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
function IsInGroup(category)
	if category == LE_PARTY_CATEGORY_INSTANCE then return world.instance end
	return world.party or world.raid
end
function IsInRaid() return world.raid end
function IsInGuild() return world.guild end
local lastTell, lastTellType -- whoever whispered last
-- Name lookup (C_AutoComplete): the players it knows, same realm without the realm.
local ROSTER = { "Bob", "Bobby", "Boris-Other", "Bonnie", "Bodhi", "Alice" }
C_AutoComplete = { GetAutoCompleteResults = function(text, numResults, cursorPosition, allowFullMatch, include, exclude)
	assert(include == 1 and exclude == 0, "the box's own include / exclude")
	if world.lookupFails then error("lookup unavailable") end
	local results = {}
	for _, name in ipairs(ROSTER) do
		if name:lower():sub(1, #text) == text:lower() and #results < numResults then results[#results + 1] = { name = name, priority = 1 } end
	end
	return results
end }
function Ambiguate(name, context) return name end
world.time = 0
function GetTime() return world.time end
local function poll() world.time = world.time + 0.016; W.update(0.016) end
local held = {} -- keys and controller buttons held down
function IsKeyDown(k) return held[k] == true end
local BOUND = { OPENCHAT = { "ENTER", "PADBACK" }, OPENCHATSLASH = { "/" }, REPLY = { "R" }, REPLY2 = { "CTRL-T" } }
function GetBindingKey(binding) return unpack(BOUND[binding] or {}) end
GAMEPAD_FACE_LEFT, GAMEPAD_FACE_TOP, GAMEPAD_SHOULDER_LEFT, GAMEPAD_SHOULDER_RIGHT = "PAD3", "PAD4", "PADLSHOULDER", "PADRSHOULDER"
-- Override bindings, as the game keeps them: per owner and key; a priority one beats any other, and of
-- those the latest wins. Protected in combat. The controller UI binds its buttons this way (owner UIParent).
local overrides, overrideOrder = {}, 0
function SetOverrideBinding(owner, isPriority, k, command)
	assert(not world.combat, "SetOverrideBinding in combat")
	for i = #overrides, 1, -1 do
		if overrides[i].owner == owner and overrides[i].key == k then table.remove(overrides, i) end
	end
	overrideOrder = overrideOrder + 1
	overrides[#overrides + 1] = { owner = owner, priority = isPriority, key = k, command = command, order = overrideOrder }
end
function SetOverrideBindingClick(owner, isPriority, k, name, mouseButton)
	SetOverrideBinding(owner, isPriority, k, "CLICK " .. name .. ":" .. (mouseButton or "LeftButton"))
end
function ClearOverrideBindings(owner)
	assert(not world.combat, "ClearOverrideBindings in combat")
	for i = #overrides, 1, -1 do if overrides[i].owner == owner then table.remove(overrides, i) end end
end
local function boundTo(k)
	local best
	for _, o in ipairs(overrides) do
		if o.key == k and o.command ~= "" and (not best or (o.priority and not best.priority) or (o.priority == best.priority and o.order > best.order)) then best = o end
	end
	return best and best.command
end

-- Blizzard's focus manager: popups return focus to the frame they opened over; focusing a frame unfocuses
-- the previous one (UnfocusGamepad), FocusGamepad on the new one.
local refuse = false
local manager = { shownFrames = {}, popupReturnFrames = {}, calls = {} }
local function indexOf(f) for i, v in ipairs(manager.shownFrames) do if v == f then return i end end end
local function focus(frame)
	if manager.focusedFrame == frame then return end
	local old = manager.focusedFrame
	manager.focusedFrame = frame
	if old and old.UnfocusGamepad then old:UnfocusGamepad() end
	if frame and frame.FocusGamepad then frame:FocusGamepad() end
end
function manager:FrameShown(frame, isPopup)
	if indexOf(frame) then return false end
	table.insert(self.shownFrames, frame)
	focus(frame)
	return true
end
function manager:FrameHidden(frame)
	local i = indexOf(frame); if not i then return false end
	table.remove(self.shownFrames, i)
	local returnFrame = self.popupReturnFrames[frame]; self.popupReturnFrames[frame] = nil
	if self.focusedFrame == frame then focus(returnFrame or self.shownFrames[1]) end
	return true
end
function manager:HandlePopupShown(popup)
	self.calls[#self.calls + 1] = "popupShown"
	if refuse then return end
	local returnFrame = self.focusedFrame
	if self:FrameShown(popup, true) then self.popupReturnFrames[popup] = returnFrame end
end
function manager:HandlePopupHide(popup)
	self.calls[#self.calls + 1] = "popupHide"
	if refuse then return end
	self:FrameHidden(popup)
end
GamepadMode = { FrameControlsManager = manager }
local navCurrent -- the key the D-pad is on
SmartNavigation = { RefreshButtonGroups = function() end, GetCurrentButton = function() return navCurrent end }
SMART_NAV_INPUT_DIRECTION = { UP = { dirKey = "up" }, DOWN = { dirKey = "down" }, LEFT = { dirKey = "left" }, RIGHT = { dirKey = "right" } }
local overrides = {}
function SmartNavigation_AddJumpNavigationOverride(button, direction, target)
	assert(not world.combat)
	overrides[button] = overrides[button] or {}
	overrides[button][direction.dirKey] = target
end

-- The chat: a chat frame with gamepad focus puts typing focus in its box; losing typing focus while empty
-- deactivates the box, which resets its chat type to the sticky one (ChatFrameEditBoxMixin:Deactivate).
local chatFrame = W.CreateFrame("Frame", "ChatFrame1", UIParent)
local chatBox = W.CreateFrame("EditBox", "ChatFrame1EditBox", chatFrame)
chatBox.chatFrame = chatFrame
chatBox.autoFocus = false -- ChatFrameEditBoxTemplate
chatBox.center = { 300, 200 }
chatBox.attrs.chatType, chatBox.attrs.stickyType = "SAY", "SAY"
chatBox.scripts.OnEditFocusLost = function(self)
	if self:GetText() == "" then
		self.attrs.chatType, self.attrs.tellTarget, self.deactivated = self.attrs.stickyType, nil, true
	end
end
-- OnTextChanged -> ParseText(0) -> HandleChatType / ProcessChatType, as when typing: a chat command and a
-- space switch the chat type and leave the rest; /r a whisper to whoever whispered last (nothing if nobody).
local CHAT_COMMANDS = { ["/S"] = "SAY", ["/P"] = "PARTY", ["/RA"] = "RAID", ["/I"] = "INSTANCE_CHAT", ["/G"] = "GUILD" }
chatBox.scripts.OnTextChanged = function(self)
	local text = self.text
	if text:sub(1, 1) ~= "/" or not text:find("%s") then return end
	local command = text:match("^(/[^%s]+)")
	local msg = text:sub(#command + 2):match("^%s*(.*)$")
	command = command:upper()
	if CHAT_COMMANDS[command] then
		self.attrs.chatType = CHAT_COMMANDS[command]
		self:SetText(msg)
	elseif command == "/R" and lastTell then
		self.attrs.chatType, self.attrs.tellTarget = lastTellType, lastTell
		self:SetText(msg)
	end
end
chatFrame.editBox = chatBox
function chatFrame:FocusGamepad() chatBox:SetFocus() end
function chatFrame:UnfocusGamepad() chatBox:ClearFocus() end
function chatFrame:SetGamepadFocus() GamepadMode.FrameControlsManager:FrameShown(self) end -- the menu dial's Chat
local menuDialChat -- set below
local function openChat(chatType, tellTarget, channelTarget)
	chatBox.attrs.chatType, chatBox.attrs.tellTarget, chatBox.attrs.channelTarget, chatBox.deactivated = chatType, tellTarget, channelTarget, nil
	menuDialChat()
end
ChatTypeInfo = { SAY = { sticky = 1 }, PARTY = { sticky = 1 }, CHANNEL = { sticky = 1 }, WHISPER = { sticky = 0 } }
local poisoned = {}
local function poison(name) return function() poisoned[#poisoned + 1] = name; error(name .. " must not be called by the keyboard") end end
for _, name in ipairs({ "SendMessage", "SendText", "ClearChat", "Deactivate", "ParseText" }) do chatBox[name] = poison("editBox:" .. name) end
-- (GetLastTellTarget only reads.)
ChatFrameUtil = setmetatable({ GetLastTellTarget = function() return lastTell, lastTellType end },
	{ __index = function(_, k) return poison("ChatFrameUtil." .. k) end })
C_ChatInfo = { SendChatMessage = poison("C_ChatInfo.SendChatMessage") }

-- A player's A on a key (SmartNavigation clicks it) or a mouse click.
-- Frames pass between presses, as in the game (the focus watcher runs every frame).
local macros = {}
-- A secure button's click on a press (down) or release, if it's registered for it: PreClick, the action
-- on the edge useOnKeyDown picks (SecureActionButton_OnClick: off - the release), PostClick.
local function secureClick(button, down)
	down = down or false
	assert(button.OnSmartNavClick == nil and button.scripts.OnClick == nil, "the secure OnClick must stay Blizzard's")
	local registered = false
	for _, c in ipairs(button.clicks or {}) do if c == (down and "AnyDown" or "AnyUp") then registered = true end end
	if not registered then return end
	if button.scripts.PreClick then button.scripts.PreClick(button, "LeftButton", down) end
	if down == (button.attrs.useOnKeyDown == true) and button.attrs.type == "macro" and button.attrs.macrotext ~= "" then
		macros[#macros + 1] = button.attrs.macrotext -- C_Macro.RunMacroText, securely
	end
	if button.scripts.PostClick then button.scripts.PostClick(button, "LeftButton", down) end
end
local function isSecure(button) return W.hasTemplate(button.template, "SecureActionButtonTemplate") end
-- The controller's A, held this long, on the key the D-pad is on: through what A is bound to - a binding's
-- click on the press and on the release - or SmartNavigation's own A (clicks the key as A goes down).
local function pressA(holdFor)
	poll()
	held.PAD1 = true
	local command = boundTo("PAD1")
	local name = command and command:match("^CLICK (.-):")
	local bound = name and _G[name]
	if bound then
		if isSecure(bound) then secureClick(bound, true) end
		local start = world.time
		repeat poll() until world.time - start >= (holdFor or 0.016)
		held.PAD1 = nil
		if isSecure(bound) then secureClick(bound, false) else bound:Click() end
	else
		if isSecure(navCurrent) then secureClick(navCurrent, false) else navCurrent:Click() end
		poll()
		held.PAD1 = nil
	end
	poll()
end
local function playerClick(button)
	poll()
	assert(button and button:IsVisible() and button:IsEnabled(), "clicking a missing, hidden or disabled key")
	navCurrent = button
	pressA()
end

-- The controller: A while a text box takes focus (SmartNavigation clicks it); the menu dial, whose button
-- comes up before Chat is chosen.
local function padA(fn) poll(); held.PAD1 = true; fn(); poll(); held.PAD1 = nil; poll() end
-- A controller button: whatever it's bound to (a binding's click: down and up, the button acting on up).
local function pad(k)
	poll()
	held[k] = true
	local command = boundTo(k)
	local name = command and command:match("^CLICK (.-):")
	if name and _G[name] then
		local button = _G[name]
		if isSecure(button) then secureClick(button, true); secureClick(button, false) else button:Click() end
	end
	held[k] = nil
	poll()
end
local function menuDial(fn) poll(); held.PADFORWARD = true; poll(); held.PADFORWARD = nil; fn() end

-- A real keyboard, as the game delivers a key: to the text box with typing focus; else to keyboard-enabled
-- frames from the top strata down until one keeps it (then its OnChar and OnKeyUp); else to the key's
-- binding. Blizzard's own: Enter, / and reply open chat (ChatFrameUtil.OpenChat(nil) / ReplyTell ->
-- editBox:SetFocus, the text kept), Escape closes special frames.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local bindingsRun = {}
local function blizzardOpenChat() chatBox.deactivated = nil; chatBox:SetFocus() end
local DEFAULT_BINDINGS = {
	ENTER = blizzardOpenChat, ["/"] = blizzardOpenChat, R = blizzardOpenChat, T = blizzardOpenChat,
	ESCAPE = function() for _, name in ipairs(UISpecialFrames) do if _G[name]:IsShown() then _G[name]:Hide() end end end,
}
local function keyboardKey(k, char, modifier)
	poll()
	held[k] = true
	if modifier then held["L" .. modifier] = true end
	local box = W.focused
	if box then
		if k == "ENTER" then if box.scripts.OnEnterPressed then box.scripts.OnEnterPressed(box) end
		elseif k == "BACKSPACE" then box.text = box.text:sub(1, -2)
		elseif char then box.text = box.text .. char end
	else
		local listeners = {}
		for _, f in ipairs(W.frames) do
			if f.keyboardEnabled and f:IsVisible() and f.scripts.OnKeyDown then listeners[#listeners + 1] = f end
		end
		table.sort(listeners, function(a, b) return STRATA[a:GetFrameStrata()] > STRATA[b:GetFrameStrata()] end)
		local keptBy
		for _, f in ipairs(listeners) do
			f.scripts.OnKeyDown(f, k)
			if not f.propagate then keptBy = f; break end
		end
		if keptBy then
			if char and keptBy.scripts.OnChar and keptBy:IsVisible() then keptBy.scripts.OnChar(keptBy, char) end
		else
			bindingsRun[#bindingsRun + 1] = k
			if DEFAULT_BINDINGS[k] then DEFAULT_BINDINGS[k]() end
		end
		held[k] = nil
		if keptBy and keptBy.scripts.OnKeyUp and keptBy:IsVisible() then keptBy.scripts.OnKeyUp(keptBy, k) end
	end
	held[k] = nil
	if modifier then held["L" .. modifier] = nil end
	poll()
end
local function mouseClick(fn) poll(); W.fireEvent("GLOBAL_MOUSE_DOWN", "LeftButton"); fn(); poll() end

function menuDialChat() menuDial(function() chatFrame:SetGamepadFocus() end) end

for _, k in ipairs({ "PAD1", "PAD3", "PAD4", "PADLSHOULDER", "PADRSHOULDER" }) do SetOverrideBindingClick(UIParent, true, k, "Blizzard_" .. k) end

-- Blizzard's Settings API (Blizzard_Settings.lua, AddOnSettingMixin): an addon setting writes its default
-- into the table if the key is nil, then reads and writes that table; SetValue fires value-changed callbacks.
local optionsPanel = { settings = {}, order = {} }
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2 } }
Settings = {
	VarType = { Boolean = "boolean", String = "string", Number = "number" },
	RegisterVerticalLayoutCategory = function(name)
		optionsPanel.category = { name = name, GetID = function() return 4242 end }
		return optionsPanel.category
	end,
	RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
		assert(category == optionsPanel.category and type(tbl) == "table" and type(default) == varType, "RegisterAddOnSetting arguments")
		if tbl[key] == nil then tbl[key] = default end
		local setting = { variable = variable, key = key, tbl = tbl, name = name, default = default, callbacks = {} }
		function setting:GetValue() return self.tbl[self.key] end
		function setting:SetValue(v) self.tbl[self.key] = v; for _, cb in ipairs(self.callbacks) do cb(self, v) end end
		function setting:SetValueChangedCallback(cb) table.insert(self.callbacks, cb) end
		optionsPanel.settings[key] = setting
		optionsPanel.order[#optionsPanel.order + 1] = key
		return setting
	end,
	CreateCheckbox = function(category, setting, tooltip) setting.control, setting.tooltip = "checkbox", tooltip end,
	CreateSlider = function(category, setting, options, tooltip) setting.control, setting.options, setting.tooltip = "slider", options, tooltip end,
	CreateSliderOptions = function(minValue, maxValue, rate)
		return { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate,
			SetLabelFormatter = function(self, labelType, format) self.labelType, self.format = labelType, format end }
	end,
	RegisterAddOnCategory = function(category) optionsPanel.addOnCategory = category end,
	OpenToCategory = function(id) optionsPanel.opened = id end,
}

-- EventRegistry (CallbackRegistryMixin): one callback per owner and event, an owner required here.
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, func, owner)
	assert(type(event) == "string" and type(func) == "function" and owner ~= nil and type(owner) ~= "number", "RegisterCallback arguments")
	self.callbacks[event] = self.callbacks[event] or {}
	self.callbacks[event][owner] = func
end
function EventRegistry:TriggerEvent(event, ...)
	for owner, func in pairs(self.callbacks[event] or {}) do func(owner, ...) end
end

-- ---- load ---------------------------------------------------------------------------------------------
H.loadAddon({})
check(SlashCmdList.GAMEPADKEYBOARD ~= nil and SLASH_GAMEPADKEYBOARD1 == "/gk", "/gk")
-- The game loads the saved table after the addon's files, then fires ADDON_LOADED.
check(optionsPanel.category == nil, "(no options before the saved table is loaded)")
GamepadKeyboardDB = { position = nil }
local savedTable = GamepadKeyboardDB
W.fireEvent("ADDON_LOADED", "SomeOtherAddOn")
check(optionsPanel.category == nil, "(another addon loading: nothing)")
W.fireEvent("ADDON_LOADED", "GamepadKeyboard")
local S = optionsPanel.settings
check(optionsPanel.addOnCategory and optionsPanel.addOnCategory.name == "Gamepad Keyboard"
	and table.concat(optionsPanel.order, ",") == "autoOpen,closeOnEnter,chatCapital,names,holdTime,scale",
	"Options > AddOns > Gamepad Keyboard: open with the controller, close after Enter, capital, names, hold time, size")
check(S.autoOpen.control == "checkbox" and S.closeOnEnter.control == "checkbox" and S.holdTime.control == "slider" and S.scale.control == "slider"
	and S.holdTime.options.minValue == 0.3 and S.holdTime.options.maxValue == 1.5 and S.holdTime.options.format(0.5) == "0.5 s"
	and S.scale.options.minValue == 0.6 and S.scale.options.maxValue == 1.5 and S.scale.options.format(1.2) == "120%",
	"checkboxes and sliders, with their ranges and labels")
check(S.closeOnEnter.tbl == savedTable and savedTable.closeOnEnter == true and savedTable.holdTime == 0.5 and savedTable.scale == 1,
	"on the loaded saved table, defaults filled in")
W.fireEvent("ADDON_LOADED", "GamepadKeyboard")
check(#optionsPanel.order == 6, "(registered once)")
poll(); poll()
check(W.focused == nil, "loading takes no typing focus (a text box of ours shown with auto-focus would keep every key)")

local function keyboard() return GamepadKeyboardFrame end
-- What a FontString shows, read left to right: "||" is one "|", "|cAARRGGBB" and "|r" are colour codes.
local function shown(s)
	local out, i = {}, 1
	while i <= #s do
		local c, n = s:sub(i, i), s:sub(i + 1, i + 1)
		if c == "|" and n == "|" then out[#out + 1] = "|"; i = i + 2
		elseif c == "|" and n == "c" then i = i + 10
		elseif c == "|" and n == "r" then i = i + 2
		else out[#out + 1] = c; i = i + 1 end
	end
	return table.concat(out)
end
local function preview() return shown(keyboard().Preview.text) end
local CARET = "|" -- the cursor, as it shows
local function key(k)
	for _, f in ipairs(W.frames) do if f.parent == keyboard() and f.key == k and f.shown then return f end end
end
local function type(s) for c in s:gmatch(".") do playerClick(key(c == " " and "SPACE" or c:lower())) end end

-- ---- chat: a whisper reply ----------------------------------------------------------------------------------
openChat("WHISPER", "Bob"); poll()
local kb = keyboard()
local ring = kb.HoldPrompt and kb.HoldPrompt.icon -- the footer's press-and-hold glyph
check(kb and kb.point and kb.point[1] == "BOTTOMLEFT" and kb.point[2] == chatFrame and kb.point[3] == "BOTTOMRIGHT",
	"for chat it opens beside the chat window, not over it")
check(kb and kb:IsShown(), "chat box focused with the controller: the keyboard opens")
check(indexOf(kb) ~= nil and manager.focusedFrame == kb and manager.popupReturnFrames[kb] == chatFrame,
	"as a popup in Blizzard's gamepad UI, returning to the chat")
check(not chatBox:HasFocus() and not chatBox.deactivated and chatBox.attrs.chatType == "WHISPER" and chatBox.attrs.tellTarget == "Bob",
	"the chat box stays open and keeps its whisper target (a placeholder space kept it from closing)")
check(key("SHIFT").locked, "an empty chat line starts with Shift on")
type("hi"); playerClick(key("SPACE")); type("there")
check(chatBox:GetText() == "Hi there" and preview() == "Hi there" .. CARET, "keys type into the chat box (its own preview) - first letter capital")
playerClick(key("BACK"))
check(chatBox:GetText() == "Hi ther", "Del removes the last letter")
kb:SmartNavigationCloseHandler() -- B
check(not kb:IsShown() and indexOf(kb) == nil, "B closes the keyboard")
check(manager.focusedFrame == chatFrame and chatBox:HasFocus() and chatBox:GetText() == "Hi ther" and chatBox.attrs.tellTarget == "Bob",
	"...and the controller is back on the chat box with the text, still to Bob, nothing sent")
poll(); poll()
check(not kb:IsShown(), "it doesn't open again for the box it went back to")
check(#poisoned == 0, "the keyboard never called a chat send function")
-- Back on the chat box, choosing Chat on the menu dial again (the chat is already the focused optionsPanel, so
-- nothing changes focus): the keyboard comes back.
menuDialChat(); poll()
check(kb:IsShown() and chatBox:GetText() == "Hi ther", "Chat chosen again while back on the chat box: the keyboard comes back, with the text")
local enter = key("ENTER")
check(enter.text == "Enter" and enter.protected and enter.attrs.type == "macro" and enter.attrs.useOnKeyDown == false and enter.clicks[1] == "AnyUp",
	"Enter is a secure macro button acting on release")
playerClick(enter)
check(macros[#macros] == "/w Bob Hi ther", "Enter sends the whisper, as a secure macro line (" .. tostring(macros[#macros]) .. ")")
check(not kb:IsShown() and indexOf(chatFrame) == nil and chatBox:GetText() == "" and chatBox.deactivated,
	"...and closes the keyboard and the chat, like Enter")
poll()
openChat("SAY"); poll()
check(kb:IsShown(), "next time chat is focused, it opens again")
check(chatBox:GetText() == " ", "(the placeholder while the keyboard is open)")
kb:SmartNavigationCloseHandler()
check(not kb:IsShown() and chatBox:GetText() == "" and chatBox:HasFocus(), "B with nothing typed: back to an empty chat box (placeholder gone)")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
local before = #macros
openChat("SAY"); poll()
playerClick(key("ENTER"))
check(#macros == before and not kb:IsShown() and indexOf(chatFrame) == nil, "Enter with nothing typed: nothing sent, chat closed")
poll()
-- Party, a typed command, a channel; the chat type sticks as with Enter.
openChat("PARTY"); poll()
type("pull")
playerClick(key("ENTER"))
check(macros[#macros] == "/p Pull" and chatBox.attrs.stickyType == "PARTY", "party chat: /p, and party sticks for the next line")
poll()
openChat("SAY"); poll()
playerClick(key("SYMBOLS")); playerClick(key("/")); playerClick(key("LETTERS")); type("p ")
check(chatBox:GetText() == "" and preview() == CARET, "the preview shows what the box made of /p (party chat, nothing typed yet)")
type("hi")
check(chatBox.attrs.chatType == "PARTY" and chatBox:GetText() == "hi" and preview() == "hi" .. CARET, "typing /p and a space switches to party, as typing does")
playerClick(key("ENTER"))
check(macros[#macros] == "/p hi", "...and Enter sends it to party")
poll()
openChat("SAY"); poll()
playerClick(key("SYMBOLS")); playerClick(key("/")); playerClick(key("LETTERS")); type("dance")
playerClick(key("ENTER"))
check(macros[#macros] == "/dance", "a command is run as typed (" .. tostring(macros[#macros]) .. ")")
poll()
openChat("CHANNEL", nil, 2); poll()
type("lfg")
playerClick(key("ENTER"))
check(macros[#macros] == "/2 Lfg", "a numbered channel: /2")
poll()
-- A chat type a macro line can't say: back to the chat box for the chat's own A.
before = #macros
openChat("VOICE_TEXT"); poll()
type("hi")
playerClick(key("ENTER"))
check(#macros == before and not kb:IsShown() and chatBox:HasFocus() and chatBox:GetText() == "Hi" and world.printed[#world.printed]:find("A"),
	"a chat type a macro line can't say: back on the chat box with the text, to send with A")
kb:Hide(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("BN_WHISPER", "|Kq1|k"); poll()
type("yo")
playerClick(key("ENTER"))
check(#macros == before and not kb:IsShown() and chatBox:HasFocus() and chatBox:GetText() == "Yo",
	"a Battle.net whisper: back on the chat box for its own A (its target may be a protected name)")
kb:Hide(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("WHISPER", "Bob"); poll()
type("x"); chatBox.text = string.rep("x", 250) -- a long line, as the box allows
playerClick(key("ENTER"))
check(#macros == before and chatBox:HasFocus() and #chatBox:GetText() == 250,
	"a whisper too long for one macro line with its /w: back on the chat box, nothing cut")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- pages, shift, limits -------------------------------------------------------------------------------------
openChat("SAY"); poll()
playerClick(key("SHIFT"))
check(not key("SHIFT").locked and key("a").text == "a", "Shift toggles back off")
playerClick(key("SHIFT"))
check(key("a").text == "A", "Shift shows capitals")
type("o"); type("k")
check(chatBox:GetText() == "Ok" and key("a").text == "a", "Shift lasts one letter")
playerClick(key("SYMBOLS"))
check(key("q") == nil and key("!") ~= nil and key("LETTERS") ~= nil, "?123 shows the symbols")
playerClick(key("!")); playerClick(key("LETTERS"))
check(chatBox:GetText() == "Ok!" and key("q") ~= nil, "a symbol, then ABC back to letters")
local hasPipe = false
for _, f in ipairs(W.frames) do if f.key == "|" then hasPipe = true end end
check(not hasPipe, "no | key (the game reads it as an escape code)")
keyboardKey("ESCAPE")
check(not kb:IsShown() and manager.focusedFrame == chatFrame and chatBox:GetText() == "Ok!", "closed by Escape on a real keyboard: same as B")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- the controller's X, Y, LB, RB: Del, Space, the cursor ---------------------------------------------------------
check(boundTo("PAD3") == "CLICK Blizzard_PAD3:LeftButton", "(the controller UI's own X before the keyboard opens)")
openChat("SAY"); poll()
check(boundTo("PAD3") == "CLICK GamepadKeyboardDelKey:LeftButton" and boundTo("PAD4") == "CLICK GamepadKeyboardSpaceKey:LeftButton"
	and boundTo("PADLSHOULDER") == "CLICK GamepadKeyboardCursorLeft:LeftButton" and boundTo("PADRSHOULDER") == "CLICK GamepadKeyboardCursorRight:LeftButton",
	"with the keyboard open: X Del, Y Space, LB / RB the cursor")
type("hi"); pad("PAD4"); type("you")
check(chatBox:GetText() == "Hi you" and preview() == "Hi you" .. CARET, "Y types a space")
pad("PAD3")
check(chatBox:GetText() == "Hi yo", "X deletes")
pad("PADLSHOULDER"); pad("PADLSHOULDER")
check(preview() == "Hi " .. CARET .. "yo" and chatBox:GetText() == "Hi yo", "LB moves the cursor left (the preview shows it)")
type("t")
check(chatBox:GetText() == "Hi tyo" and preview() == "Hi t" .. CARET .. "yo", "keys type at the cursor")
pad("PAD3"); pad("PAD3")
check(chatBox:GetText() == "Hiyo" and preview() == "Hi" .. CARET .. "yo", "X deletes the letter before the cursor")
for _ = 1, 5 do pad("PADLSHOULDER") end
check(preview() == CARET .. "Hiyo", "...not past the start")
pad("PAD3")
check(chatBox:GetText() == "Hiyo", "X at the start: nothing to delete")
for _ = 1, 6 do pad("PADRSHOULDER") end
check(preview() == "Hiyo" .. CARET, "RB moves it right, not past the end")
pad("PADLSHOULDER"); playerClick(key("SYMBOLS")); pad("PAD4"); playerClick(key("!")); pad("PAD3")
check(chatBox:GetText() == "Hiy o" and preview() == "Hiy " .. CARET .. "o", "on the symbols page too (Space, Del)")
playerClick(key("LETTERS"))
pad("PADLSHOULDER")
playerClick(key("CHAT"))
check(chatBox.attrs.chatType == "SAY" and preview() == "Hiy" .. CARET .. " o", "the chat key keeps the cursor")
-- The controller UI binding X over the keyboard's while it's open: the keyboard's again.
SetOverrideBindingClick(UIParent, true, "PAD3", "Blizzard_Other")
check(boundTo("PAD3") == "CLICK GamepadKeyboardDelKey:LeftButton", "the controller UI binding X over it while open: bound again")
-- LT / RT to another window: the buttons are the controller UI's again; back to the keyboard: ours.
local other = W.CreateFrame("Frame", "OtherPanel", UIParent)
manager:FrameShown(other); poll()
check(boundTo("PAD3") == "CLICK Blizzard_Other:LeftButton" and boundTo("PADLSHOULDER") == "CLICK Blizzard_PADLSHOULDER:LeftButton",
	"the controller on another window: X / Y / LB / RB are the controller UI's again")
focus(kb); manager:FrameHidden(other); poll()
check(boundTo("PAD4") == "CLICK GamepadKeyboardSpaceKey:LeftButton", "back on the keyboard: ours again")
kb:SmartNavigationCloseHandler()
check(boundTo("PAD3") == "CLICK Blizzard_Other:LeftButton" and boundTo("PAD4") == "CLICK Blizzard_PAD4:LeftButton",
	"closed: the controller UI's again at once")
pad("PAD3")
check(chatBox:GetText() == "Hiy o", "...and X doesn't touch the text then")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
local long = string.rep("abcdefghij", 6) -- 60 letters
chatBox.text = long; pad("PADRSHOULDER") -- (the keyboard reads the box at its next key)
check(preview() == "..." .. long:sub(13) .. CARET, "a long line: the preview shows the 48 letters before the cursor")
for _ = 1, 50 do pad("PADLSHOULDER") end
check(preview() == long:sub(1, 10) .. CARET .. long:sub(11, 48) .. "...", "...and with the cursor near the start, the start")
type("x")
check(chatBox:GetText() == long:sub(1, 10) .. "X" .. long:sub(11), "(typed at the cursor in a long line)")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- holding A: Enter ---------------------------------------------------------------------------------------------
openChat("PARTY"); poll()
check(boundTo("PAD1") == "CLICK GamepadKeyboardAButton:LeftButton", "with the keyboard open, A is the keyboard's (a tap types, a hold sends)")
type("hold")
check(chatBox:GetText() == "Hold", "(a tap types the key the D-pad is on, as A did)")
navCurrent = key("k")
pressA(0.6)
check(macros[#macros] == "/p Hold" and not kb:IsShown() and indexOf(chatFrame) == nil and chatBox:GetText() == "",
	"holding A on any key is Enter: sent, the chat closed, nothing typed")
check(boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton", "...and A is the controller UI's again")
poll()
before = #macros
openChat("SAY"); poll()
type("ok")
navCurrent = key("a")
pressA(0.3)
check(#macros == before and chatBox:GetText() == "Oka" and kb:IsShown() and not ring.holding, "a press shorter than the hold: a tap (the ring stops)")
-- The footer: A Type, and Blizzard's press-and-hold glyph for A, Enter.
check(kb.Prompts[1].text.text == "Type" and ring and ring.inputKey == "PAD1" and ring.isHoldAction and kb.HoldPrompt.text.text == "Enter"
	and not ring.holding, "the footer: A Type, and A with the press-and-hold ring for Enter")
-- While held: the ring fills, and the Enter keys light up once it's long enough.
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true)
check(ring.holding == 0.5, "A down on the keyboard: the ring fills over the hold")
for _ = 1, 10 do poll() end
check(not key("ENTER").locked, "(not lit while too short)")
for _ = 1, 30 do poll() end
check(key("ENTER").locked, "held long enough: the Enter key lights up (letting go sends)")
held.PAD1 = nil; secureClick(GamepadKeyboardAButton, false); poll()
check(macros[#macros] == "/s Oka" and not kb:IsShown() and not key("ENTER").locked and not ring.holding, "...letting go sends, the light and the ring go out")
poll()
-- The D-pad still on a key the page switch hid: a tap does nothing.
openChat("SAY"); poll()
local hiddenQ = key("q")
playerClick(key("SYMBOLS"))
navCurrent = hiddenQ
pressA()
check(preview() == CARET and chatBox:GetText() == " " and kb:IsShown(), "a tap on a key that's hidden now (another page): nothing")
playerClick(key("LETTERS"))
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
-- The release of an A whose press went to the controller UI (the A that opened the keyboard): nothing.
openChat("SAY"); poll()
type("x")
secureClick(GamepadKeyboardAButton, false); poll()
check(chatBox:GetText() == "X" and kb:IsShown() and #macros == before + 1, "a release without its press on the keyboard: nothing")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true); poll()
kb:SmartNavigationCloseHandler(); held.PAD1 = nil; chatBox.text = ""; manager:FrameHidden(chatFrame)
check(not ring.holding, "closed while A is held: the ring stops")
for _ = 1, 40 do poll() end
openChat("SAY"); poll(); poll()
check(not key("ENTER").locked, "closed while A is held: not a hold the next time it opens")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
-- A name box: holding A is its own Enter.
local holdBox = W.CreateFrame("EditBox", nil, optionsPanel or UIParent, "InputBoxTemplate")
holdBox.center = { 500, 300 }
local holdEntered = 0
holdBox.scripts.OnEnterPressed = function(self) holdEntered = holdEntered + 1; self:ClearFocus() end
padA(function() holdBox:SetFocus() end)
type("ab")
pressA(0.7)
check(holdEntered == 1 and not kb:IsShown() and holdBox:GetText() == "ab", "in another text box, holding A is that box's Enter")
holdBox:ClearFocus(); poll()

-- ---- names, for a box that looks them up (the mail's To:) ----------------------------------------------------------
local mail = W.CreateFrame("Frame", "MockMailFrame", UIParent)
local mailTo = W.CreateFrame("EditBox", "SendMailNameEditBox", mail, "InputBoxTemplate")
mailTo.center = { 400, 700 }
mailTo.autoCompleteSource, mailTo.autoCompleteParams, mailTo.autoCompleteContext = C_AutoComplete.GetAutoCompleteResults, { 1, 0 }, "mail"
local function nameKeys()
	local list = {}
	for _, f in ipairs(W.frames) do
		if f.parent == kb and f.template == "UIPanelButtonTemplate" and f.key == nil then list[#list + 1] = f end
	end
	return list
end
local function shownNames()
	local list = {}
	for _, f in ipairs(nameKeys()) do if f.shown then list[#list + 1] = f.text end end
	return table.concat(list, ",")
end
manager:FrameShown(mail)
padA(function() mailTo:SetFocus() end)
check(kb:IsShown() and shownNames() == "" and kb.height == 84 + 6 * 34 and key("1").point[3] == -56 - 34,
	"the mail's To: box: a row for names above the keys, empty with nothing typed")
type("bo")
check(shownNames() == "Bob,Bobby,Boris-Other,Bonnie", "typing: the names it knows that start so, four at most (" .. shownNames() .. ")")
check(overrides[key("1")] and overrides[key("1")].up == nameKeys()[1], "up from the top row of keys: the names")
playerClick(nameKeys()[2])
check(mailTo:GetText() == "Bobby" and shownNames() == "" and preview() == "Bobby|", "A on a name: it's put in (and nothing left to pick)")
check(overrides[key("1")].up == true, "...and up from the keys goes nowhere again")
pad("PAD3")
check(mailTo:GetText() == "Bobb" and shownNames() == "Bobby", "Del: the names follow")
type("x")
check(shownNames() == "", "no one by that name: no names")
kb:SmartNavigationCloseHandler(); mailTo:ClearFocus(); mailTo.text = ""; manager:FrameHidden(mail); poll()
-- Moving between the mail's boxes while the keyboard is open: LT to the mail window, A on another box.
local subject = W.CreateFrame("EditBox", "SendMailSubjectEditBox", mail, "InputBoxTemplate")
subject.center = { 400, 650 }
manager:FrameShown(mail)
padA(function() mailTo:SetFocus() end)
type("bo")
focus(mail); poll()
padA(function() subject:SetFocus() end)
check(kb:IsShown() and preview() == "|" and shownNames() == "" and kb.height == 84 + 5 * 34,
	"A on the Subject: while the keyboard is open: it types there now (no names there)")
focus(kb); poll()
type("hi")
check(subject:GetText() == "hi" and mailTo:GetText() == "bo", "...the letters go into the Subject:, To: keeps its own")
focus(mail); poll()
padA(function() mailTo:SetFocus() end)
check(preview() == "bo|" and shownNames() == "Bob,Bobby,Boris-Other,Bonnie" and kb.height == 84 + 6 * 34,
	"back to To:: it types there again, with its names")
focus(kb); poll()
type("b")
check(mailTo:GetText() == "bob" and subject:GetText() == "hi", "...and the letters go there")
SlashCmdList.GAMEPADKEYBOARD("names")
check(world.printed[#world.printed]:find('SendMailNameEditBox: "bob" finds Bob, Bobby', 1, true) ~= nil,
	"/gk names: what the lookup finds for the box (" .. world.printed[#world.printed] .. ")")
world.lookupFails = true
type("x")
check(mailTo:GetText() == "bobx" and preview() == "bobx|" and shownNames() == "", "a lookup that fails: typing goes on, no names")
SlashCmdList.GAMEPADKEYBOARD("names")
check(world.printed[#world.printed]:find("failed", 1, true) and world.printed[#world.printed]:find("lookup unavailable", 1, true),
	"...and /gk names says why")
world.lookupFails = false
mouseClick(function() subject:SetFocus() end)
check(not kb:IsShown() and subject:HasFocus(), "a mouse click on another box while it's open: it steps aside")
subject:ClearFocus(); mailTo.text = ""; subject.text = ""; manager:FrameHidden(mail); poll()
padA(function() subject:SetFocus() end)
kb:SmartNavigationCloseHandler(); subject:ClearFocus(); poll()
SlashCmdList.GAMEPADKEYBOARD("names")
check(world.printed[#world.printed]:find("SendMailSubjectEditBox doesn't look names up", 1, true) ~= nil,
	"/gk names for a box without a lookup says so")

-- Leaving the chat box for another box: the chat box as it was (no placeholder left in it).
openChat("SAY"); poll()
check(chatBox:GetText() == " ", "(the chat's placeholder while the keyboard is open)")
manager:FrameShown(mail); focus(mail); poll()
padA(function() mailTo:SetFocus() end)
check(kb:IsShown() and preview() == "|" and chatBox:GetText() == "" and key("CHAT") == nil, "leaving the chat box for To:: no placeholder left in chat, no chat key")
focus(kb); poll()
padA(function() focus(chatFrame) end) -- LT to the chat window: its box gets typing focus
focus(kb); poll(); poll()
check(kb:IsShown() and key("CHAT") ~= nil and chatBox:GetText() == " ",
	"...and back to the chat window then: the keyboard types in chat again, not taken for a real keyboard's")
kb:SmartNavigationCloseHandler(); mailTo:ClearFocus(); manager:FrameHidden(mail); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- a box of several lines (the mail's text): Enter is a new line ---------------------------------------------------
local mailBody = W.CreateFrame("EditBox", "SendMailBodyEditBox", mail, "InputBoxTemplate")
mailBody.center = { 400, 500 }
mailBody:SetMultiLine(true)
local bodyEntered = 0
mailBody.scripts.OnEnterPressed = function() bodyEntered = bodyEntered + 1 end
manager:FrameShown(mail)
padA(function() mailBody:SetFocus() end)
check(key("ENTER").text == "New line" and kb.HoldPrompt.text.text == "New line", "a box of several lines: Enter says New line (the key and the hold prompt)")
type("hi"); playerClick(key("ENTER"))
check(mailBody:GetText() == "hi\n" and kb:IsShown() and bodyEntered == 0 and preview() == "|   line 2 of 2",
	"Enter: a new line, the keyboard stays, the box's Enter isn't run; the preview shows the line it's on")
type("yo")
for _ = 1, 3 do pad("PADLSHOULDER") end
check(preview() == "hi|   line 1 of 2", "the cursor back on the first line: the preview shows that line")
pressA(0.6)
check(mailBody:GetText() == "hi\n\nyo" and kb:IsShown(), "holding A there: a new line too")
kb:SmartNavigationCloseHandler(); mailBody:ClearFocus(); poll()
check(key("ENTER").text == "Enter" or not kb:IsShown(), "(closed)")
-- The keyboard goes when its box does (the window closes).
padA(function() mailTo:SetFocus() end)
check(kb:IsShown(), "(open on To:)")
mail:Hide(); poll()
check(not kb:IsShown(), "the window closed: the keyboard goes with its box")
mail:Show(); mailTo:ClearFocus(); mailTo.text = ""; mailBody.text = ""; manager:FrameHidden(mail); poll()

-- Only Blizzard's own lookup, never a box's own function or completion handler.
local custom = W.CreateFrame("EditBox", nil, mail, "InputBoxTemplate")
custom.center = { 400, 700 }
local calls = 0
custom.autoCompleteSource, custom.autoCompleteParams = function() calls = calls + 1; return { { name = "Bob" } } end, { 1, 0 }
manager:FrameShown(mail)
padA(function() custom:SetFocus() end)
type("bo")
check(calls == 0 and shownNames() == "" and kb.height == 84 + 5 * 34, "a box with its own lookup function: not called, no name row")
kb:SmartNavigationCloseHandler(); custom:ClearFocus(); poll()
local handled = W.CreateFrame("EditBox", nil, mail, "InputBoxTemplate")
handled.center = { 400, 700 }
handled.autoCompleteSource, handled.autoCompleteParams = C_AutoComplete.GetAutoCompleteResults, { 1, 0 }
handled.customAutoCompleteFunction = function() end
padA(function() handled:SetFocus() end)
type("bo")
check(shownNames() == "", "a box with its own completion handler: no name row")
kb:SmartNavigationCloseHandler(); handled:ClearFocus(); manager:FrameHidden(mail); poll()
chatBox.autoCompleteSource, chatBox.autoCompleteParams = C_AutoComplete.GetAutoCompleteResults, { 1, 0 } -- (a whisper's)
openChat("SAY"); poll()
type("bo")
check(shownNames() == "" and kb.height == 84 + 5 * 34, "chat: no name row (its own list is for whisper targets)")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
chatBox.autoCompleteSource, chatBox.autoCompleteParams = nil, nil
local withCommand = W.CreateFrame("EditBox", nil, mail, "InputBoxTemplate")
withCommand.center = { 400, 700 }
withCommand.autoCompleteSource, withCommand.autoCompleteParams = C_AutoComplete.GetAutoCompleteResults, { 1, 0 }
withCommand.command, withCommand.addSpaceToAutoComplete = "/invite", true
manager:FrameShown(mail)
padA(function() withCommand:SetFocus() end)
type("ali")
playerClick(nameKeys()[1])
check(withCommand:GetText() == "/invite Alice ", "a box with a command and a space, as Blizzard's list puts them in")
kb:SmartNavigationCloseHandler(); withCommand:ClearFocus(); manager:FrameHidden(mail); poll()

-- ---- settings ------------------------------------------------------------------------------------------------------
-- Close after Enter, off: chat sends and stays open for the next line, in the same chat.
GamepadKeyboardDB.closeOnEnter = false
openChat("PARTY"); poll()
type("one"); playerClick(key("ENTER"))
check(macros[#macros] == "/p One" and kb:IsShown() and indexOf(chatFrame) ~= nil and chatBox:GetText() == " " and preview() == "|"
	and key("SHIFT").locked, "Close after Enter off: sent, the keyboard and the chat stay, ready for the next line")
type("two"); playerClick(key("ENTER"))
check(macros[#macros] == "/p Two" and chatBox.attrs.chatType == "PARTY", "...the next line goes to the same chat")
kb:SmartNavigationCloseHandler()
check(not kb:IsShown() and chatBox:GetText() == "" and chatBox:HasFocus(), "...B: back on the chat box, empty")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
-- ...in another box: its Enter runs, the keyboard stays; if Enter hides the box, the keyboard goes.
local searchPanel = W.CreateFrame("Frame", "SearchPanel", UIParent)
local search = W.CreateFrame("EditBox", nil, searchPanel, "InputBoxTemplate")
search.center = { 400, 700 }
local searched = 0
search.scripts.OnEnterPressed = function() searched = searched + 1 end
manager:FrameShown(searchPanel)
padA(function() search:SetFocus() end)
type("ore"); playerClick(key("ENTER"))
check(searched == 1 and kb:IsShown() and search:GetText() == "ore", "...in another box: its Enter runs, the keyboard stays")
search.scripts.OnEnterPressed = function() searchPanel:Hide() end
playerClick(key("ENTER")); poll()
check(not kb:IsShown(), "...and when its Enter closes the window, the keyboard goes too")
searchPanel:Show(); search:ClearFocus(); manager:FrameHidden(searchPanel); poll()
GamepadKeyboardDB.closeOnEnter = nil
-- A chat line without a capital to start.
GamepadKeyboardDB.chatCapital = false
openChat("SAY"); poll()
check(not key("SHIFT").locked, "Capital at the start of a chat line, off: Shift off")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
GamepadKeyboardDB.chatCapital = nil
-- No name keys.
GamepadKeyboardDB.names = false
manager:FrameShown(mail)
padA(function() mailTo:SetFocus() end)
type("bo")
check(shownNames() == "" and kb.height == 84 + 5 * 34, "Name suggestions off: no name row")
kb:SmartNavigationCloseHandler(); mailTo:ClearFocus(); mailTo.text = ""; manager:FrameHidden(mail); poll()
GamepadKeyboardDB.names = nil
-- A longer hold.
GamepadKeyboardDB.holdTime = 1
openChat("SAY"); poll()
type("a")
navCurrent = key("b")
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true)
check(ring.holding == 1, "Hold time 1 s: the ring fills over 1 s")
held.PAD1 = nil; secureClick(GamepadKeyboardAButton, false); poll() -- (a tap: b)
pressA(0.6)
check(chatBox:GetText() == "Abb" and kb:IsShown(), "...and a 0.6 s press is a tap then")
pressA(1.1)
check(not kb:IsShown() and macros[#macros] == "/s Abb", "...a 1.1 s one is Enter")
GamepadKeyboardDB.holdTime = nil
poll()

-- ---- the chat key ------------------------------------------------------------------------------------------------
openChat("SAY"); poll()
local chatKey = key("CHAT")
check(chatKey and chatKey.text == "Say", "chat: a chat key showing the chat type")
type("hi")
playerClick(chatKey)
check(chatBox.attrs.chatType == "SAY" and chatBox:GetText() == "Hi" and chatKey.text == "Say",
	"no group, no guild, nobody to reply to: Say is all there is")
world.party, world.guild = true, true
lastTell, lastTellType = "Bob-Realm", "WHISPER"
playerClick(chatKey)
check(chatBox.attrs.chatType == "PARTY" and chatBox:GetText() == "Hi" and chatKey.text == "Party" and preview() == "Hi" .. CARET,
	"in a party: Party next, the text kept")
playerClick(chatKey)
check(chatBox.attrs.chatType == "GUILD" and chatKey.text == "Guild" and chatBox:GetText() == "Hi", "...then Guild")
playerClick(chatKey)
check(chatBox.attrs.chatType == "WHISPER" and chatBox.attrs.tellTarget == "Bob-Realm" and chatKey.text == "To Bob" and chatBox:GetText() == "Hi",
	"...then a reply to whoever whispered last")
playerClick(chatKey)
check(chatBox.attrs.chatType == "SAY" and chatKey.text == "Say" and chatBox:GetText() == "Hi", "...and round to Say")
playerClick(chatKey)
playerClick(key("ENTER"))
check(macros[#macros] == "/p Hi" and chatBox.attrs.stickyType == "PARTY", "Enter sends to the chat type picked")
poll()
world.raid, world.instance = true, true
openChat("SAY"); poll()
playerClick(key("CHAT")); playerClick(key("CHAT"))
check(chatBox.attrs.chatType == "RAID" and key("CHAT").text == "Raid", "in a raid: Party, then Raid")
playerClick(key("CHAT"))
check(chatBox.attrs.chatType == "INSTANCE_CHAT" and key("CHAT").text == "Instance", "...then Instance (an instance group)")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
world.raid, world.instance = false, false
openChat("SAY"); poll()
playerClick(key("CHAT"))
check(chatBox.attrs.chatType == "PARTY" and chatBox:GetText() == "" and preview() == CARET and key("SHIFT").locked,
	"with nothing typed yet: switched, still nothing typed, Shift still on")
type("go")
playerClick(key("ENTER"))
check(macros[#macros] == "/p Go", "...and what's typed then goes there")
poll()
openChat("SAY"); poll()
playerClick(key("SYMBOLS"))
check(key("CHAT") ~= nil and key("CHAT").text == "Say", "the symbols page has it too")
playerClick(key("/")); playerClick(key("LETTERS")); type("g ")
check(chatBox.attrs.chatType == "GUILD" and key("CHAT").text == "Guild", "typing /g and a space: the chat key follows")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("WHISPER", "Alice"); poll()
check(key("CHAT").text == "To Alice", "a whisper shows who to")
playerClick(key("CHAT"))
check(chatBox.attrs.chatType == "SAY", "...and a whisper to someone other than the last one goes on to Say")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("WHISPER", "Bob-Realm"); poll()
playerClick(key("CHAT"))
check(chatBox.attrs.chatType == "SAY", "the reply already picked: on to Say")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("WHISPER", "Christopherson"); poll()
check(key("CHAT").text == "To Christop..", "a long name is cut to fit")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("CHANNEL", nil, 2); poll()
check(key("CHAT").text == "/2", "a channel shows its number")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("BN_WHISPER", "|Kq1-2|k"); poll()
check(key("CHAT").text == "To |Kq1-2|k", "a Battle.net name is kept whole (the game shows it as the name)")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
world.party, world.guild = false, false
lastTell, lastTellType = nil, nil

-- ---- any other text box: a window with a name box ----------------------------------------------------------------
local panel = W.CreateFrame("Frame", "SomePanel", UIParent)
local nameBox = W.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
nameBox.maxLetters = 5
nameBox.center = { 500, 800 }
nameBox.text = "Tot"
local entered = 0
nameBox.scripts.OnEnterPressed = function(self) entered = entered + 1; self:ClearFocus() end
manager:FrameShown(panel)
padA(function() nameBox:SetFocus() end) -- A on the name box
check(kb:IsShown() and manager.popupReturnFrames[kb] == panel, "a name box in a window: the keyboard opens over that window")
check(kb.point and kb.point[1] == "TOP" and kb.point[2] == nameBox, "below the box (it's in the upper half of the screen)")
check(not key("SHIFT").locked and nameBox:GetText() == "Tot", "no Shift, and it starts from the box's text")
local symbolsKey, enterKey = key("SYMBOLS"), key("ENTER")
check(key("CHAT") == nil and math.abs(symbolsKey.point[2] - (kb.width - enterKey.point[2] - enterKey.width)) < 0.01,
	"no chat key outside chat, and the bottom row centred without it")
type("ems"); type("x")
check(nameBox:GetText() == "Totem", "keys type into the box, up to its letter limit")
kb:SmartNavigationCloseHandler()
check(manager.focusedFrame == panel and nameBox:GetText() == "Totem" and entered == 0, "B: back to the window, the text stays")
poll(); poll()
check(not kb:IsShown(), "it doesn't open again while the box still has focus")
padA(function() nameBox:SetFocus() end) -- A on the name box again: it still has focus
check(kb:IsShown(), "A on the box again (it never lost focus): the keyboard comes back")
playerClick(key("ENTER"))
check(entered == 1 and not kb:IsShown() and manager.focusedFrame == panel and nameBox:GetText() == "Totem" and not nameBox:HasFocus(),
	"Enter: the box's own Enter action (here: done typing), back to the window")
padA(function() nameBox:SetFocus() end)
check(kb:IsShown(), "focusing the box again later opens it again")
kb:Hide(); nameBox:ClearFocus(); poll()

-- ---- a real keyboard, the mouse, the controller ----------------------------------------------------------------
local listening = {}
for _, f in ipairs(W.frames) do if f.keyboardEnabled then listening[#listening + 1] = f end end
check(#listening == 0, "no frame of ours listens to keys (addon code can't pass a key on in this client: it would keep them all)")
keyboardKey("W")
check(bindingsRun[#bindingsRun] == "W", "a key on a real keyboard reaches its binding (walking)")
keyboardKey("ESCAPE")
check(bindingsRun[#bindingsRun] == "ESCAPE", "...Escape too")
-- Enter on a real keyboard in controller mode: the chat is for that keyboard.
keyboardKey("ENTER")
check(chatBox:HasFocus() and not kb:IsShown(), "Enter on a real keyboard opens chat without the on-screen keyboard")
keyboardKey("H", "H"); keyboardKey("I", "i")
check(chatBox:GetText() == "Hi" and not kb:IsShown(), "...and the real keyboard types in it")
poll(); poll()
check(not kb:IsShown(), "...and it stays closed")
menuDialChat(); poll()
check(kb:IsShown() and chatBox:GetText() == "Hi", "Chat on the menu dial then: the on-screen keyboard comes, with the text")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
keyboardKey("R")
check(chatBox:HasFocus() and not kb:IsShown(), "the real keyboard's reply key: no on-screen keyboard either")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
padA(function() end) -- the controller last, so only the key held can tell
keyboardKey("T", nil, "CTRL")
check(chatBox:HasFocus() and not kb:IsShown(), "...nor a reply key bound with a modifier (Ctrl-T)")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
-- A chat key bound on the controller is the controller.
padA(function() end)
held.PADBACK = true; DEFAULT_BINDINGS.ENTER(); poll(); held.PADBACK = nil; poll()
check(kb:IsShown(), "chat opened by a controller button bound to Open Chat: it opens")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
-- A ctrl-click on an item that puts focus in some addon's box (a link to copy, say).
local copyBox = W.CreateFrame("EditBox", nil, UIParent); copyBox:SetAutoFocus(false)
keyboardKey("LCTRL")
mouseClick(function() copyBox:SetFocus() end)
check(copyBox:HasFocus() and not kb:IsShown(), "a mouse click that puts focus in a box: no on-screen keyboard")
padA(function() copyBox:SetFocus() end)
check(kb:IsShown(), "A on that box, which kept focus: it opens (the controller's button is down)")
kb:SmartNavigationCloseHandler(); copyBox:ClearFocus(); poll()

-- A real keyboard (or the mouse) taking the chat box back while the on-screen keyboard is open.
openChat("WHISPER", "Bob"); poll()
type("hey")
keyboardKey("ENTER")
check(not kb:IsShown() and chatBox:HasFocus() and chatBox:GetText() == "Hey" and chatBox.attrs.tellTarget == "Bob",
	"Enter on a real keyboard while it's open: it steps aside, the chat box has the text and its target")
keyboardKey("!", "!")
check(chatBox:GetText() == "Hey!" and not kb:IsShown(), "...and the real keyboard carries on typing there")
poll(); poll()
check(not kb:IsShown(), "...and it doesn't come back by itself")
chatBox.text = ""; chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
type("ok")
mouseClick(function() chatBox:SetFocus() end)
check(not kb:IsShown() and chatBox:HasFocus() and chatBox:GetText() == "Ok", "a mouse click in the chat box while it's open: same")
chatBox.text = ""; chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
keyboardKey("LSHIFT"); keyboardKey("F1")
check(kb:IsShown() and bindingsRun[#bindingsRun] == "F1", "other keys on a real keyboard while it's open: their bindings, and it stays")
kb:SmartNavigationCloseHandler(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
-- A box that kept typing focus while the keyboard is open: a real keyboard types into it; the keyboard follows.
nameBox.text = ""
padA(function() nameBox:SetFocus() end)
type("ab")
keyboardKey("C", "c")
check(nameBox:GetText() == "abc", "a box that kept typing focus: the real keyboard types into it")
playerClick(key("d"))
check(nameBox:GetText() == "abcd", "...and the on-screen keyboard carries on from there, not from its own copy")
kb:SmartNavigationCloseHandler(); nameBox:ClearFocus(); poll()

-- ---- dragging it somewhere else -------------------------------------------------------------------------------
openChat("SAY"); poll()
check(kb.movable and kb.drag and kb.drag[1] == "LeftButton" and kb.scripts.OnDragStart ~= nil, "it can be dragged with the mouse")
kb.scripts.OnDragStart(kb)
kb:ClearAllPoints(); kb:SetPoint("CENTER", UIParent, "CENTER", 250, 120) -- where the game leaves it after the drag
kb.scripts.OnDragStop(kb)
check(not kb.moving and GamepadKeyboardDB.position and GamepadKeyboardDB.position.x == 250, "the dragged spot is saved")
kb:Hide(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
check(kb.point[1] == "CENTER" and kb.point[2] == UIParent and kb.point[4] == 250 and kb.point[5] == 120, "next time it opens where it was dragged")
kb:Hide(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
SlashCmdList.GAMEPADKEYBOARD("reset")
openChat("SAY"); poll()
check(GamepadKeyboardDB.position == nil and kb.point[2] == chatFrame, "/gk reset: back beside the chat window")
kb:Hide(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- size --------------------------------------------------------------------------------------------------------
openChat("SAY"); poll()
check(kb.scale == 1, "(normal size)")
S.scale:SetValue(1.25)
check(kb.scale == 1.25, "Size: the keyboard changes size at once")
kb.scripts.OnDragStart(kb)
kb:ClearAllPoints(); kb:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 200, 80) -- where the game leaves it after a drag, in its own scaled units
kb.scripts.OnDragStop(kb)
check(GamepadKeyboardDB.position.x == 250 and GamepadKeyboardDB.position.y == 100, "dragged at 125%: kept in screen units")
S.scale:SetValue(1)
check(kb.point[4] == 250 and kb.point[5] == 100 and kb.scale == 1, "the same spot at 100%")
S.scale:SetValue(0.8)
check(kb.point[4] == 312.5 and kb.point[5] == 125, "...and at 80% (offsets in its own units: 250 / 0.8)")
S.scale:SetValue(1.25)
SlashCmdList.GAMEPADKEYBOARD("reset")
check(GamepadKeyboardDB.position == nil and S.scale:GetValue() == 1 and kb.scale == 1 and kb.point[2] == chatFrame,
	"/gk reset: usual place and size, at once")
kb:Hide(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- Edit Mode: placed and sized there ---------------------------------------------------------------------------
check(EventRegistry.callbacks["EditMode.Enter"] and EventRegistry.callbacks["EditMode.Exit"], "it follows Edit Mode's enter and exit")
EventRegistry:TriggerEvent("EditMode.Enter")
local overlay = kb.EditModeOverlay
check(kb:IsShown() and overlay and overlay.shown and overlay.mouseWheel and overlay.Label.text == "Gamepad Keyboard"
	and kb.strata == "HIGH" and kb.point[1] == "CENTER" and kb.scale == 1,
	"Edit Mode: the keyboard shows (middle of the screen till placed), with its own selection, under Edit Mode's panels")
check(indexOf(kb) == nil and boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton", "...not a gamepad panel, the controller's buttons left alone")
overlay.scripts.OnDragStart(overlay)
check(kb.moving, "dragging its selection moves it")
kb:ClearAllPoints(); kb:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 40, 600)
overlay.scripts.OnDragStop(overlay)
check(not kb.moving and GamepadKeyboardDB.position.point == "TOPLEFT" and GamepadKeyboardDB.position.x == 40, "...and keeps where it's put")
overlay.scripts.OnMouseWheel(overlay, 1); overlay.scripts.OnMouseWheel(overlay, 1)
check(S.scale:GetValue() == 1.1 and kb.scale == 1.1 and kb.point[4] == 40 / 1.1, "the mouse wheel over it: bigger, in steps, the same spot")
for _ = 1, 3 do overlay.scripts.OnMouseWheel(overlay, -1) end
check(S.scale:GetValue() == 0.95, "...smaller in the same steps, exact sizes")
S.scale:SetValue(0.83); overlay.scripts.OnMouseWheel(overlay, 1)
check(S.scale:GetValue() == 0.9, "...from a size between steps: the nearest step, then one more")
for _ = 1, 20 do overlay.scripts.OnMouseWheel(overlay, -1) end
check(S.scale:GetValue() == 0.6, "...not smaller than the smallest size")
S.scale:SetValue(1)
padA(function() nameBox:SetFocus() end) -- the controller on a text box meanwhile: nothing of typing
check(kb:IsShown() and overlay.shown and indexOf(kb) == nil and preview() == "|", "a text box focused in Edit Mode: it stays a preview")
EventRegistry:TriggerEvent("EditMode.Exit")
check(not kb:IsShown() and not overlay.shown and kb.strata == "FULLSCREEN_DIALOG", "leaving Edit Mode: it goes, back on its own layer")
poll(); poll()
check(not kb:IsShown(), "...and doesn't open for the box focused in Edit Mode")
nameBox:ClearFocus(); poll()
openChat("SAY"); poll()
check(kb:IsShown() and kb.point[1] == "TOPLEFT" and kb.point[4] == 40 and not overlay.shown, "next time it opens where it was put")
type("hi")
EventRegistry:TriggerEvent("EditMode.Enter")
check(overlay.shown and chatBox:GetText() == "Hi" and preview() == "|", "Edit Mode while typing: the keyboard becomes the preview, the text stays in the box")
EventRegistry:TriggerEvent("EditMode.Exit")
chatBox.text = ""; chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
GamepadKeyboardDB.position = nil

-- ---- the D-pad ---------------------------------------------------------------------------------------------------
padA(function() nameBox:SetFocus() end)
local function jump(k, dir) return overrides[key(k)] and overrides[key(k)][dir] end
check(jump("q", "right") == key("w") and jump("p", "right") == true and jump("q", "left") == true, "left / right along a row, stopping at its ends")
check(jump("w", "down") == key("s") and jump("s", "up") == key("w"), "up / down between rows, to the nearest key")
check(jump("b", "down") == key("SPACE") and jump("SPACE", "up") ~= nil, "down to the wide Space bar and back up")
kb:Hide(); nameBox:ClearFocus(); poll()

-- ---- when it doesn't open ------------------------------------------------------------------------------------------
world.combat = true
openChat("SAY"); poll()
check(not kb:IsShown(), "in combat: doesn't open (Blizzard's gamepad UI takes no addon windows then)")
world.combat = false
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
style = 0
openChat("SAY"); poll()
check(not kb:IsShown(), "keyboard and mouse: doesn't open")
style = 1
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
local secret = W.CreateFrame("EditBox", nil, UIParent); secret.forbidden = true; secret:SetAutoFocus(false)
padA(function() secret:SetFocus() end)
check(not kb:IsShown(), "a forbidden box (Blizzard's store and such): doesn't open")
secret:ClearFocus(); poll()
SlashCmdList.GAMEPADKEYBOARD("off")
openChat("SAY"); poll()
check(not kb:IsShown() and S.autoOpen:GetValue() == false, "/gk off: doesn't open (and the options show it off)")
SlashCmdList.GAMEPADKEYBOARD("on")
check(S.autoOpen:GetValue() == true, "/gk on: on again")
SlashCmdList.GAMEPADKEYBOARD("")
check(optionsPanel.opened == 4242, "/gk: opens its options")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- combat starting while typing ----------------------------------------------------------------------------------
openChat("PARTY"); poll()
type("go"); playerClick(key("ENTER")) -- a line sent just before
check(macros[#macros] == "/p Go", "(a line sent before combat)")
poll()
openChat("PARTY"); poll()
type("pull")
W.fireEvent("PLAYER_REGEN_DISABLED")
world.combat = true
poll()
check(not kb:IsShown() and chatBox:GetText() == "Pull" and chatBox.attrs.chatType == "PARTY", "combat starts: the keyboard closes, the text and chat type stay")
check((W.blockedMessages or 0) == 0 and boundTo("PAD4") == "CLICK Blizzard_PAD4:LeftButton" and boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton",
	"...A / X / Y / LB / RB the controller UI's again, nothing blocked")
before = #macros
check(pcall(secureClick, enter) and #macros == before, "its Enter pressed in combat somehow: nothing set on it, nothing sent")
world.combat = false
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
-- Blizzard refusing the hide as combat starts: retried after combat.
openChat("SAY"); poll()
refuse = true
W.fireEvent("PLAYER_REGEN_DISABLED")
refuse = false
check(not kb:IsShown() and indexOf(kb) ~= nil, "refused as combat started: still listed by Blizzard")
W.fireEvent("PLAYER_REGEN_ENABLED")
check(indexOf(kb) == nil, "...and removed after combat")

-- Our frames never carry fields Blizzard's focus manager or SmartNavigation read without a taint barrier.
local unsafe = { "returnToPlayerControl", "FrameControlManagerGroup", "skipGamepadAutoFocus", "disableFrameFocusPagingWhenFocused",
	"useCustomNavigation", "skipFrameDeactivation", "dismissOnUnfocus", "smartNavigationProxyTarget", "isFocused", "lockedFocus" }
local found = {}
for _, f in ipairs(W.frames) do
	if f == kb or f.parent == kb then for _, k in ipairs(unsafe) do if rawget(f, k) ~= nil then found[#found + 1] = k end end end
end
check(#found == 0, "no unbarriered Blizzard gamepad fields on our frames (" .. table.concat(found, ", ") .. ")")
check(#W.violations == 0, "nothing done that Blizzard's widgets refuse (" .. table.concat(W.violations, ", ") .. ")")
check(#poisoned == 0, "no chat send function was ever called")

H.finish()
