-- Gamepad Keyboard: an on-screen keyboard for typing with a controller.
--
-- When a text box gets typing focus in the game's controller UI (out of combat), the keyboard opens as a
-- popup in Blizzard's gamepad UI, like its own panels: the D-pad moves between keys (left / right along a
-- row, up / down between rows), A types, B or Done goes back. Each key writes straight into the text box,
-- which is the preview, and going back returns the controller to the window the box belongs to.
--
-- Chat: the keyboard never sends. Going back returns to the chat box with the text, where the chat's own A
-- sends it - Blizzard's code, so whispers, channels, /p and emotes work as when typing, and nothing of ours
-- runs in its send path. Opening the keyboard moves the controller off the chat box, which would close an
-- empty box and reset its chat type (a whisper target, say); a single space put in first keeps it open.
--
-- In combat Blizzard's gamepad UI takes no addon windows, so the keyboard doesn't open (a real keyboard
-- types as always), and an open one closes when combat starts; the text stays in the box.

local ADDON_NAME = ...;

local KEY_WIDTH, KEY_HEIGHT, GAP = 36, 30, 4;
local PLACEHOLDER = " ";

local BACK, SHIFT, SYMBOLS, LETTERS, SPACE, DONE = "BACK", "SHIFT", "SYMBOLS", "LETTERS", "SPACE", "DONE";
local SPECIAL_KEYS = {
	[BACK] = { label = "Del", units = 1.6 },
	[SHIFT] = { label = "Shift", units = 1.6 },
	[SYMBOLS] = { label = "?123", units = 2 },
	[LETTERS] = { label = "ABC", units = 2 },
	[SPACE] = { label = "Space", units = 5 },
	[DONE] = { label = "Done", units = 2.5 },
};
-- No "|": the game reads it as the start of an escape code.
local PAGES = {
	letters = {
		{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", BACK },
		{ "q", "w", "e", "r", "t", "y", "u", "i", "o", "p" },
		{ "a", "s", "d", "f", "g", "h", "j", "k", "l", "'" },
		{ SHIFT, "z", "x", "c", "v", "b", "n", "m", ",", "." },
		{ SYMBOLS, SPACE, DONE },
	},
	symbols = {
		{ "!", "@", "#", "$", "%", "&", "*", "(", ")", "-", BACK },
		{ "/", "\\", ":", ";", "\"", "?", "+", "=", "_", "~" },
		{ "<", ">", "[", "]", "{", "}", "^", "`", "'", "," },
		{ LETTERS, SPACE, DONE },
	},
};

local keyboard;
local keys = {}; -- page -> rows of key buttons
local page = "letters";
local target; -- the text box being typed into
local isChat = false;
local text = "";
local shift = false;
local handedBack; -- the box the keyboard just went back to: not opened for again until focus moves on

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

local function UpdatePreview()
	local shown = text;
	if Utf8Length(shown) > 48 then
		shown = "..." .. shown:sub(-48);
	end
	keyboard.Preview:SetText(shown .. "_");
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

local function SetText(newText)
	text = newText;
	if target then
		target:SetText(text);
	end
	UpdatePreview();
end

local function Insert(characters)
	local maxLetters = target and target:GetMaxLetters() or 0;
	if maxLetters > 0 and Utf8Length(text) + Utf8Length(characters) > maxLetters then
		return;
	end
	SetText(text .. characters);
end

local function Layout()
	for name, rows in pairs(keys) do
		for _, row in ipairs(rows) do
			for _, button in ipairs(row) do
				button:SetShown(name == page);
			end
		end
	end
	keyboard:SetHeight(84 + #keys[page] * (KEY_HEIGHT + GAP));
end

local function Close()
	if keyboard and keyboard:IsShown() then
		keyboard:Hide();
	end
end

local function Press(button)
	local key = button.key;
	if key == BACK then
		SetText((text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")));
	elseif key == SPACE then
		Insert(" ");
	elseif key == SHIFT then
		shift = not shift;
		UpdateLabels();
	elseif key == SYMBOLS or key == LETTERS then
		page = key == SYMBOLS and "symbols" or "letters";
		Layout();
		RefreshNavigation();
	elseif key == DONE then
		Close();
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

local function CreateKey(key)
	local special = SPECIAL_KEYS[key];
	local units = special and special.units or 1;
	local button = CreateFrame("Button", nil, keyboard, "UIPanelButtonTemplate");
	button.width = units * KEY_WIDTH + (units - 1) * GAP;
	button:SetSize(button.width, KEY_HEIGHT);
	button:SetText(special and special.label or key);
	button.key = key;
	button:SetScript("OnClick", Press);
	return button;
end

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
	keyboard:Hide();
	tinsert(UISpecialFrames, "GamepadKeyboardFrame");

	keyboard.Title = keyboard:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	keyboard.Title:SetPoint("TOP", 0, -5);
	keyboard.Title:SetText("Keyboard");
	keyboard.Preview = keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	keyboard.Preview:SetPoint("TOPLEFT", 16, -32);
	keyboard.Preview:SetPoint("TOPRIGHT", -16, -32);
	keyboard.Preview:SetJustifyH("LEFT");

	for name, layout in pairs(PAGES) do
		keys[name] = {};
		for r, rowKeys in ipairs(layout) do
			local row = {};
			local width = 0;
			for c, key in ipairs(rowKeys) do
				row[c] = CreateKey(key);
				width = width + row[c].width + (c > 1 and GAP or 0);
			end
			-- Each row centred.
			local x = (keyboard:GetWidth() - width) / 2;
			for _, button in ipairs(row) do
				button:SetPoint("TOPLEFT", x, -56 - (r - 1) * (KEY_HEIGHT + GAP));
				x = x + button.width + GAP;
				if button.key == SHIFT then
					keyboard.ShiftKey = button;
				end
			end
			keys[name][r] = row;
		end
	end

	keyboard.Prompts = { CreatePrompt(GAMEPAD_FACE_BOTTOM, "Type") };
	table.insert(keyboard.Prompts, CreatePrompt(GAMEPAD_FACE_RIGHT, "Done", keyboard.Prompts[1].text));

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
	-- However it closes (Done, B, Escape, combat): back to the window the box belongs to, and the box isn't
	-- opened for again until focus moves elsewhere. An untouched chat box loses its placeholder.
	keyboard:SetScript("OnHide", function()
		if isChat and target and target:GetText() == PLACEHOLDER then
			target:SetText("");
		end
		handedBack = target;
		Unregister();
		target = nil;
	end);
end

-- Above the text box if it's in the lower half of the screen, else below it.
local function Position(box)
	keyboard:ClearAllPoints();
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

local function Open(box)
	if not keyboard then
		CreateKeyboard();
	end
	target = box;
	isChat = box.chatFrame ~= nil;
	text = box:GetText() or "";
	if isChat and text == "" then
		-- Keeps the chat box open, and its chat type, while the controller is on the keyboard.
		box:SetText(PLACEHOLDER);
	end
	page = "letters";
	shift = isChat and text == "";
	Position(box);
	keyboard:Show();
end

local function ShouldOpen(box)
	return DB().autoOpen ~= false
		and not InCombatLockdown()
		and UsesGamepadUI()
		and GetManager() ~= nil
		and not (keyboard and keyboard:IsShown())
		and box:IsObjectType("EditBox")
		and not box:IsForbidden()
		and box:IsVisible();
end

-------------------------------------------------------------------------------
-- Watching for text boxes, combat
-------------------------------------------------------------------------------

-- One check per frame: the keyboard opens when typing focus moves to a text box.
local lastFocus;
local watcher = CreateFrame("Frame");
watcher:SetScript("OnUpdate", function()
	local focus = GetCurrentKeyBoardFocus();
	if focus == lastFocus then
		return;
	end
	lastFocus = focus;
	if focus ~= handedBack then
		handedBack = nil;
		if focus and ShouldOpen(focus) then
			Open(focus);
		end
	end
end);
watcher:RegisterEvent("PLAYER_REGEN_DISABLED");
watcher:RegisterEvent("PLAYER_REGEN_ENABLED");
watcher:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Close(); -- the text stays in the box
	elseif keyboard and not keyboard:IsShown() and registered then
		Unregister(); -- a hide Blizzard refused as combat started
	end
end);

SLASH_GAMEPADKEYBOARD1 = "/gk";
SLASH_GAMEPADKEYBOARD2 = "/gamepadkeyboard";
SlashCmdList.GAMEPADKEYBOARD = function(message)
	message = strtrim(message or ""):lower();
	if message == "on" or message == "off" then
		DB().autoOpen = message == "on";
		Print(message == "on" and "opens when a text box gets focus with the controller."
			or "off - type with a keyboard; /gk on turns it back on.");
	else
		Print(("%s. /gk on | off."):format(DB().autoOpen ~= false and "On" or "Off"));
	end
end;
