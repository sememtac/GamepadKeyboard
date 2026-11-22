-- A window's name box; a real keyboard, the mouse, the controller; where it goes, its size, Edit Mode; the D-pad; when it doesn't open.
-- Run: tests/run.sh input (or luajit / nvim -l tests/input_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
setfenv(1, dofile(lib .. "keyboard.lua"))

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
check(kb:IsShown() and preview():find("^Hi") and preview():find("A sends it", 1, true) and chatBox:GetText() == "Hi",
	"Chat on the menu dial then: the on-screen keyboard comes, showing the chat box's line (the real keyboard's, sent from there)")
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

finish()
