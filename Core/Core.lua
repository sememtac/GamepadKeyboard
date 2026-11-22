


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
S.keyboard = nil; -- the keyboard's frame (made the first time it opens)
S.target = nil; -- the text box being typed into
S.isChat = false; -- ...a chat box
S.suggesting = false; -- ...one that looks names up (a row of name keys above the keys)
S.text = ""; -- the line
S.cursor = 0; -- characters before the cursor
S.page = "qwerty"; -- a letters page (the layout's), "symbols", or "numbers" (a box of numbers only)
S.shift = false; -- the next letter a capital
-- Over chat the line and its chat are the keyboard's own: typed here, sent with a secure macro line, never
-- written into Blizzard's chat box. What typing there sets off (its text-changed fields, the chat type's
-- parsing) would run as this addon's doing and stay so - read by Blizzard's chat later, on into the
-- controller's bindings: blocked, blamed on the addon. The chat box is only read - but for its chat
-- attributes (what its own send reads; attributes come back clean).
S.chat = {}; -- the chat the line goes to: { chatType, tellTarget, channelTarget }
S.seenChat = nil; -- the chat box's own chat last frame, as ChatKey gives it (to see a whisper started elsewhere)
S.chatDraft = nil; -- a chat line closed unsent: { text, chat, boxChats } - back the next time it opens on chat
S.whisperedTo = nil; -- the whisper this chat was in while the keyboard was up: { chatType, target }
S.picking = false; -- the chat list is open (see OpenChatList)
S.handedBack = nil; -- the box the keyboard just went back to: not opened for again until focus moves on
S.closing = false; -- while closing hands the controller back (which focuses the box again)
S.previewing = false; -- shown in Edit Mode to be placed, not typing anywhere
S.lastNamesBox = nil; -- the last box typed into that isn't chat (for /gk names)

-- The keyboard on screen; over a chat box (with one to type into).
local function IsOpen()
	return S.keyboard and S.keyboard:IsShown();
end
local function OverChat()
	return S.isChat and S.target;
end

local KEY_WIDTH, KEY_HEIGHT, GAP = 36, 30, 4;
local ROW = KEY_HEIGHT + GAP; -- a row of keys and the gap under it
-- The frame: its edge to the keys, name keys and footer; its top to the first row of keys (under the title
-- and the line); the line (the preview) under the title; the footer's prompts (a glyph, the space before the
-- next one) and their margin under them.
local EDGE, KEYS_TOP = 14, 56;
local LINE_TOP, LINE_INSET = 32, 16;
local PROMPT_SIZE, PROMPT_SPACING, PROMPT_BOTTOM = 22, 12, 10;
local FOOTER = PROMPT_SIZE + PROMPT_BOTTOM;

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

-- A key's width in keys (a special key's own, or its page's), and in pixels (the gaps it spans with it).
local function KeyUnits(key, pageUnits)
	local special = SPECIAL_KEYS[key];
	return pageUnits or special and special.units or 1;
end
local function KeyWidth(units)
	return units * KEY_WIDTH + (units - 1) * GAP;
end

-- The widest row of keys on any page: the frame is that and its edges.
local function WidestRow()
	local widest = 0;
	for name, layout in pairs(PAGES) do
		for _, rowKeys in ipairs(layout) do
			local width = (#rowKeys - 1) * GAP;
			for _, key in ipairs(rowKeys) do
				width = width + KeyWidth(KeyUnits(key, PAGE_KEY_UNITS[name]));
			end
			widest = math.max(widest, width);
		end
	end
	return widest;
end

local keys = {}; -- page -> rows of key buttons
local suggestions = {}; -- the name keys
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

ns.BACK, ns.CHAT, ns.DB, ns.DEFAULTS, ns.EDGE, ns.ENTER = BACK, CHAT, DB, DEFAULTS, EDGE, ENTER;
ns.FOOTER, ns.GAP, ns.IsOpen, ns.KEYS_TOP, ns.KEY_HEIGHT = FOOTER, GAP, IsOpen, KEYS_TOP, KEY_HEIGHT;
ns.KeyUnits, ns.KeyWidth, ns.LETTERS, ns.LINE_INSET = KeyUnits, KeyWidth, LETTERS, LINE_INSET;
ns.LINE_TOP, ns.LettersPage, ns.OverChat, ns.PAGES = LINE_TOP, LettersPage, OverChat, PAGES;
ns.PAGE_KEY_UNITS, ns.PROMPT_BOTTOM, ns.PROMPT_SIZE = PAGE_KEY_UNITS, PROMPT_BOTTOM, PROMPT_SIZE;
ns.PROMPT_SPACING, ns.Print, ns.ROW, ns.SHIFT, ns.SPACE = PROMPT_SPACING, Print, ROW, SHIFT, SPACE;
ns.SPECIAL_KEYS, ns.SYMBOLS, ns.Setting = SPECIAL_KEYS, SYMBOLS, Setting;
ns.UsesGamepadUI, ns.Utf8Length, ns.WidestRow = UsesGamepadUI, Utf8Length, WidestRow;
ns.chatChoices, ns.keys, ns.suggestions = chatChoices, keys, suggestions;
