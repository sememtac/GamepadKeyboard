-- The keyboard's frame: its keys, name keys, chat list, footer, and where it opens.

local ADDON_NAME, ns = ...;
local S = ns.S;
local CHAT, CHAT_TYPES, ChooseSuggestion = ns.CHAT, ns.CHAT_TYPES, ns.ChooseSuggestion;
local ClearShortcuts, Close, CloseChatList = ns.ClearShortcuts, ns.Close, ns.CloseChatList;
local CreateAButton, CreateKey, DB, EDGE, ENTER = ns.CreateAButton, ns.CreateKey, ns.DB, ns.EDGE, ns.ENTER;
local HideChatList, KeepChatDraft, LINE_INSET = ns.HideChatList, ns.KeepChatDraft, ns.LINE_INSET;
local LINE_TOP, Layout, MAX_SUGGESTIONS = ns.LINE_TOP, ns.Layout, ns.MAX_SUGGESTIONS;
local MoveCursor, OverChat, PAGES, PAGE_KEY_UNITS = ns.MoveCursor, ns.OverChat, ns.PAGES, ns.PAGE_KEY_UNITS;
local PROMPT_BOTTOM, PROMPT_SIZE, PROMPT_SPACING = ns.PROMPT_BOTTOM, ns.PROMPT_SIZE, ns.PROMPT_SPACING;
local PickChat, RefreshNavigation, Register = ns.PickChat, ns.RefreshNavigation, ns.Register;
local ResetHold, SHIFT, SetUpFocusVisuals, Setting = ns.ResetHold, ns.SHIFT, ns.SetUpFocusVisuals, ns.Setting;
local Unregister, UpdateLabels, UpdatePreview = ns.Unregister, ns.UpdateLabels, ns.UpdatePreview;
local UsesGamepadUI, WidestRow, chatChoices, keys = ns.UsesGamepadUI, ns.WidestRow, ns.chatChoices, ns.keys;
local suggestions = ns.suggestions;

local function CreatePrompt(key, label, anchorTo, isHold)
	local icon = CreateFrame("Frame", nil, S.keyboard, "InputIconTextureFrameTemplate");
	icon:SetSize(PROMPT_SIZE, PROMPT_SIZE);
	icon:SetInputKey(key);
	if isHold then
		icon:SetIsHoldAction(true); -- the press-and-hold ring
	end
	if anchorTo then
		icon:SetPoint("LEFT", anchorTo, "RIGHT", PROMPT_SPACING, 0);
	else
		icon:SetPoint("BOTTOMLEFT", EDGE, PROMPT_BOTTOM);
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

-- The keys of every page (each made once; Layout shows the page's).
local function CreateKeys()
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
end

-- The name keys (shown for a box that looks names up).
local function CreateNameKeys()
	for i = 1, MAX_SUGGESTIONS do
		local button = CreateFrame("Button", nil, S.keyboard, "UIPanelButtonTemplate");
		button:SetScript("OnClick", ChooseSuggestion);
		button:Hide();
		suggestions[i] = button;
	end
end

local function CreateChatList()
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
end

local function CreateCursorButtons()
	-- LB / RB press these (hidden: not keys to move to).
	for name, step in pairs({ GamepadKeyboardCursorLeft = -1, GamepadKeyboardCursorRight = 1 }) do
		local button = CreateFrame("Button", name, S.keyboard);
		button:SetScript("OnClick", function()
			MoveCursor(step);
		end);
		button:Hide();
	end
end

-- The footer: what the controller's buttons do here.
local function CreateFooter()
	S.keyboard.Prompts = { CreatePrompt(GAMEPAD_FACE_BOTTOM, "Type") };
	S.keyboard.HoldPrompt = CreatePrompt(GAMEPAD_FACE_BOTTOM, "Enter", S.keyboard.Prompts[1].text, true);
	table.insert(S.keyboard.Prompts, S.keyboard.HoldPrompt);
	for _, prompt in ipairs({
		{ GAMEPAD_FACE_LEFT, "Del" }, { GAMEPAD_FACE_TOP, "Space" }, { GAMEPAD_FACE_RIGHT, "Back" },
		{ GAMEPAD_SHOULDER_LEFT, "" }, { GAMEPAD_SHOULDER_RIGHT, "Cursor" },
	}) do
		table.insert(S.keyboard.Prompts, CreatePrompt(prompt[1], prompt[2], S.keyboard.Prompts[#S.keyboard.Prompts].text));
	end
end

local function KeyboardShown()
	Layout();
	UpdateLabels();
	UpdatePreview();
	for _, prompt in ipairs(S.keyboard.Prompts) do
		prompt.icon:SetShown(UsesGamepadUI());
		prompt.text:SetShown(UsesGamepadUI());
	end
	if not S.previewing then
		Register();
		RefreshNavigation();
	end
end

-- However it closes (Enter, B, Escape, combat): back to the window the box belongs to, which focuses the
-- box again - not a request for the keyboard - and the box isn't opened for again until focus moves
-- elsewhere or it's asked for again. A chat line not sent waits for next time.
local function KeyboardHidden()
	if OverChat() then
		KeepChatDraft();
	end
	S.handedBack = S.target;
	HideChatList();
	ClearShortcuts();
	ResetHold(); -- (a press the keyboard closed under isn't a hold next time)
	Unregister();
	S.target = nil;
end

local function CreateKeyboard()
	S.keyboard = CreateFrame("Frame", "GamepadKeyboardFrame", UIParent, "BasicFrameTemplateWithInset, FocusFramesInterfaceTemplate");
	S.keyboard:SetWidth(WidestRow() + 2 * EDGE); -- (its height is the page's: see Layout)
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
	S.keyboard.ChatHeader:SetPoint("TOPLEFT", LINE_INSET, -LINE_TOP);
	S.keyboard.Preview = S.keyboard:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	S.keyboard.Preview:SetPoint("TOPLEFT", LINE_INSET, -LINE_TOP);
	S.keyboard.Preview:SetPoint("TOPRIGHT", -LINE_INSET, -LINE_TOP);
	S.keyboard.Preview:SetJustifyH("LEFT");

	CreateKeys();
	CreateNameKeys();
	CreateChatList();
	CreateAButton();
	CreateCursorButtons();
	CreateFooter();

	S.keyboard.CloseButton:SetScript("OnClick", Close);
	-- Controller B: go back, rather than Blizzard's gamepad UI pressing the close button.
	function S.keyboard:SmartNavigationCloseHandler()
		if S.picking then
			CloseChatList(); -- (from the chat list: back to the keys)
		else
			Close();
		end
		return true;
	end

	SetUpFocusVisuals();
	S.keyboard:SetScript("OnShow", KeyboardShown);
	S.keyboard:SetScript("OnHide", KeyboardHidden);
end

-- The size first, then where it was put (kept in UIParent's units: a frame's offsets are in its own scaled
-- units, so they're multiplied by its scale to keep and divided to use - the same spot at any size); else for
-- chat beside the chat window, not over it; else above the text box if it's in the lower half of the
-- screen, below it if not; with no box (Edit Mode), the middle of the screen.
local BESIDE_CHAT, BY_BOX = 24, 8; -- (the gap to the chat window, to the box)

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
		S.keyboard:SetPoint("BOTTOMLEFT", box.chatFrame, "BOTTOMRIGHT", BESIDE_CHAT, 0);
		return;
	end
	local _, y = box:GetCenter();
	local screenHeight = UIParent:GetHeight();
	if y and screenHeight and screenHeight > 0 and y > screenHeight / 2 then
		S.keyboard:SetPoint("TOP", box, "BOTTOM", 0, -BY_BOX);
	elseif y then
		S.keyboard:SetPoint("BOTTOM", box, "TOP", 0, BY_BOX);
	else
		S.keyboard:SetPoint("CENTER");
	end
end

ns.CreateKeyboard, ns.Position, ns.SavePosition = CreateKeyboard, Position, SavePosition;
