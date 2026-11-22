-- Blizzard's own text boxes: which it types into and which not; boxes of numbers; Enter pressing a window's button.
-- Run: tests/run.sh blizzard (or luajit / nvim -l tests/blizzard_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
setfenv(1, dofile(lib .. "keyboard.lua"))

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
	and not key("SYMBOLS") and not key("CHAT") and not key("SHIFT") and kb.height == 88 + 4 * 34,
	"the mail's gold (a box of numbers, looked through): the keyboard opens on a numpad, four rows")
local function rowY(k) return key(k).point[3] end
local function colX(k) return key(k).point[2] end
check(rowY("7") == rowY("9") and rowY("4") == rowY("6") and rowY("1") == rowY("3") and rowY("BACK") == rowY("0") and rowY("0") == rowY("ENTER")
	and rowY("7") > rowY("4") and rowY("4") > rowY("1") and rowY("1") > rowY("0"), "...7 8 9 / 4 5 6 / 1 2 3 / Del 0 Enter, top to bottom")
check(colX("7") == colX("4") and colX("4") == colX("1") and colX("1") == colX("BACK") and colX("8") == colX("0") and colX("9") == colX("ENTER")
	and key("BACK").width == key("5").width and key("ENTER").width == key("5").width and key("5").width == 2 * 36 + 4,
	"...a grid: every key the same width (two letter keys), in columns")
check(jump("5", "up") == key("8") and jump("5", "down") == key("2") and jump("2", "down") == key("0") and jump("0", "left") == key("BACK")
	and jump("ENTER", "right") == key("BACK") and jump("8", "up") == key("0"), "...the D-pad moves round the grid (wrapping at the edges)")
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
AuctionHouseFrame.CommoditiesBuyFrame = W.CreateFrame("Frame", nil, AuctionHouseFrame)
AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay = W.CreateFrame("Frame", nil, AuctionHouseFrame.CommoditiesBuyFrame)
AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.QuantityInput = W.CreateFrame("Frame", nil, AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay)
local buyQuantity = numberBox(nil, AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.QuantityInput, { 400, 700 })
AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.QuantityInput.InputBox = buyQuantity
AuctionHouseFrame.ItemBuyFrame = W.CreateFrame("Frame", nil, AuctionHouseFrame)
AuctionHouseFrame.ItemBuyFrame.BidFrame = W.CreateFrame("Frame", nil, AuctionHouseFrame.ItemBuyFrame)
local bidAmount = W.CreateFrame("Frame", nil, AuctionHouseFrame.ItemBuyFrame.BidFrame)
AuctionHouseFrame.ItemBuyFrame.BidFrame.BidAmount = bidAmount
for _, coin in ipairs({ "gold", "silver", "copper" }) do bidAmount[coin] = numberBox(nil, bidAmount, { 400, 650 }) end
manager:FrameShown(AuctionHouseFrame)
for label, box in pairs({ ["an item's price (gold)"] = itemSell.PriceInput.MoneyInputFrame.GoldBox,
	["an item's price (copper)"] = itemSell.PriceInput.MoneyInputFrame.CopperBox, ["an item's quantity"] = itemSell.QuantityInput.InputBox,
	["a stack's price (silver)"] = stackSell.PriceInput.MoneyInputFrame.SilverBox, ["a stack's quantity"] = stackSell.QuantityInput.InputBox }) do
	padA(function() box:SetFocus() end)
	type("42")
	check(kb:IsShown() and key("1") and not key("q") and box:GetText() == "42", "auction house, " .. label .. ": the keyboard, on its numbers")
	kb:SmartNavigationCloseHandler(); box:ClearFocus(); box.text = ""; poll()
end
for _, coin in ipairs({ "gold", "silver", "copper" }) do
	padA(function() bidAmount[coin]:SetFocus() end)
	type("7")
	check(kb:IsShown() and key("1") and bidAmount[coin]:GetText() == "7", "auction house, a single item's bid (" .. coin .. "): the keyboard, on its numbers")
	kb:SmartNavigationCloseHandler(); bidAmount[coin]:ClearFocus(); bidAmount[coin].text = ""; poll()
end
local notesBeforeBuy = #world.printed
padA(function() buyQuantity:SetFocus() end)
check(not kb:IsShown() and #world.printed == notesBeforeBuy + 1 and world.printed[#world.printed]:find("price list", 1, true),
	"...but not a stack's buy quantity (its price only follows real typing): a note pointing to the price list")
buyQuantity:ClearFocus(); poll()
-- The Filter list's level range (a Blizzard menu's, LevelRangeFrameTemplate): no, and why, with a way round.
local levelRange = W.CreateFrame("Frame", nil, UIParent)
for _, k in ipairs({ "MinLevel", "MaxLevel" }) do
	levelRange[k] = numberBox(nil, levelRange, { 400, 650 }); levelRange[k].sourceLocation = "Interface/AddOns/Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml:390"
end
local notesBeforeLevel = #world.printed
padA(function() levelRange.MaxLevel:SetFocus() end)
check(not kb:IsShown() and #world.printed == notesBeforeLevel + 1 and world.printed[#world.printed]:find("Usable Only", 1, true),
	"...nor the Filter list's level range (the search's filters, which buying reads): a note pointing to Usable Only")
levelRange.MaxLevel:ClearFocus(); poll()
AuctionHouseFrame:Hide()
padA(function() levelRange.MinLevel:SetFocus() end)
check(not kb:IsShown() and world.printed[#world.printed]:find("the game's own text box", 1, true),
	"(a level range elsewhere, the auction house closed: the usual note)")
levelRange.MinLevel:ClearFocus(); levelRange:Hide(); AuctionHouseFrame:Show(); poll()
-- Its search: typed in; Enter presses Search (securely), never the box's own Enter.
AuctionHouseFrame.SearchBar = W.CreateFrame("Frame", nil, AuctionHouseFrame)
local ahSearch = W.CreateFrame("EditBox", nil, AuctionHouseFrame.SearchBar, "InputBoxTemplate"); ahSearch.center = { 400, 750 }
AuctionHouseFrame.SearchBar.SearchBox = ahSearch
local searchButton = W.CreateFrame("Button", nil, AuctionHouseFrame.SearchBar)
AuctionHouseFrame.SearchBar.SearchButton = searchButton
local searches = {}
searchButton.scripts.OnClick = function() searches[#searches + 1] = { text = ahSearch:GetText(), secure = W.inSecure } end
local boxEnter = 0
ahSearch.scripts.OnEnterPressed = function() boxEnter = boxEnter + 1 end -- (StartSearch: the shared filters, then the query)
padA(function() ahSearch:SetFocus() end)
check(kb:IsShown() and key("q") and key("SPACE"), "the auction house's search box: the keyboard, letters")
type("linen")
W.fireEvent("ADDON_ACTION_FORBIDDEN", "GamepadKeyboard", "SomeCall()")
check(world.printed[#world.printed]:find("Last typed into: AuctionHouseFrame.SearchBar.SearchBox.", 1, true),
	"(a block report names an unnamed Blizzard box by where it is: " .. world.printed[#world.printed] .. ")")
before = #macros
playerClick(key("ENTER"))
check(#searches == 1 and searches[1].text == "linen" and searches[1].secure and boxEnter == 0 and #macros == before,
	"...Enter presses its Search button, securely (Blizzard's search) - not the box's own Enter, no macro")
check(not kb:IsShown() and not ahSearch:HasFocus() and key("ENTER").attrs.type == "macro" and key("ENTER").attrs.clickbutton == nil,
	"...the keyboard closes, the box lets go of typing, and the Enter key is a macro button again")
padA(function() ahSearch:SetFocus() end)
type("cloth")
navCurrent = key("c"); pressA(0.6)
check(#searches == 2 and searches[2].text == "linencloth" and searches[2].secure and boxEnter == 0 and GamepadKeyboardAButton.attrs.type == "macro",
	"...holding A searches the same way (and A is a macro button again after)")
pressA()
check(#searches == 2, "...a later A press doesn't search again")
ahSearch:ClearFocus(); ahSearch.text = ""; manager:FrameHidden(AuctionHouseFrame); AuctionHouseFrame = nil; poll()
openChat("SAY"); poll()
GamepadKeyboardAButton.attrs.type, GamepadKeyboardAButton.attrs.clickbutton = "click", searchButton -- (a press cut short: combat)
secureClick(GamepadKeyboardAButton, false); poll() -- a release whose press went elsewhere
check(#searches == 2, "...A left set to press Search: a release without its press doesn't search")
GamepadKeyboardAButton.attrs.type, GamepadKeyboardAButton.attrs.clickbutton = "click", searchButton
type("ok")
check(#searches == 2 and preview() == "Ok" .. CARET, "...A left set to press Search (a press cut short): a tap still just types")
playerClick(key("ENTER"))
check(macros[#macros] == "/s Ok" and #searches == 2, "...and Enter in chat still sends its line")
poll()
openChat("SAY"); poll()
type("by mouse"); secureClick(key("ENTER"), false) -- (a click on the Enter key itself: its own secure action)
check(macros[#macros] == "/s By mouse" and not kb:IsShown() and key("ENTER").attrs.macrotext == "",
	"the Enter key clicked (the mouse): its own secure action sends the line, then empties")
poll()
-- Blizzard's other looked-through boxes, found where they are once their window has loaded.
local function blizzardBox(parent, center, name)
	local box = W.CreateFrame("EditBox", name, parent, "InputBoxTemplate"); box.center = center
	box.sourceLocation = "Interface/AddOns/Blizzard_Test/Test.xml:1"
	if name then blizzardGlobals[name] = true end
	return box
end
-- A list filter (the mount journal's): its own Enter.
MountJournal = blizzardFrame(W.CreateFrame("Frame", "MountJournal", UIParent))
MountJournal.searchBox = blizzardBox(MountJournal, { 400, 700 })
local mountEnter = 0
MountJournal.searchBox.scripts.OnEnterPressed = function(self) mountEnter = mountEnter + 1; self:ClearFocus() end
manager:FrameShown(MountJournal)
padA(function() MountJournal.searchBox:SetFocus() end)
check(kb:IsShown() and key("q") and key("SPACE"), "the mount journal's search: the keyboard, letters")
type("raptor"); before = #macros
playerClick(key("ENTER"))
check(MountJournal.searchBox:GetText() == "raptor" and mountEnter == 1 and #macros == before and not kb:IsShown(),
	"...Enter: the box's own Enter (it only drops focus)")
MountJournal.searchBox.text = ""; manager:FrameHidden(MountJournal); MountJournal = nil; poll()
-- A search whose own Enter is Blizzard's to make (Who): its button, pressed securely.
local whoBox = blizzardBox(UIParent, { 400, 700 }, "WhoFrameEditBox")
_G.WhoFrameEditBox = whoBox
LFGWhoListFrame = blizzardFrame(W.CreateFrame("Frame", "LFGWhoListFrame", UIParent))
LFGWhoListFrame.WhoSearch = W.CreateFrame("Button", nil, LFGWhoListFrame)
local whoSearches, whoEnter = {}, 0
LFGWhoListFrame.WhoSearch.scripts.OnClick = function() whoSearches[#whoSearches + 1] = { text = whoBox:GetText(), secure = W.inSecure } end
whoBox.scripts.OnEnterPressed = function() whoEnter = whoEnter + 1 end -- (C_FriendList.SendWho)
manager:FrameShown(LFGWhoListFrame)
padA(function() whoBox:SetFocus() end)
type("bob")
playerClick(key("ENTER"))
check(#whoSearches == 1 and whoSearches[1].text == "bob" and whoSearches[1].secure and whoEnter == 0 and not kb:IsShown() and not whoBox:HasFocus(),
	"Who: Enter presses Who's search button, securely - not the box's own Enter")
padA(function() whoBox:SetFocus() end)
playerClick(key("SYMBOLS"))
secureClick(key("ENTER"), false) -- (the symbols page's Enter key, clicked)
check(#whoSearches == 2 and whoSearches[2].secure and whoEnter == 0 and not kb:IsShown() and key("ENTER").attrs.type == "macro" and key("ENTER").attrs.clickbutton == nil,
	"...the Enter key itself clicked (the symbols page's): the same, and it's a macro button again after")
table.remove(whoSearches)
-- Its button missing (a window half there): nothing pressed, and still never its own Enter.
local whoButton = LFGWhoListFrame.WhoSearch; LFGWhoListFrame.WhoSearch = nil
padA(function() whoBox:SetFocus() end)
type("x")
playerClick(key("ENTER"))
check(#whoSearches == 1 and whoEnter == 0 and not kb:IsShown() and not whoBox:HasFocus() and key("ENTER").attrs.type == "macro",
	"...its button not there: nothing pressed, not its own Enter either; the box lets go")
LFGWhoListFrame.WhoSearch = whoButton
-- (the keyboard staying open after Enter: the search, still never its own Enter)
GamepadKeyboardDB.closeOnEnter = false
padA(function() whoBox:SetFocus() end)
playerClick(key("ENTER"))
check(#whoSearches == 2 and whoEnter == 0 and kb:IsShown() and whoBox:HasFocus(), "...set to stay open after Enter: searched, still typing")
GamepadKeyboardDB.closeOnEnter = nil
kb:SmartNavigationCloseHandler(); whoBox:ClearFocus(); whoBox.text = ""; manager:FrameHidden(LFGWhoListFrame)
_G.WhoFrameEditBox, LFGWhoListFrame = nil, nil; poll()
-- Its own Enter not run from here, nothing to press (the professions' small search): Enter just lets go.
ProfessionsFrame = blizzardFrame(W.CreateFrame("Frame", "ProfessionsFrame", UIParent))
ProfessionsFrame.CraftingPage = W.CreateFrame("Frame", nil, ProfessionsFrame)
local miniSearch = blizzardBox(ProfessionsFrame.CraftingPage, { 400, 700 })
ProfessionsFrame.CraftingPage.MinimizedSearchBox = miniSearch
local miniEnter = 0
miniSearch.scripts.OnEnterPressed = function() miniEnter = miniEnter + 1 end -- (picks a result: SmartNavigation)
manager:FrameShown(ProfessionsFrame)
for _, stay in ipairs({ false, true }) do
	if stay then GamepadKeyboardDB.closeOnEnter = false end
	padA(function() miniSearch:SetFocus() end)
	type("bolt")
	playerClick(key("ENTER")); poll()
	check(miniEnter == 0 and not miniSearch:HasFocus() and miniSearch:GetText():find("bolt", 1, true) and kb:IsShown() == stay,
		"the professions' small search: Enter lets go of typing, not the box's own Enter" .. (stay and " (set to stay open: the keyboard stays)" or ""))
	kb:SmartNavigationCloseHandler(); poll()
end
GamepadKeyboardDB.closeOnEnter = nil
manager:FrameHidden(ProfessionsFrame); ProfessionsFrame = nil; poll()
-- A currency transfer's amount: numbers; its own Enter.
CurrencyTransferMenu = blizzardFrame(W.CreateFrame("Frame", "CurrencyTransferMenu", UIParent))
CurrencyTransferMenu.Content = W.CreateFrame("Frame", nil, CurrencyTransferMenu)
CurrencyTransferMenu.Content.AmountSelector = W.CreateFrame("Frame", nil, CurrencyTransferMenu.Content)
local amount = blizzardBox(CurrencyTransferMenu.Content.AmountSelector, { 400, 700 }); amount:SetNumeric(true)
CurrencyTransferMenu.Content.AmountSelector.InputBox = amount
local amountEnter = 0
amount.scripts.OnEnterPressed = function(self) amountEnter = amountEnter + 1; self:ClearFocus() end
manager:FrameShown(CurrencyTransferMenu)
padA(function() amount:SetFocus() end)
check(kb:IsShown() and key("1") and not key("q"), "a currency transfer's amount: the numpad")
type("250")
playerClick(key("ENTER"))
check(amount:GetText() == "250" and amountEnter == 1 and not kb:IsShown(), "...Enter: the box's own Enter")
amount.text = ""; manager:FrameHidden(CurrencyTransferMenu); CurrencyTransferMenu = nil; poll()
-- A Blizzard box not looked through (the quest log's search): not opened, and said why.
QuestScrollFrame = blizzardFrame(W.CreateFrame("Frame", "QuestScrollFrame", UIParent))
QuestScrollFrame.SearchBox = blizzardBox(QuestScrollFrame, { 400, 700 })
manager:FrameShown(QuestScrollFrame)
local notesBeforeQuest = #world.printed
padA(function() QuestScrollFrame.SearchBox:SetFocus() end)
check(not kb:IsShown() and #world.printed == notesBeforeQuest + 1 and world.printed[#world.printed]:find("the game's own text box", 1, true),
	"the quest log's search (Blizzard's, not looked through): no keyboard, and a note why")
QuestScrollFrame.SearchBox:ClearFocus(); manager:FrameHidden(QuestScrollFrame); QuestScrollFrame = nil; poll()
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

finish()
