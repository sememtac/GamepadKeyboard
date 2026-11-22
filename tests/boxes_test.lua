-- Other text boxes: names (the mail's To:), a box of several lines, the settings.
-- Run: tests/run.sh boxes (or luajit / nvim -l tests/boxes_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
setfenv(1, dofile(lib .. "keyboard.lua"))

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
check(kb:IsShown() and shownNames() == "" and kb.height == 88 + 6 * 34 and key("1").point[3] == -56 - 34,
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
check(kb:IsShown() and preview() == "|" and shownNames() == "" and kb.height == 88 + 5 * 34,
	"A on the Subject: while the keyboard is open: it types there now (no names there)")
focus(kb); poll()
type("hi")
check(subject:GetText() == "hi" and mailTo:GetText() == "bo", "...the letters go into the Subject:, To: keeps its own")
focus(mail); poll()
padA(function() mailTo:SetFocus() end)
check(preview() == "bo|" and shownNames() == "Bob,Bobby,Boris-Other,Bonnie" and kb.height == 88 + 6 * 34,
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
check(calls == 0 and shownNames() == "" and kb.height == 88 + 5 * 34, "a box with its own lookup function: not called, no name row")
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
check(shownNames() == "" and kb.height == 88 + 5 * 34, "chat: no name row (its own list is for whisper targets)")
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
check(shownNames() == "" and kb.height == 88 + 5 * 34, "Name suggestions off: no name row")
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

finish()
