-- Combat: starting while typing, and on without its start seen.
-- Run: tests/run.sh combat (or luajit / nvim -l tests/combat_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
setfenv(1, dofile(lib .. "keyboard.lua"))

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
menuDialChat(); poll()
check(not kb:IsShown() and (W.blockedMessages or 0) == 0, "...Chat on the menu dial in combat: no keyboard (it can't open then), nothing blocked")
before = #macros
local blockedEnter = W.blockedMessages or 0
check(pcall(secureClick, enter) and #macros == before and (W.blockedMessages or 0) == blockedEnter,
	"its Enter pressed in combat somehow: nothing set on it (nothing blocked), nothing sent")
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
W.fireEvent("PLAYER_REGEN_ENABLED"); poll()
check(indexOf(kb) == nil and not kb:IsShown(), "...and removed after combat (the box focused again as it goes: not opened for)")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
-- ---- combat without its start seen (lockdown on with the keyboard still up) ------------------------------------------
-- Every combat guard: nothing the game refuses an addon in combat is tried, and the keyboard does nothing
-- until combat ends - the line kept.
openChat("SAY"); poll()
type("hi")
local chatKeyNow = key("CHAT")
local combatOther = W.CreateFrame("Frame", "CombatOtherPanel", UIParent)
local blockedAt, macrosAt = W.blockedMessages or 0, #macros
local function nothingBlocked() return (W.blockedMessages or 0) == blockedAt end
world.combat = true
poll(); poll()
check(kb:IsShown() and nothingBlocked(), "combat without its start seen: the keyboard left up, nothing tried")
navCurrent = key("a"); pressA()
check(preview() == "Hi" .. CARET and nothingBlocked() and GamepadKeyboardAButton.attrs.type == "macro", "...A on a key: nothing typed, nothing set on its secure buttons")
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true)
for _ = 1, 40 do poll() end
check(not ring.holding and not key("ENTER").locked, "...A held: no ring, Enter not lit")
held.PAD1 = nil; secureClick(GamepadKeyboardAButton, false); poll()
check(#macros == macrosAt and kb:IsShown() and nothingBlocked(), "...let go: nothing sent")
key("SYMBOLS"):Click() -- (the mouse)
check(key("q") and not key("!") and nothingBlocked(), "...a click on ?123: no page change (its keys can't move in combat)")
local qBefore = key("q").points[#key("q").points]
S.layout:SetValue("dvorak"); S.scale:SetValue(1.25)
check(key("q").points[#key("q").points] == qBefore and kb.scale ~= 1.25 and nothingBlocked(), "...the layout and size changed in Options: nothing moved now")
S.layout:SetValue("qwerty"); S.scale:SetValue(1)
SetOverrideBindingClick(UIParent, true, "PAD3", "Blizzard_Other") -- (the controller UI binding X over it)
check(boundTo("PAD3") == "CLICK Blizzard_Other:LeftButton" and nothingBlocked(), "...the controller UI binding X over it: not bound back in combat")
manager:FrameShown(combatOther); poll() -- LT / RT away
check(boundTo("PAD1") == "CLICK GamepadKeyboardAButton:LeftButton" and nothingBlocked(), "...LT / RT away: its bindings left (they can't change in combat)")
focus(kb); manager:FrameHidden(combatOther); poll()
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED"); poll(); poll()
check(boundTo("PAD3") == "CLICK GamepadKeyboardDelKey:LeftButton" and preview() == "Hi" .. CARET, "after combat: X the keyboard's again, the line kept")
-- Its bindings cleared before combat (the controller on another window), back on the keyboard in combat: left
-- as they are until combat ends.
manager:FrameShown(combatOther); poll()
check(boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton", "(on another window: A the controller UI's)")
world.combat = true
focus(kb); poll()
check(boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton" and nothingBlocked(), "back on the keyboard in combat: A not bound to it (can't be, in combat)")
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED"); poll()
check(boundTo("PAD1") == "CLICK GamepadKeyboardAButton:LeftButton", "...after combat: A the keyboard's again")
manager:FrameHidden(combatOther); poll()
-- The chat list open as combat comes: B closes the list, nothing steered.
playerClick(chatKeyNow)
check(kb.ChatList.shown, "(the chat list open)")
local targetsAt = #navTargets
world.combat = true
kb:SmartNavigationCloseHandler()
check(not kb.ChatList.shown and kb:IsShown() and #navTargets == targetsAt and nothingBlocked(), "...B in combat: the list goes, the cursor and the D-pad left alone")
-- The game hiding it in combat (the whole UI hidden: Alt-Z): what it tells Blizzard waits for combat's end.
W.inSecure = true; kb:Hide(); W.inSecure = false
check(not kb:IsShown() and indexOf(kb) ~= nil and boundTo("PAD1") == "CLICK GamepadKeyboardAButton:LeftButton" and nothingBlocked(),
	"hidden by the game in combat: still listed by Blizzard, its bindings left, nothing blocked")
world.combat = false; W.fireEvent("PLAYER_REGEN_ENABLED"); poll()
check(indexOf(kb) == nil and boundTo("PAD1") == "CLICK Blizzard_PAD1:LeftButton", "...after combat: taken off Blizzard's list, A the controller UI's again")
chatBox.text = ""; manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
check(kb:IsShown() and preview() == "Hi" .. CARET, "...the line back the next time")
endChat()
-- A blocked report in combat (a protected call refused): it says so.
W.fireEvent("ADDON_ACTION_BLOCKED", "GamepadKeyboard", "SomeProtectedCall()")
check(world.printed[#world.printed]:find("SomeProtectedCall()", 1, true) and world.printed[#world.printed]:find("in combat", 1, true),
	"blocked in combat: it says what")

finish()
