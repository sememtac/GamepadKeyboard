-- Gamepad Keyboard tests. Run from the repo root: luajit tests/keyboard_test.lua (or nvim -l).
-- The focus manager and the chat box follow Blizzard's code (FrameControlsManager.lua, ChatFrameEditBox.lua,
-- FloatingChatFrame.lua). Every chat send function is poisoned: the keyboard must never call one.
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local W = dofile(lib .. "widgets.lua")
local check = H.check

-- ---- a small game world -------------------------------------------------------------------------------
local world = { combat = false, printed = {} }
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
local function poll() W.update(0.016) end

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
chatBox.center = { 300, 200 }
chatBox.attrs.chatType, chatBox.attrs.stickyType = "SAY", "SAY"
chatBox.scripts.OnEditFocusLost = function(self)
	if self:GetText() == "" then
		self.attrs.chatType, self.attrs.tellTarget, self.deactivated = self.attrs.stickyType, nil, true
	end
end
-- OnTextChanged -> ParseText(0): "/p " switches the chat type and leaves the rest, as when typing.
chatBox.scripts.OnTextChanged = function(self)
	local rest = self.text:match("^/p%s(.*)$")
	if rest then self.attrs.chatType, self.text = "PARTY", rest end
end
chatFrame.editBox = chatBox
function chatFrame:FocusGamepad() chatBox:SetFocus() end
function chatFrame:UnfocusGamepad() chatBox:ClearFocus() end
function chatFrame:SetGamepadFocus() GamepadMode.FrameControlsManager:FrameShown(self) end -- the menu dial's Chat
local function openChat(chatType, tellTarget, channelTarget)
	chatBox.attrs.chatType, chatBox.attrs.tellTarget, chatBox.attrs.channelTarget, chatBox.deactivated = chatType, tellTarget, channelTarget, nil
	chatFrame:SetGamepadFocus()
end
ChatTypeInfo = { SAY = { sticky = 1 }, PARTY = { sticky = 1 }, CHANNEL = { sticky = 1 }, WHISPER = { sticky = 0 } }
local poisoned = {}
local function poison(name) return function() poisoned[#poisoned + 1] = name; error(name .. " must not be called by the keyboard") end end
for _, name in ipairs({ "SendMessage", "SendText", "ClearChat", "Deactivate", "ParseText" }) do chatBox[name] = poison("editBox:" .. name) end
ChatFrameUtil = setmetatable({}, { __index = function(_, k) return poison("ChatFrameUtil." .. k) end })
C_ChatInfo = { SendChatMessage = poison("C_ChatInfo.SendChatMessage") }

-- A player's A on a key (SmartNavigation clicks it) or a mouse click.
-- Frames pass between presses, as in the game (the focus watcher runs every frame).
local macros = {}
local function playerClick(button)
	poll()
	assert(button and button:IsVisible() and button:IsEnabled(), "clicking a missing, hidden or disabled key")
	if W.hasTemplate(button.template, "SecureActionButtonTemplate") then
		-- SecureActionButton_OnClick: PreClick, the action on release (useOnKeyDown off), PostClick.
		assert(button.OnSmartNavClick == nil and button.scripts.OnClick == nil, "the secure OnClick must stay Blizzard's")
		if button.scripts.PreClick then button.scripts.PreClick(button, "LeftButton", false) end
		if button.attrs.useOnKeyDown == false and button.clicks[1] == "AnyUp" and button.attrs.type == "macro" and button.attrs.macrotext ~= "" then
			macros[#macros + 1] = button.attrs.macrotext -- C_Macro.RunMacroText, securely
		end
		if button.scripts.PostClick then button.scripts.PostClick(button, "LeftButton", false) end
	else
		button:Click()
	end
	poll()
end

-- ---- load ---------------------------------------------------------------------------------------------
H.loadAddon({})
check(SlashCmdList.GAMEPADKEYBOARD ~= nil and SLASH_GAMEPADKEYBOARD1 == "/gk", "/gk")

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
chatFrame:SetGamepadFocus(); poll()
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
playerClick(key("SYMBOLS")); playerClick(key("/")); playerClick(key("LETTERS")); type("p "); type("hi")
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
kb:Hide() -- Escape on a real keyboard
check(manager.focusedFrame == chatFrame and chatBox:GetText() == "Ok!", "closed by Escape: same as B")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- any other text box: a window with a name box ----------------------------------------------------------------
local panel = W.CreateFrame("Frame", "SomePanel", UIParent)
local nameBox = W.CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
nameBox.maxLetters = 5
nameBox.center = { 500, 800 }
nameBox.text = "Tot"
local entered = 0
nameBox.scripts.OnEnterPressed = function(self) entered = entered + 1; self:ClearFocus() end
manager:FrameShown(panel)
nameBox:SetFocus(); poll() -- A on the name box (OnSmartNavClick -> SetFocus)
check(kb:IsShown() and manager.popupReturnFrames[kb] == panel, "a name box in a window: the keyboard opens over that window")
check(kb.point and kb.point[1] == "TOP" and kb.point[2] == nameBox, "below the box (it's in the upper half of the screen)")
check(not key("SHIFT").locked and nameBox:GetText() == "Tot", "no Shift, and it starts from the box's text")
type("ems"); type("x")
check(nameBox:GetText() == "Totem", "keys type into the box, up to its letter limit")
kb:SmartNavigationCloseHandler()
check(manager.focusedFrame == panel and nameBox:GetText() == "Totem" and entered == 0, "B: back to the window, the text stays")
poll(); poll()
check(not kb:IsShown(), "it doesn't open again while the box still has focus")
nameBox:SetFocus(); poll() -- A on the name box again: it still has focus
check(kb:IsShown(), "A on the box again (it never lost focus): the keyboard comes back")
playerClick(key("ENTER"))
check(entered == 1 and not kb:IsShown() and manager.focusedFrame == panel and nameBox:GetText() == "Totem" and not nameBox:HasFocus(),
	"Enter: the box's own Enter action (here: done typing), back to the window")
poll(); nameBox:SetFocus(); poll()
check(kb:IsShown(), "focusing the box again later opens it again")
kb:Hide(); nameBox:ClearFocus(); poll()

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
for _, f in ipairs(W.frames) do
	if f.parent == kb and f.key and f.point then f.center = { f.point[2] + f.width / 2, -f.point[3] } end
end
nameBox:SetFocus(); poll()
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
local secret = W.CreateFrame("EditBox", nil, UIParent); secret.forbidden = true
secret:SetFocus(); poll()
check(not kb:IsShown(), "a forbidden box (Blizzard's store and such): doesn't open")
secret:ClearFocus(); poll()
SlashCmdList.GAMEPADKEYBOARD("off")
openChat("SAY"); poll()
check(not kb:IsShown() and GamepadKeyboardDB.autoOpen == false, "/gk off: doesn't open")
SlashCmdList.GAMEPADKEYBOARD("on")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()

-- ---- combat starting while typing ----------------------------------------------------------------------------------
openChat("PARTY"); poll()
type("pull")
W.fireEvent("PLAYER_REGEN_DISABLED")
world.combat = true
poll()
check(not kb:IsShown() and chatBox:GetText() == "Pull" and chatBox.attrs.chatType == "PARTY", "combat starts: the keyboard closes, the text and chat type stay")
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
