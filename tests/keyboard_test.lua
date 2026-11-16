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
local function poll() W.update(0.016) end
local held = {} -- keys and controller buttons held down
function IsKeyDown(k) return held[k] == true end
local BOUND = { OPENCHAT = { "ENTER", "PADBACK" }, OPENCHATSLASH = { "/" }, REPLY = { "R" }, REPLY2 = { "CTRL-T" } }
function GetBindingKey(binding) return unpack(BOUND[binding] or {}) end

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
SmartNavigation = { RefreshButtonGroups = function() end }
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
-- SecureActionButton_OnClick: PreClick, the action on release (useOnKeyDown off), PostClick.
local function secureClick(button)
	assert(button.OnSmartNavClick == nil and button.scripts.OnClick == nil, "the secure OnClick must stay Blizzard's")
	if button.scripts.PreClick then button.scripts.PreClick(button, "LeftButton", false) end
	if button.attrs.useOnKeyDown == false and button.clicks[1] == "AnyUp" and button.attrs.type == "macro" and button.attrs.macrotext ~= "" then
		macros[#macros + 1] = button.attrs.macrotext -- C_Macro.RunMacroText, securely
	end
	if button.scripts.PostClick then button.scripts.PostClick(button, "LeftButton", false) end
end
local function playerClick(button)
	poll()
	assert(button and button:IsVisible() and button:IsEnabled(), "clicking a missing, hidden or disabled key")
	held.PAD1 = true -- A
	if W.hasTemplate(button.template, "SecureActionButtonTemplate") then secureClick(button) else button:Click() end
	poll()
	held.PAD1 = nil
	poll()
end

-- The controller: A while a text box takes focus (SmartNavigation clicks it); the menu dial, whose button
-- comes up before Chat is chosen.
local function padA(fn) poll(); held.PAD1 = true; fn(); poll(); held.PAD1 = nil; poll() end
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

-- ---- load ---------------------------------------------------------------------------------------------
H.loadAddon({})
check(SlashCmdList.GAMEPADKEYBOARD ~= nil and SLASH_GAMEPADKEYBOARD1 == "/gk", "/gk")
poll(); poll()
check(W.focused == nil, "loading takes no typing focus (a text box of ours shown with auto-focus would keep every key)")

local function keyboard() return GamepadKeyboardFrame end
local function key(k)
	for _, f in ipairs(W.frames) do if f.parent == keyboard() and f.key == k and f.shown then return f end end
end
local function type(s) for c in s:gmatch(".") do playerClick(key(c == " " and "SPACE" or c:lower())) end end

-- ---- chat: a whisper reply ----------------------------------------------------------------------------------
openChat("WHISPER", "Bob"); poll()
local kb = keyboard()
check(kb and kb.point and kb.point[1] == "BOTTOMLEFT" and kb.point[2] == chatFrame and kb.point[3] == "BOTTOMRIGHT",
	"for chat it opens beside the chat window, not over it")
check(kb and kb:IsShown(), "chat box focused with the controller: the keyboard opens")
check(indexOf(kb) ~= nil and manager.focusedFrame == kb and manager.popupReturnFrames[kb] == chatFrame,
	"as a popup in Blizzard's gamepad UI, returning to the chat")
check(not chatBox:HasFocus() and not chatBox.deactivated and chatBox.attrs.chatType == "WHISPER" and chatBox.attrs.tellTarget == "Bob",
	"the chat box stays open and keeps its whisper target (a placeholder space kept it from closing)")
check(key("SHIFT").locked, "an empty chat line starts with Shift on")
type("hi"); playerClick(key("SPACE")); type("there")
check(chatBox:GetText() == "Hi there" and kb.Preview.text == "Hi there_", "keys type into the chat box (its own preview) - first letter capital")
playerClick(key("BACK"))
check(chatBox:GetText() == "Hi ther", "Del removes the last letter")
kb:SmartNavigationCloseHandler() -- B
check(not kb:IsShown() and indexOf(kb) == nil, "B closes the keyboard")
check(manager.focusedFrame == chatFrame and chatBox:HasFocus() and chatBox:GetText() == "Hi ther" and chatBox.attrs.tellTarget == "Bob",
	"...and the controller is back on the chat box with the text, still to Bob, nothing sent")
poll(); poll()
check(not kb:IsShown(), "it doesn't open again for the box it went back to")
check(#poisoned == 0, "the keyboard never called a chat send function")
-- Back on the chat box, choosing Chat on the menu dial again (the chat is already the focused panel, so
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
check(chatBox:GetText() == "" and kb.Preview.text == "_", "the preview shows what the box made of /p (party chat, nothing typed yet)")
type("hi")
check(chatBox.attrs.chatType == "PARTY" and chatBox:GetText() == "hi" and kb.Preview.text == "hi_", "typing /p and a space switches to party, as typing does")
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
check(chatBox.attrs.chatType == "PARTY" and chatBox:GetText() == "Hi" and chatKey.text == "Party" and kb.Preview.text == "Hi_",
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
check(chatBox.attrs.chatType == "PARTY" and chatBox:GetText() == "" and kb.Preview.text == "_" and key("SHIFT").locked,
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
check(not kb:IsShown() and GamepadKeyboardDB.autoOpen == false, "/gk off: doesn't open")
SlashCmdList.GAMEPADKEYBOARD("on")
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
check((W.blockedMessages or 0) == 0, "...nothing blocked")
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
check(#poisoned == 0, "no chat send function was ever called")

H.finish()
