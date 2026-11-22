-- Chat: the line, its chat, sending it; pages, X / Y / LB / RB, holding A; the chat key's list.
-- Run: tests/run.sh chat (or luajit / nvim -l tests/chat_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
setfenv(1, dofile(lib .. "keyboard.lua"))

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
chatTo("To Bobby"); playerClick(key("ENTER"))
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
chatTo("Party")
check(key("CHAT").text == "Party" and preview() == "Hiy" .. CARET .. " o", "the chat key keeps the cursor")
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
-- LT / RT to another window while A is held: A is the controller UI's again, its release goes there - the hold
-- ends with it.
type("go")
local holdOther = W.CreateFrame("Frame", "HoldOtherPanel", UIParent)
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true); poll()
manager:FrameShown(holdOther); poll()
held.PAD1 = nil
for _ = 1, 40 do poll() end
check(boundTo("PAD1") ~= "CLICK GamepadKeyboardAButton:LeftButton" and not ring.holding and not key("ENTER").locked,
	"A held, then LT / RT to another window: the ring stops and Enter doesn't light (the release goes to that window)")
focus(kb); manager:FrameHidden(holdOther); poll()
navCurrent = key("o"); pressA()
check(preview() == "Goo" .. CARET and kb:IsShown(), "...back on the keyboard: a tap types as ever")
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
-- ---- the frame's size: the widest row of keys and a 14 edge each side; the last row clear of the footer ---------------
openChat("SAY"); poll()
local function rowSpan(k1, k2) return key(k2).point[2] + key(k2).width - key(k1).point[2] end
check(kb.width == rowSpan("1", "BACK") + 2 * 14 and math.abs(key("1").point[2] - 14) < 0.01,
	"the frame: its widest row (the numbers and Del) with a 14 edge each side")
local lastRowBottom = -key("ENTER").point[3] + key("ENTER").height
check(kb.height - lastRowBottom == 4 + 22 + 10, "...and under the last row a gap, then the footer (its glyphs and their margin)")
endChat()
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
-- ---- a line already in the chat box (a link Blizzard put there): shown, steered, handed back ------------------------
world.party = true
chatBox.text = "[Sword]" -- (ChatFrameUtil.OpenChat(link): chat opened with the link in it)
openChat("SAY"); poll()
check(kb:IsShown() and preview():find("^%[Sword%]") and preview():find("Enter, then A sends it", 1, true) and key("CHAT").text == "Say",
	"the chat box already holds a line (a link): the preview shows it, and how it's sent")
chatTo("Party")
check(key("CHAT").text == "Party" and chatBox.attrs.chatType == "PARTY" and chatBox.header == "PARTY:nil" and chatBox:GetText() == "[Sword]",
	"...the chat key steers the chat box's own line: its chat and its header (the text untouched)")
before = #macros
local notes = #world.printed
playerClick(key("ENTER"))
check(#macros == before and not kb:IsShown() and manager.focusedFrame == chatFrame and chatBox:HasFocus() and chatBox:GetText() == "[Sword]"
	and world.printed[#world.printed]:find("A sends it", 1, true) and #world.printed == notes + 1,
	"...Enter: back on the chat box with its line, in Party, for the chat's own A (said the first time)")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
notes = #world.printed
playerClick(key("ENTER"))
check(not kb:IsShown() and chatBox:HasFocus() and #world.printed == notes, "...and again: back to the chat box (said once, not every time)")
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("SAY"); poll()
chatBox.text = chatBox.text .. " [Shield]"; poll()
check(preview():find("^%[Sword%] %[Shield%]"), "...another link put in the chat box meanwhile: the preview follows")
type("hi")
check(preview() == "Hi" .. CARET and chatBox:GetText() == "[Sword] [Shield]", "...typing starts the keyboard's own line (the chat box keeps its own)")
playerClick(key("ENTER"))
check(macros[#macros] == "/s Hi", "...which Enter sends itself")
poll()
chatBox.text = ""; chatBox.attrs.chatType = "SAY"; chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
world.party = false
-- ---- the chat key ------------------------------------------------------------------------------------------------
openChat("SAY"); poll()
local chatKey = key("CHAT")
check(chatKey and chatKey.text == "Say" and kb.ChatHeader.text == "Say:" and kb.ChatHeader.shown and kb.Preview.points[1][2] == kb.ChatHeader,
	"chat: a chat key showing the chat, and the line headed by it (the line after the header)")
type("hi")
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell" and preview() == "Hi" .. CARET,
	"the chat key: a list of every chat, in a group or a guild or not (where you aren't, the game says so)")
lastTell, lastTellType = "Bob-Realm", "WHISPER"
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell,To Bob" and preview() == "Hi" .. CARET and #chatWrites == 0,
	"...then a reply to whoever whispered last (the text kept, the chat box never touched)")
-- The list: over the keys, the D-pad's cursor on the line's chat, up and down it and nowhere else.
local choices = kb.ChatChoices
local aboveChatKey = overrides[chatKey].up -- (with the list closed: a key above it)
playerClick(chatKey)
check(kb.ChatList.shown and choices[1].shown and choices[8].shown and not choices[9].shown and navCurrent == choices[1]
	and navTargets[#navTargets] == false and navTargets[#navTargets - 1] == choices[1],
	"the list opens with the D-pad's cursor on the line's chat (Say); the keyboard's target cleared after")
check(kb.ChatList.level > kb:GetFrameLevel() and kb.ChatList.level > kb.FrameGlow.level and choices[1].level > kb.ChatList.level
	and choices[1].parent == kb and kb.ChatList.mouse
	and choices[1].points[1][2] == kb.ChatList and kb.ChatList.points[1][2] == chatKey and kb.ChatList.clamped,
	"...over the keys and the focus glow round the keyboard, up from the chat key, on the screen (the mouse doesn't reach the keys through it); its buttons the keyboard's own")
check(overrides[choices[1]].down == choices[2] and overrides[choices[1]].up == choices[8] and overrides[choices[8]].down == choices[1]
	and overrides[choices[2]].left == true and overrides[choices[2]].right == true,
	"...up / down along it, round at the ends; left / right nowhere")
check(overrides[chatKey].up == choices[1], "...and up from the chat key into it (should the cursor stay on the key)")
navCurrent = overrides[choices[1]].down; pressA() -- (D-pad down, A)
check(aboveChatKey and aboveChatKey.key and overrides[chatKey].up == aboveChatKey,
	"...closed: up from the chat key to the key above it again (" .. tostring(aboveChatKey and aboveChatKey.key) .. ")")
check(not kb.ChatList.shown and not choices[1].shown and chatKey.text == "Party" and navCurrent == chatKey and navTargets[#navTargets] == false
	and kb.ChatHeader.text == "Party:" and kb.ChatHeader.textColor[3] == 1 and kb.ChatHeader.textColor[1] < 1 and preview() == "Hi" .. CARET,
	"...A takes Party: the list goes, the cursor back on the chat key; the key and the header follow (in Party's blue), the line kept")
playerClick(chatKey)
check(navCurrent == choices[2] and overrides[chatKey].up == choices[2], "opened again: the cursor on Party now (up from the chat key too)")
before = #macros
held.PAD1 = true; secureClick(GamepadKeyboardAButton, true) -- A held on Guild
navCurrent = choices[5]
for _ = 1, 60 do poll() end
check(not kb.HoldPrompt.icon.holding and not key("ENTER").locked, "...A held in the list: no hold ring, Enter not lit")
held.PAD1 = nil; secureClick(GamepadKeyboardAButton, false); poll()
check(chatKey.text == "Guild" and #macros == before and not kb.ChatList.shown, "...and let go: Guild taken, nothing sent")
playerClick(chatKey); choices[4]:Click() -- (the mouse)
check(chatKey.text == "Instance" and not kb.ChatList.shown, "a chat in the list clicked with the mouse: taken")
playerClick(chatKey); choices[5]:Click()
playerClick(chatKey); kb:SmartNavigationCloseHandler()
check(kb:IsShown() and not kb.ChatList.shown and chatKey.text == "Guild" and navCurrent == chatKey,
	"B in the list: back to the keys, the chat as it was (the keyboard stays)")
playerClick(chatKey); playerClick(chatKey)
check(kb:IsShown() and not kb.ChatList.shown and chatKey.text == "Guild", "the chat key again (a click): the list goes")
GamepadKeyboardDB.closeOnEnter = false
type("x"); playerClick(chatKey); before = #macros
playerClick(key("ENTER")) -- (a click: the D-pad doesn't reach Enter past the list)
check(macros[#macros] == "/g Hix" and #macros == before + 1 and kb:IsShown() and not kb.ChatList.shown,
	"Enter clicked with the list open (staying open after Enter): sent, and the list goes")
GamepadKeyboardDB.closeOnEnter = nil
type("hi")
playerClick(chatKey); pad("PAD4")
check(not kb.ChatList.shown and preview() == "Hi " .. CARET, "Y with the list open: the list goes, Y types its space")
pad("PAD3")
playerClick(chatKey); keyboardKey("ESCAPE")
check(not kb:IsShown() and not kb.ChatList.shown and not choices[1].shown, "closed with the list open (Escape): the list goes with it")
menuDialChat(); poll()
check(kb:IsShown() and not kb.ChatList.shown and not choices[1].shown and preview() == "Hi" .. CARET and chatKey.text == "Guild",
	"closed with the list open: no list next time (the line and its chat kept)")
playerClick(chatKey)
padA(function() outside:SetFocus() end)
check(kb:IsShown() and not kb.ChatList.shown and not choices[1].shown, "the list open, then another text box: no list there")
kb:SmartNavigationCloseHandler(); outside:ClearFocus(); poll()
menuDialChat(); poll()
chatTo("Party")
playerClick(key("ENTER"))
check(macros[#macros] == "/p Hi" and chatBox.attrs.stickyType == "PARTY", "Enter sends to the chat picked")
poll()
openChat("SAY"); poll()
chatTo("Party")
check(key("CHAT").text == "Party" and preview() == CARET and key("SHIFT").locked,
	"with nothing typed yet: switched, still nothing typed, Shift still on")
type("go")
playerClick(key("ENTER"))
check(macros[#macros] == "/p Go", "...and what's typed then goes there")
poll()
openChat("SAY"); poll()
chatTo("Yell"); type("hey"); playerClick(key("ENTER"))
check(macros[#macros] == "/y Hey", "Yell: /y")
poll()
openChat("SAY"); poll()
playerClick(key("SYMBOLS"))
check(key("CHAT") ~= nil and key("CHAT").text == "Say", "the symbols page has it too")
playerClick(key("/")); playerClick(key("LETTERS")); type("g ")
check(preview() == "/g " .. CARET and key("CHAT").text == "Say", "a typed /g stays in the line (it's sent as typed)")
endChat()
openChat("WHISPER", "Alice"); poll()
check(key("CHAT").text == "To Alice" and kb.ChatHeader.text == "To Alice:", "a whisper shows who to (the key and the header)")
type("hey")
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell,To Alice,To Bob" and preview() == "Hey" .. CARET,
	"...from a whisper to someone else: every chat, the whisper it was opened in, the reply (the text kept)")
playerClick(key("CHAT"))
check(navCurrent == kb.ChatChoices[8], "...the list's cursor on her")
kb:SmartNavigationCloseHandler()
chatTo("To Bob"); playerClick(key("CHAT"))
check(navCurrent == kb.ChatChoices[9], "...switched to the reply: the cursor on Bob next time (whispers told apart by who to)")
playerClick(kb.ChatChoices[8])
lastTell = "Alice"
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell,To Alice", "she whispers meanwhile (the reply is to her now): offered once")
lastTell = "Bob-Realm"
playerClick(key("ENTER"))
check(macros[#macros] == "/w Alice Hey", "Enter sends it to her")
endChat()
openChat("WHISPER", "Bob-Realm"); poll()
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell,To Bob", "the whisper and the reply to the same person: offered once")
endChat()
-- A Battle.net whisperer to reply to: not offered (a macro line can't say it).
lastTell, lastTellType = "|Kq7|k", "BN_WHISPER"
openChat("SAY"); poll()
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell", "a Battle.net whisper to reply to: not offered")
endChat()
-- A whisper started in the chat box while the keyboard is up: the line goes there, and it's offered back.
lastTell, lastTellType = nil, nil
openChat("SAY"); poll()
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell", "a new chat: no whisper from before offered")
chatBox.attrs.chatType, chatBox.attrs.tellTarget = "WHISPER", "Carol" -- (a name's menu, "/w Carol " on a real keyboard)
poll()
check(key("CHAT").text == "To Carol" and kb.ChatHeader.text == "To Carol:", "a whisper started in the chat box meanwhile: the line goes to her")
check(chatList() == "Say,Party,Raid,Instance,Guild,Officer,Yell,To Carol", "...and she's offered back too")
lastTell, lastTellType = "Bob-Realm", "WHISPER"
endChat()
openChat("WHISPER", "Christopherson"); poll()
check(key("CHAT").text == "To Christop..", "a long name is cut to fit")
endChat()
openChat("CHANNEL", nil, 2); poll()
check(key("CHAT").text == "/2" and kb.ChatHeader.text == "/2:", "a channel shows its number")
playerClick(key("CHAT"))
check(navCurrent == kb.ChatChoices[1], "...its list: the cursor on Say (a channel isn't in it)")
kb:SmartNavigationCloseHandler()
endChat()
-- A whisper picked from the list and sent: the chat box sticks to it as Blizzard's own send leaves it, who
-- it's to with it (closing, the box goes back to its sticky type only).
lastTell, lastTellType = "Bob-Realm", "WHISPER"
openChat("SAY"); poll()
chatTo("To Bob"); type("yo"); playerClick(key("ENTER"))
check(macros[#macros] == "/w Bob-Realm Yo" and chatBox.attrs.stickyType == "WHISPER" and chatBox.attrs.tellTarget == "Bob-Realm",
	"a whisper picked from the list and sent: the chat box sticks to it, with who it's to (" .. tostring(macros[#macros]) .. ")")
poll()
menuDialChat(); poll()
check(kb:IsShown() and key("CHAT").text == "To Bob", "...the next chat opens to Bob again, as after Blizzard's own send")
-- Then Say picked, a line typed and left: it waits in Say (the box still sticking to Bob is no new whisper).
chatTo("Say"); type("later"); kb:SmartNavigationCloseHandler(); poll()
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
menuDialChat(); poll()
check(kb:IsShown() and key("CHAT").text == "Say" and preview() == "Later" .. CARET, "...a line left unsent in Say after that: back in Say, not moved to Bob")
-- A whisper started in the chat box since (a name's Whisper) still takes it.
kb:SmartNavigationCloseHandler(); poll()
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
mouseClick(function() chatFrame:SetGamepadFocus() end); blizzardSendTell("Carol"); poll()
menuDialChat(); poll()
check(kb:IsShown() and key("CHAT").text == "To Carol" and preview() == "Later" .. CARET, "...but a whisper started since: the line goes to her")
endChat()
-- A whisper started while the keyboard is up is taken in; Say picked after it and the line left (B, back on
-- the chat box, still in that whisper): back in Say - that whisper isn't new to the line.
openChat("SAY"); poll()
blizzardSendTell("Alice"); poll()
check(key("CHAT").text == "To Alice", "(a name's Whisper while it's up: taken in)")
chatTo("Say"); type("not her"); kb:SmartNavigationCloseHandler(); poll()
check(chatBox.attrs.chatType == "WHISPER" and chatBox.attrs.tellTarget == "Alice", "(B: back on the chat box, still whispering her)")
menuDialChat(); poll()
check(kb:IsShown() and key("CHAT").text == "Say" and preview() == "Not her" .. CARET,
	"...Say picked after a whisper was taken in, the line left: back in Say, not to her")
endChat()
-- The box in Say but sticking to a whisper (a real keyboard's /s after one): closing, it goes back to the
-- whisper - which isn't new either.
openChat("SAY"); chatBox.attrs.stickyType, chatBox.attrs.tellTarget = "WHISPER", "Bob-Realm"; poll()
type("soon"); kb:SmartNavigationCloseHandler(); poll()
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
check(chatBox.attrs.chatType == "WHISPER", "(closed: the box back to its whisper)")
menuDialChat(); poll()
check(kb:IsShown() and key("CHAT").text == "Say" and preview() == "Soon" .. CARET, "...a line left in Say then: still in Say")
endChat()
-- A channel line sent: the box sticks to that channel (its number with it).
openChat("CHANNEL", nil, 1); poll()
type("a"); kb:SmartNavigationCloseHandler(); poll()
chatBox:ClearFocus(); manager:FrameHidden(chatFrame); poll()
openChat("CHANNEL", nil, 2); poll()
check(key("CHAT").text == "/1", "(a line waiting in channel 1, the box on channel 2: the line's own)")
playerClick(key("ENTER"))
check(macros[#macros] == "/1 A" and chatBox.attrs.stickyType == "CHANNEL" and chatBox.attrs.channelTarget == 1,
	"a channel line sent: the box sticks to that channel, its number with it")
poll()
chatBox.attrs.stickyType, chatBox.attrs.chatType, chatBox.attrs.tellTarget, chatBox.attrs.channelTarget = "SAY", "SAY", nil, nil
lastTell, lastTellType = nil, nil
padA(function() outside:SetFocus() end)
check(kb:IsShown() and not kb.ChatHeader.shown and kb.Preview.points[1][1] == "TOPLEFT" and kb.Preview.points[1][2] == 16,
	"another text box: no header, the line where it always is")
kb:SmartNavigationCloseHandler(); outside:ClearFocus(); poll()
lastTell, lastTellType = nil, nil

finish()
