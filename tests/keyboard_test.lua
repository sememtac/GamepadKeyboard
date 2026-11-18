-- Gamepad Keyboard tests. Run from the repo root: luajit tests/keyboard_test.lua (or nvim -l).
-- The focus manager and the chat box follow Blizzard's code (FrameControlsManager.lua, ChatFrameEditBox.lua,
-- FloatingChatFrame.lua). Every chat send function is poisoned: the keyboard must never call one.
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local W = dofile(lib .. "widgets.lua")
local check = H.check

-- ---- a small game world -------------------------------------------------------------------------------
local world = { combat = false, printed = {}, party = false, raid = false, instance = false, guild = false }
W.install({ inCombat = function() return world.combat end, addonFile = "GamepadKeyboard.lua",
	sourceLocation = "Interface/AddOns/SomeAddon/SomeAddon.lua:1" })
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
-- Whose a frame is: issecurevariable(name) - a global set by Blizzard's code is secure, one an addon set
-- names the addon - and GetSourceLocation, the file it was made in. Frames the test makes are an addon's
-- unless marked Blizzard's. (No issecurevalue: on a value an addon reads it never says Blizzard's.)
local blizzardGlobals = {}
local function blizzardFrame(f)
	blizzardGlobals[f:GetName() or ""] = true
	f.sourceLocation = "Interface/AddOns/Blizzard_Test/Test.xml:1"
	return f
end
function issecurevariable(t, k)
	if k == nil then t, k = _G, t end
	if t ~= _G then return true end
	if blizzardGlobals[k] then return true end
	return false, "SomeAddon"
end
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
local classicChat = false -- the "classic" chat style: Deactivate hides the box, ActivateChat shows it
chatBox.scripts.OnEditFocusLost = function(self)
	if self:GetText() == "" then
		self.attrs.chatType, self.attrs.tellTarget, self.deactivated = self.attrs.stickyType, nil, true
		if classicChat then self:Hide() end
	end
end
chatBox.scripts.OnEditFocusGained = function(self) -- (ChatFrameUtil.ActivateChat)
	self.deactivated = nil
	if classicChat then self:Show() end
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
	elseif command == "/W" then
		local name, rest = msg:match("^(%S+)%s(.*)$")
		if name then
			self.attrs.chatType, self.attrs.tellTarget = "WHISPER", name
			self:SetText(rest)
		end
	end
end
chatFrame.editBox = chatBox
-- ChatFrameEditBoxBaseMixin's setters (attributes) and the header (ChatFrameEditBoxMixin:UpdateHeader).
function chatBox:SetChatType(chatType) self.attrs.chatType = chatType end
function chatBox:SetTellTarget(tellTarget) self.attrs.tellTarget = tellTarget end
function chatBox:UpdateHeader() self.header = self.attrs.chatType .. ":" .. tostring(self.attrs.tellTarget) end
-- The keyboard never writes into Blizzard's chat box: what that sets off there (OnTextChanged's fields, the
-- chat type's parsing, focus scripts) runs as the addon's doing and stays so - read by Blizzard's own chat
-- later, and on into the controller's bindings (blocked). Reads, and the sticky chat type (an attribute,
-- which comes back clean), only. Each write from GamepadKeyboard.lua is noted with its line.
local chatWrites = {}
for _, name in ipairs({ "SetText", "Insert", "SetTellTarget", "SetChatType", "UpdateHeader", "SetFocus", "ClearFocus",
	"SetCursorPosition", "HighlightText" }) do
	local own = rawget(chatBox, name)
	chatBox[name] = function(self, ...)
		local caller = debug.getinfo(2, "Sl")
		if caller and caller.source:find("GamepadKeyboard.lua", 1, true) then
			chatWrites[#chatWrites + 1] = name .. "@" .. caller.currentline
		end
		return (own or getmetatable(self).__index[name])(self, ...) -- (the class's, hooks and all)
	end
end
function chatFrame:FocusGamepad() chatBox:SetFocus() end
function chatFrame:UnfocusGamepad() chatBox:ClearFocus() end
function chatFrame:SetGamepadFocus() GamepadMode.FrameControlsManager:FrameShown(self) end -- the menu dial's Chat
-- A menu's Whisper (ChatFrameUtil.SendTellWithMessage): "/w Name " into the chat box, parsed (it ends empty).
local function blizzardSendTell(name) chatBox:SetText("/w " .. name .. " ") end
local menuDialChat -- set below
local function openChat(chatType, tellTarget, channelTarget)
	chatBox.attrs.chatType, chatBox.attrs.tellTarget, chatBox.attrs.channelTarget, chatBox.deactivated = chatType, tellTarget, channelTarget, nil
	menuDialChat()
end
ChatTypeInfo = { SAY = { sticky = 1 }, PARTY = { sticky = 1 }, CHANNEL = { sticky = 1 }, WHISPER = { sticky = 0 } }
local poisoned = {}
local function poison(name) return function() poisoned[#poisoned + 1] = name; error(name .. " must not be called by the keyboard") end end
for _, name in ipairs({ "SendMessage", "SendText", "ClearChat", "Deactivate", "ParseText" }) do chatBox[name] = poison("editBox:" .. name) end
-- (GetLastTellTarget and GetActiveWindow only read. InsertLink, a shift-click's: into the active chat box -
-- ACTIVE_CHAT_EDIT_BOX, which deactivating clears - else nowhere; the keyboard only hooks it.)
ChatFrameUtil = setmetatable({
	GetLastTellTarget = function() return lastTell, lastTellType end,
	GetActiveWindow = function() return not chatBox.deactivated and chatBox or nil end,
	InsertLink = function(link)
		local active = ChatFrameUtil.GetActiveWindow()
		if active then active.text = active.text .. link; active:SetFocus(); return true end
		return false
	end,
}, { __index = function(_, k) return poison("ChatFrameUtil." .. k) end })
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

-- Blizzard's Settings API. A canvas page: the addon's own frame, which the panel shows (frame:Show(), no
-- isolation - so no OnShow) and whose OnRefresh / OnDefault it calls isolated. Blizzard's list controls are
-- off limits: the panel keeps their data as the addon wrote it, and redraws them as it hides, right before
-- SaveBindings (Blizzard UI only) - the "blocked from an action only available to the Blizzard UI" dialog.
-- Opening the panel from addon code is off limits too: its open event fires inside the call, so the panel
-- opens as the addon's doing.
local optionsPanel = { registered = 0 }
local function offLimits(name) return function() error(name .. ": list controls taint the Settings panel's hide (SaveBindings)") end end
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		optionsPanel.registered = optionsPanel.registered + 1
		optionsPanel.frame = frame
		optionsPanel.category = { name = name, GetID = function() return 4242 end }
		return optionsPanel.category
	end,
	RegisterAddOnCategory = function(category) optionsPanel.addOnCategory = category end,
	OpenToCategory = function() error("OpenToCategory: the panel would open as the addon's doing") end,
	RegisterVerticalLayoutCategory = offLimits("RegisterVerticalLayoutCategory"),
	RegisterAddOnSetting = offLimits("RegisterAddOnSetting"),
	CreateCheckbox = offLimits("CreateCheckbox"),
	CreateSlider = offLimits("CreateSlider"),
	CreateDropdown = offLimits("CreateDropdown"),
}
GameTooltip = { SetOwner = function() end, SetText = function() end, Show = function() end, Hide = function() end }

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
-- The options page, and S: each option as the player changes it there (a click on its checkbox or layout
-- button, steps of the - / + buttons).
local page = optionsPanel.frame
local DEFAULT_VALUES = { autoOpen = true, closeOnEnter = true, chatCapital = true, names = true, holdTime = 0.5, scale = 1, layout = "qwerty" }
local function optionValue(key) local v = GamepadKeyboardDB[key]; if v == nil then return DEFAULT_VALUES[key] end; return v end
local S = setmetatable({}, { __index = function(_, key)
	return {
		GetValue = function() return optionValue(key) end,
		SetValue = function(_, value)
			if page.Checks[key] then
				if (optionValue(key) and true or false) ~= value then page.Checks[key]:Click() end
			elseif key == "layout" then
				for _ = 1, #page.LayoutDropdown.radios do
					if optionValue(key) ~= value then page.LayoutDropdown.parent:OnSmartNavClick() end -- A on it: the next one
				end
			else
				local stepper, step = page.Steppers[key], key == "scale" and 0.05 or 0.1
				for _ = 1, 40 do
					local diff = value - optionValue(key)
					if math.abs(diff) < step / 2 then break end
					(diff > 0 and stepper.Plus or stepper.Minus):Click()
				end
				assert(math.abs(optionValue(key) - value) < 1e-9, "a value the steppers can't reach: " .. tostring(value))
			end
		end,
	}
end })
check(optionsPanel.addOnCategory and optionsPanel.addOnCategory.name == "Gamepad Keyboard" and optionsPanel.registered == 1 and page,
	"Options > AddOns > Gamepad Keyboard: its own page")
check(page.Checks.autoOpen and page.Checks.closeOnEnter and page.Checks.chatCapital and page.Checks.names
	and page.LayoutDropdown and page.Steppers.holdTime and page.Steppers.scale,
	"...open with the controller, keyboard layout (QWERTY / Dvorak), close after Enter, capital, names, hold time, size")
check(page.scripts.OnShow == nil and page.OnRefresh and page.OnDefault, "...no OnShow (the panel shows it unguarded); refresh and defaults for the panel")
check(page.Checks.autoOpen.checked and page.Checks.closeOnEnter.checked and page.LayoutDropdown.text == "QWERTY"
	and page.Steppers.holdTime.Value.text == "0.5 s" and page.Steppers.scale.Value.text == "100%", "...showing the defaults")
check(next(savedTable) == nil, "...nothing written to the saved table until something's changed")
-- Keyboard layout: Blizzard's Options dropdown (with < > steppers).
local layoutControl, layoutDropdown = page.LayoutDropdown.parent, page.LayoutDropdown
check(layoutControl.template == "SettingsDropdownWithButtonsTemplate" and #layoutDropdown.radios == 2
	and layoutDropdown.radios[1].text == "QWERTY" and layoutDropdown.radios[2].text == "Dvorak",
	"Keyboard layout: the Options dropdown (with < >), QWERTY or Dvorak")
check(layoutControl:OnSmartNavClick() and savedTable.layout == "dvorak" and layoutDropdown.text == "Dvorak",
	"...A on it with the controller: the next layout, Dvorak, saved and shown")
check(layoutControl:OnSmartNavClick() and savedTable.layout == "qwerty" and layoutDropdown.text == "QWERTY", "...again: round to QWERTY")
layoutDropdown:MouseDown(); layoutDropdown:MouseUp()
check(savedTable.layout == "dvorak" and layoutDropdown.text == "Dvorak", "...a click on it: the next one too")
check(not layoutDropdown.menusOpened and not layoutDropdown:IsMenuOpen(),
	"...and no Blizzard menu ever opened from here (one opened by an addon taints the controller UI's focus manager)")
layoutControl.DecrementButton:Click()
check(savedTable.layout == "qwerty" and layoutDropdown.text == "QWERTY", "...the < stepper: back to QWERTY")
layoutControl.IncrementButton:Click()
check(savedTable.layout == "dvorak", "...the > stepper: Dvorak")
layoutControl.IncrementButton:Click()
check(savedTable.layout == "dvorak" and not layoutDropdown.menusOpened, "...> at the last one: stays (as Blizzard's), no menu")
page.OnDefault(page)
check(savedTable.layout == "qwerty" and layoutDropdown.text == "QWERTY", "...Defaults: QWERTY, shown")
W.fireEvent("ADDON_LOADED", "GamepadKeyboard")
check(optionsPanel.registered == 1, "(registered once)")
page.Steppers.holdTime.Plus:Click(); page.Steppers.holdTime.Plus:Click()
check(savedTable.holdTime == 0.7 and page.Steppers.holdTime.Value.text == "0.7 s", "the hold time's + : in tenths of a second, shown")
for _ = 1, 20 do page.Steppers.holdTime.Minus:Click() end
check(savedTable.holdTime == 0.3, "...not under 0.3 s")
savedTable.holdTime = 0.55; page.Steppers.holdTime.Plus:Click()
check(savedTable.holdTime == 0.7, "...from a time between steps: the nearest step, then one more")
page.Checks.names:Click()
check(savedTable.names == false and not page.Checks.names.checked, "a checkbox: off")
page.OnDefault(page)
check(savedTable.holdTime == 0.5 and savedTable.names == true and page.Checks.names.checked and page.Steppers.holdTime.Value.text == "0.5 s",
	"Defaults (the panel's button): all back")
savedTable.closeOnEnter = false; page.OnRefresh(page)
check(not page.Checks.closeOnEnter.checked, "Refresh: the page shows what's saved")
savedTable.closeOnEnter = nil; page.OnRefresh(page)
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
-- Done with chat: the keyboard's line dropped as a player would (RB to its end, X till it's empty, B - an
-- unsent line would wait for the next chat), then the chat closed.
local function endChat()
	local kb = keyboard()
	if not kb:IsShown() then
		chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
		openChat("SAY"); poll()
	end
	if kb:IsShown() then
		for _ = 1, 300 do if preview():sub(-1) == CARET then break end pad("PADRSHOULDER") end
		for _ = 1, 300 do if preview() == CARET then break end pad("PAD3") end
		kb:SmartNavigationCloseHandler()
	end
	chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
end

-- ---- chat: a whisper reply ----------------------------------------------------------------------------------
openChat("WHISPER", "Bob"); poll()
local kb = keyboard()
local ring = kb.HoldPrompt and kb.HoldPrompt.icon -- the footer's press-and-hold glyph
check(kb and kb.point and kb.point[1] == "BOTTOMLEFT" and kb.point[2] == chatFrame and kb.point[3] == "BOTTOMRIGHT",
	"for chat it opens beside the chat window, not over it")
check(kb and kb:IsShown(), "chat box focused with the controller: the keyboard opens")
check(indexOf(kb) ~= nil and manager.focusedFrame == kb and manager.popupReturnFrames[kb] == chatFrame,
	"as a popup in Blizzard's gamepad UI, returning to the chat")
check(not chatBox:HasFocus() and chatBox:GetText() == "" and key("CHAT").text == "To Bob",
	"the chat box is left as Blizzard leaves it (emptied, back to its usual chat as it lost focus); the keyboard keeps the whisper to Bob")
check(key("SHIFT").locked, "an empty chat line starts with Shift on")
type("hi"); playerClick(key("SPACE")); type("there")
check(preview() == "Hi there" .. CARET and chatBox:GetText() == "",
	"keys type into the keyboard's own line (its preview), never into the chat box - first letter capital")
playerClick(key("BACK"))
check(preview() == "Hi ther" .. CARET, "Del removes the last letter")
kb:SmartNavigationCloseHandler() -- B
check(not kb:IsShown() and indexOf(kb) == nil, "B closes the keyboard")
check(manager.focusedFrame == chatFrame and chatBox:HasFocus() and chatBox:GetText() == "" and #macros == 0,
	"...and the controller is back on the chat box, nothing sent")
poll(); poll()
check(not kb:IsShown(), "it doesn't open again for the box it went back to")
check(#poisoned == 0, "the keyboard never called a chat send function")
-- Back on the chat box, choosing Chat on the menu dial again (the chat is already the focused optionsPanel, so
-- nothing changes focus): the keyboard comes back.
menuDialChat(); poll()
check(kb:IsShown() and preview() == "Hi ther" .. CARET and key("CHAT").text == "To Bob",
	"Chat chosen again while back on the chat box: the keyboard comes back with the line, still to Bob")
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
check(preview() == CARET and key("CHAT").text == "Say", "...with an empty line (the last one was sent), in the chat box's chat")
kb:SmartNavigationCloseHandler()
check(not kb:IsShown() and chatBox:GetText() == "" and chatBox:HasFocus(), "B with nothing typed: back to the empty chat box")
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
playerClick(key("SYMBOLS")); playerClick(key("/")); playerClick(key("LETTERS")); type("p hi")
check(preview() == "/p hi" .. CARET and key("CHAT").text == "Say", "a typed /p stays in the line (the chat key switches chats)")
playerClick(key("ENTER"))
check(macros[#macros] == "/p hi", "...and Enter runs it as typed: to party")
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
-- A chat no macro line can say: no keyboard - Blizzard sends those only from its own chat box.
before = #macros
openChat("VOICE_TEXT"); poll()
check(not kb:IsShown() and world.printed[#world.printed]:find("VOICE_TEXT", 1, true), "a chat a macro line can't say (voice text): no keyboard, a note why")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
-- A line stops at what one chat line holds with its command.
openChat("WHISPER", "Bob"); poll()
for _ = 1, 260 do playerClick(key("x")) end
playerClick(key("ENTER"))
check(macros[#macros] == "/w Bob X" .. string.rep("x", 247) and #macros[#macros] == 255, "a line stops at 255 letters with its /w Bob")
poll()
lastTell, lastTellType = "Bobby-Realm", "WHISPER"
openChat("SAY"); poll()
for _ = 1, 260 do playerClick(key("x")) end
before = #macros
playerClick(key("CHAT")); playerClick(key("ENTER"))
check(#macros == before and kb:IsShown() and world.printed[#world.printed]:find("too long", 1, true),
	"switched to a whisper whose /w makes it too long: nothing sent, the keyboard stays, a note why")
lastTell, lastTellType = nil, nil
endChat()

-- ---- pages, shift, limits -------------------------------------------------------------------------------------
openChat("SAY"); poll()
playerClick(key("SHIFT"))
check(not key("SHIFT").locked and key("a").text == "a", "Shift toggles back off")
playerClick(key("SHIFT"))
check(key("a").text == "A", "Shift shows capitals")
type("o"); type("k")
check(preview() == "Ok" .. CARET and key("a").text == "a", "Shift lasts one letter")
playerClick(key("SYMBOLS"))
check(key("q") == nil and key("!") ~= nil and key("LETTERS") ~= nil, "?123 shows the symbols")
playerClick(key("!")); playerClick(key("LETTERS"))
check(preview() == "Ok!" .. CARET and key("q") ~= nil, "a symbol, then ABC back to letters")
local hasPipe = false
for _, f in ipairs(W.frames) do if f.key == "|" then hasPipe = true end end
check(not hasPipe, "no | key (the game reads it as an escape code)")
keyboardKey("ESCAPE")
check(not kb:IsShown() and manager.focusedFrame == chatFrame, "closed by Escape on a real keyboard: same as B")
menuDialChat(); poll()
check(kb:IsShown() and preview() == "Ok!" .. CARET, "...the line kept for next time")
endChat()

-- ---- the controller's X, Y, LB, RB: Del, Space, the cursor ---------------------------------------------------------
check(boundTo("PAD3") == "CLICK Blizzard_PAD3:LeftButton", "(the controller UI's own X before the keyboard opens)")
openChat("SAY"); poll()
check(boundTo("PAD3") == "CLICK GamepadKeyboardDelKey:LeftButton" and boundTo("PAD4") == "CLICK GamepadKeyboardSpaceKey:LeftButton"
	and boundTo("PADLSHOULDER") == "CLICK GamepadKeyboardCursorLeft:LeftButton" and boundTo("PADRSHOULDER") == "CLICK GamepadKeyboardCursorRight:LeftButton",
	"with the keyboard open: X Del, Y Space, LB / RB the cursor")
type("hi"); pad("PAD4"); type("you")
check(preview() == "Hi you" .. CARET and chatBox:GetText() == "", "Y types a space")
pad("PAD3")
check(preview() == "Hi yo" .. CARET, "X deletes")
pad("PADLSHOULDER"); pad("PADLSHOULDER")
check(preview() == "Hi " .. CARET .. "yo", "LB moves the cursor left (the preview shows it)")
type("t")
check(preview() == "Hi t" .. CARET .. "yo", "keys type at the cursor")
pad("PAD3"); pad("PAD3")
check(preview() == "Hi" .. CARET .. "yo", "X deletes the letter before the cursor")
for _ = 1, 5 do pad("PADLSHOULDER") end
check(preview() == CARET .. "Hiyo", "...not past the start")
pad("PAD3")
check(preview() == CARET .. "Hiyo", "X at the start: nothing to delete")
for _ = 1, 6 do pad("PADRSHOULDER") end
check(preview() == "Hiyo" .. CARET, "RB moves it right, not past the end")
pad("PADLSHOULDER"); playerClick(key("SYMBOLS")); pad("PAD4"); playerClick(key("!")); pad("PAD3")
check(preview() == "Hiy " .. CARET .. "o", "on the symbols page too (Space, Del)")
playerClick(key("LETTERS"))
pad("PADLSHOULDER")
playerClick(key("CHAT"))
check(key("CHAT").text == "Say" and preview() == "Hiy" .. CARET .. " o", "the chat key keeps the cursor")
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
menuDialChat(); poll()
check(preview() == "Hiy o" .. CARET, "...and X doesn't touch the line then")
endChat()
openChat("SAY"); poll()
local long = "A" .. string.rep("abcdefghij", 6):sub(2) -- 60 letters (the first a capital)
type(long)
check(preview() == "..." .. long:sub(13) .. CARET, "a long line: the preview shows the 48 letters before the cursor")
for _ = 1, 50 do pad("PADLSHOULDER") end
check(preview() == long:sub(1, 10) .. CARET .. long:sub(11, 48) .. "...", "...and with the cursor near the start, the start")
type("x")
check(preview() == long:sub(1, 10) .. "x" .. CARET .. long:sub(11, 47) .. "...", "(typed at the cursor in a long line)")
playerClick(key("ENTER"))
check(macros[#macros] == "/s " .. long:sub(1, 10) .. "x" .. long:sub(11), "...and the whole line is sent")
poll()

-- ---- holding A: Enter ---------------------------------------------------------------------------------------------
openChat("PARTY"); poll()
check(boundTo("PAD1") == "CLICK GamepadKeyboardAButton:LeftButton", "with the keyboard open, A is the keyboard's (a tap types, a hold sends)")
type("hold")
check(preview() == "Hold" .. CARET, "(a tap types the key the D-pad is on, as A did)")
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
check(#macros == before and preview() == "Oka" .. CARET and kb:IsShown() and not ring.holding, "a press shorter than the hold: a tap (the ring stops)")
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
check(preview() == CARET and kb:IsShown(), "a tap on a key that's hidden now (another page): nothing")
playerClick(key("LETTERS"))
endChat()
-- The release of an A whose press went to the controller UI (the A that opened the keyboard): nothing.
openChat("SAY"); poll()
type("x")
secureClick(GamepadKeyboardAButton, false); poll()
check(preview() == "X" .. CARET and kb:IsShown() and #macros == before + 1, "a release without its press on the keyboard: nothing")
endChat()
openChat("SAY"); poll()
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true); poll()
kb:SmartNavigationCloseHandler(); held.PAD1 = nil; chatBox.text = ""; manager:FrameHidden(chatFrame)
check(not ring.holding, "closed while A is held: the ring stops")
for _ = 1, 40 do poll() end
openChat("SAY"); poll(); poll()
check(not key("ENTER").locked, "closed while A is held: not a hold the next time it opens")
endChat()
-- A name box: holding A is its own Enter.
local holdBox = W.CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
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
check(overrides[nameKeys()[1]].up == key("SYMBOLS") and overrides[key("SYMBOLS")].down == nameKeys()[1]
	and overrides[nameKeys()[4]].right == nameKeys()[1], "the names are the top row for wrapping round too")
playerClick(nameKeys()[2])
check(mailTo:GetText() == "Bobby" and shownNames() == "" and preview() == "Bobby|", "A on a name: it's put in (and nothing left to pick)")
check(overrides[key("1")].up == key("SYMBOLS"), "...and up from the keys wraps to the bottom row again")
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

-- Leaving the chat box for another box: the chat line waits.
openChat("SAY"); poll()
type("hey")
manager:FrameShown(mail); focus(mail); poll()
padA(function() mailTo:SetFocus() end)
check(kb:IsShown() and preview() == "|" and mailTo:GetText() == "" and chatBox:GetText() == "" and key("CHAT") == nil,
	"leaving the chat box for To:: it types in To: (its own text), no chat key")
focus(kb); poll()
padA(function() focus(chatFrame) end) -- LT to the chat window: its box gets typing focus
focus(kb); poll(); poll()
check(kb:IsShown() and key("CHAT") ~= nil and preview() == "Hey" .. CARET,
	"...and back to the chat window then: the keyboard types in chat again, the chat line back - not taken for a real keyboard's")
kb:SmartNavigationCloseHandler(); mailTo:ClearFocus(); manager:FrameHidden(mail); endChat()

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

-- Its box cleared by the game (the mail sent): the preview and the names follow at once.
manager:FrameShown(mail)
padA(function() mailTo:SetFocus() end)
type("bo")
check(preview() == "bo|" and shownNames() ~= "", "(typed in To:, names showing)")
mailTo:SetText("") -- SendMailFrame_Reset, after Send
poll()
check(preview() == "|" and shownNames() == "", "the mail sent (its boxes cleared): the preview and the names clear at once")
type("al")
check(mailTo:GetText() == "al", "...and typing starts afresh")
kb:SmartNavigationCloseHandler(); mailTo:ClearFocus(); mailTo.text = ""; manager:FrameHidden(mail); poll()
padA(function() mailBody:SetFocus() end)
type("hi"); playerClick(key("ENTER")); type("yo")
mailBody:SetText("")
poll()
check(preview() == "|" and kb:IsShown(), "...the mail's text too (several lines)")
kb:SmartNavigationCloseHandler(); mailBody:ClearFocus(); poll()
-- A link while the keyboard is up over chat (shift-click on an item): Blizzard finds no active chat box (the
-- line is the keyboard's), so it goes into the keyboard's line.
openChat("SAY"); poll()
type("look ")
check(ChatFrameUtil.GetActiveWindow() == nil, "(no active chat box while the keyboard has the line)")
ChatFrameUtil.InsertLink("[Sword]")
check(preview() == "Look [Sword]" .. CARET and chatBox:GetText() == "", "a link while the keyboard is up over chat: into its line, at the cursor")
local link = "|cff0070dd|Hitem:123|h[Shield]|h|r"
ChatFrameUtil.InsertLink(link)
playerClick(key("ENTER"))
check(macros[#macros] == "/s Look [Sword]" .. link, "...sent with it, the link whole")
poll()
openChat("SAY"); poll()
AuctionHouseFrame = W.CreateFrame("Frame", nil, UIParent)
ChatFrameUtil.InsertLink("[Sword]")
check(preview() == CARET, "...not while the auction house is open (it takes a link as a search)")
AuctionHouseFrame = nil
padA(function() focus(chatFrame) end) -- LT to the chat window: its box active again
ChatFrameUtil.InsertLink("[Axe]")
check(kb:IsShown() and chatBox:GetText() == "[Axe]" and preview() == CARET,
	"...with the chat box active (LT to it), Blizzard puts the link there: not in the keyboard's line too")
chatBox.text = ""
endChat()

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
endChat()
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
check(macros[#macros] == "/p One" and kb:IsShown() and indexOf(chatFrame) ~= nil and preview() == "|"
	and key("SHIFT").locked, "Close after Enter off: sent, the keyboard and the chat stay, ready for the next line")
type("two"); playerClick(key("ENTER"))
check(macros[#macros] == "/p Two" and key("CHAT").text == "Party" and chatBox.attrs.stickyType == "PARTY", "...the next line goes to the same chat")
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
-- Keyboard layout: Dvorak.
openChat("SAY"); poll()
local function rowOf(k) return key(k) and key(k).point[3] end
check(rowOf("q") == rowOf("w") and rowOf("a") == rowOf("s"), "(QWERTY: q w ..., a s ...)")
S.layout:SetValue("dvorak")
check(key("'") and rowOf("'") == rowOf("p") and rowOf("a") == rowOf("o") and rowOf(";") == rowOf("z") and rowOf("q") == rowOf("z")
	and rowOf("1") ~= nil and key("SPACE") and key("CHAT"), "Dvorak, at once: ' , . p y ..., a o e u i ..., ; q j k x ...; numbers and the bottom row the same")
local function jump(k, dir) return overrides[key(k)] and overrides[key(k)][dir] end
check(jump("a", "right") == key("o") and jump("s", "right") == key("a"), "...and the D-pad follows it (a, o, e ...; round from s to a)")
check(key("SHIFT").locked and key("a").text == "A", "...Shift as before")
type("hello")
check(preview() == "Hello" .. CARET, "...and types (" .. preview() .. ")")
playerClick(key("SYMBOLS")); playerClick(key("LETTERS"))
check(rowOf("a") == rowOf("o"), "?123 and back: Dvorak")
endChat()
openChat("SAY"); poll()
check(rowOf("a") == rowOf("o"), "and it opens in Dvorak next time")
S.layout:SetValue("qwerty")
check(rowOf("a") == rowOf("s") and rowOf("q") == rowOf("w"), "back to QWERTY, at once")
endChat()

-- A chat line without a capital to start.
GamepadKeyboardDB.chatCapital = false
openChat("SAY"); poll()
check(not key("SHIFT").locked, "Capital at the start of a chat line, off: Shift off")
endChat()
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
check(preview() == "Abb" .. CARET and kb:IsShown(), "...and a 0.6 s press is a tap then")
pressA(1.1)
check(not kb:IsShown() and macros[#macros] == "/s Abb", "...a 1.1 s one is Enter")
GamepadKeyboardDB.holdTime = nil
poll()

-- ---- a whisper started from a menu while the keyboard is up ------------------------------------------------------
openChat("SAY"); poll()
check(kb:IsShown() and key("CHAT").text == "Say", "(the keyboard over chat, in Say)")
padA(function() focus(chatFrame) end) -- LT to the chat window
check(kb:IsShown() and chatBox:HasFocus(), "LT to the chat window: the keyboard stays (it's the controller, not a real keyboard)")
padA(function() blizzardSendTell("Alice") end) -- Whisper, from the chat's channels menu or a name's menu
check(chatBox.attrs.chatType == "WHISPER" and chatBox.attrs.tellTarget == "Alice", "(a whisper to Alice started)")
poll()
check(key("CHAT").text == "To Alice", "a whisper started elsewhere while the keyboard is up: its line goes to her now")
padA(function() focus(kb) end) -- LT back to the keyboard: the chat box loses typing focus (and, empty, its whisper)
check(chatBox.deactivated and chatBox.attrs.chatType == "SAY" and key("CHAT").text == "To Alice",
	"LT back to the keyboard: still to Alice (the chat box going back to its usual chat isn't a change of chat)")
type("hi")
playerClick(key("ENTER"))
check(macros[#macros] == "/w Alice Hi", "...and what's typed goes to her (" .. tostring(macros[#macros]) .. ")")
poll()
-- The whisper started with the keyboard closed (with the mouse, say), the keyboard brought up after.
chatBox.attrs.chatType, chatBox.deactivated = "SAY", nil
mouseClick(function() chatFrame:SetGamepadFocus() end)
blizzardSendTell("Bob")
check(chatBox:HasFocus() and not kb:IsShown() and chatBox.attrs.tellTarget == "Bob" and chatBox:GetText() == "", "(a whisper to Bob, chat open, no keyboard)")
menuDialChat(); poll()
check(kb:IsShown() and key("CHAT").text == "To Bob", "Chat on the menu dial then: the keyboard comes, to Bob")
type("yo"); playerClick(key("ENTER"))
check(macros[#macros] == "/w Bob Yo", "...and it goes to him")
poll()
-- A line waiting in Say, then a whisper started (a name's menu): the line goes to the whisper.
openChat("SAY"); poll()
type("later"); kb:SmartNavigationCloseHandler()
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("WHISPER", "Carol"); poll()
check(kb:IsShown() and preview() == "Later" .. CARET and key("CHAT").text == "To Carol",
	"a line waiting, and a whisper just started: the line goes to the whisper")
endChat()
-- A Battle.net whisper started while the keyboard is up (the friends list): Blizzard sends those only from its
-- own chat box - the keyboard steps aside, the line waits.
openChat("SAY"); poll()
type("hey")
chatBox.attrs.chatType, chatBox.attrs.tellTarget = "BN_WHISPER", "|Kq3|k"
poll()
check(not kb:IsShown() and world.printed[#world.printed]:find("Battle.net whispers", 1, true),
	"a Battle.net whisper started while it's up: it steps aside, a note why")
chatBox.attrs.chatType, chatBox.attrs.tellTarget = "SAY", nil
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
check(kb:IsShown() and preview() == "Hey" .. CARET and key("CHAT").text == "Say", "...the line waits, in its own chat")
endChat()
local notesBefore = #world.printed
openChat("BN_WHISPER", "|Kq1|k"); poll()
check(not kb:IsShown() and #world.printed == notesBefore, "opened on a Battle.net whisper (its name may be a protected string): no keyboard (said once)")
chatBox.attrs.chatType = "SAY"; chatBox.text = ""; chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
-- The classic chat style: the chat box hides as it empties - the keyboard stays (its window is up).
classicChat = true
openChat("PARTY"); poll()
check(kb:IsShown() and not chatBox:IsShown(), "classic chat style: the chat box hides as the keyboard takes over; the keyboard stays")
type("ok"); playerClick(key("ENTER"))
check(macros[#macros] == "/p Ok", "...and sends")
poll()
openChat("SAY"); poll()
chatFrame:Hide(); poll()
check(not kb:IsShown(), "...the chat window closed: the keyboard goes")
chatFrame:Show(); classicChat = false; chatBox:Show()
endChat()

-- ---- Blizzard's Settings panel: not for the keyboard ---------------------------------------------------------------
SettingsPanel = blizzardFrame(W.CreateFrame("Frame", "SettingsPanel", UIParent))
local settingsSearch = W.CreateFrame("EditBox", nil, SettingsPanel, "InputBoxTemplate") -- (its own source: an addon's, say)
settingsSearch.center = { 400, 700 }
local bindingsPage = W.CreateFrame("Frame", nil, SettingsPanel)
local bindingsSearch = W.CreateFrame("EditBox", nil, bindingsPage, "InputBoxTemplate")
bindingsSearch.center = { 400, 600 }
manager:FrameShown(SettingsPanel)
padA(function() settingsSearch:SetFocus() end)
check(not kb:IsShown(), "the Options search box: no keyboard (what's typed there would get the panel's close blocked)")
check(world.printed[#world.printed]:find("game's own text box", 1, true), "...and it says why")
settingsSearch:ClearFocus(); poll()
padA(function() bindingsSearch:SetFocus() end)
check(not kb:IsShown(), "...nor any text box inside the Options panel")
bindingsSearch:ClearFocus(); poll()
local outside = W.CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
outside.center = { 400, 500 }
padA(function() outside:SetFocus() end)
check(kb:IsShown(), "(a text box elsewhere: as before)")
padA(function() focus(SettingsPanel) end)
padA(function() settingsSearch:SetFocus() end)
check(not kb:IsShown(), "focus moving to the Options search box while it's open: it steps aside")
settingsSearch:ClearFocus(); outside:ClearFocus(); manager:FrameHidden(SettingsPanel); poll()
SettingsPanel = nil
-- The rule: chat, the mail's boxes, and boxes another addon made - by the first named frame up, else the file.
local bags = blizzardFrame(W.CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent))
local bagSearch = blizzardFrame(W.CreateFrame("EditBox", "BagItemSearchBox", bags, "InputBoxTemplate"))
bagSearch.center = { 400, 300 }
bagSearch.scripts.OnTextChanged = function() end -- BagSearch_OnTextChanged: SetItemSearch, a synchronous inventory event
manager:FrameShown(bags)
local printed = #world.printed
padA(function() bagSearch:SetFocus() end)
check(not kb:IsShown() and #world.printed == printed + 1 and world.printed[#world.printed]:find("BagItemSearchBox", 1, true),
	"the bag search box (Blizzard's): no keyboard, and a note saying why")
bagSearch:ClearFocus(); poll()
padA(function() bagSearch:SetFocus() end)
check(not kb:IsShown() and #world.printed == printed + 1, "...said once, not every time")
bagSearch:ClearFocus(); manager:FrameHidden(bags); poll()
local popup = blizzardFrame(W.CreateFrame("Frame", "StaticPopup1", UIParent))
local popupBox = blizzardFrame(W.CreateFrame("EditBox", "StaticPopup1EditBox", popup, "InputBoxTemplate"))
popupBox.center = { 400, 600 }
popupBox.scripts.OnEnterPressed = function() end -- StaticPopup_EditBoxOnEnterPressed: accepts the dialog
manager:FrameShown(popup)
padA(function() popupBox:SetFocus() end)
check(not kb:IsShown(), "a confirmation popup's box (Blizzard's): no keyboard either")
popupBox:ClearFocus(); manager:FrameHidden(popup); poll()
local mailFrameReal = blizzardFrame(W.CreateFrame("Frame", "SendMailFrame", UIParent))
local mailSubject = blizzardFrame(W.CreateFrame("EditBox", "SendMailSubjectEditBox", mailFrameReal, "InputBoxTemplate"))
mailSubject.center = { 400, 650 }
mailSubject.scripts.OnTextChanged = function() end -- SendMailFrame_CanSend
manager:FrameShown(mailFrameReal)
padA(function() mailSubject:SetFocus() end)
check(kb:IsShown(), "the mail's boxes: Blizzard's, but looked through - yes")
kb:SmartNavigationCloseHandler(); mailSubject:ClearFocus(); manager:FrameHidden(mailFrameReal); poll()
padA(function() outside:SetFocus() end)
check(kb:IsShown(), "another addon's box (unnamed, under UIParent: made in an addon's file): yes")
kb:SmartNavigationCloseHandler(); outside:ClearFocus(); poll()
local addonWindow = W.CreateFrame("Frame", "SomeAddonWindow", UIParent)
local addonBox = W.CreateFrame("EditBox", nil, addonWindow, "InputBoxTemplate")
addonBox.center = { 400, 500 }; addonBox.sourceLocation = nil
manager:FrameShown(addonWindow)
padA(function() addonBox:SetFocus() end)
check(kb:IsShown(), "a box in an addon's named window (its global the addon's): yes")
kb:SmartNavigationCloseHandler(); addonBox:ClearFocus(); manager:FrameHidden(addonWindow); poll()
local loose = W.CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
loose.center = { 400, 500 }; loose.sourceLocation = "Interface/AddOns/Blizzard_Communities/Blizzard_CommunitiesFrame.xml:12"
padA(function() loose:SetFocus() end)
check(not kb:IsShown(), "an unnamed box made in Blizzard's own file: no")
loose:ClearFocus(); poll()
loose.sourceLocation = "Interface/FrameXML/SomeFrame.xml:3"
padA(function() loose:SetFocus() end)
check(not kb:IsShown(), "...nor one made in the game's base UI files")
loose:ClearFocus(); poll()
local unknown = W.CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
unknown.center = { 400, 500 }; unknown.sourceLocation = nil
local before = #world.printed
padA(function() unknown:SetFocus() end)
check(not kb:IsShown() and #world.printed == before + 1 and world.printed[#world.printed]:find("no telling", 1, true),
	"no way to tell whose (no named window, no source file): no keyboard, and it says so")
unknown:ClearFocus(); poll()
openChat("SAY"); poll()
check(kb:IsShown(), "...chat still")
endChat()
-- ---- boxes of numbers: the mail's money, the auction house's prices and quantities ---------------------------------
local function numberBox(name, parent, center)
	local box = W.CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	box:SetNumeric(true); box.center = center
	return box
end
local mailMoney = blizzardFrame(W.CreateFrame("Frame", "SendMailMoney", mailFrameReal))
local gold = blizzardFrame(numberBox("SendMailMoneyGold", mailMoney, { 400, 300 }))
local silver = blizzardFrame(numberBox("SendMailMoneySilver", mailMoney, { 440, 300 }))
gold:SetMaxLetters(7)
gold.scripts.OnTextChanged = function() end -- MoneyInputFrame_OnTextChanged -> SendMailFrame_CanSend
gold.scripts.OnEnterPressed = function() silver:SetFocus() end -- MoneyFrameEditBoxGold_OnEnterPressed
manager:FrameShown(mailFrameReal)
padA(function() gold:SetFocus() end)
check(kb:IsShown() and key("1") and key("0") and key("BACK") and key("ENTER") and not key("q") and not key("SPACE")
	and not key("SYMBOLS") and not key("CHAT") and not key("SHIFT") and kb.height == 84 + 2 * 34,
	"the mail's gold (a box of numbers, looked through): the keyboard opens on its numbers - the number row and Enter")
type("12"); pad("PAD4"); type("5")
check(gold:GetText() == "125" and preview() == "125" .. CARET, "...digits go in; Y's space doesn't (the box takes numbers only)")
pad("PAD3")
check(gold:GetText() == "12", "...X deletes")
S.layout:SetValue("dvorak")
check(key("1") and not key("a"), "...a change of layout leaves the numbers page alone")
S.layout:SetValue("qwerty")
playerClick(key("ENTER"))
check(silver:HasFocus() and kb:IsShown() and key("1") and preview() == CARET, "...Enter: the box's own Enter (on to silver), the keyboard follows, numbers still")
kb:SmartNavigationCloseHandler(); silver:ClearFocus(); gold.text = ""; manager:FrameHidden(mailFrameReal); poll()
-- The auction house's sell forms: unnamed boxes, found by where they are.
AuctionHouseFrame = blizzardFrame(W.CreateFrame("Frame", "AuctionHouseFrame", UIParent))
local function sellForm(key)
	local form = W.CreateFrame("Frame", nil, AuctionHouseFrame)
	form.QuantityInput = W.CreateFrame("Frame", nil, form)
	form.QuantityInput.InputBox = numberBox(nil, form.QuantityInput, { 400, 600 })
	form.PriceInput = W.CreateFrame("Frame", nil, form)
	form.PriceInput.MoneyInputFrame = W.CreateFrame("Frame", nil, form.PriceInput)
	for _, coin in ipairs({ "GoldBox", "SilverBox", "CopperBox" }) do
		form.PriceInput.MoneyInputFrame[coin] = numberBox(nil, form.PriceInput.MoneyInputFrame, { 400, 550 })
	end
	AuctionHouseFrame[key] = form
	return form
end
local itemSell, stackSell = sellForm("ItemSellFrame"), sellForm("CommoditiesSellFrame")
local ahSearch = W.CreateFrame("EditBox", nil, AuctionHouseFrame, "InputBoxTemplate"); ahSearch.center = { 400, 700 }
manager:FrameShown(AuctionHouseFrame)
for label, box in pairs({ ["an item's price (gold)"] = itemSell.PriceInput.MoneyInputFrame.GoldBox,
	["an item's price (copper)"] = itemSell.PriceInput.MoneyInputFrame.CopperBox, ["an item's quantity"] = itemSell.QuantityInput.InputBox,
	["a stack's price (silver)"] = stackSell.PriceInput.MoneyInputFrame.SilverBox, ["a stack's quantity"] = stackSell.QuantityInput.InputBox }) do
	padA(function() box:SetFocus() end)
	type("42")
	check(kb:IsShown() and key("1") and not key("q") and box:GetText() == "42", "auction house, " .. label .. ": the keyboard, on its numbers")
	kb:SmartNavigationCloseHandler(); box:ClearFocus(); box.text = ""; poll()
end
padA(function() ahSearch:SetFocus() end)
check(not kb:IsShown(), "...but not the auction house's other boxes (its search: Blizzard's, not looked through)")
ahSearch:ClearFocus(); manager:FrameHidden(AuctionHouseFrame); AuctionHouseFrame = nil; poll()
-- Another addon's box of numbers: its numbers too; a text box after it: letters again.
local addonNumbers = numberBox(nil, UIParent, { 400, 500 })
padA(function() addonNumbers:SetFocus() end)
check(kb:IsShown() and key("1") and not key("q"), "another addon's box of numbers: the numbers page")
padA(function() outside:SetFocus() end)
check(kb:IsShown() and key("q") and key("SPACE"), "...then a text box: letters again")
kb:SmartNavigationCloseHandler(); outside:ClearFocus(); poll()
-- A tap only ever clicks the keyboard's own keys.
openChat("SAY"); poll()
local clicked = 0
local otherButton = W.CreateFrame("Button", "SomeBagItem", UIParent)
otherButton.scripts.OnClick = function() clicked = clicked + 1 end
navCurrent = otherButton
pressA()
check(clicked == 0 and kb:IsShown(), "A with SmartNavigation on someone else's button (focus just moving): not clicked from here")
endChat()
-- If the game blocks the addon anyway: what, and where it last typed.
local printedBefore = #world.printed
W.fireEvent("ADDON_ACTION_FORBIDDEN", "SomeOtherAddOn", "SaveBindings()")
check(#world.printed == printedBefore, "(another addon blocked: not ours to report)")
W.fireEvent("ADDON_ACTION_FORBIDDEN", "GamepadKeyboard", "SaveBindings()")
check(#world.printed == printedBefore + 1 and world.printed[#world.printed]:find("SaveBindings()", 1, true)
	and world.printed[#world.printed]:find("Blizzard UI only", 1, true) and world.printed[#world.printed]:find("Last typed into: ChatFrame1EditBox in ChatFrame1", 1, true),
	"blocked anyway: it says what, and the last box it typed into (" .. world.printed[#world.printed] .. ")")

-- ---- the chat key ------------------------------------------------------------------------------------------------
openChat("SAY"); poll()
local chatKey = key("CHAT")
check(chatKey and chatKey.text == "Say", "chat: a chat key showing the chat type")
type("hi")
playerClick(chatKey)
check(chatKey.text == "Say" and preview() == "Hi" .. CARET, "no group, no guild, nobody to reply to: Say is all there is")
world.party, world.guild = true, true
lastTell, lastTellType = "Bob-Realm", "WHISPER"
playerClick(chatKey)
check(chatKey.text == "Party" and preview() == "Hi" .. CARET, "in a party: Party next, the text kept")
playerClick(chatKey)
check(chatKey.text == "Guild" and preview() == "Hi" .. CARET, "...then Guild")
playerClick(chatKey)
check(chatKey.text == "To Bob" and preview() == "Hi" .. CARET, "...then a reply to whoever whispered last")
playerClick(chatKey)
check(chatKey.text == "Say" and preview() == "Hi" .. CARET and #chatWrites == 0, "...and round to Say (the chat box never touched)")
playerClick(chatKey)
playerClick(key("ENTER"))
check(macros[#macros] == "/p Hi" and chatBox.attrs.stickyType == "PARTY", "Enter sends to the chat type picked")
poll()
world.raid, world.instance = true, true
openChat("SAY"); poll()
playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "Raid", "in a raid: Party, then Raid")
playerClick(key("CHAT"))
check(key("CHAT").text == "Instance", "...then Instance (an instance group)")
endChat()
world.raid, world.instance = false, false
openChat("SAY"); poll()
playerClick(key("CHAT"))
check(key("CHAT").text == "Party" and preview() == CARET and key("SHIFT").locked,
	"with nothing typed yet: switched, still nothing typed, Shift still on")
type("go")
playerClick(key("ENTER"))
check(macros[#macros] == "/p Go", "...and what's typed then goes there")
poll()
openChat("SAY"); poll()
playerClick(key("SYMBOLS"))
check(key("CHAT") ~= nil and key("CHAT").text == "Say", "the symbols page has it too")
playerClick(key("/")); playerClick(key("LETTERS")); type("g ")
check(preview() == "/g " .. CARET and key("CHAT").text == "Say", "a typed /g stays in the line (it's sent as typed)")
endChat()
openChat("WHISPER", "Alice"); poll()
check(key("CHAT").text == "To Alice", "a whisper shows who to")
type("hey")
playerClick(key("CHAT"))
check(key("CHAT").text == "To Bob", "...from a whisper to someone else, on to the reply to whoever whispered last")
playerClick(key("CHAT"))
check(key("CHAT").text == "Say", "...then round to Say")
playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "Guild", "(Party, Guild)")
playerClick(key("CHAT"))
check(key("CHAT").text == "To Alice" and preview() == "Hey" .. CARET, "...and back to the whisper the chat was opened in: offered, the text kept")
lastTell = "Alice"
playerClick(key("CHAT")); playerClick(key("CHAT")); playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "To Alice", "(round to Alice)")
playerClick(key("CHAT"))
check(key("CHAT").text == "Say", "she whispers meanwhile (the reply is to her now): offered once")
playerClick(key("CHAT")); playerClick(key("CHAT")); playerClick(key("CHAT"))
lastTell = "Bob-Realm"
playerClick(key("ENTER"))
check(macros[#macros] == "/w Alice Hey", "Enter sends it to her")
endChat()
openChat("WHISPER", "Bob-Realm"); poll()
playerClick(key("CHAT"))
check(key("CHAT").text == "Say", "the reply already picked: on to Say")
playerClick(key("CHAT")); playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "To Bob" and playerClick(key("CHAT")) == nil and key("CHAT").text == "Say",
	"...the whisper and the reply to the same person: offered once")
endChat()
-- A Battle.net whisperer to reply to: not offered (a macro line can't say it).
lastTell, lastTellType = "|Kq7|k", "BN_WHISPER"
openChat("SAY"); poll()
playerClick(key("CHAT")); playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "Say", "a Battle.net whisper to reply to: not offered (Say, Party, Guild, Say)")
endChat()
-- A whisper started in the chat box while the keyboard is up: the line goes there, and it's offered back after
-- other types.
lastTell, lastTellType = nil, nil
openChat("SAY"); poll()
playerClick(key("CHAT")); playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "Say", "a new chat: no whisper from before offered (Say, Party, Guild, Say)")
chatBox.attrs.chatType, chatBox.attrs.tellTarget = "WHISPER", "Carol" -- (a name's menu, "/w Carol " on a real keyboard)
poll()
check(key("CHAT").text == "To Carol", "a whisper started in the chat box meanwhile: the line goes to her")
playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "Party", "(Say, Party)")
playerClick(key("CHAT")); playerClick(key("CHAT"))
check(key("CHAT").text == "To Carol", "...and she's offered back too")
lastTell, lastTellType = "Bob-Realm", "WHISPER"
endChat()
openChat("WHISPER", "Christopherson"); poll()
check(key("CHAT").text == "To Christop..", "a long name is cut to fit")
endChat()
openChat("CHANNEL", nil, 2); poll()
check(key("CHAT").text == "/2", "a channel shows its number")
endChat()
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
check(kb:IsShown() and preview() == CARET and chatBox:GetText() == "Hi",
	"Chat on the menu dial then: the on-screen keyboard comes, with its own line (the real keyboard's stays in the box)")
endChat()
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
endChat()
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
check(not kb:IsShown() and chatBox:HasFocus() and chatBox:GetText() == "",
	"Enter on a real keyboard while it's open: it steps aside to the chat box (as Blizzard's Enter opens it: the line isn't put in it)")
keyboardKey("Y", "y"); keyboardKey("O", "o")
check(chatBox:GetText() == "yo" and not kb:IsShown(), "...and the real keyboard types there")
poll(); poll()
check(not kb:IsShown(), "...and it doesn't come back by itself")
chatBox.text = ""; chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
check(kb:IsShown() and preview() == "Hey" .. CARET and key("CHAT").text == "To Bob",
	"...the on-screen keyboard's line waits for it, still to Bob")
endChat()
openChat("SAY"); poll()
type("ok")
mouseClick(function() chatBox:SetFocus() end)
check(not kb:IsShown() and chatBox:HasFocus() and chatBox:GetText() == "", "a mouse click in the chat box while it's open: same")
endChat()
openChat("SAY"); poll()
keyboardKey("LSHIFT"); keyboardKey("F1")
check(kb:IsShown() and bindingsRun[#bindingsRun] == "F1", "other keys on a real keyboard while it's open: their bindings, and it stays")
endChat()
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
GamepadKeyboardDB.scale = 0.83; overlay.scripts.OnMouseWheel(overlay, 1) -- (a size between steps, as saved)
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
check(overlay.shown and preview() == "|", "Edit Mode while typing: the keyboard becomes the preview")
EventRegistry:TriggerEvent("EditMode.Exit")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
check(kb:IsShown() and preview() == "Hi" .. CARET, "...the line waits for the next time")
endChat()
GamepadKeyboardDB.position = nil
-- Edit Mode and combat: the keyboard holds secure buttons, so addon code can't hide it or change its layer then.
local blockedBefore = W.blockedMessages or 0
EventRegistry:TriggerEvent("EditMode.Enter")
W.fireEvent("PLAYER_REGEN_DISABLED"); world.combat = true
check(not kb:IsShown() and kb.strata == "FULLSCREEN_DIALOG", "Edit Mode, combat starts: the preview goes (just before the lockdown)")
EventRegistry:TriggerEvent("EditMode.Exit")
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED")
check(not kb:IsShown() and (W.blockedMessages or 0) == blockedBefore, "...Edit Mode left in combat: nothing blocked, no preview after")
EventRegistry:TriggerEvent("EditMode.Enter")
W.fireEvent("PLAYER_REGEN_DISABLED"); world.combat = true
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED")
check(kb:IsShown() and kb.EditModeOverlay.shown and kb.strata == "HIGH", "...Edit Mode still open as combat ends: the preview is back")
world.combat = true -- (combat without its start seen: a loading screen, say)
EventRegistry:TriggerEvent("EditMode.Exit")
check(kb:IsShown() and (W.blockedMessages or 0) == blockedBefore, "...left in combat with the preview up: left alone, nothing blocked")
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED")
check(not kb:IsShown() and not kb.EditModeOverlay.shown and kb.strata == "FULLSCREEN_DIALOG", "...and put away as combat ends")
world.combat = true
EventRegistry:TriggerEvent("EditMode.Enter")
check(not kb:IsShown() and (W.blockedMessages or 0) == blockedBefore, "Edit Mode opened in combat: no preview yet, nothing blocked")
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED")
check(kb:IsShown() and kb.EditModeOverlay.shown, "...shown as combat ends")
EventRegistry:TriggerEvent("EditMode.Exit")
check(not kb:IsShown(), "...and gone with Edit Mode")

-- ---- the D-pad ---------------------------------------------------------------------------------------------------
padA(function() nameBox:SetFocus() end)
local function jump(k, dir) return overrides[key(k)] and overrides[key(k)][dir] end
check(jump("q", "right") == key("w") and jump("w", "left") == key("q"), "left / right along a row")
check(jump("p", "right") == key("q") and jump("q", "left") == key("p") and jump("1", "left") == key("BACK") and jump("BACK", "right") == key("1"),
	"...wrapping round at its ends")
check(jump("w", "down") == key("s") and jump("s", "up") == key("w"), "up / down between rows, to the nearest key")
check(jump("b", "down") == key("SPACE") and jump("SPACE", "up") ~= nil, "down to the wide Space bar and back up")
check(jump("1", "up") == key("SYMBOLS") and jump("SYMBOLS", "down") == key("3") and jump("ENTER", "down").point[3] == key("1").point[3],
	"up from the top row wraps to the bottom one, down from the bottom to the top (to the nearest key)")
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
check(not kb:IsShown(), "a forbidden box (Blizzard's store and such): doesn't open, nothing asked of it but IsForbidden")
secret:ClearFocus(); poll()
openChat("SAY"); poll()
padA(function() secret:SetFocus() end)
check(not kb:IsShown(), "...moved to from the keyboard: the keyboard steps aside, nothing asked of it")
secret:ClearFocus(); chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
SlashCmdList.GAMEPADKEYBOARD("off")
openChat("SAY"); poll()
check(not kb:IsShown() and S.autoOpen:GetValue() == false, "/gk off: doesn't open (and the options show it off)")
SlashCmdList.GAMEPADKEYBOARD("on")
check(S.autoOpen:GetValue() == true, "/gk on: on again")
SlashCmdList.GAMEPADKEYBOARD("")
check(world.printed[#world.printed]:find("Options > AddOns > Gamepad Keyboard", 1, true),
	"/gk: says where its options are (opening them from an addon command would open the panel as its doing)")
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
check(not kb:IsShown() and chatBox:GetText() == "", "combat starts: the keyboard closes (the line waits)")
check((W.blockedMessages or 0) == 0 and boundTo("PAD4") == "CLICK Blizzard_PAD4:LeftButton" and boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton",
	"...A / X / Y / LB / RB the controller UI's again, nothing blocked")
before = #macros
check(pcall(secureClick, enter) and #macros == before, "its Enter pressed in combat somehow: nothing set on it, nothing sent")
world.combat = false
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
check(kb:IsShown() and preview() == "Pull" .. CARET and key("CHAT").text == "Party", "after combat: the line back, still to party")
playerClick(key("ENTER"))
check(macros[#macros] == "/p Pull", "...and sent there")
poll()
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
local seenWrites, writes = {}, {}
for _, w in ipairs(chatWrites) do if not seenWrites[w] then seenWrites[w] = true; writes[#writes + 1] = w end end
check(#chatWrites == 0, "the keyboard never wrote into Blizzard's chat box (" .. table.concat(writes, ", ") .. ")")

H.finish()
