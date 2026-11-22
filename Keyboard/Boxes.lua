-- Which text boxes the keyboard types into: Blizzard's looked through (REVIEWED), other addons', none
-- unknown - and the note when it doesn't open.

local ADDON_NAME, ns = ...;
local S = ns.S;
local ChatFor, Print, Sayable = ns.ChatFor, ns.Print, ns.Sayable;

-- Blizzard's own text boxes looked through: what typing runs there (as this addon's doing) only redraws,
-- reads or filters a list, and what they lead to reads the box itself (GetText / GetNumber) - so the calls
-- only Blizzard's UI may make stay Blizzard's. The rest are left to a real keyboard. Each is found where it
-- is (a global name, then keys: windows that load when first opened aren't there before), with what Enter
-- does there: its own Enter (no `enter`), "clear" (let go of typing), or one of its buttons - pressed through
-- the Enter key's secure action, where its own Enter would make a call only Blizzard's UI may make (a
-- search whose results lead to buying, a purchase) the addon's.
local REVIEWED = {
	-- The mail: To:, Subject:, text, money (read the text, show / hide the money boxes, enable Send; Enter in
	-- the money moves to the next box).
	{ box = { "SendMailNameEditBox" } }, { box = { "SendMailSubjectEditBox" } }, { box = { "SendMailBodyEditBox" } },
	{ box = { "SendMailMoneyGold" } }, { box = { "SendMailMoneySilver" } }, { box = { "SendMailMoneyCopper" } },
	-- The auction house's search (redraws the box; its own Enter keeps the filters in a table the results -
	-- and buying - read).
	{ box = { "AuctionHouseFrame", "SearchBar", "SearchBox" }, enter = { "AuctionHouseFrame", "SearchBar", "SearchButton" } },
	-- Collections, the transmogrifier, professions, the addon list: list filters (results arrive later or
	-- only redraw), their own Enter just drops focus.
	{ box = { "MountJournal", "searchBox" } },
	{ box = { "PetJournal", "searchBox" } },
	{ box = { "WardrobeCollectionFrame", "SearchBox" } },
	{ box = { "TransmogFrame", "WardrobeCollection", "TabContent", "ItemsFrame", "SearchBox" } },
	{ box = { "TransmogFrame", "WardrobeCollection", "TabContent", "SetsFrame", "SearchBox" } },
	{ box = { "ProfessionsFrame", "CraftingPage", "RecipeList", "SearchBox" } },
	-- (its own Enter picks a result from the addon's code: SmartNavigation refuses that)
	{ box = { "ProfessionsFrame", "CraftingPage", "MinimizedSearchBox" }, enter = "clear" },
	{ box = { "AddonList", "SearchBox" } },
	-- Searches whose own Enter makes a call only Blizzard's UI may make, as their buttons do: the button.
	{ box = { "WhoFrameEditBox" }, enter = { "LFGWhoListFrame", "WhoSearch" } },
	{ box = { "ClubFinderGuildFinderFrame", "OptionsList", "SearchBox" }, enter = { "ClubFinderGuildFinderFrame", "OptionsList", "Search" } },
	{ box = { "ClubFinderCommunityAndGuildFinderFrame", "OptionsList", "SearchBox" },
		enter = { "ClubFinderCommunityAndGuildFinderFrame", "OptionsList", "Search" } },
	{ box = { "ProfessionsCustomerOrdersFrame", "BrowseOrders", "SearchBar", "SearchBox" },
		enter = { "ProfessionsCustomerOrdersFrame", "BrowseOrders", "SearchBar", "SearchButton" } },
	-- A crafting order: who it's for, the tip (the order reads them itself).
	{ box = { "ProfessionsCustomerOrdersFrame", "Form", "OrderRecipientTarget" } },
	{ box = { "ProfessionsCustomerOrdersFrame", "Form", "PaymentContainer", "TipMoneyInputFrame", "GoldBox" }, enter = "clear" },
	{ box = { "ProfessionsCustomerOrdersFrame", "Form", "PaymentContainer", "TipMoneyInputFrame", "SilverBox" }, enter = "clear" },
	-- A currency transfer's amount (Confirm reads the box), the alarm's message, a guild charter's name (its
	-- own Enter is Purchase's), the Black Market's bid (Bid reads it, then Blizzard's confirmation; its own
	-- Enter only moves on to a silver box the Black Market hides).
	{ box = { "CurrencyTransferMenu", "Content", "AmountSelector", "InputBox" } },
	{ box = { "TimeManagerAlarmMessageEditBox" } },
	{ box = { "GuildRegistrarFrameEditBox" }, enter = { "GuildRegistrarFramePurchaseButton" } },
	{ box = { "BlackMarketBidPrice", "gold" }, enter = "clear" },
};
-- The auction house's sell forms (an item, a stack): quantity (its handler acts only on a real keyboard's
-- typing) and price (redraws the form; its undercut hint never shows in the controller UI) - Create Auction
-- reads the boxes' numbers itself. And a single item's bid: Bid reads the boxes, then Blizzard's own
-- confirmation. Not a stack's buy quantity (see SpecialNote).
for _, form in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
	table.insert(REVIEWED, { box = { "AuctionHouseFrame", form, "QuantityInput", "InputBox" } });
	for _, price in ipairs({ "PriceInput", "SecondaryPriceInput" }) do
		for _, coin in ipairs({ "GoldBox", "SilverBox", "CopperBox" }) do
			table.insert(REVIEWED, { box = { "AuctionHouseFrame", form, price, "MoneyInputFrame", coin } });
		end
	end
end
for _, coin in ipairs({ "gold", "silver", "copper" }) do
	table.insert(REVIEWED, { box = { "AuctionHouseFrame", "ItemBuyFrame", "BidFrame", "BidAmount", coin } });
end

-- The frame at a place: a global's name, then keys (nil while any of it isn't there).
local function FrameAt(place)
	local node = _G[place[1]];
	for i = 2, #place do
		if type(node) ~= "table" then
			return nil;
		end
		node = node[place[i]];
	end
	return node;
end

-- The looked-through entry for a box, if it's one.
local function Reviewed(box)
	for _, entry in ipairs(REVIEWED) do
		if FrameAt(entry.box) == box then
			return entry;
		end
	end
end

-- The button Enter presses for a box (nil: none - its own Enter, or just letting go).
local function EnterButton(box)
	local entry = Reviewed(box);
	if entry and type(entry.enter) == "table" then
		return FrameAt(entry.enter);
	end
end

-- The text boxes it types into. What it types runs the box's own handlers as this addon's doing (tainted),
-- and a Blizzard box's can go on into calls only Blizzard's UI may make - the bag search's fires a
-- synchronous inventory event whose listeners reach the gamepad action bar's interact target; the Options
-- search keeps the text for the panel's close, right before it saves key bindings: "blocked from an action
-- only available to the Blizzard UI", blamed on this addon. So: chat boxes (never typed into: the keyboard
-- keeps the line - in a chat a macro line can say), Blizzard boxes looked through, and boxes another addon
-- made. Not knowing whose: none. (Blizzard's looked through: REVIEWED.)

-- Whose a text box is - not from its handlers: a value this addon reads comes back as its own, so
-- issecurevalue never says Blizzard's (in the game every box passed that, the bag search too). From where it
-- was made: the first named frame from the box up (short of UIParent) is Blizzard's if its global was set
-- by Blizzard's code (issecurevariable), an addon's if not; with none, the file it was made in
-- (GetSourceLocation: Blizzard's own, or an addon's). nil: no telling.
local function MadeByBlizzard(box)
	if issecurevariable then
		local frame = box;
		while frame and frame ~= UIParent do
			local name = frame:GetName();
			if name and _G[name] == frame then
				return issecurevariable(name) and true or false;
			end
			frame = frame:GetParent();
		end
	end
	local location = box.GetSourceLocation and box:GetSourceLocation();
	if (issecretvalue and issecretvalue(location)) or type(location) ~= "string" then
		return nil;
	end
	location = location:lower():gsub("\\", "/");
	return location:find("/addons/blizzard_", 1, true) ~= nil or not location:find("/addons/", 1, true);
end

local function CanType(box)
	if box.chatFrame then
		return Sayable(ChatFor(box));
	end
	if Reviewed(box) then
		return true;
	end
	return MadeByBlizzard(box) == false;
end

-- Said once a box (a chat: once a chat type): why the keyboard didn't come.
local toldAbout = {};

-- Boxes with a reason of their own, and a way that works with the controller.
local function SpecialNote(box)
	local buyFrame = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame;
	local buyQuantity = buyFrame and buyFrame.BuyDisplay and buyFrame.BuyDisplay.QuantityInput;
	if buyQuantity and box == buyQuantity.InputBox then
		-- Its price is worked out only on a real keyboard's typing, and Buy then checks it against the
		-- server's (typed from here: "price unavailable"); working it out from here would make the purchase,
		-- a call only Blizzard's UI may make, the addon's.
		return "not for the Auction House's buy quantity: its price only follows a real keyboard's typing. Pick the amount from the price list instead (A on a row buys up to it).";
	end
	local parent = box:GetParent();
	if parent and (box == parent.MinLevel or box == parent.MaxLevel) and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
		-- The Filter list's level range (LevelRangeFrameTemplate): typing there writes the search's filters
		-- (g_auctionHouseFilters), which every search, and buying from it, reads - the addon's from then on.
		return "not for the Auction House's level range: it goes into the search's filters, which buying reads too. For gear you can use now, tick Usable Only in the same list.";
	end
end

local function TellCantType(box)
	if box.chatFrame then
		local chatType = tostring(ChatFor(box).chatType);
		if not toldAbout[chatType] then
			toldAbout[chatType] = true;
			Print(("not for %s: Blizzard sends that only from its own chat box. A real keyboard types there as usual."):format(
				chatType == "BN_WHISPER" and "Battle.net whispers" or ("this chat (" .. chatType .. ")")));
		end
	elseif not toldAbout[box] then
		toldAbout[box] = true;
		if SpecialNote(box) then
			Print(SpecialNote(box));
		elseif MadeByBlizzard(box) then
			Print(("not for %s: it's the game's own text box, and typing into it from an addon gets the game to block the addon. A real keyboard types there as usual."):format(
				box:GetName() or "this text box"));
		else
			Print(("not for %s: there's no telling whose text box it is (the game's own would get the addon blocked). A real keyboard types there as usual."):format(
				box:GetName() or "this text box"));
		end
	end
end

ns.CanType, ns.EnterButton, ns.Reviewed, ns.TellCantType = CanType, EnterButton, Reviewed, TellCantType;
