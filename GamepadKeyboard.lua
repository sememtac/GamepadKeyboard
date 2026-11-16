-- Gamepad Keyboard: an on-screen keyboard for typing with a controller.
--
-- When a text box gets typing focus in the game's controller UI (out of combat), the keyboard opens as a
-- popup in Blizzard's gamepad UI, like its own panels: the D-pad moves between keys (left / right along a
-- row, up / down between rows), A types, Enter does what Enter does, B goes back without it. Each key
-- writes straight into the text box, which is the preview, and closing returns the controller to the
-- window the box belongs to.
--
-- Enter in chat sends the message and closes the chat, as Enter does - but not through the chat's send code,
-- which addon code shouldn't run (it writes chat state that secure commands read later). The Enter key is a
-- secure macro button: the message becomes the line Enter would send (/w Bob ..., /p ..., /2 ..., or a typed
-- command as is), run by Blizzard's secure macro action on the press. A chat type no macro line can say
-- goes back to the chat box instead, where the chat's own A sends it. Opening the keyboard moves the
-- controller off the chat box, which would close an empty box and reset its chat type (a whisper target,
-- say); a single space put in first keeps it open. Enter in any other box runs that box's own Enter action.
--
-- While it has the controller, X is Del, Y is Space, LB / RB move the cursor left and right, and holding A
-- is Enter: override bindings that click those keys, as the game's controller UI binds its own buttons.
-- A goes to a hidden secure button that hears the press and the release: a tap presses the key the D-pad
-- is on (on release), a hold sends - a real press, so Enter's secure macro line runs as from the Enter key.
-- Keys type at the cursor, which the preview shows.
--
-- A text box that looks names up as they're typed (the mail's To:) gets them as keys on a row of their own:
-- Blizzard's list there only follows typing on a real keyboard and is picked with Tab or the mouse.
--
-- For chat, a chat key steps through the chat types there are to use (Say, Party, Raid, Instance, Guild,
-- a reply to the last whisper). It switches the way typing does: it puts the type's slash command before
-- the text, and the chat box's own parsing switches the chat and keeps the text.
--
-- Whichever the player is using has the text box. The keyboard opens only when the controller asked for it
-- (A on a text box, Chat on the menu dial) - not when a real keyboard opened the chat (Enter, /, reply) or
-- a mouse click put focus in some box. And when a real keyboard or the mouse takes the chat box back while
-- it's open, it steps aside. Keys are only ever looked at (IsKeyDown), never listened to: a
-- listening frame keeps every key it isn't allowed to pass on, and SetPropagateKeyboardInput is restricted
-- (in combat at least).
--
-- In combat Blizzard's gamepad UI takes no addon windows, so the keyboard doesn't open (a real keyboard
-- types as always), and an open one closes when combat starts; the text stays in the box.

local ADDON_NAME = ...;

local KEY_WIDTH, KEY_HEIGHT, GAP = 36, 30, 4;
local PLACEHOLDER = " ";

local BACK, SHIFT, SYMBOLS, LETTERS, SPACE, ENTER, CHAT = "BACK", "SHIFT", "SYMBOLS", "LETTERS", "SPACE", "ENTER", "CHAT";
local SPECIAL_KEYS = {
	[BACK] = { label = "Del", units = 1.6 },
	[SHIFT] = { label = "Shift", units = 1.6 },
	[SYMBOLS] = { label = "?123", units = 2 },
	[LETTERS] = { label = "ABC", units = 2 },
	[SPACE] = { label = "Space", units = 4 },
	[ENTER] = { label = "Enter", units = 2.5 },
	[CHAT] = { label = "Say", units = 2.5 }, -- chat only; shows the chat type
};
-- No "|": the game reads it as the start of an escape code.
local PAGES = {
	letters = {
		{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", BACK },
		{ "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
		{ "a", "s", "d", "f", "g", "h", "j", "k", "l", "'" },
		{ SHIFT, "z", "x", "c", "v", "b", "n", "m", ",", "." },
		{ SYMBOLS, CHAT, SPACE, ENTER },
	},
	symbols = {
		{ "!", "@", "#", "$", "%", "&", "*", "(", ")", "-", BACK },
		{ "/", "\\", ":", ";", "\"", "?", "+", "=", "_", "~" },
		{ "<", ">", "[", "]", "{", "}", "^", "`", "'", "," },
		{ LETTERS, CHAT, SPACE, ENTER },
	},
};

local keyboard;
local keys = {}; -- page -> rows of key buttons
local page = "letters";
local target; -- the text box being typed into
local isChat = false;
local suggesting = false; -- the box looks names up (a row of name keys above the keys)
local suggestions = {}; -- the name keys
local lastNamesBox; -- the last box typed into that isn't chat (for /gk names)
local text = "";
local cursor = 0; -- characters before the cursor
local shift = false;
local handedBack; -- the box the keyboard just went back to: not opened for again until focus moves on
local closing = false; -- while closing hands the controller back (which focuses the box again)
local lastInput = "gamepad"; -- what the player pressed last: "gamepad", "keyboard" or "mouse"
local chatHadFocus; -- while open over chat: whether the chat box had typing focus last frame

local function DB()
	GamepadKeyboardDB = GamepadKeyboardDB or {};
	return GamepadKeyboardDB;
end

local function Print(message)
	print("|cff33ff99Gamepad Keyboard|r: " .. message);
end

local function UsesGamepadUI()
	return C_InputInterfaceStyle ~= nil and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad;
end

local function Utf8Length(s)
	return select(2, s:gsub("[^\128-\191]", ""));
end

-------------------------------------------------------------------------------
-- Blizzard's gamepad UI: the keyboard as a popup over the window the text box belongs to
-------------------------------------------------------------------------------

-- Only through the functions Blizzard wraps for outside callers (HandlePopupShown / HandlePopupHide,
-- RefreshButtonGroups, jump overrides), only out of combat; our frames never set the fields its focus
-- manager reads directly. A refused call returns nothing, so the manager's list is checked, and the
-- registration is retried after combat.
local registered = false;

local function GetManager()
	return GamepadMode and GamepadMode.FrameControlsManager;
end

local function IsListed(manager)
	if type(manager.shownFrames) ~= "table" then
		return nil;
	end
	for _, shown in ipairs(manager.shownFrames) do
		if shown == keyboard then
			return true;
		end
	end
	return false;
end

local function Register()
	local manager = GetManager();
	if registered or not manager or InCombatLockdown() or not UsesGamepadUI() then
		return;
	end
	local ok = pcall(manager.HandlePopupShown, manager, keyboard);
	local listed = IsListed(manager);
	registered = listed or (listed == nil and ok) or false;
end

local function Unregister()
	local manager = GetManager();
	if not registered or not manager or InCombatLockdown() then
		return;
	end
	local ok = pcall(manager.HandlePopupHide, manager, keyboard);
	local listed = IsListed(manager);
	registered = not (listed == false or (listed == nil and ok));
end

-- Rows for the D-pad: left / right move along a row of keys, up / down go to the next row, to the key
-- nearest in X. Sent as SmartNavigation jump overrides (Blizzard's setter for this), only changes.
local DIRECTIONS = { UP = { -1, 0 }, DOWN = { 1, 0 }, LEFT = { 0, -1 }, RIGHT = { 0, 1 } };
local applied = setmetatable({}, { __mode = "k" }); -- key -> direction -> target

local function IsUsable(button)
	return button:IsVisible() and button:IsEnabled() and true or false;
end

local function FindInRows(rows, from, direction)
	local step = DIRECTIONS[direction];
	for r, row in ipairs(rows) do
		for c, button in ipairs(row) do
			if button == from then
				if step[2] ~= 0 then
					for i = c + step[2], step[2] > 0 and #row or 1, step[2] do
						if IsUsable(row[i]) then
							return row[i];
						end
					end
					return nil;
				end
				local fromX = from:GetCenter();
				for i = r + step[1], step[1] > 0 and #rows or 1, step[1] do
					local best, bestDistance;
					for _, candidate in ipairs(rows[i]) do
						if IsUsable(candidate) then
							local x = candidate:GetCenter();
							local distance = (fromX and x) and math.abs(x - fromX) or 0;
							if not bestDistance or distance < bestDistance then
								best, bestDistance = candidate, distance;
							end
						end
					end
					if best then
						return best;
					end
				end
				return nil;
			end
		end
	end
	return nil;
end

local function RefreshNavigation()
	if not registered or InCombatLockdown() then
		return;
	end
	if SmartNavigation and SmartNavigation.RefreshButtonGroups then
		pcall(SmartNavigation.RefreshButtonGroups, SmartNavigation, keyboard);
	end
	if not (SmartNavigation_AddJumpNavigationOverride and SMART_NAV_INPUT_DIRECTION) then
		return;
	end
	local rows = keys[page];
	if suggesting then
		rows = { suggestions, unpack(keys[page]) };
	end
	for _, row in ipairs(rows) do
		for _, button in ipairs(row) do
			applied[button] = applied[button] or {};
			for direction in pairs(DIRECTIONS) do
				local destination = FindInRows(rows, button, direction) or true;
				if applied[button][direction] ~= destination then
					local ok = pcall(SmartNavigation_AddJumpNavigationOverride, button, SMART_NAV_INPUT_DIRECTION[direction], destination);
					applied[button][direction] = ok and destination or nil;
				end
			end
		end
	end
end

-- Blizzard's LT / RT / View jump hints and focus glow (FocusFramesInterfaceTemplate): lift the hints to our
-- strata, and give the glow the frame art Blizzard uses for plain panels.
local function SetUpFocusVisuals()
	for _, key in ipairs({ "LeftJumpHint", "RightJumpHint", "FocusJumpHint" }) do
		if keyboard[key] then
			keyboard[key]:SetFrameStrata(keyboard:GetFrameStrata());
		end
	end
	if keyboard.FrameGlow and keyboard.FrameGlow.OnLoad then
		keyboard.layoutType = "ButtonFrameTemplateNoPortrait";
		keyboard.FrameGlow:OnLoad();
	end
end

-------------------------------------------------------------------------------
-- Typing
-------------------------------------------------------------------------------

-- The chat types the chat key steps through, each when it's there to use, and the slash command that
-- switches to it. Reply: a whisper to whoever whispered last (Blizzard's own getter, which only reads).
local function LastTell()
	if ChatFrameUtil and ChatFrameUtil.GetLastTellTarget then
		return ChatFrameUtil.GetLastTellTarget();
	end
end

local CHAT_TYPES = { -- Reply last: from it, round to Say
	{ chatType = "SAY", command = "/s" },
	{ chatType = "PARTY", command = "/p", available = function() return IsInGroup(LE_PARTY_CATEGORY_HOME) end },
	{ chatType = "RAID", command = "/ra", available = function() return IsInRaid(LE_PARTY_CATEGORY_HOME) end },
	{ chatType = "INSTANCE_CHAT", command = "/i", available = function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end },
	{ chatType = "GUILD", command = "/g", available = function() return IsInGuild() end },
	{ reply = true, command = "/r", available = function() return LastTell() ~= nil end },
};
local CHAT_LABELS = {
	SAY = "Say", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance", GUILD = "Guild", OFFICER = "Officer",
	YELL = "Yell", EMOTE = "Emote", RAID_WARNING = "Warning",
};

local function IsWhisper(chatType)
	return chatType == "WHISPER" or chatType == "BN_WHISPER";
end

local function ChatLabel(box)
	local chatType = box:GetAttribute("chatType");
	if IsWhisper(chatType) then
		local name = tostring(box:GetAttribute("tellTarget") or "");
		if not name:find("^|K") then -- a Battle.net name shows as itself
			name = name:gsub("%-.*$", "");
			if Utf8Length(name) > 9 then
				name = name:sub(1, 8) .. "..";
			end
		end
		return "To " .. name;
	elseif chatType == "CHANNEL" then
		return "/" .. tostring(box:GetAttribute("channelTarget") or "?");
	end
	return CHAT_LABELS[chatType] or "Chat";
end

-- The byte just after the first `characters` characters of s.
local function ByteAfter(s, characters)
	local i = 1;
	for _ = 1, characters do
		if i > #s then
			break;
		end
		i = i + 1;
		while i <= #s and s:byte(i) >= 128 and s:byte(i) < 192 do
			i = i + 1;
		end
	end
	return i;
end

local function Split(s, characters)
	local at = ByteAfter(s, characters);
	return s:sub(1, at - 1), s:sub(at);
end

-- The text with the cursor (a gold bar; "||" shows one "|"), at most 48 characters of it around the cursor.
local CARET = "|cffffd100|||r"; -- "||" a "|", then "|r" ends the colour
local PREVIEW_LENGTH = 48;

-- Names for a box that looks them up as it's typed in: Blizzard's own list (AutoCompleteBox) updates only
-- on a real keyboard's typing, is picked with Tab or the mouse, and calling its update from here would leave
-- addon-written state that the chat's Enter reads. So: the box's own lookup - only Blizzard's read-only
-- C_AutoComplete.GetAutoCompleteResults, never a box's own function - shown as keys; picking one puts the
-- name in as Blizzard's list does (AutoCompleteButton_OnClick).
local MAX_SUGGESTIONS = 4;

local function LooksUpNames(box)
	return not box.chatFrame and C_AutoComplete ~= nil and box.autoCompleteSource == C_AutoComplete.GetAutoCompleteResults
		and type(box.autoCompleteParams) == "table" and box.customAutoCompleteFunction == nil;
end

local function UpdateSuggestions()
	local names = {};
	if suggesting and target and text ~= "" then
		-- Protected: a lookup that fails leaves no names, never a key press half done (and /gk names says why).
		local ok, results = pcall(C_AutoComplete.GetAutoCompleteResults, text, MAX_SUGGESTIONS + 1, cursor, true, unpack(target.autoCompleteParams));
		results = ok and type(results) == "table" and results or {};
		if not (#results == 1 and results[1].name == text) then -- the name already typed: nothing to pick
			for i = 1, math.min(#results, MAX_SUGGESTIONS) do
				names[i] = results[i].name;
			end
		end
	end
	local changed = false;
	for i, button in ipairs(suggestions) do
		changed = changed or button.suggestion ~= names[i];
		button.suggestion = names[i];
		button:SetText(names[i] and Ambiguate(names[i], "none") or "");
		button:SetShown(names[i] ~= nil);
	end
	if changed then
		RefreshNavigation(); -- up from the top row of keys: to a name, or nowhere
	end
end

local function UpdatePreview()
	local length = Utf8Length(text);
	local first = math.max(0, math.min(cursor - PREVIEW_LENGTH + 8, length - PREVIEW_LENGTH));
	local last = math.min(length, first + PREVIEW_LENGTH);
	local before = select(2, Split(select(1, Split(text, cursor)), first));
	local after = select(1, Split(select(2, Split(text, cursor)), last - cursor));
	keyboard.Preview:SetText((first > 0 and "..." or "") .. before .. CARET .. after .. (last < length and "..." or ""));
	if isChat and target then
		for _, chatKey in ipairs(keyboard.ChatKeys) do
			chatKey:SetText(ChatLabel(target));
		end
	end
	UpdateSuggestions();
end

local function UpdateLabels()
	for _, row in ipairs(keys.letters) do
		for _, button in ipairs(row) do
			if not SPECIAL_KEYS[button.key] then
				button:SetText(shift and button.key:upper() or button.key);
			end
		end
	end
	keyboard.ShiftKey:LockHighlight();
	if not shift then
		keyboard.ShiftKey:UnlockHighlight();
	end
end

local function SetText(newText, newCursor)
	text = newText;
	cursor = newCursor or Utf8Length(text);
	if target then
		target:SetText(text);
		text = target:GetText() or ""; -- the box may change it (chat: "/p " switches to party chat)
		cursor = math.min(cursor, Utf8Length(text));
	end
	UpdatePreview();
end

-- The box may have changed under the keyboard (typed into on a real keyboard, a link put in): carry on from
-- what's in it. A chat box holding only the placeholder is still empty.
local function Sync()
	local current = target and target:GetText() or "";
	if not (isChat and current == PLACEHOLDER and text == "") and current ~= text then
		text = current;
		cursor = Utf8Length(text);
	end
end

-- The character before the cursor.
local function DeleteBack()
	if cursor > 0 then
		local before, after = Split(text, cursor);
		SetText(select(1, Split(before, cursor - 1)) .. after, cursor - 1);
	end
end

local function Insert(characters)
	local maxLetters = target and target:GetMaxLetters() or 0;
	if maxLetters > 0 and Utf8Length(text) + Utf8Length(characters) > maxLetters then
		return;
	end
	local before, after = Split(text, cursor);
	SetText(before .. characters .. after, cursor + Utf8Length(characters));
end

local function ChooseSuggestion(button)
	if target and button.suggestion then
		local name = Ambiguate(button.suggestion, "none");
		SetText((target.command and (target.command .. " ") or "") .. name .. (target.addSpaceToAutoComplete and " " or ""));
	end
end

local function MoveCursor(step)
	if target then
		Sync();
		cursor = math.max(0, math.min(Utf8Length(text), cursor + step));
		UpdatePreview();
	end
end

-- The page's keys, the chat key only for chat; each row centred over the keys it shows.
local function Layout()
	local top = suggesting and 1 or 0;
	local nameWidth = (keyboard:GetWidth() - 28 - (MAX_SUGGESTIONS - 1) * GAP) / MAX_SUGGESTIONS;
	for i, button in ipairs(suggestions) do
		button:SetSize(nameWidth, KEY_HEIGHT);
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", 14 + (i - 1) * (nameWidth + GAP), -56);
		button:SetShown(suggesting and button.suggestion ~= nil);
	end
	for name, rows in pairs(keys) do
		for r, row in ipairs(rows) do
			local width = 0;
			for _, button in ipairs(row) do
				button:SetShown(name == page and (button.key ~= CHAT or isChat));
				if button:IsShown() then
					width = width + button.width + (width > 0 and GAP or 0);
				end
			end
			local x = (keyboard:GetWidth() - width) / 2;
			for _, button in ipairs(row) do
				if button:IsShown() then
					button:ClearAllPoints();
					button:SetPoint("TOPLEFT", x, -56 - (r - 1 + top) * (KEY_HEIGHT + GAP));
					x = x + button.width + GAP;
				end
			end
		end
	end
	keyboard:SetHeight(84 + (#keys[page] + top) * (KEY_HEIGHT + GAP));
end

-- The next chat type there is to use, after the box's own: its slash command goes before the text, and the
-- chat box's parsing (as when typing it) switches the chat and leaves the text.
local function NextChatType()
	local available = {};
	for _, entry in ipairs(CHAT_TYPES) do
		if not entry.available or entry.available() then
			available[#available + 1] = entry;
		end
	end
	-- After the box's own type; from anything else (a reply - always last - a whisper, a channel): Say.
	local chatType = target:GetAttribute("chatType");
	local current = 0;
	for i, entry in ipairs(available) do
		if entry.chatType == chatType then
			current = i;
		end
	end
	local nextType = available[current % #available + 1];
	local keep = cursor;
	SetText(nextType.command .. " " .. text);
	cursor = math.min(keep, Utf8Length(text));
	UpdatePreview();
end

local function Close()
	if keyboard and keyboard:IsShown() then
		keyboard:Hide();
	end
end

local function Press(button)
	local key = button.key;
	Sync();
	if key == BACK then
		DeleteBack();
	elseif key == SPACE then
		Insert(" ");
	elseif key == SHIFT then
		shift = not shift;
		UpdateLabels();
	elseif key == SYMBOLS or key == LETTERS then
		page = key == SYMBOLS and "symbols" or "letters";
		Layout();
		RefreshNavigation();
	elseif key == CHAT then
		if isChat and target then
			NextChatType();
		end
	else
		Insert(shift and key:upper() or key);
		if shift then
			shift = false;
			UpdateLabels();
		end
	end
end

-------------------------------------------------------------------------------
-- The keyboard
-------------------------------------------------------------------------------

-- The line Enter would send for a chat message, as a macro line: nil and false if there's nothing to send,
-- nil and true if no macro line can say it (the chat's own A sends it instead).
local CHAT_COMMANDS = {
	SAY = "/s", YELL = "/y", EMOTE = "/e", PARTY = "/p", RAID = "/ra", RAID_WARNING = "/rw",
	INSTANCE_CHAT = "/i", GUILD = "/g", OFFICER = "/o", WHISPER = "/w",
}; -- not BN_WHISPER: its target can be a protected name string, which a macro line can't be trusted to keep
local MAX_LINE = 255;

local function ChatLine(box)
	local message = box:GetText() or "";
	if message == "" or message == PLACEHOLDER then
		return nil, false;
	end
	local line;
	if message:sub(1, 1) == "/" then
		line = message; -- a command, run as typed
	else
		local chatType = box:GetAttribute("chatType");
		if chatType == "WHISPER" then
			local tellTarget = box:GetAttribute("tellTarget");
			line = tellTarget and ("/w " .. tellTarget .. " " .. message);
		elseif chatType == "CHANNEL" then
			local channel = tonumber(box:GetAttribute("channelTarget"));
			line = channel and ("/" .. channel .. " " .. message);
		elseif CHAT_COMMANDS[chatType] then
			line = CHAT_COMMANDS[chatType] .. " " .. message;
		end
	end
	if not line or #line > MAX_LINE then
		return nil, true;
	end
	return line, false;
end

-- Before the secure macro action runs: the line to send (out of combat - the keyboard is closed in combat).
local function EnterPreClick(button)
	if InCombatLockdown() then
		return; -- closed in combat (its line was emptied after the last press)
	end
	local line, cannot;
	if target and isChat then
		line, cannot = ChatLine(target);
	end
	button.handBack = cannot;
	button:SetAttribute("macrotext", line or "");
end

-- After it: chat closes like after Enter (the chat type sticks, as Enter makes it); a chat type no macro
-- line can say goes back to the chat box to send with A; any other box gets its own Enter action.
local function EnterPostClick(button)
	if InCombatLockdown() then
		return;
	end
	local sentLine = button:GetAttribute("macrotext") or "";
	button:SetAttribute("macrotext", ""); -- nothing for a later press to send again
	local box, chat = target, isChat;
	if not box then
		return;
	end
	if chat and button.handBack then
		Close();
		Print("this chat sends with A on the chat box.");
		return;
	end
	if chat then
		local chatType = box:GetAttribute("chatType");
		local sent = sentLine ~= "" and (box:GetText() or ""):sub(1, 1) ~= "/";
		if sent and ChatTypeInfo and ChatTypeInfo[chatType] and ChatTypeInfo[chatType].sticky == 1 then
			box:SetAttribute("stickyType", chatType);
		end
		box:SetText("");
		Close(); -- back on the chat box, now empty...
		local manager = GetManager();
		if manager and box.chatFrame then
			pcall(manager.FrameHidden, manager, box.chatFrame); -- ...and the chat closes, as after Enter
		end
		return;
	end
	local onEnter = box:GetScript("OnEnterPressed");
	Close();
	if onEnter then
		onEnter(box);
	else
		box:ClearFocus();
	end
end

-- Holding A this long (seconds) is Enter.
local HOLD_TO_ENTER = 0.5;
local aDownAt; -- when A went down on the keyboard (nil when it isn't down)

-- A, as a hidden secure button: on the press, the time; on the release, either Enter (held, or on the
-- Enter key) - the Enter key's own PreClick / PostClick around Blizzard's secure macro action - or a tap on
-- the key the D-pad is on (SmartNavigation's current button; its getter only reads).
local function APreClick(button, _, down)
	if InCombatLockdown() then
		return;
	end
	if down then
		aDownAt = GetTime();
		button:SetAttribute("macrotext", "");
		return;
	end
	local current = SmartNavigation and SmartNavigation.GetCurrentButton and SmartNavigation:GetCurrentButton();
	local held = aDownAt and GetTime() - aDownAt >= HOLD_TO_ENTER;
	if not aDownAt then
		button.action = nil; -- a release whose press went elsewhere (A that opened the keyboard)
	elseif held or (current and current.key == ENTER) then
		button.action = "enter";
	else
		button.action = "tap";
		button.tapped = current;
	end
	aDownAt = nil;
	if button.action == "enter" then
		EnterPreClick(button);
	else
		button:SetAttribute("macrotext", "");
	end
end

local function APostClick(button, _, down)
	if down or InCombatLockdown() then
		return;
	end
	local action, tapped = button.action, button.tapped;
	button.action, button.tapped = nil, nil;
	if action == "enter" then
		EnterPostClick(button);
	elseif action == "tap" and tapped and tapped:IsVisible() and tapped:IsEnabled() then
		tapped:Click();
	end
end

-- The keys X and Y press (the first of each, on either page): a binding clicks a button by name.
local SHORTCUT_KEYS = { [BACK] = "GamepadKeyboardDelKey", [SPACE] = "GamepadKeyboardSpaceKey" };
local named = {};

local function CreateKey(key)
	local special = SPECIAL_KEYS[key];
	local units = special and special.units or 1;
	local name = SHORTCUT_KEYS[key];
	if named[key] then
		name = nil;
	end
	named[key] = named[key] or name ~= nil;
	local button;
	if key == ENTER then
		-- Blizzard's secure macro action, on release (a controller's A and a mouse click both act).
		button = CreateFrame("Button", name, keyboard, "SecureActionButtonTemplate, UIPanelButtonTemplate");
		button:RegisterForClicks("AnyUp");
		button:SetAttribute("type", "macro");
		button:SetAttribute("useOnKeyDown", false);
		button:SetAttribute("macrotext", "");
		button:SetScript("PreClick", EnterPreClick);
		button:SetScript("PostClick", EnterPostClick);
	else
		button = CreateFrame("Button", name, keyboard, "UIPanelButtonTemplate");
		button:SetScript("OnClick", Press);
	end
	button.width = units * KEY_WIDTH + (units - 1) * GAP;
	button:SetSize(button.width, KEY_HEIGHT);
	button:SetText(special and special.label or key);
	button.key = key;
	return button;
end

-- A, X, Y, LB and RB while the keyboard has the controller. The controller UI binds its buttons the same way (priority
-- override bindings, owner UIParent) and the latest binding of a button wins, so they're bound again when it
-- binds one of these over them (seen by post-hooking the binding functions). Cleared as soon as the
-- controller leaves the keyboard: the buttons are the controller UI's (and the crossbar's) again. Only out of combat (the
-- keyboard is closed in combat).
local SHORTCUTS = {
	[GAMEPAD_FACE_BOTTOM or "PAD1"] = "GamepadKeyboardAButton",
	[GAMEPAD_FACE_LEFT or "PAD3"] = SHORTCUT_KEYS[BACK],
	[GAMEPAD_FACE_TOP or "PAD4"] = SHORTCUT_KEYS[SPACE],
	[GAMEPAD_SHOULDER_LEFT or "PADLSHOULDER"] = "GamepadKeyboardCursorLeft",
	[GAMEPAD_SHOULDER_RIGHT or "PADRSHOULDER"] = "GamepadKeyboardCursorRight",
};
local shortcutsBound = false;

local function BindShortcuts()
	ClearOverrideBindings(keyboard);
	for button, keyName in pairs(SHORTCUTS) do
		SetOverrideBindingClick(keyboard, true, button, keyName);
	end
	shortcutsBound = true;
end

local function ClearShortcuts()
	if shortcutsBound and not InCombatLockdown() then
		ClearOverrideBindings(keyboard);
		shortcutsBound = false;
	end
end

local function UpdateShortcuts()
	if InCombatLockdown() then
		return;
	end
	local manager = GetManager();
	if keyboard and keyboard:IsShown() and manager and manager.focusedFrame == keyboard then
		if not shortcutsBound then
			BindShortcuts();
		end
	else
		ClearShortcuts();
	end
end

-- Held long enough: the Enter keys light up (letting go sends).
local function UpdateHoldHint()
	local lit = aDownAt ~= nil and GetTime() - aDownAt >= HOLD_TO_ENTER;
	if keyboard and keyboard.EnterKeys and keyboard.holdLit ~= lit then
		keyboard.holdLit = lit;
		for _, enterKey in ipairs(keyboard.EnterKeys) do
			if lit then
				enterKey:LockHighlight();
			else
				enterKey:UnlockHighlight();
			end
		end
	end
end

local function BoundOver(owner, _, button)
	if shortcutsBound and owner ~= keyboard and SHORTCUTS[button] and not InCombatLockdown() then
		BindShortcuts();
	end
end
hooksecurefunc("SetOverrideBindingClick", BoundOver);
hooksecurefunc("SetOverrideBinding", BoundOver);

local function CreatePrompt(key, label, anchorTo)
	local icon = CreateFrame("Frame", nil, keyboard, "InputIconTextureFrameTemplate");
	icon:SetSize(22, 22);
	icon:SetInputKey(key);
	if anchorTo then
		icon:SetPoint("LEFT", anchorTo, "RIGHT", 12, 0);
	else
		icon:SetPoint("BOTTOMLEFT", 14, 10);
	end
	local caption = keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	caption:SetPoint("LEFT", icon, "RIGHT", 3, 0);
	caption:SetText(label);
	return { icon = icon, text = caption };
end

local function CreateKeyboard()
	keyboard = CreateFrame("Frame", "GamepadKeyboardFrame", UIParent, "BasicFrameTemplateWithInset, FocusFramesInterfaceTemplate");
	keyboard:SetSize(11 * KEY_WIDTH + 10 * GAP + 28, 260);
	keyboard:SetFrameStrata("FULLSCREEN_DIALOG");
	keyboard:SetClampedToScreen(true);
	keyboard:EnableMouse(true);
	-- Drag it with the mouse; it opens there from then on (/gk reset forgets it).
	keyboard:SetMovable(true);
	keyboard:RegisterForDrag("LeftButton");
	keyboard:SetScript("OnDragStart", keyboard.StartMoving);
	keyboard:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing();
		local point, _, relativePoint, x, y = self:GetPoint();
		DB().position = { point = point, relativePoint = relativePoint, x = x, y = y };
	end);
	keyboard:Hide();
	tinsert(UISpecialFrames, "GamepadKeyboardFrame");

	keyboard.Title = keyboard:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	keyboard.Title:SetPoint("TOP", 0, -5);
	keyboard.Title:SetText("Keyboard");
	keyboard.Preview = keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	keyboard.Preview:SetPoint("TOPLEFT", 16, -32);
	keyboard.Preview:SetPoint("TOPRIGHT", -16, -32);
	keyboard.Preview:SetJustifyH("LEFT");

	keyboard.ChatKeys = {};
	keyboard.EnterKeys = {};
	for name, layout in pairs(PAGES) do
		keys[name] = {};
		for r, rowKeys in ipairs(layout) do
			local row = {};
			for c, key in ipairs(rowKeys) do
				row[c] = CreateKey(key);
				if key == SHIFT then
					keyboard.ShiftKey = row[c];
				elseif key == CHAT then
					table.insert(keyboard.ChatKeys, row[c]);
				elseif key == ENTER then
					table.insert(keyboard.EnterKeys, row[c]);
				end
			end
			keys[name][r] = row;
		end
	end

	for i = 1, MAX_SUGGESTIONS do
		local button = CreateFrame("Button", nil, keyboard, "UIPanelButtonTemplate");
		button:SetScript("OnClick", ChooseSuggestion);
		button:Hide();
		suggestions[i] = button;
	end

	-- A presses this one (hidden, secure: Enter's macro line runs from it).
	local aButton = CreateFrame("Button", "GamepadKeyboardAButton", keyboard, "SecureActionButtonTemplate");
	aButton:RegisterForClicks("AnyDown", "AnyUp");
	aButton:SetAttribute("type", "macro");
	aButton:SetAttribute("useOnKeyDown", false);
	aButton:SetAttribute("macrotext", "");
	aButton:SetScript("PreClick", APreClick);
	aButton:SetScript("PostClick", APostClick);
	aButton:Hide();

	-- LB / RB press these (hidden: not keys to move to).
	for name, step in pairs({ GamepadKeyboardCursorLeft = -1, GamepadKeyboardCursorRight = 1 }) do
		local button = CreateFrame("Button", name, keyboard);
		button:SetScript("OnClick", function()
			MoveCursor(step);
		end);
		button:Hide();
	end

	keyboard.Prompts = { CreatePrompt(GAMEPAD_FACE_BOTTOM, "Type (hold: Enter)") };
	for _, prompt in ipairs({
		{ GAMEPAD_FACE_LEFT, "Del" }, { GAMEPAD_FACE_TOP, "Space" }, { GAMEPAD_FACE_RIGHT, "Back" },
		{ GAMEPAD_SHOULDER_LEFT, "" }, { GAMEPAD_SHOULDER_RIGHT, "Cursor" },
	}) do
		table.insert(keyboard.Prompts, CreatePrompt(prompt[1], prompt[2], keyboard.Prompts[#keyboard.Prompts].text));
	end

	keyboard.CloseButton:SetScript("OnClick", Close);
	-- Controller B: go back, rather than Blizzard's gamepad UI pressing the close button.
	function keyboard:SmartNavigationCloseHandler()
		Close();
		return true;
	end

	SetUpFocusVisuals();
	keyboard:SetScript("OnShow", function()
		Layout();
		UpdateLabels();
		UpdatePreview();
		for _, prompt in ipairs(keyboard.Prompts) do
			prompt.icon:SetShown(UsesGamepadUI());
			prompt.text:SetShown(UsesGamepadUI());
		end
		Register();
		RefreshNavigation();
	end);
	-- However it closes (Enter, B, Escape, combat): back to the window the box belongs to, which focuses the
	-- box again - not a request for the keyboard - and the box isn't opened for again until focus moves
	-- elsewhere or it's asked for again. An untouched chat box loses its placeholder.
	keyboard:SetScript("OnHide", function()
		if isChat and target and target:GetText() == PLACEHOLDER then
			target:SetText("");
		end
		handedBack = target;
		ClearShortcuts();
		aDownAt = nil; -- a press the keyboard closed under isn't a hold next time
		closing = true;
		Unregister();
		closing = false;
		target = nil;
	end);
end

-- Where it was dragged to; else for chat beside the chat window, not over it; else above the text box if
-- it's in the lower half of the screen, below it if not.
local function Position(box)
	keyboard:ClearAllPoints();
	local saved = DB().position;
	if saved then
		keyboard:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y);
		return;
	end
	if box.chatFrame then
		keyboard:SetPoint("BOTTOMLEFT", box.chatFrame, "BOTTOMRIGHT", 24, 0);
		return;
	end
	local _, y = box:GetCenter();
	local screenHeight = UIParent:GetHeight();
	if y and screenHeight and screenHeight > 0 and y > screenHeight / 2 then
		keyboard:SetPoint("TOP", box, "BOTTOM", 0, -8);
	elseif y then
		keyboard:SetPoint("BOTTOM", box, "TOP", 0, 8);
	else
		keyboard:SetPoint("CENTER");
	end
end

local function SetTarget(box)
	target = box;
	chatHadFocus = nil; -- a new box: no focus seen yet
	isChat = box.chatFrame ~= nil;
	suggesting = LooksUpNames(box);
	if not isChat then
		lastNamesBox = box;
	end
	text = box:GetText() or "";
	cursor = Utf8Length(text);
	if isChat and text == "" then
		-- Keeps the chat box open, and its chat type, while the controller is on the keyboard.
		box:SetText(PLACEHOLDER);
	end
	page = "letters";
	shift = isChat and text == "";
end

local function Open(box)
	if not keyboard then
		CreateKeyboard();
	end
	SetTarget(box);
	Position(box);
	keyboard:Show();
end

-- The controller asked if one of its buttons is down now (A on a text box) or was what the player pressed
-- last (the menu dial acts as its button comes up). A real keyboard's chat key held (Enter, /, reply - the
-- keys bound to opening chat that aren't the controller's) or a mouse button since then means they didn't.
local PAD_BUTTONS = {
	"PAD1", "PAD2", "PAD3", "PAD4", "PAD5", "PAD6", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT",
	"PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER", "PADLSTICK", "PADRSTICK",
	"PADBACK", "PADFORWARD", "PADSYSTEM", "PADSOCIAL", "PADPADDLE1", "PADPADDLE2", "PADPADDLE3", "PADPADDLE4",
};
local CHAT_BINDINGS = { "OPENCHAT", "OPENCHATSLASH", "REPLY", "REPLY2" };

local function PadButtonDown()
	for _, button in ipairs(PAD_BUTTONS) do
		if IsKeyDown(button) then
			return true;
		end
	end
	return false;
end

local function ChatKeyDown()
	for _, binding in ipairs(CHAT_BINDINGS) do
		for _, bound in ipairs({ GetBindingKey(binding) }) do
			local key = bound:match("^.*%-(.+)$") or bound; -- without its modifiers (SHIFT-R: R)
			if not key:find("^PAD") and IsKeyDown(key) then
				return true;
			end
		end
	end
	return false;
end

local function ControllerAsked()
	if ChatKeyDown() then
		lastInput = "keyboard"; -- for the frame check after this too, if the key's already up by then
		return false;
	end
	return PadButtonDown() or lastInput == "gamepad";
end

local function ShouldOpen(box)
	return DB().autoOpen ~= false
		and ControllerAsked()
		and not InCombatLockdown()
		and UsesGamepadUI()
		and GetManager() ~= nil
		and not (keyboard and keyboard:IsShown())
		and box:IsObjectType("EditBox")
		and not box:IsForbidden()
		and box:IsVisible();
end

-- Typing focus went to another text box while the keyboard is open. The controller's doing (LT to the
-- window, A on another box): the keyboard types there now - in place, the controller staying where it is
-- (back to the keyboard with LT / RT). A real keyboard's or the mouse's: the keyboard steps aside.
local function SwitchTo(box)
	if not (ControllerAsked() and box:IsObjectType("EditBox") and not box:IsForbidden() and box:IsVisible()) then
		Close();
		return;
	end
	if isChat and target and target:GetText() == PLACEHOLDER then
		target:SetText(""); -- the chat box it leaves, as it was
	end
	SetTarget(box);
	Layout();
	UpdateLabels();
	UpdatePreview();
	RefreshNavigation();
end

-------------------------------------------------------------------------------
-- Watching for text boxes, combat
-------------------------------------------------------------------------------

-- Asked for again on a box that already has focus (A on a name box again, Chat chosen again on the menu
-- dial): no focus change to watch, so these are hooked. Not while closing, which focuses the box itself.
local function Requested(box)
	if closing or not (box and box:HasFocus()) then
		return;
	end
	if ShouldOpen(box) then
		Open(box);
	end
end
-- Every text box shares one method table; Blizzard's chat box (made hidden, auto-focus off) gives it. A text
-- box made here would be shown with auto-focus on, as CreateFrame makes them, and take the real keyboard at
-- login: every key into an invisible box.
local function EditBoxMethods()
	local box = ChatFrame1EditBox;
	if not box then
		local holder = CreateFrame("Frame");
		holder:Hide();
		box = CreateFrame("EditBox", nil, holder); -- never shown, so never focused
		box:SetAutoFocus(false);
	end
	return getmetatable(box).__index;
end
hooksecurefunc(EditBoxMethods(), "SetFocus", Requested);
for index = 1, NUM_CHAT_WINDOWS or 10 do
	local chatFrame = _G["ChatFrame" .. index];
	if chatFrame and chatFrame.SetGamepadFocus then
		hooksecurefunc(chatFrame, "SetGamepadFocus", function(self)
			Requested(self.editBox);
		end);
	end
end

-- One check per frame: what the player is pressing, the chat box taken back, and the keyboard opens when
-- typing focus moves to a text box.
local lastFocus;
local watcher = CreateFrame("Frame");
watcher:SetScript("OnUpdate", function()
	if lastInput ~= "gamepad" and PadButtonDown() then
		lastInput = "gamepad";
	end
	UpdateShortcuts();
	UpdateHoldHint();
	-- Open over chat, the chat box has no typing focus (the controller is here). Getting it back means a
	-- real keyboard (Enter, /) or the mouse took the chat: this keyboard steps aside, the text stays.
	if keyboard and keyboard:IsShown() and isChat and target then
		local hasFocus = target:HasFocus();
		if chatHadFocus == false and hasFocus then
			Close();
		end
		chatHadFocus = hasFocus;
	end
	local focus = GetCurrentKeyBoardFocus();
	if focus == lastFocus then
		return;
	end
	lastFocus = focus;
	if keyboard and keyboard:IsShown() then
		if focus and focus ~= target then
			SwitchTo(focus);
		end
		return;
	end
	if focus ~= handedBack then
		handedBack = nil;
		if focus and ShouldOpen(focus) then
			Open(focus);
		end
	end
end);
watcher:RegisterEvent("PLAYER_REGEN_DISABLED");
watcher:RegisterEvent("PLAYER_REGEN_ENABLED");
watcher:RegisterEvent("GLOBAL_MOUSE_DOWN");
watcher:SetScript("OnEvent", function(_, event)
	if event == "GLOBAL_MOUSE_DOWN" then
		lastInput = "mouse";
	elseif event == "PLAYER_REGEN_DISABLED" then
		Close(); -- the text stays in the box
	elseif keyboard and not keyboard:IsShown() then
		ClearShortcuts(); -- if combat stopped it as the keyboard closed
		if registered then
			Unregister(); -- a hide Blizzard refused as combat started
		end
	end
end);

-- /gk names: what the name lookup does for the last box typed into (for a box that should show names).
local function DescribeNames(box)
	local name = box:GetName() or "That text box";
	if not LooksUpNames(box) then
		Print(("%s doesn't look names up as the keyboard sees it (lookup: %s, Blizzard's: %s, include / exclude: %s, own handler: %s)."):format(
			name, tostring(box.autoCompleteSource ~= nil),
			tostring(C_AutoComplete ~= nil and box.autoCompleteSource == C_AutoComplete.GetAutoCompleteResults),
			type(box.autoCompleteParams) == "table" and table.concat(box.autoCompleteParams, " / ") or "none",
			tostring(box.customAutoCompleteFunction ~= nil)));
		return;
	end
	local typed = box:GetText() or "";
	local ok, results = pcall(C_AutoComplete.GetAutoCompleteResults, typed, MAX_SUGGESTIONS + 1, Utf8Length(typed), true, unpack(box.autoCompleteParams));
	if not ok then
		Print(("%s: the lookup for \"%s\" failed: %s"):format(name, typed, tostring(results)));
		return;
	end
	local found = {};
	for i, result in ipairs(type(results) == "table" and results or {}) do
		found[i] = tostring(result.name);
	end
	Print(("%s: \"%s\" finds %s."):format(name, typed, #found > 0 and table.concat(found, ", ") or "nobody"));
end

SLASH_GAMEPADKEYBOARD1 = "/gk";
SLASH_GAMEPADKEYBOARD2 = "/gamepadkeyboard";
SlashCmdList.GAMEPADKEYBOARD = function(message)
	message = strtrim(message or ""):lower();
	if message == "reset" then
		DB().position = nil;
		Print("back to its usual place.");
	elseif message == "names" then
		if lastNamesBox then
			DescribeNames(lastNamesBox);
		else
			Print("type in a text box with the keyboard first (the mail's To:, say), then /gk names.");
		end
	elseif message == "on" or message == "off" then
		DB().autoOpen = message == "on";
		Print(message == "on" and "opens when a text box gets focus with the controller."
			or "off - type with a keyboard; /gk on turns it back on.");
	else
		Print(("%s. /gk on | off, /gk reset puts it back in its usual place."):format(DB().autoOpen ~= false and "On" or "Off"));
	end
end;
