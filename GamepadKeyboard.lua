-- Gamepad Keyboard: an on-screen keyboard for typing with a controller.
--
-- When a text box gets typing focus in the game's controller UI (out of combat), the keyboard opens as a
-- popup in Blizzard's gamepad UI, like its own panels: the D-pad moves between keys (left / right along a
-- row, up / down between rows), A types, Enter does what Enter does, B goes back without it. Each key
-- writes straight into the text box (over chat: into the keyboard's own line - see below), the keyboard's
-- preview shows it, and closing returns the controller to the window the box belongs to.
--
-- Enter in chat sends the message and closes the chat, as Enter does - but not through the chat's send code,
-- which addon code shouldn't run (it writes chat state that secure commands read later). The Enter key is a
-- secure macro button: the message becomes the line Enter would send (/w Bob ..., /p ..., /2 ..., or a typed
-- command as is), run by Blizzard's secure macro action on the press. The chat box itself is never written:
-- the line and its chat are the keyboard's own (what typing into the box sets off would stay the addon's
-- doing, read by Blizzard's chat later); a line closed unsent waits for the next time. Chats no macro line
-- can say (Battle.net whispers) it doesn't open for. Enter in any other box runs that box's own Enter action.
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
-- For chat, a chat key opens a list of every chat (Say, Party, Raid, Instance, Guild, Officer, Yell, the
-- whisper the chat was in, a reply to the last whisper): the line's chat, the text kept.
--
-- Whichever the player is using has the text box. The keyboard opens only when the controller asked for it
-- (A on a text box, Chat on the menu dial) - not when a real keyboard opened the chat (Enter, /, reply) or
-- a mouse click put focus in some box. And when a real keyboard or the mouse takes the chat box back while
-- it's open, it steps aside. Keys are only ever looked at (IsKeyDown), never listened to: a
-- listening frame keeps every key it isn't allowed to pass on, and SetPropagateKeyboardInput is restricted
-- (in combat at least).
--
-- Options: Options > AddOns > Gamepad Keyboard (or /gk), through Blizzard's Settings API. Where it opens and
-- its size: in Edit Mode it shows, to be dragged and resized (mouse wheel) - Edit Mode takes no addon frames
-- (they'd taint it), so this follows its enter / exit events and draws its own selection.
--
-- In combat Blizzard's gamepad UI takes no addon windows, so the keyboard doesn't open (a real keyboard
-- types as always), and an open one closes when combat starts; the text stays in the box.

local ADDON_NAME, ns = ...;

-- The keyboard's state that its parts share - what it types into, the line, the page, the chat - in one table
-- (read at each use: never copied into a local that would keep an old value).
local S = {};
ns.S = S;
S.keyboard = nil;

local KEY_WIDTH, KEY_HEIGHT, GAP = 36, 30, 4;

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
-- The letters in either layout (an option), with the same number and bottom rows; one symbols page.
-- No "|": the game reads it as the start of an escape code.
local NUMBER_ROW = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", BACK };
local BOTTOM_ROW = { SYMBOLS, CHAT, SPACE, ENTER };
local PAGES = {
	qwerty = {
		NUMBER_ROW,
		{ "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
		{ "a", "s", "d", "f", "g", "h", "j", "k", "l", "'" },
		{ SHIFT, "z", "x", "c", "v", "b", "n", "m", ",", "." },
		BOTTOM_ROW,
	},
	dvorak = {
		NUMBER_ROW,
		{ "'", ",", ".", "p", "y", "f", "g", "c", "r", "l" },
		{ "a", "o", "e", "u", "i", "d", "h", "t", "n", "s" },
		{ SHIFT, ";", "q", "j", "k", "x", "b", "m", "w", "v", "z" },
		BOTTOM_ROW,
	},
	symbols = {
		{ "!", "@", "#", "$", "%", "&", "*", "(", ")", "-", BACK },
		{ "/", "\\", ":", ";", "\"", "?", "+", "=", "_", "~" },
		{ "<", ">", "[", "]", "{", "}", "^", "`", "'", "," },
		{ LETTERS, CHAT, SPACE, ENTER },
	},
	numbers = { -- a box that takes only numbers (a price, a quantity): a numpad
		{ "7", "8", "9" },
		{ "4", "5", "6" },
		{ "1", "2", "3" },
		{ BACK, "0", ENTER },
	},
};
-- A page whose keys are all one width (in keys): the numpad's grid.
local PAGE_KEY_UNITS = { numbers = 2 };

local keys = {}; -- page -> rows of key buttons
local page = "qwerty"; -- a letters page (the layout's), "symbols", or "numbers" (a box of numbers only)
local target; -- the text box being typed into
local isChat = false;
local suggesting = false; -- the box looks names up (a row of name keys above the keys)
local suggestions = {}; -- the name keys
-- Over chat the line and its chat are the keyboard's own: typed here, sent with a secure macro line, never
-- written into Blizzard's chat box. What typing there sets off (its text-changed fields, the chat type's
-- parsing) would run as this addon's doing and stay so - read by Blizzard's chat later, on into the
-- controller's bindings: blocked, blamed on the addon. The chat box is only read - but for its chat
-- attributes (what its own send reads; attributes come back clean).
local chat = {}; -- the chat the line goes to: { chatType, tellTarget, channelTarget }
local seenChat; -- the chat box's own chat type last frame (to see a whisper started elsewhere)
local seenBoxText; -- the chat box's own text last frame (a line Blizzard put there: the preview follows)
local toldBoxLine = false; -- said once: a line in the chat box is sent from there
local chatDraft; -- a chat line closed unsent: { text, chat } - back the next time the keyboard opens on chat
local whisperedTo; -- the whisper this chat was in while the keyboard was up: { chatType, target }
local lastNamesBox; -- the last box typed into that isn't chat (for /gk names)
local lastBoxName; -- the last box typed into (for a report if the game blocks the addon)
local text = "";
local cursor = 0; -- characters before the cursor
local shift = false;
local handedBack; -- the box the keyboard just went back to: not opened for again until focus moves on
local closing = false; -- while closing hands the controller back (which focuses the box again)
local previewing = false; -- shown in Edit Mode to be placed, not typing anywhere
local lastInput = "gamepad"; -- what the player pressed last: "gamepad", "keyboard" or "mouse"
local chatHadFocus; -- while open over chat: whether the chat box had typing focus last frame
local picking = false; -- the chat list is open (see OpenChatList)
local chatChoices = {}; -- its buttons, each with the chat it's for (.entry)

local function DB()
	GamepadKeyboardDB = GamepadKeyboardDB or {};
	return GamepadKeyboardDB;
end

-- The settings (the options panel), each with its default.
local DEFAULTS = {
	autoOpen = true, -- opens when the controller asks for a text box
	closeOnEnter = true, -- Enter closes the keyboard (in chat: sends and closes the chat)
	chatCapital = true, -- a chat line starts with Shift on
	names = true, -- name keys for boxes that look names up
	holdTime = 0.5, -- holding A this long (seconds) is Enter
	layout = "qwerty", -- the letters: "qwerty" or "dvorak"
	scale = 1, -- the keyboard's size
};

local function Setting(key)
	local value = DB()[key];
	if value == nil then
		return DEFAULTS[key];
	end
	return value;
end

-- The letters page of the layout chosen.
local function LettersPage()
	return Setting("layout") == "dvorak" and "dvorak" or "qwerty";
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

-- Only through the functions Blizzard wraps for outside callers (HandlePopupShown / HandlePopupHide /
-- FrameHidden, RefreshButtonGroups, SetTargetButtonForFrame, jump overrides), only out of combat; our frames
-- never set the fields its focus manager reads directly. A refused call returns nothing, so the manager's
-- list is checked: a hide refused as combat started is retried after it; a show, the next time it opens.
local registered = false;

local function GetManager()
	return GamepadMode and GamepadMode.FrameControlsManager;
end

local function IsListed(manager)
	if type(manager.shownFrames) ~= "table" then
		return nil;
	end
	for _, shown in ipairs(manager.shownFrames) do
		if shown == S.keyboard then
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
	local ok = pcall(manager.HandlePopupShown, manager, S.keyboard);
	local listed = IsListed(manager);
	registered = listed or (listed == nil and ok) or false;
end

local function Unregister()
	local manager = GetManager();
	if not registered or not manager or InCombatLockdown() then
		return;
	end
	-- Handing the controller back focuses the box again: not a request for the keyboard (here, not only in
	-- OnHide - after combat a hide refused as it started is retried, and the box mustn't reopen it unlisted).
	closing = true;
	local ok = pcall(manager.HandlePopupHide, manager, S.keyboard);
	closing = false;
	local listed = IsListed(manager);
	registered = not (listed == false or (listed == nil and ok));
end

-- Rows for the D-pad: left / right move along a row of keys, up / down go to the next row, to the key
-- nearest in X; past an end it wraps round (right from the last key to the first, up from the top row to the
-- bottom one). Sent as SmartNavigation jump overrides (Blizzard's setter for this), only changes.
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
					for k = 1, #row - 1 do
						local i = (c - 1 + k * step[2]) % #row + 1;
						if IsUsable(row[i]) then
							return row[i];
						end
					end
					return nil;
				end
				local fromX = from:GetCenter();
				for k = 1, #rows - 1 do
					local i = (r - 1 + k * step[1]) % #rows + 1;
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

-- Whether the keyboard may steer the controller UI now: registered with it, and out of combat (its functions
-- wrapped for outside callers refuse an addon in combat).
local function CanSteer()
	return registered and not InCombatLockdown();
end

local function Override(button, direction, destination)
	applied[button] = applied[button] or {};
	if applied[button][direction] ~= destination then
		local ok = pcall(SmartNavigation_AddJumpNavigationOverride, button, SMART_NAV_INPUT_DIRECTION[direction], destination);
		applied[button][direction] = ok and destination or nil;
	end
end

local function RefreshNavigation()
	if not CanSteer() then
		return;
	end
	if SmartNavigation and SmartNavigation.RefreshButtonGroups then
		pcall(SmartNavigation.RefreshButtonGroups, SmartNavigation, S.keyboard);
	end
	if not (SmartNavigation_AddJumpNavigationOverride and SMART_NAV_INPUT_DIRECTION) then
		return;
	end
	local rows = keys[page];
	if picking then
		rows = {}; -- the chat list, one under another (and nowhere else: the keys under it aren't reached)
		for _, choice in ipairs(chatChoices) do
			if choice:IsShown() then
				rows[#rows + 1] = { choice };
			end
		end
	elseif suggesting then
		rows = { suggestions, unpack(keys[page]) };
	end
	for _, row in ipairs(rows) do
		for _, button in ipairs(row) do
			for direction in pairs(DIRECTIONS) do
				Override(button, direction, FindInRows(rows, button, direction) or true);
			end
		end
	end
end

-- The D-pad's cursor onto a button: SmartNavigation's setter for outside callers (wrapped, as
-- RefreshButtonGroups is), then the keyboard's target there cleared again - the cursor would go back to it
-- later (a list closed by then, a page not shown).
local function PointAt(button)
	if not (CanSteer() and SmartNavigation and SmartNavigation.SetTargetButtonForFrame) then
		return;
	end
	pcall(SmartNavigation.SetTargetButtonForFrame, SmartNavigation, S.keyboard, button);
	pcall(SmartNavigation.SetTargetButtonForFrame, SmartNavigation, S.keyboard, nil);
end

-- Blizzard's LT / RT / View jump hints and focus glow (FocusFramesInterfaceTemplate): lift the hints to our
-- strata, and give the glow the frame art Blizzard uses for plain panels.
local function SetUpFocusVisuals()
	for _, key in ipairs({ "LeftJumpHint", "RightJumpHint", "FocusJumpHint" }) do
		if S.keyboard[key] then
			S.keyboard[key]:SetFrameStrata(S.keyboard:GetFrameStrata());
		end
	end
	if S.keyboard.FrameGlow and S.keyboard.FrameGlow.OnLoad then
		S.keyboard.layoutType = "ButtonFrameTemplateNoPortrait";
		S.keyboard.FrameGlow:OnLoad();
	end
end

-------------------------------------------------------------------------------
-- Typing
-------------------------------------------------------------------------------

-- The chats the chat key's list offers. Reply: a whisper to whoever whispered last (Blizzard's own getter,
-- which only reads).
local function LastTell()
	if ChatFrameUtil and ChatFrameUtil.GetLastTellTarget then
		return ChatFrameUtil.GetLastTellTarget();
	end
end

-- Every chat, in a group or a guild or not - one you aren't in gets the game's own "you aren't in a party";
-- then the whispers (see ChatTypesToUse).
local CHAT_TYPES = {
	{ chatType = "SAY" }, { chatType = "PARTY" }, { chatType = "RAID" }, { chatType = "INSTANCE_CHAT" },
	{ chatType = "GUILD" }, { chatType = "OFFICER" }, { chatType = "YELL" },
};
local CHAT_LABELS = {
	SAY = "Say", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance", GUILD = "Guild", OFFICER = "Officer",
	YELL = "Yell", EMOTE = "Emote", RAID_WARNING = "Warning",
};

local function IsWhisper(chatType)
	return chatType == "WHISPER" or chatType == "BN_WHISPER";
end

-- A chat's name (the line's, unless another's given): "Guild", "To Bob", "/2".
local function ChatLabel(to)
	to = to or chat;
	local chatType = to.chatType;
	if IsWhisper(chatType) then
		local name = tostring(to.tellTarget or ""):gsub("%-.*$", "");
		if Utf8Length(name) > 9 then
			name = name:sub(1, 8) .. "..";
		end
		return "To " .. name;
	elseif chatType == "CHANNEL" then
		return "/" .. tostring(to.channelTarget or "?");
	end
	return CHAT_LABELS[chatType] or "Chat";
end

-- A chat box's chat type as it is (its attributes: reading them is all the keyboard does to the box).
local function ChatOf(box)
	return { chatType = box:GetAttribute("chatType"), tellTarget = box:GetAttribute("tellTarget"),
		channelTarget = box:GetAttribute("channelTarget") };
end

-- A chat told from another by its type and who it's to (a change in the box: a whisper started there).
local function ChatKey(to)
	return tostring(to.chatType) .. " " .. tostring(to.tellTarget);
end

-- The macro line that says a message in a chat (a command - "/dance" - runs as typed); nil if no slash
-- command can say it. Not Battle.net whispers: their name can be a protected string, which a macro line
-- can't be trusted to keep - and Blizzard sends them only from its own chat box.
local CHAT_COMMANDS = {
	SAY = "/s", YELL = "/y", EMOTE = "/e", PARTY = "/p", RAID = "/ra", RAID_WARNING = "/rw",
	INSTANCE_CHAT = "/i", GUILD = "/g", OFFICER = "/o",
};
local MAX_LINE = 255;

local function ChatLine(message, to)
	if message:sub(1, 1) == "/" then
		return message;
	elseif to.chatType == "WHISPER" then
		return to.tellTarget and ("/w " .. to.tellTarget .. " " .. message);
	elseif to.chatType == "CHANNEL" then
		local channel = tonumber(to.channelTarget);
		return channel and ("/" .. channel .. " " .. message);
	elseif CHAT_COMMANDS[to.chatType] then
		return CHAT_COMMANDS[to.chatType] .. " " .. message;
	end
end

local function Sayable(to)
	return ChatLine("x", to) ~= nil;
end

-- The chat the keyboard opens in over a chat box: an unsent line's own, unless a whisper was started in the
-- box since the line was left (a name's menu, the reply key) - not the box still in, or sticking to, the
-- whisper it had then - else the box's.
local function ChatFor(box)
	local boxChat = ChatOf(box);
	if chatDraft and not (IsWhisper(boxChat.chatType) and not chatDraft.boxChats[ChatKey(boxChat)]) then
		return chatDraft.chat;
	end
	return boxChat;
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

-- The text with the cursor (a gold bar; "||" shows one "|"), at most PREVIEW_LENGTH characters of it around
-- the cursor.
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

-- The line the cursor is on (a box can have several: "line 2 of 3" after it), at most PREVIEW_LENGTH
-- characters of it around the cursor.
local LINE_FORMAT = "|cff808080   line %d of %d|r";

-- The chat key follows the chat (its label), and a whisper the chat is in is remembered - when the keyboard
-- changes it, and each frame for a change from elsewhere (a menu's Whisper).
local function UpdateChatKey()
	if not (isChat and target) then
		return;
	end
	local label = ChatLabel();
	for _, chatKey in ipairs(S.keyboard.ChatKeys) do
		if chatKey:GetText() ~= label then
			chatKey:SetText(label);
		end
	end
	-- A whisper to someone other than whoever whispered last (they're the reply, always offered).
	if chat.chatType == "WHISPER" and chat.tellTarget and chat.tellTarget ~= LastTell() then
		whisperedTo = { chatType = chat.chatType, target = chat.tellTarget };
	end
end

-- The chat box's own line, while the keyboard's is empty: one Blizzard put there (a link - shift-click with
-- the chat box open, or a window's "link in chat" opening it with one). The keyboard can't move it (writing
-- in the chat box would leave it the addon's doing), so it shows it, steers its chat, and hands it back for
-- the chat's own A to send. Typing starts the keyboard's own line instead.
local BOX_LINE_HINT = "|cff808080   in the chat box: Enter, then A sends it|r";

local function BoxLine()
	if isChat and target and text == "" then
		local boxText = target:GetText() or "";
		if boxText ~= "" then
			return boxText;
		end
	end
end

-- Over chat, the line's chat heads it - "Guild:", "To Bob:" - in the chat's colour, as Blizzard's chat box
-- heads its own.
local function UpdateChatHeader()
	local header = S.keyboard.ChatHeader;
	local label = isChat and target and (ChatLabel() .. ":") or nil;
	local info = label and ChatTypeInfo
		and ChatTypeInfo[chat.chatType == "CHANNEL" and ("CHANNEL" .. tostring(chat.channelTarget)) or chat.chatType];
	local r, g, b = info and info.r or 1, info and info.g or 0.82, info and info.b or 0;
	header:SetText(label or "");
	header:SetTextColor(r, g, b);
	header:SetShown(label ~= nil);
	S.keyboard.Preview:ClearAllPoints();
	if label then
		S.keyboard.Preview:SetPoint("TOPLEFT", header, "TOPRIGHT", 6, 0);
	else
		S.keyboard.Preview:SetPoint("TOPLEFT", 16, -32);
	end
	S.keyboard.Preview:SetPoint("TOPRIGHT", -16, -32);
end

local function UpdatePreview()
	UpdateChatHeader();
	local boxLine = BoxLine();
	if boxLine then
		S.keyboard.Preview:SetText(boxLine .. BOX_LINE_HINT);
		UpdateChatKey();
		UpdateSuggestions();
		return;
	end
	local before, after = Split(text, cursor);
	local lineBefore, lineAfter = before:match("[^\n]*$"), after:match("^[^\n]*");
	local column, length = Utf8Length(lineBefore), Utf8Length(lineBefore) + Utf8Length(lineAfter);
	local first = math.max(0, math.min(column - PREVIEW_LENGTH + 8, length - PREVIEW_LENGTH));
	local last = math.min(length, first + PREVIEW_LENGTH);
	local shown = (first > 0 and "..." or "") .. select(2, Split(lineBefore, first)) .. CARET
		.. select(1, Split(lineAfter, last - column)) .. (last < length and "..." or "");
	local _, lines = text:gsub("\n", "");
	if lines > 0 then
		local _, line = before:gsub("\n", "");
		shown = shown .. LINE_FORMAT:format(line + 1, lines + 1);
	end
	S.keyboard.Preview:SetText(shown);
	UpdateChatKey();
	UpdateSuggestions();
end

local function UpdateLabels()
	for name, rows in pairs(keys) do
		if name ~= "symbols" then
			for _, row in ipairs(rows) do
				for _, button in ipairs(row) do
					if not SPECIAL_KEYS[button.key] then
						button:SetText(shift and button.key:upper() or button.key);
					end
				end
			end
		end
	end
	for _, shiftKey in ipairs(S.keyboard.ShiftKeys) do
		shiftKey:LockHighlight();
		if not shift then
			shiftKey:UnlockHighlight();
		end
	end
	local enterLabel = target and not isChat and target:IsMultiLine() and "New line" or "Enter";
	for _, enterKey in ipairs(S.keyboard.EnterKeys) do
		enterKey:SetText(enterLabel);
	end
	if S.keyboard.HoldPrompt then
		S.keyboard.HoldPrompt.text:SetText(enterLabel);
	end
end

local function SetText(newText, newCursor)
	text = newText;
	cursor = newCursor or Utf8Length(text);
	if target and not isChat then
		target:SetText(text);
		text = target:GetText() or ""; -- the box may change it
		cursor = math.min(cursor, Utf8Length(text));
	end
	UpdatePreview();
end

-- The box may have changed under the keyboard (typed into on a real keyboard, the mail sent): carry on from
-- what's in it. Not chat: there the line is the keyboard's own.
local function Sync()
	if isChat then
		return;
	end
	local current = target and target:GetText() or "";
	if current ~= text then
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
	local before, after = Split(text, cursor);
	local newText = before .. characters .. after;
	if isChat then
		if #(ChatLine(newText, chat) or newText) > MAX_LINE then
			return; -- (as long as one chat line can be)
		end
	elseif target and target:IsNumeric() and characters:find("%D") then
		return; -- a box of numbers: digits only (Y's space too)
	else
		local maxLetters = target and target:GetMaxLetters() or 0;
		if maxLetters > 0 and Utf8Length(newText) > maxLetters then
			return;
		end
	end
	SetText(newText, cursor + Utf8Length(characters));
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
	local nameWidth = (S.keyboard:GetWidth() - 28 - (MAX_SUGGESTIONS - 1) * GAP) / MAX_SUGGESTIONS;
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
			local x = (S.keyboard:GetWidth() - width) / 2;
			for _, button in ipairs(row) do
				if button:IsShown() then
					button:ClearAllPoints();
					button:SetPoint("TOPLEFT", x, -56 - (r - 1 + top) * (KEY_HEIGHT + GAP));
					x = x + button.width + GAP;
				end
			end
		end
	end
	S.keyboard:SetHeight(84 + (#keys[page] + top) * (KEY_HEIGHT + GAP));
end

-- The chat types there are to use, then the whispers: the one this chat was in (opened from a name, say)
-- and a reply to whoever whispered last (not a Battle.net one: see ChatLine), once each.
local function ChatTypesToUse()
	local list = {};
	for _, entry in ipairs(CHAT_TYPES) do
		list[#list + 1] = entry;
	end
	local lastTell, lastTellType = LastTell();
	if whisperedTo and whisperedTo.target ~= lastTell then
		list[#list + 1] = whisperedTo;
	end
	if lastTell and (lastTellType or "WHISPER") == "WHISPER" then
		list[#list + 1] = { chatType = "WHISPER", target = lastTell };
	end
	return list;
end

-- One of those as a chat (a whisper's target is who it's to).
local function EntryChat(entry)
	return { chatType = entry.chatType, tellTarget = entry.target };
end

-- Whether it's the line's own chat (a whisper: by who it's to).
local function SameChat(entry)
	if entry.target then
		return chat.chatType == "WHISPER" and entry.target == chat.tellTarget;
	end
	return entry.chatType == chat.chatType;
end

local function SetChat(entry)
	chat = EntryChat(entry);
	if (target:GetText() or "") ~= "" then
		-- The chat box's own line goes there too: its chat (attributes - what its send reads, and they come
		-- back clean) and its header (Blizzard's, which only redraws).
		target:SetAttribute("chatType", chat.chatType);
		target:SetAttribute("tellTarget", chat.tellTarget);
		target:SetAttribute("channelTarget", nil);
		target:UpdateHeader();
	end
	UpdatePreview();
end

-- The chat key opens a list of the chats over the keys - a dropdown of the keyboard's own buttons, the D-pad's
-- cursor on the line's chat (from anything else, a channel say: on Say): up / down, A takes one (held too),
-- B goes back. Not a Blizzard menu: one an addon opens runs the controller UI's menu callbacks as the addon's
-- doing (see the layout option).
local CHOICE_HEIGHT, CHOICE_STEP = 26, 28;

-- A chat's name in its colour (in the text: a button's own colour changes with its highlight).
local function ChatChoiceText(to)
	local info = ChatTypeInfo and ChatTypeInfo[to.chatType];
	if not (info and info.r) then
		return ChatLabel(to);
	end
	local function Hex(value)
		return math.floor(value * 255 + 0.5);
	end
	return ("|cff%02x%02x%02x%s|r"):format(Hex(info.r), Hex(info.g), Hex(info.b), ChatLabel(to));
end

local function VisibleChatKey()
	for _, chatKey in ipairs(S.keyboard.ChatKeys) do
		if chatKey:IsVisible() then
			return chatKey;
		end
	end
end

local function HideChatList()
	picking = false;
	S.keyboard.ChatList:Hide();
	for _, choice in ipairs(chatChoices) do
		choice:Hide();
	end
end

-- Back to the keys, the cursor on the chat key.
local function CloseChatList()
	if picking then
		HideChatList();
		RefreshNavigation();
		PointAt(VisibleChatKey());
	end
end

local function OpenChatList(chatKey)
	local list = ChatTypesToUse();
	local frame = S.keyboard.ChatList;
	-- Over the keys, and over the controller UI's focus glow round the keyboard (a frame level of its own,
	-- far above the keyboard's) where the list goes past the keyboard's edge.
	frame:SetFrameLevel(math.max(S.keyboard:GetFrameLevel() + 10, S.keyboard.FrameGlow and S.keyboard.FrameGlow:GetFrameLevel() + 1 or 0));
	frame:SetSize(chatKey.width + 12, #list * CHOICE_STEP - (CHOICE_STEP - CHOICE_HEIGHT) + 12);
	frame:ClearAllPoints();
	frame:SetPoint("BOTTOMLEFT", chatKey, "TOPLEFT", -6, GAP); -- up from the key (kept on the screen)
	local current;
	for i, choice in ipairs(chatChoices) do
		local entry = list[i];
		choice.entry = entry;
		choice:SetShown(entry ~= nil);
		if entry then
			choice:SetFrameLevel(frame:GetFrameLevel() + 1);
			choice:SetSize(chatKey.width, CHOICE_HEIGHT);
			choice:ClearAllPoints();
			choice:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6 - (i - 1) * CHOICE_STEP);
			choice:SetText(ChatChoiceText(EntryChat(entry)));
			current = current or (SameChat(entry) and choice);
		end
	end
	frame:Show();
	picking = true;
	RefreshNavigation();
	PointAt(current or chatChoices[1]);
	if CanSteer() and SmartNavigation_AddJumpNavigationOverride and SMART_NAV_INPUT_DIRECTION then
		Override(chatKey, "UP", current or chatChoices[1]); -- (the cursor left on the key: up into the list; back as it was after)
	end
end

local function PickChat(choice)
	if picking and choice.entry and isChat and target then
		SetChat(choice.entry);
	end
	CloseChatList();
end

local function Close()
	if S.keyboard and S.keyboard:IsShown() then
		S.keyboard:Hide();
	end
end

-- A chat line closed unsent (B, combat, a real keyboard taking over, another box) waits for the next time the
-- keyboard opens on chat, in its chat; an empty one leaves nothing.
local function KeepChatDraft()
	if text == "" or not target then
		chatDraft = nil;
		return;
	end
	-- (and the chat box's own chat as the keyboard last took it in, and as it goes back to when it closes: its
	-- sticky type)
	chatDraft = { text = text, chat = chat, boxChats = {
		[seenChat] = true,
		[ChatKey({ chatType = target:GetAttribute("stickyType"), tellTarget = target:GetAttribute("tellTarget") })] = true,
	} };
end

local function Press(button)
	if InCombatLockdown() then
		return; -- (closed in combat: a click that gets here anyway changes nothing - its keys can't move then)
	end
	local key = button.key;
	if picking then
		CloseChatList(); -- (a key pressed past it - X, Y, the mouse: the list goes; the chat key: just that)
		if key == CHAT then
			return;
		end
	end
	Sync();
	if key == BACK then
		DeleteBack();
	elseif key == SPACE then
		Insert(" ");
	elseif key == SHIFT then
		shift = not shift;
		UpdateLabels();
	elseif key == SYMBOLS or key == LETTERS then
		page = key == SYMBOLS and "symbols" or LettersPage();
		Layout();
		RefreshNavigation();
	elseif key == CHAT then
		if isChat and target then
			OpenChatList(button);
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

-- What a press of a secure button (the Enter keys, A) does: a macro line (a chat line), or a press of a
-- Blizzard window's button (Search, Purchase: see REVIEWED). Blizzard's secure action runs either, so it's
-- Blizzard's doing; nothing (an empty macro) for anything else.
local function SetPressAction(button, line, clickButton)
	button:SetAttribute("type", clickButton and "click" or "macro");
	button:SetAttribute("clickbutton", clickButton);
	button:SetAttribute("macrotext", line or "");
end

-- Before the secure action runs: the line to send, or the button to press (out of combat - the keyboard is
-- closed in combat).
local function EnterPreClick(button)
	if InCombatLockdown() then
		return; -- closed in combat (its line was emptied after the last press)
	end
	local line;
	if target and isChat and text ~= "" then
		line = ChatLine(text, chat);
		if line and #line > MAX_LINE then
			line = nil; -- (the chat key moved it to a longer whisper)
		end
	end
	SetPressAction(button, line, target and EnterButton(target));
end

-- After it: chat closes like after Enter (the chat type sticks, as Enter makes it - an attribute, which comes
-- back clean); any other box gets its own Enter action.
local function EnterPostClick(button)
	if InCombatLockdown() then
		return;
	end
	local sentLine = button:GetAttribute("macrotext") or "";
	SetPressAction(button); -- nothing for a later press to send again
	CloseChatList(); -- (Enter clicked past the chat list: it goes)
	local box, overChat = target, isChat;
	if not box then
		return;
	end
	local entry = Reviewed(box);
	if entry and type(entry.enter) == "table" then
		-- Its button pressed (securely): the box lets go of typing, as its own Enter does. Never its own Enter
		-- (not even with its button missing).
		if Setting("closeOnEnter") then
			Close();
			box:ClearFocus();
		end
		return;
	end
	if overChat then
		if sentLine == "" and text == "" and (box:GetText() or "") ~= "" then
			Close(); -- back on the chat box, its line still in it, in the chat the chat key picked
			if not toldBoxLine then
				toldBoxLine = true;
				Print("the line is in the chat box: A sends it.");
			end
			return;
		end
		if sentLine == "" and text ~= "" then
			Print(("too long to send to %s - a chat line is at most %d letters with its command."):format(ChatLabel(), MAX_LINE));
			return;
		end
		local sent = sentLine ~= "" and text:sub(1, 1) ~= "/";
		if sent and ChatTypeInfo and ChatTypeInfo[chat.chatType] and ChatTypeInfo[chat.chatType].sticky == 1 then
			-- As Blizzard's own send leaves the box: the chat it goes back to, and who or which channel that is
			-- (going back, it takes only the type - a whisper with someone else's name, or none, otherwise).
			box:SetAttribute("stickyType", chat.chatType);
			if chat.chatType == "WHISPER" then
				box:SetAttribute("tellTarget", chat.tellTarget);
			elseif chat.chatType == "CHANNEL" then
				box:SetAttribute("channelTarget", chat.channelTarget);
			end
		end
		text, cursor = "", 0; -- sent: no line to keep
		if not Setting("closeOnEnter") then
			-- Staying open: the next line, in the same chat.
			shift = Setting("chatCapital");
			UpdateLabels();
			UpdatePreview();
			return;
		end
		Close(); -- back on the chat box...
		local manager = GetManager();
		if manager and box.chatFrame then
			pcall(manager.FrameHidden, manager, box.chatFrame); -- ...and the chat closes, as after Enter
		end
		return;
	end
	if box:IsMultiLine() then
		Sync();
		Insert("\n"); -- a new line (the mail's text, say); B is the way out
		return;
	end
	local onEnter = not (entry and entry.enter == "clear") and box:GetScript("OnEnterPressed");
	if Setting("closeOnEnter") then
		Close();
	end
	if onEnter then
		onEnter(box); -- staying open: if that hides the box, the keyboard goes with it (the frame check)
	else
		box:ClearFocus();
	end
end

-- Holding A this long (seconds) is Enter - the ring, the lit Enter key and the release all ask here.
local function HoldTime()
	return Setting("holdTime");
end
local aDownAt; -- when A went down on the keyboard (nil when it isn't down)

-- The footer's hold prompt: Blizzard's press-and-hold glyph (InputIconTextureMixin: a ring that fills
-- radially over the hold). It fills while A is down on the keyboard; at full it's back to its ring, and the
-- lit Enter key shows that letting go sends.
local function HoldRing(holding)
	local prompt = S.keyboard and S.keyboard.HoldPrompt;
	if prompt then
		if holding then
			prompt.icon:BeginHold(HoldTime());
		else
			prompt.icon:EndHold();
		end
	end
end

-- A, as a hidden secure button: on the press, the time; on the release, either Enter (held, or on the
-- Enter key) - the Enter key's own PreClick / PostClick around Blizzard's secure macro action - or a tap on
-- the key the D-pad is on (SmartNavigation's current button; its getter only reads).
local function APreClick(button, _, down)
	if InCombatLockdown() then
		return;
	end
	if down then
		aDownAt = GetTime(); -- (it acts on the release, set then)
		if not picking then
			HoldRing(true);
		end
		return;
	end
	HoldRing(false);
	local current = SmartNavigation and SmartNavigation.GetCurrentButton and SmartNavigation:GetCurrentButton();
	local held = not picking and aDownAt and GetTime() - aDownAt >= HoldTime(); -- (in the chat list: a pick)
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
		SetPressAction(button);
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
	elseif action == "tap" and tapped and tapped:GetParent() == S.keyboard and tapped:IsVisible() and tapped:IsEnabled() then
		-- (only this keyboard's own keys: anything else clicked from here would run as this addon's doing)
		tapped:Click();
	end
end

-- The keys X and Y press (the first Del and Space made, whatever page they're on - a binding clicks a
-- button by name, shown or not, and the key does the same on any page).
local SHORTCUT_KEYS = { [BACK] = "GamepadKeyboardDelKey", [SPACE] = "GamepadKeyboardSpaceKey" };
local named = {};

local function CreateKey(key, pageUnits)
	local special = SPECIAL_KEYS[key];
	local units = pageUnits or special and special.units or 1;
	local name = SHORTCUT_KEYS[key];
	if named[key] then
		name = nil;
	end
	named[key] = named[key] or name ~= nil;
	local button;
	if key == ENTER then
		-- Blizzard's secure macro action, on release (a controller's A and a mouse click both act).
		button = CreateFrame("Button", name, S.keyboard, "SecureActionButtonTemplate, UIPanelButtonTemplate");
		button:RegisterForClicks("AnyUp");
		button:SetAttribute("type", "macro");
		button:SetAttribute("useOnKeyDown", false);
		button:SetAttribute("macrotext", "");
		button:SetScript("PreClick", EnterPreClick);
		button:SetScript("PostClick", EnterPostClick);
	else
		button = CreateFrame("Button", name, S.keyboard, "UIPanelButtonTemplate");
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
	ClearOverrideBindings(S.keyboard);
	for button, keyName in pairs(SHORTCUTS) do
		SetOverrideBindingClick(S.keyboard, true, button, keyName);
	end
	shortcutsBound = true;
end

local function ClearShortcuts()
	if shortcutsBound and not InCombatLockdown() then
		ClearOverrideBindings(S.keyboard);
		shortcutsBound = false;
		-- A held as the controller left: its release goes to the controller UI now, so the hold ends here.
		aDownAt = nil;
		HoldRing(false);
	end
end

local function UpdateShortcuts()
	if InCombatLockdown() then
		return;
	end
	local manager = GetManager();
	if S.keyboard and S.keyboard:IsShown() and manager and manager.focusedFrame == S.keyboard then
		if not shortcutsBound then
			BindShortcuts();
		end
	else
		ClearShortcuts();
	end
end

-- Held long enough: the Enter keys light up (letting go sends).
local function UpdateHoldHint()
	local lit = not picking and aDownAt ~= nil and GetTime() - aDownAt >= HoldTime();
	if S.keyboard and S.keyboard.EnterKeys and S.keyboard.holdLit ~= lit then
		S.keyboard.holdLit = lit;
		for _, enterKey in ipairs(S.keyboard.EnterKeys) do
			if lit then
				enterKey:LockHighlight();
			else
				enterKey:UnlockHighlight();
			end
		end
	end
end

local function BoundOver(owner, _, button)
	if shortcutsBound and owner ~= S.keyboard and SHORTCUTS[button] and not InCombatLockdown() then
		BindShortcuts();
	end
end
hooksecurefunc("SetOverrideBindingClick", BoundOver);
hooksecurefunc("SetOverrideBinding", BoundOver);

local function CreatePrompt(key, label, anchorTo, isHold)
	local icon = CreateFrame("Frame", nil, S.keyboard, "InputIconTextureFrameTemplate");
	icon:SetSize(22, 22);
	icon:SetInputKey(key);
	if isHold then
		icon:SetIsHoldAction(true); -- the press-and-hold ring
	end
	if anchorTo then
		icon:SetPoint("LEFT", anchorTo, "RIGHT", 12, 0);
	else
		icon:SetPoint("BOTTOMLEFT", 14, 10);
	end
	local caption = S.keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	caption:SetPoint("LEFT", icon, "RIGHT", 3, 0);
	caption:SetText(label);
	return { icon = icon, text = caption };
end

-- Where it was dragged to, in UIParent's units (see Position).
local function SavePosition()
	S.keyboard:StopMovingOrSizing();
	local point, _, relativePoint, x, y = S.keyboard:GetPoint();
	local scale = S.keyboard:GetScale();
	DB().position = { point = point, relativePoint = relativePoint, x = x * scale, y = y * scale };
end

local function CreateKeyboard()
	S.keyboard = CreateFrame("Frame", "GamepadKeyboardFrame", UIParent, "BasicFrameTemplateWithInset, FocusFramesInterfaceTemplate");
	S.keyboard:SetSize(11 * KEY_WIDTH + 10 * GAP + 28, 260);
	S.keyboard:SetFrameStrata("FULLSCREEN_DIALOG");
	S.keyboard:SetClampedToScreen(true);
	S.keyboard:EnableMouse(true);
	-- Drag it with the mouse; it opens there from then on (/gk reset forgets it).
	S.keyboard:SetMovable(true);
	S.keyboard:RegisterForDrag("LeftButton");
	S.keyboard:SetScript("OnDragStart", S.keyboard.StartMoving);
	S.keyboard:SetScript("OnDragStop", SavePosition);
	S.keyboard:Hide();
	tinsert(UISpecialFrames, "GamepadKeyboardFrame");

	S.keyboard.Title = S.keyboard:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	S.keyboard.Title:SetPoint("TOP", 0, -5);
	S.keyboard.Title:SetText("Keyboard");
	S.keyboard.ChatHeader = S.keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	S.keyboard.ChatHeader:SetPoint("TOPLEFT", 16, -32);
	S.keyboard.Preview = S.keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	S.keyboard.Preview:SetPoint("TOPLEFT", 16, -32);
	S.keyboard.Preview:SetPoint("TOPRIGHT", -16, -32);
	S.keyboard.Preview:SetJustifyH("LEFT");

	S.keyboard.ChatKeys = {};
	S.keyboard.EnterKeys = {};
	S.keyboard.ShiftKeys = {};
	for name, layout in pairs(PAGES) do
		keys[name] = {};
		for r, rowKeys in ipairs(layout) do
			local row = {};
			for c, key in ipairs(rowKeys) do
				row[c] = CreateKey(key, PAGE_KEY_UNITS[name]);
				if key == SHIFT then
					table.insert(S.keyboard.ShiftKeys, row[c]);
				elseif key == CHAT then
					table.insert(S.keyboard.ChatKeys, row[c]);
				elseif key == ENTER then
					table.insert(S.keyboard.EnterKeys, row[c]);
				end
			end
			keys[name][r] = row;
		end
	end

	for i = 1, MAX_SUGGESTIONS do
		local button = CreateFrame("Button", nil, S.keyboard, "UIPanelButtonTemplate");
		button:SetScript("OnClick", ChooseSuggestion);
		button:Hide();
		suggestions[i] = button;
	end

	-- The chat list: its backing (the mouse doesn't reach the keys through it), its buttons the keyboard's
	-- own, as keys are, set on it.
	S.keyboard.ChatList = CreateFrame("Frame", nil, S.keyboard, "TooltipBackdropTemplate");
	S.keyboard.ChatList:EnableMouse(true);
	S.keyboard.ChatList:SetClampedToScreen(true);
	S.keyboard.ChatList:Hide();
	for i = 1, #CHAT_TYPES + 2 do -- (and the two whispers: see ChatTypesToUse)
		local choice = CreateFrame("Button", nil, S.keyboard, "UIPanelButtonTemplate");
		choice:SetScript("OnClick", PickChat);
		choice:Hide();
		chatChoices[i] = choice;
	end
	S.keyboard.ChatChoices = chatChoices;

	-- A presses this one (hidden, secure: Enter's macro line runs from it).
	local aButton = CreateFrame("Button", "GamepadKeyboardAButton", S.keyboard, "SecureActionButtonTemplate");
	aButton:RegisterForClicks("AnyDown", "AnyUp");
	aButton:SetAttribute("type", "macro");
	aButton:SetAttribute("useOnKeyDown", false);
	aButton:SetAttribute("macrotext", "");
	aButton:SetScript("PreClick", APreClick);
	aButton:SetScript("PostClick", APostClick);
	aButton:Hide();

	-- LB / RB press these (hidden: not keys to move to).
	for name, step in pairs({ GamepadKeyboardCursorLeft = -1, GamepadKeyboardCursorRight = 1 }) do
		local button = CreateFrame("Button", name, S.keyboard);
		button:SetScript("OnClick", function()
			MoveCursor(step);
		end);
		button:Hide();
	end

	S.keyboard.Prompts = { CreatePrompt(GAMEPAD_FACE_BOTTOM, "Type") };
	S.keyboard.HoldPrompt = CreatePrompt(GAMEPAD_FACE_BOTTOM, "Enter", S.keyboard.Prompts[1].text, true);
	table.insert(S.keyboard.Prompts, S.keyboard.HoldPrompt);
	for _, prompt in ipairs({
		{ GAMEPAD_FACE_LEFT, "Del" }, { GAMEPAD_FACE_TOP, "Space" }, { GAMEPAD_FACE_RIGHT, "Back" },
		{ GAMEPAD_SHOULDER_LEFT, "" }, { GAMEPAD_SHOULDER_RIGHT, "Cursor" },
	}) do
		table.insert(S.keyboard.Prompts, CreatePrompt(prompt[1], prompt[2], S.keyboard.Prompts[#S.keyboard.Prompts].text));
	end

	S.keyboard.CloseButton:SetScript("OnClick", Close);
	-- Controller B: go back, rather than Blizzard's gamepad UI pressing the close button.
	function S.keyboard:SmartNavigationCloseHandler()
		if picking then
			CloseChatList(); -- (from the chat list: back to the keys)
		else
			Close();
		end
		return true;
	end

	SetUpFocusVisuals();
	S.keyboard:SetScript("OnShow", function()
		Layout();
		UpdateLabels();
		UpdatePreview();
		for _, prompt in ipairs(S.keyboard.Prompts) do
			prompt.icon:SetShown(UsesGamepadUI());
			prompt.text:SetShown(UsesGamepadUI());
		end
		if not previewing then
			Register();
			RefreshNavigation();
		end
	end);
	-- However it closes (Enter, B, Escape, combat): back to the window the box belongs to, which focuses the
	-- box again - not a request for the keyboard - and the box isn't opened for again until focus moves
	-- elsewhere or it's asked for again. A chat line not sent waits for next time.
	S.keyboard:SetScript("OnHide", function()
		if isChat and target then
			KeepChatDraft();
		end
		handedBack = target;
		HideChatList();
		ClearShortcuts();
		aDownAt = nil; -- a press the keyboard closed under isn't a hold next time
		HoldRing(false);
		Unregister();
		target = nil;
	end);
end

-- The size first, then where it was put (kept in UIParent's units: a frame's offsets are in its own scaled
-- units, so they're multiplied by its scale to keep and divided to use - the same spot at any size); else for
-- chat beside the chat window, not over it; else above the text box if it's in the lower half of the
-- screen, below it if not; with no box (Edit Mode), the middle of the screen.
local function Position(box)
	local scale = Setting("scale");
	S.keyboard:SetScale(scale);
	S.keyboard:ClearAllPoints();
	local saved = DB().position;
	if saved then
		S.keyboard:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x / scale, saved.y / scale);
		return;
	end
	if not box then
		S.keyboard:SetPoint("CENTER");
		return;
	end
	if box.chatFrame then
		S.keyboard:SetPoint("BOTTOMLEFT", box.chatFrame, "BOTTOMRIGHT", 24, 0);
		return;
	end
	local _, y = box:GetCenter();
	local screenHeight = UIParent:GetHeight();
	if y and screenHeight and screenHeight > 0 and y > screenHeight / 2 then
		S.keyboard:SetPoint("TOP", box, "BOTTOM", 0, -8);
	elseif y then
		S.keyboard:SetPoint("BOTTOM", box, "TOP", 0, 8);
	else
		S.keyboard:SetPoint("CENTER");
	end
end

local function SetTarget(box)
	target = box;
	local parent = box:GetParent();
	local reviewed = not box:GetName() and Reviewed(box); -- (one of Blizzard's without a name: where it is)
	lastBoxName = reviewed and table.concat(reviewed.box, ".")
		or (box:GetName() or "an unnamed text box") .. " in " .. tostring(parent and parent:GetName() or "an unnamed frame");
	chatHadFocus = nil; -- a new box: no focus seen yet
	whisperedTo = nil; -- (the box's own, if it's in one, at the next preview)
	HideChatList();
	isChat = box.chatFrame ~= nil;
	suggesting = Setting("names") and LooksUpNames(box);
	if isChat then
		-- The chat box empties and goes back to its usual chat as the controller moves to the keyboard; the
		-- line and its chat stay here.
		chat = ChatFor(box);
		text = chatDraft and chatDraft.text or "";
		chatDraft = nil;
		local boxChat = ChatOf(box);
		seenChat = ChatKey(boxChat);
	else
		lastNamesBox = box;
		text = box:GetText() or "";
	end
	cursor = Utf8Length(text);
	page = box:IsNumeric() and "numbers" or LettersPage();
	shift = isChat and text == "" and Setting("chatCapital");
end

local function Open(box)
	if not S.keyboard then
		CreateKeyboard();
	end
	SetTarget(box);
	Position(box);
	S.keyboard:Show();
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

local function ShouldOpen(box)
	if not (not box:IsForbidden() -- (first: a forbidden box answers nothing else)
		and Setting("autoOpen")
		and ControllerAsked()
		and not InCombatLockdown()
		and UsesGamepadUI()
		and GetManager() ~= nil
		and not (S.keyboard and S.keyboard:IsShown())
		and box:IsObjectType("EditBox")
		and box:IsVisible()) then
		return false;
	end
	if not CanType(box) then
		TellCantType(box);
		return false;
	end
	return true;
end

-- Typing focus went to another text box while the keyboard is open. The controller's doing (LT to the
-- window, A on another box): the keyboard types there now - in place, the controller staying where it is
-- (back to the keyboard with LT / RT). A real keyboard's or the mouse's: the keyboard steps aside.
local function SwitchTo(box)
	if box:IsForbidden() or not (ControllerAsked() and box:IsObjectType("EditBox") and box:IsVisible()) then
		Close();
		return;
	end
	if not CanType(box) then
		Close();
		TellCantType(box);
		return;
	end
	if isChat then
		KeepChatDraft(); -- (the chat line waits)
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
	if closing or not box or box:IsForbidden() or not box:HasFocus() then
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
-- A link (shift-click on an item) while the keyboard is up over chat: Blizzard puts links in the active chat
-- box, and there's none then (the line is the keyboard's) - so it goes into the keyboard's line. Not when
-- the auction house took it as a search.
if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.GetActiveWindow then
	hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
		if S.keyboard and S.keyboard:IsShown() and isChat and target and type(link) == "string" and link ~= ""
			and not ChatFrameUtil.GetActiveWindow() and not (AuctionHouseFrame and AuctionHouseFrame:IsVisible()) then
			Insert(link);
		end
	end);
end
for index = 1, NUM_CHAT_WINDOWS or 10 do
	local chatFrame = _G["ChatFrame" .. index];
	if chatFrame and chatFrame.SetGamepadFocus then
		hooksecurefunc(chatFrame, "SetGamepadFocus", function(self)
			Requested(self.editBox);
		end);
	end
end

-------------------------------------------------------------------------------
-- Options: the addon's own page in Blizzard's Settings panel (Options > AddOns)
-------------------------------------------------------------------------------
-- A canvas page - a frame of its own, which the panel only shows - not Blizzard's list of controls: the
-- panel keeps a list control's data as the addon wrote it, so drawing one is the addon's doing (tainted),
-- and as the panel hides it can redraw its page (clearing its search box) and then save key bindings,
-- which only Blizzard's UI may do - blocked, and blamed on the addon. A canvas page's own calls (refresh,
-- defaults, commit) the panel makes isolated, and this one has no OnShow (the panel shows it directly).

local optionsPanel;
local LAYOUT_CHOICES = { { "qwerty", "QWERTY" }, { "dvorak", "Dvorak" } };

-- The layout after the current one (round to the first).
local function NextLayout()
	for i, layout in ipairs(LAYOUT_CHOICES) do
		if layout[1] == Setting("layout") and LAYOUT_CHOICES[i + 1] then
			return LAYOUT_CHOICES[i + 1][1];
		end
	end
	return LAYOUT_CHOICES[1][1];
end

-- A change of layout shows at once if the keyboard is up on its letters.
local function ApplyLayout()
	if S.keyboard and S.keyboard:IsShown() and page ~= "symbols" and page ~= "numbers" and not InCombatLockdown() then
		page = LettersPage();
		Layout();
		UpdateLabels();
		RefreshNavigation();
	end
end

-- A change of size shows at once if the keyboard is up.
local function ApplySize()
	if S.keyboard and S.keyboard:IsShown() and not InCombatLockdown() then
		Position(target);
	end
end

local function UpdateOptionsPanel()
	if not optionsPanel then
		return;
	end
	for key, check in pairs(optionsPanel.Checks) do
		check:SetChecked(Setting(key));
	end
	optionsPanel.LayoutDropdown:GenerateMenu(); -- shows the layout chosen (after Defaults, say)
	optionsPanel.Steppers.holdTime.Value:SetText(("%.1f s"):format(Setting("holdTime")));
	optionsPanel.Steppers.scale.Value:SetText(("%d%%"):format(Setting("scale") * 100 + 0.5));
end

-- A setting changed (the options page, /gk, Edit Mode): it takes effect, and the page shows it.
local function SetOption(key, value)
	DB()[key] = value;
	if key == "scale" then
		ApplySize();
	elseif key == "layout" then
		ApplyLayout();
	end
	UpdateOptionsPanel();
end

-- A step of 5% from the nearest step - in whole percents, so the sizes stay exact.
local function Resize(delta)
	local percent = math.floor(Setting("scale") * 20 + 0.5) * 5 + delta * 5;
	SetOption("scale", math.max(60, math.min(150, percent)) / 100);
end

-- A step of 0.1 s, in tenths for the same reason.
local function ChangeHoldTime(delta)
	local tenths = math.floor(Setting("holdTime") * 10 + 0.5) + delta;
	SetOption("holdTime", math.max(3, math.min(15, tenths)) / 10);
end

local function CreateOptionsPanel()
	local panel = CreateFrame("Frame");
	panel.Checks, panel.Steppers = {}, {};
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	title:SetPoint("TOPLEFT", 16, -16);
	title:SetText("Gamepad Keyboard");
	local y = -52;
	local function NextRow()
		local rowY = y;
		y = y - 36;
		return rowY;
	end
	local function Describe(widget, text) -- (hooked: a template's own hover look stays)
		widget:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(text, nil, nil, nil, nil, true);
			GameTooltip:Show();
		end);
		widget:HookScript("OnLeave", function()
			GameTooltip:Hide();
		end);
	end
	local function Label(text, x, rowY)
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
		label:SetPoint("TOPLEFT", x, rowY - 6);
		label:SetText(text);
		return label;
	end
	local function Check(key, text, tooltip)
		local rowY = NextRow();
		local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate");
		check:SetPoint("TOPLEFT", 16, rowY);
		check:SetScript("OnClick", function(self)
			SetOption(key, self:GetChecked() and true or false);
		end);
		Describe(check, tooltip);
		Label(text, 50, rowY);
		panel.Checks[key] = check;
	end
	local function Stepper(key, text, tooltip, change)
		local rowY = NextRow();
		Label(text, 20, rowY);
		local stepper = {};
		for i, step in ipairs({ -1, 1 }) do
			local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
			button:SetSize(32, 26);
			button:SetPoint("TOPLEFT", 220 + (i - 1) * 110, rowY);
			button:SetText(step < 0 and "-" or "+");
			button:SetScript("OnClick", function()
				change(step);
			end);
			Describe(button, tooltip);
			stepper[step < 0 and "Minus" or "Plus"] = button;
		end
		stepper.Value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
		stepper.Value:SetPoint("TOPLEFT", 262, rowY - 6);
		panel.Steppers[key] = stepper;
	end

	Check("autoOpen", "Open with the controller",
		"Opens when you go to a text box with the controller: A on it, or Chat on the menu dial. A real keyboard or the mouse never opens it.");
	-- Keyboard layout: Blizzard's own dropdown with < > steppers, as the dropdowns in Options are; the
	-- controller's cursor lands on the whole control, as in Options. Its menu never opens: a menu opened by
	-- an addon has the controller UI suspend its focused frame as the addon's doing (FrameControlsManager's
	-- MenuProxy.OnShow / OnClose aren't isolated), and that frame's footer bindings, put back on the close,
	-- go on to block the interact icon and RB targeting ("blocked from an action only available to the
	-- Blizzard UI": SetPreferredGamepadInteractTarget, TargetNearestEnemy). So a click or A on it picks the
	-- next layout, and < > step (picking without a menu).
	local layoutY = NextRow();
	Label("Keyboard layout", 20, layoutY);
	local layoutControl = CreateFrame("Frame", nil, panel, "SettingsDropdownWithButtonsTemplate");
	layoutControl:SetPoint("TOPLEFT", 200, layoutY + 6);
	layoutControl.Dropdown:SetWidth(180);
	layoutControl.Dropdown:SetupMenu(function(_, rootDescription)
		for _, layout in ipairs(LAYOUT_CHOICES) do
			rootDescription:CreateRadio(layout[2], function()
				return Setting("layout") == layout[1];
			end, function()
				SetOption("layout", layout[1]);
			end);
		end
	end);
	function layoutControl.Dropdown:OpenMenu() -- (the click's way in: SetMenuOpen)
		SetOption("layout", NextLayout());
	end
	function layoutControl:OnSmartNavClick()
		SetOption("layout", NextLayout());
		return true;
	end
	Describe(layoutControl.Dropdown, "Where the letters are. Numbers, symbols and the bottom row are the same in both.");
	panel.LayoutDropdown = layoutControl.Dropdown;
	Check("closeOnEnter", "Close after Enter",
		"Enter sends a chat line and closes the chat, or runs a text box's Enter and closes the keyboard. Off: the keyboard stays open for the next line.");
	Check("chatCapital", "Capital letter to start a chat line", "A chat line starts with Shift on.");
	Check("names", "Name suggestions", "Name keys above the keyboard for a text box that looks names up, like the mail's To:.");
	Stepper("holdTime", "Hold A for Enter", "How long to hold A for Enter (or a new line in a box of several lines).", ChangeHoldTime);
	Stepper("scale", "Size", "The keyboard's size. In Edit Mode, the mouse wheel over it changes it too.", Resize);
	local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
	hint:SetPoint("TOPLEFT", 20, NextRow() - 6);
	hint:SetText("Where it opens: drag it in Edit Mode. /gk reset puts back its usual place and size.");

	-- Called by the panel, isolated: its refresh, and its Defaults button (all the options back; where it
	-- opens stays - /gk reset for that).
	panel.OnRefresh = UpdateOptionsPanel;
	panel.OnDefault = function()
		for key, value in pairs(DEFAULTS) do
			SetOption(key, value);
		end
	end;
	return panel;
end

local function RegisterOptions()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return;
	end
	optionsPanel = CreateOptionsPanel();
	Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(optionsPanel, "Gamepad Keyboard"));
	UpdateOptionsPanel();
end

-------------------------------------------------------------------------------
-- Edit Mode: the keyboard shows where it opens, to be dragged and resized
-------------------------------------------------------------------------------

local EDIT_MODE_STRATA = "HIGH"; -- under Edit Mode's own panels (DIALOG)
local inEditMode = false;


-- Its selection: drag to move, mouse wheel to resize (Blizzard's selection templates call back into Edit
-- Mode with the frame, so this one is its own).
local function CreateEditModeOverlay()
	local overlay = CreateFrame("Frame", nil, S.keyboard);
	overlay:SetAllPoints();
	overlay:SetFrameLevel(S.keyboard:GetFrameLevel() + 50);
	overlay:EnableMouse(true);
	overlay:EnableMouseWheel(true);
	overlay:RegisterForDrag("LeftButton");
	local fill = overlay:CreateTexture(nil, "BACKGROUND");
	fill:SetAllPoints();
	fill:SetColorTexture(0.25, 0.6, 1, 0.3);
	overlay.Label = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
	overlay.Label:SetPoint("CENTER", 0, 12);
	overlay.Label:SetText("Gamepad Keyboard");
	overlay.Hint = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	overlay.Hint:SetPoint("TOP", overlay.Label, "BOTTOM", 0, -6);
	overlay.Hint:SetText("Drag to move, mouse wheel to resize");
	overlay:SetScript("OnDragStart", function()
		S.keyboard:StartMoving();
	end);
	overlay:SetScript("OnDragStop", SavePosition);
	overlay:SetScript("OnMouseWheel", function(_, delta)
		Resize(delta);
	end);
	overlay:Hide();
	S.keyboard.EditModeOverlay = overlay;
end

local function EditModeEnter()
	inEditMode = true;
	if InCombatLockdown() then
		return; -- shown as combat ends, if Edit Mode is still open
	end
	Close(); -- typing somewhere: the text stays in the box
	if not S.keyboard then
		CreateKeyboard();
	end
	if not S.keyboard.EditModeOverlay then
		CreateEditModeOverlay();
	end
	previewing = true;
	target, isChat, suggesting = nil, false, false;
	text, cursor, page, shift = "", 0, LettersPage(), false;
	S.keyboard:SetFrameStrata(EDIT_MODE_STRATA);
	Position(nil);
	S.keyboard:Show();
	S.keyboard.EditModeOverlay:Show();
end

-- The preview goes - not in combat: the keyboard holds secure buttons, so only Blizzard's UI may hide it
-- then (finished as combat ends).
local function EndPreview()
	if not previewing or InCombatLockdown() then
		return;
	end
	previewing = false;
	S.keyboard.EditModeOverlay:Hide();
	S.keyboard:Hide();
	S.keyboard:SetFrameStrata("FULLSCREEN_DIALOG");
end

local function EditModeExit()
	inEditMode = false;
	EndPreview();
end

if EventRegistry then
	EventRegistry:RegisterCallback("EditMode.Enter", EditModeEnter, ADDON_NAME);
	EventRegistry:RegisterCallback("EditMode.Exit", EditModeExit, ADDON_NAME);
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
	if previewing then
		lastFocus = GetCurrentKeyBoardFocus(); -- in Edit Mode: not typing anywhere, and nothing to open after it
		return;
	end
	-- Its box gone (the window closed, Enter hid it; for chat its window - the chat box itself can hide as it
	-- empties): the keyboard goes too.
	if S.keyboard and S.keyboard:IsShown() and target and not (isChat and target.chatFrame or target):IsVisible() then
		Close();
	end
	if S.keyboard and S.keyboard:IsShown() and isChat and target then
		-- A whisper started elsewhere while the keyboard is up (a name's menu, the reply key): the line goes
		-- there. Other changes are the chat box's own (emptied as it lost focus: back to its usual chat).
		local boxChat = ChatOf(target);
		local seen = ChatKey(boxChat);
		if seen ~= seenChat then
			if IsWhisper(boxChat.chatType) and boxChat.tellTarget and not Sayable(boxChat) then
				local box = target;
				Close(); -- (the line waits, in its own chat: this one is new to it)
				TellCantType(box);
			else
				seenChat = seen;
				if IsWhisper(boxChat.chatType) and boxChat.tellTarget then
					chat = boxChat;
					UpdatePreview();
				end
			end
		end
	end
	if S.keyboard and S.keyboard:IsShown() and isChat and target then
		UpdateChatKey();
		local boxText = target:GetText() or "";
		if boxText ~= seenBoxText then
			seenBoxText = boxText;
			UpdatePreview(); -- (a link put in the chat box's own line)
		end
		-- The chat box has no typing focus while the controller is on the keyboard. Getting it back from a real
		-- keyboard (Enter, /) or the mouse: this keyboard steps aside, its line waits. From the controller (LT
		-- to the chat window): it stays.
		local hasFocus = target:HasFocus();
		if chatHadFocus == false and hasFocus and not ControllerAsked() then
			Close();
		end
		chatHadFocus = hasFocus;
	end
	-- Its box changed under it (the mail sent and its boxes cleared, a box's Enter, a link put in): the
	-- preview, cursor and name keys follow at once, not at the next key.
	if S.keyboard and S.keyboard:IsShown() and target then
		local before = text;
		Sync();
		if text ~= before then
			UpdatePreview();
		end
	end
	local focus = GetCurrentKeyBoardFocus();
	if focus == lastFocus then
		return;
	end
	lastFocus = focus;
	if S.keyboard and S.keyboard:IsShown() then
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
watcher:RegisterEvent("ADDON_LOADED");
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN");
watcher:RegisterEvent("ADDON_ACTION_BLOCKED");
watcher:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
		-- The game blocked something and blamed this addon: what, and where it last typed (for a report).
		local addon, action = ...;
		if addon == ADDON_NAME then
			Print(("the game blocked %s (%s). Last typed into: %s. A /reload clears it; please report this."):format(
				tostring(action), event == "ADDON_ACTION_FORBIDDEN" and "Blizzard UI only" or "in combat", lastBoxName or "nothing yet"));
		end
	elseif event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			watcher:UnregisterEvent("ADDON_LOADED");
			RegisterOptions(); -- the saved table is the loaded one now
		end
	elseif event == "GLOBAL_MOUSE_DOWN" then
		lastInput = "mouse";
	elseif event == "PLAYER_REGEN_DISABLED" then
		Close(); -- the text stays in the box
		EndPreview(); -- (the moment before combat locks it)
	else -- PLAYER_REGEN_ENABLED
		if S.keyboard and not S.keyboard:IsShown() then
			ClearShortcuts(); -- if combat stopped it as the keyboard closed
			if registered then
				Unregister(); -- a hide Blizzard refused as combat started
			end
		elseif shortcutsBound then
			BindShortcuts(); -- (still up: the controller UI may have bound its buttons over them in combat)
		end
		if not inEditMode then
			EndPreview(); -- Edit Mode left in combat
		elseif not previewing then
			EditModeEnter(); -- Edit Mode still open: the preview back
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
		SetOption("scale", DEFAULTS.scale);
		Print("back to its usual place and size.");
	elseif message == "names" then
		if lastNamesBox then
			DescribeNames(lastNamesBox);
		else
			Print("type in a text box with the keyboard first (the mail's To:, say), then /gk names.");
		end
	elseif message == "on" or message == "off" then
		SetOption("autoOpen", message == "on");
		Print(message == "on" and "opens when a text box gets focus with the controller."
			or "off - type with a keyboard; /gk on turns it back on.");
	else
		-- Where the options are, not opening them: opened from here (Settings.OpenToCategory) the panel
		-- would open as this addon's doing - its open event comes straight back into this call - and what it
		-- builds then stays the addon's (blocked later, blamed on it).
		Print(("%s. Options: Game Menu > Options > AddOns > Gamepad Keyboard. /gk on | off, /gk reset puts it back in its usual place and size."):format(
			Setting("autoOpen") and "On" or "Off"));
	end
end;
