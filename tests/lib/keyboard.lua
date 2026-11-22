-- Gamepad Keyboard tests: the world every suite runs in - the game's widgets and Blizzard's code as the addon
-- meets them, the addon loaded, and the helpers. A suite sets this file's result as its environment
-- (setfenv), then runs its sections as written. Run the suites with tests/run.sh.
-- The focus manager and the chat box follow Blizzard's code (FrameControlsManager.lua, ChatFrameEditBox.lua,
-- FloatingChatFrame.lua). Every chat send function is poisoned: the keyboard must never call one.
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") -- (this folder)
local H = dofile(lib .. "harness.lua")
local W = dofile(lib .. "widgets.lua")
local check = H.check
-- What the suites set as they go (nav cursor, whoever whispered last, the chat style, the input style, the
-- focus manager refusing): one table, so a suite's `navCurrent = x` is the world's.
local shared = {}

-- ---- a small game world -------------------------------------------------------------------------------
local world = { combat = false, printed = {}, party = false, raid = false, instance = false, guild = false }
W.install({ inCombat = function() return world.combat end,
	isAddonCaller = function(level) return H.isAddonSource(H.callerSource(level + 1)) end,
	sourceLocation = "Interface/AddOns/SomeAddon/SomeAddon.lua:1" })
function InCombatLockdown() return world.combat end
function print(s) world.printed[#world.printed + 1] = s end
function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function tinsert(t, v) table.insert(t, v) end
UISpecialFrames, SlashCmdList = {}, {}
UIParent = W.CreateFrame("Frame", "UIParent"); UIParent.height = 1000
GAMEPAD_FACE_BOTTOM, GAMEPAD_FACE_RIGHT = "PAD1", "PAD2"
Enum = { InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }
shared.style = 1
C_InputInterfaceStyle = { GetCurrentStyle = function() return shared.style end }
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
shared.lastTell, shared.lastTellType = nil, nil -- whoever whispered last
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
-- those the latest wins. The controller UI binds its buttons this way (owner UIParent), in combat too; for an
-- addon they're protected in combat (blocked).
local overrides, overrideOrder = {}, 0
local function BindingRefused()
	if world.combat and H.addonInStack(3) then
		W.blockedMessages = (W.blockedMessages or 0) + 1
		return true
	end
end
function SetOverrideBinding(owner, isPriority, k, command)
	if BindingRefused() then return end
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
	if BindingRefused() then return end
	for i = #overrides, 1, -1 do if overrides[i].owner == owner then table.remove(overrides, i) end end
end
local function boundTo(k)
	local best
	for _, o in ipairs(overrides) do
		if o.key == k and o.command ~= "" and (not best or (o.priority and not best.priority) or (o.priority == best.priority and o.order > best.order)) then best = o end
	end
	return best and best.command
end

-- Blizzard's functions wrapped for outside callers (SecureHelper:WrapFunction, SetSecureValue): called from
-- the addon in combat, the validation refuses them - nothing happens, "Interface action failed" (counted in
-- W.blockedMessages). The test's own calls stand for Blizzard's.
local function RefusedToAddon()
	if world.combat and H.isAddonSource(H.callerSource(3)) then
		W.blockedMessages = (W.blockedMessages or 0) + 1
		return true
	end
end
-- Blizzard's focus manager: popups return focus to the frame they opened over; focusing a frame unfocuses
-- the previous one (UnfocusGamepad), FocusGamepad on the new one.
shared.refuse = false
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
	if RefusedToAddon() then return end
	local i = indexOf(frame); if not i then return false end
	table.remove(self.shownFrames, i)
	local returnFrame = self.popupReturnFrames[frame]; self.popupReturnFrames[frame] = nil
	if self.focusedFrame == frame then focus(returnFrame or self.shownFrames[1]) end
	return true
end
function manager:HandlePopupShown(popup)
	self.calls[#self.calls + 1] = "popupShown"
	if shared.refuse or RefusedToAddon() then return end
	local returnFrame = self.focusedFrame
	if self:FrameShown(popup, true) then self.popupReturnFrames[popup] = returnFrame end
end
function manager:HandlePopupHide(popup)
	self.calls[#self.calls + 1] = "popupHide"
	if shared.refuse or RefusedToAddon() then return end
	self:FrameHidden(popup)
end
GamepadMode = { FrameControlsManager = manager }
shared.navCurrent = nil -- the key the D-pad is on
local navTargets = {} -- SetTargetButtonForFrame: each button the cursor was put on (false: the target cleared)
SmartNavigation = { GetCurrentButton = function() return shared.navCurrent end,
	RefreshButtonGroups = function() RefusedToAddon() end,
	SetTargetButtonForFrame = function(_, frame, button) -- (wrapped; selects it only in the panel that has the controller)
		if RefusedToAddon() then return end
		assert(frame == GamepadKeyboardFrame)
		navTargets[#navTargets + 1] = button or false
		if button and manager.focusedFrame == frame then shared.navCurrent = button end
	end }
SMART_NAV_INPUT_DIRECTION = { UP = { dirKey = "up" }, DOWN = { dirKey = "down" }, LEFT = { dirKey = "left" }, RIGHT = { dirKey = "right" } }
local overrides = {}
function SmartNavigation_AddJumpNavigationOverride(button, direction, target)
	if RefusedToAddon() then return end
	overrides[button] = overrides[button] or {}
	overrides[button][direction.dirKey] = target
end

-- The chat: a chat frame with gamepad focus puts typing focus in its box; losing typing focus while empty
-- deactivates the box, which resets its chat type to the sticky one (ChatFrameEditBoxMixin:Deactivate ->
-- ResetChatTypeToSticky: the type only - who a whisper was to stays as it was).
local chatFrame = W.CreateFrame("Frame", "ChatFrame1", UIParent)
local chatBox = W.CreateFrame("EditBox", "ChatFrame1EditBox", chatFrame)
chatBox.chatFrame = chatFrame
chatBox.autoFocus = false -- ChatFrameEditBoxTemplate
chatBox.center = { 300, 200 }
chatBox.attrs.chatType, chatBox.attrs.stickyType = "SAY", "SAY"
shared.classicChat = false -- the "classic" chat style: Deactivate hides the box, ActivateChat shows it
chatBox.scripts.OnEditFocusLost = function(self)
	if self:GetText() == "" then
		self.attrs.chatType, self.deactivated = self.attrs.stickyType, true
		if shared.classicChat then self:Hide() end
	end
end
chatBox.scripts.OnEditFocusGained = function(self) -- (ChatFrameUtil.ActivateChat)
	self.deactivated = nil
	if shared.classicChat then self:Show() end
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
	elseif command == "/R" and shared.lastTell then
		self.attrs.chatType, self.attrs.tellTarget = shared.lastTellType, shared.lastTell
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
-- which comes back clean), only. Each write from the addon's files is noted with its file and line.
local chatWrites = {}
for _, name in ipairs({ "SetText", "Insert", "SetTellTarget", "SetChatType", "SetFocus", "ClearFocus",
	"SetCursorPosition", "HighlightText" }) do -- (UpdateHeader may: it only redraws the header)
	local own = rawget(chatBox, name)
	chatBox[name] = function(self, ...)
		local source, line = H.callerSource(2)
		if H.isAddonSource(source) then
			chatWrites[#chatWrites + 1] = name .. "@" .. H.shortName(source) .. ":" .. tostring(line)
		end
		return (own or getmetatable(self).__index[name])(self, ...) -- (the class's, hooks and all)
	end
end
-- The guards know the addon's code by where it is - any file under the addon's folder but tests/ - and look
-- past pcall: a chunk standing for a file in a subfolder sets both off.
do
	local forbiddenFrame = W.CreateFrame("Frame", nil, UIParent); forbiddenFrame.forbidden = true
	local canary = assert(loadstring([[
		local box, frame = ...
		pcall(box.SetText, box, "canary")
		return pcall(function() return frame:Show() end)
	]], "@" .. H.root .. "/Keyboard/Canary.lua"))
	local shown = canary(chatBox, forbiddenFrame)
	check(#chatWrites == 1 and chatWrites[1] == "SetText@Keyboard/Canary.lua:2" and shown == false,
		"(the guards see the addon's code in any of its files, through pcall: " .. tostring(chatWrites[1]) .. ")")
	chatWrites[1], chatBox.text = nil, ""
end
function chatFrame:FocusGamepad() chatBox:SetFocus() end
function chatFrame:UnfocusGamepad() chatBox:ClearFocus() end
function chatFrame:SetGamepadFocus() GamepadMode.FrameControlsManager:FrameShown(self) end -- the menu dial's Chat
-- A menu's Whisper (ChatFrameUtil.SendTellWithMessage): "/w Name " into the chat box, parsed (it ends empty).
local function blizzardSendTell(name) chatBox:SetText("/w " .. name .. " ") end
local menuDialChat -- set below
-- Chat opened in a chat (the box's usual one: its sticky type too - a box doesn't sit in Say sticky to a whisper).
local function openChat(chatType, tellTarget, channelTarget)
	chatBox.attrs.chatType, chatBox.attrs.tellTarget, chatBox.attrs.channelTarget, chatBox.deactivated = chatType, tellTarget, channelTarget, nil
	chatBox.attrs.stickyType = chatType
	menuDialChat()
end
ChatTypeInfo = { SAY = { sticky = 1, r = 1, g = 1, b = 1 }, PARTY = { sticky = 1, r = 0.667, g = 0.667, b = 1 }, CHANNEL = { sticky = 1 },
	WHISPER = { sticky = 1 }, YELL = { sticky = 0 } } -- (ChatTypeInfoConstants.lua)
local poisoned = {}
local function poison(name) return function() poisoned[#poisoned + 1] = name; error(name .. " must not be called by the keyboard") end end
for _, name in ipairs({ "SendMessage", "SendText", "ClearChat", "Deactivate", "ParseText" }) do chatBox[name] = poison("editBox:" .. name) end
-- (GetLastTellTarget and GetActiveWindow only read. InsertLink, a shift-click's: into the active chat box -
-- ACTIVE_CHAT_EDIT_BOX, which deactivating clears - else nowhere; the keyboard only hooks it.)
ChatFrameUtil = setmetatable({
	GetLastTellTarget = function() return shared.lastTell, shared.lastTellType end,
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
	elseif down == (button.attrs.useOnKeyDown == true) and button.attrs.type == "click" and button.attrs.clickbutton then
		W.inSecure = true; button.attrs.clickbutton:Click(); W.inSecure = false -- SECURE_ACTIONS.click: delegate:Click(), securely
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
		if isSecure(shared.navCurrent) then secureClick(shared.navCurrent, false) else shared.navCurrent:Click() end
		poll()
		held.PAD1 = nil
	end
	poll()
end
local function playerClick(button)
	poll()
	assert(button and button:IsVisible() and button:IsEnabled(), "clicking a missing, hidden or disabled key")
	shared.navCurrent = button
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
-- The chat key's list: a chat in it picked (the chat key, then A on it); what it offers, top to bottom (then B).
local function chatTo(label)
	playerClick(key("CHAT"))
	for _, choice in ipairs(keyboard().ChatChoices) do
		if choice.shown and shown(choice.text) == label then playerClick(choice); return true end
	end
	keyboard():SmartNavigationCloseHandler()
end
local function chatList()
	playerClick(key("CHAT"))
	local labels = {}
	for _, choice in ipairs(keyboard().ChatChoices) do if choice.shown then labels[#labels + 1] = shown(choice.text) end end
	keyboard():SmartNavigationCloseHandler()
	return table.concat(labels, ",")
end
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

-- Fixtures more than one suite uses: a text box of another addon's, and where the D-pad goes from a key.
local outside = W.CreateFrame("EditBox", nil, UIParent, "InputBoxTemplate")
outside.center = { 400, 500 }
local function jump(k, dir) return overrides[key(k)] and overrides[key(k)][dir] end

-- After a suite: what the whole run may never have done, then the totals.
local function finish()
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
end

-- The suites' environment: the values they set (shared), the keyboard and its parts as they are when asked
-- (made the first time it opens), this file's locals, then the game's globals - which suites also set.
local exports = {
	BOUND = BOUND,
	BindingRefused = BindingRefused,
	CARET = CARET,
	CHAT_COMMANDS = CHAT_COMMANDS,
	DEFAULT_BINDINGS = DEFAULT_BINDINGS,
	DEFAULT_VALUES = DEFAULT_VALUES,
	H = H,
	ROSTER = ROSTER,
	RefusedToAddon = RefusedToAddon,
	S = S,
	STRATA = STRATA,
	W = W,
	bindingsRun = bindingsRun,
	blizzardFrame = blizzardFrame,
	blizzardGlobals = blizzardGlobals,
	blizzardOpenChat = blizzardOpenChat,
	blizzardSendTell = blizzardSendTell,
	boundTo = boundTo,
	chatBox = chatBox,
	chatFrame = chatFrame,
	chatList = chatList,
	chatTo = chatTo,
	chatWrites = chatWrites,
	check = check,
	endChat = endChat,
	finish = finish,
	focus = focus,
	held = held,
	indexOf = indexOf,
	isSecure = isSecure,
	jump = jump,
	key = key,
	keyboard = keyboard,
	keyboardKey = keyboardKey,
	layoutControl = layoutControl,
	layoutDropdown = layoutDropdown,
	lib = lib,
	macros = macros,
	manager = manager,
	menuDial = menuDial,
	menuDialChat = menuDialChat,
	mouseClick = mouseClick,
	navTargets = navTargets,
	offLimits = offLimits,
	openChat = openChat,
	optionValue = optionValue,
	optionsPanel = optionsPanel,
	outside = outside,
	overrideOrder = overrideOrder,
	overrides = overrides,
	pad = pad,
	padA = padA,
	page = page,
	playerClick = playerClick,
	poison = poison,
	poisoned = poisoned,
	poll = poll,
	pressA = pressA,
	preview = preview,
	savedTable = savedTable,
	secureClick = secureClick,
	shared = shared,
	shown = shown,
	type = type,
	world = world,
}
local SHARED = { style = true, lastTell = true, lastTellType = true, refuse = true, navCurrent = true, classicChat = true }
local NOT_MADE = { IsShown = function() return false end }
local LIVE = {
	kb = function() return GamepadKeyboardFrame or NOT_MADE end, -- (before it first opens: not shown, and nothing else)
	ring = function() return GamepadKeyboardFrame and GamepadKeyboardFrame.HoldPrompt and GamepadKeyboardFrame.HoldPrompt.icon end,
	enter = function() return GamepadKeyboardFrame and GamepadKeyboardFrame.EnterKeys[1] end,
}
return setmetatable({}, {
	__index = function(_, k)
		if SHARED[k] then return shared[k] end
		if LIVE[k] then return LIVE[k]() end
		local v = exports[k]
		if v ~= nil then return v end
		return _G[k]
	end,
	__newindex = function(_, k, v)
		if SHARED[k] then shared[k] = v else _G[k] = v end
	end,
})
