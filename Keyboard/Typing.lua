-- Typing: the line and its cursor, the preview, the name keys, the page's layout, the chat key's list, a
-- key's press.

local ADDON_NAME, ns = ...;
local S = ns.S;
local BACK, CHAT, CanSteer, ChatKey, ChatLabel = ns.BACK, ns.CHAT, ns.CanSteer, ns.ChatKey, ns.ChatLabel;
local ChatLine, ChatTypesToUse, EDGE, EntryChat = ns.ChatLine, ns.ChatTypesToUse, ns.EDGE, ns.EntryChat;
local FOOTER, GAP, IsOpen, KEYS_TOP, KEY_HEIGHT = ns.FOOTER, ns.GAP, ns.IsOpen, ns.KEYS_TOP, ns.KEY_HEIGHT;
local LETTERS, LINE_INSET, LINE_TOP, LastTell = ns.LETTERS, ns.LINE_INSET, ns.LINE_TOP, ns.LastTell;
local LettersPage, MAX_LINE, OverChat, Override = ns.LettersPage, ns.MAX_LINE, ns.OverChat, ns.Override;
local PointAt, ROW, RefreshNavigation, SHIFT = ns.PointAt, ns.ROW, ns.RefreshNavigation, ns.SHIFT;
local SPACE, SPECIAL_KEYS, SYMBOLS, SameChat = ns.SPACE, ns.SPECIAL_KEYS, ns.SYMBOLS, ns.SameChat;
local Utf8Length, chatChoices, keys, suggestions = ns.Utf8Length, ns.chatChoices, ns.keys, ns.suggestions;

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
	if S.suggesting and S.target and S.text ~= "" then
		-- Protected: a lookup that fails leaves no names, never a key press half done (and /gk names says why).
		local ok, results = pcall(C_AutoComplete.GetAutoCompleteResults, S.text, MAX_SUGGESTIONS + 1, S.cursor, true, unpack(S.target.autoCompleteParams));
		results = ok and type(results) == "table" and results or {};
		if not (#results == 1 and results[1].name == S.text) then -- the name already typed: nothing to pick
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
	if not OverChat() then
		return;
	end
	local label = ChatLabel(S.chat);
	for _, chatKey in ipairs(S.keyboard.ChatKeys) do
		if chatKey:GetText() ~= label then
			chatKey:SetText(label);
		end
	end
	-- A whisper to someone other than whoever whispered last (they're the reply, always offered).
	if S.chat.chatType == "WHISPER" and S.chat.tellTarget and S.chat.tellTarget ~= LastTell() then
		S.whisperedTo = { chatType = S.chat.chatType, target = S.chat.tellTarget };
	end
end

-- The chat box's own line, while the keyboard's is empty: one Blizzard put there (a link - shift-click with
-- the chat box open, or a window's "link in chat" opening it with one). The keyboard can't move it (writing
-- in the chat box would leave it the addon's doing), so it shows it, steers its chat, and hands it back for
-- the chat's own A to send. Typing starts the keyboard's own line instead.
local BOX_LINE_HINT = "|cff808080   in the chat box: Enter, then A sends it|r";

local function BoxLine()
	if OverChat() and S.text == "" then
		local boxText = S.target:GetText() or "";
		if boxText ~= "" then
			return boxText;
		end
	end
end

-- Over chat, the line's chat heads it - "Guild:", "To Bob:" - in the chat's colour, as Blizzard's chat box
-- heads its own.
-- A chat's colour, as Blizzard's chat shows it (a channel's by its number); nothing for one without.
local function ChatColor(to)
	local info = ChatTypeInfo and ChatTypeInfo[to.chatType == "CHANNEL" and ("CHANNEL" .. tostring(to.channelTarget)) or to.chatType];
	if info and info.r then
		return info.r, info.g, info.b;
	end
end

local function UpdateChatHeader()
	local header = S.keyboard.ChatHeader;
	local label = OverChat() and (ChatLabel(S.chat) .. ":") or nil;
	local r, g, b = 1, 0.82, 0;
	if label and ChatColor(S.chat) then
		r, g, b = ChatColor(S.chat);
	end
	header:SetText(label or "");
	header:SetTextColor(r, g, b);
	header:SetShown(label ~= nil);
	S.keyboard.Preview:ClearAllPoints();
	if label then
		S.keyboard.Preview:SetPoint("TOPLEFT", header, "TOPRIGHT", 6, 0);
	else
		S.keyboard.Preview:SetPoint("TOPLEFT", LINE_INSET, -LINE_TOP);
	end
	S.keyboard.Preview:SetPoint("TOPRIGHT", -LINE_INSET, -LINE_TOP);
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
	local before, after = Split(S.text, S.cursor);
	local lineBefore, lineAfter = before:match("[^\n]*$"), after:match("^[^\n]*");
	local column, length = Utf8Length(lineBefore), Utf8Length(lineBefore) + Utf8Length(lineAfter);
	local first = math.max(0, math.min(column - PREVIEW_LENGTH + 8, length - PREVIEW_LENGTH));
	local last = math.min(length, first + PREVIEW_LENGTH);
	local shown = (first > 0 and "..." or "") .. select(2, Split(lineBefore, first)) .. CARET
		.. select(1, Split(lineAfter, last - column)) .. (last < length and "..." or "");
	local _, lines = S.text:gsub("\n", "");
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
						button:SetText(S.shift and button.key:upper() or button.key);
					end
				end
			end
		end
	end
	for _, shiftKey in ipairs(S.keyboard.ShiftKeys) do
		shiftKey:LockHighlight();
		if not S.shift then
			shiftKey:UnlockHighlight();
		end
	end
	local enterLabel = S.target and not S.isChat and S.target:IsMultiLine() and "New line" or "Enter";
	for _, enterKey in ipairs(S.keyboard.EnterKeys) do
		enterKey:SetText(enterLabel);
	end
	if S.keyboard.HoldPrompt then
		S.keyboard.HoldPrompt.text:SetText(enterLabel);
	end
end

local function SetTyped(newText, newCursor)
	S.text = newText;
	S.cursor = newCursor or Utf8Length(S.text);
	if S.target and not S.isChat then
		S.target:SetText(S.text);
		S.text = S.target:GetText() or ""; -- the box may change it
		S.cursor = math.min(S.cursor, Utf8Length(S.text));
	end
	UpdatePreview();
end

-- The box may have changed under the keyboard (typed into on a real keyboard, the mail sent): carry on from
-- what's in it. Not chat: there the line is the keyboard's own.
local function Sync()
	if S.isChat then
		return;
	end
	local current = S.target and S.target:GetText() or "";
	if current ~= S.text then
		S.text = current;
		S.cursor = Utf8Length(S.text);
	end
end

-- The character before the cursor.
local function DeleteBack()
	if S.cursor > 0 then
		local before, after = Split(S.text, S.cursor);
		SetTyped(select(1, Split(before, S.cursor - 1)) .. after, S.cursor - 1);
	end
end

local function Insert(characters)
	local before, after = Split(S.text, S.cursor);
	local newText = before .. characters .. after;
	if S.isChat then
		if #(ChatLine(newText, S.chat) or newText) > MAX_LINE then
			return; -- (as long as one chat line can be)
		end
	elseif S.target and S.target:IsNumeric() and characters:find("%D") then
		return; -- a box of numbers: digits only (Y's space too)
	else
		local maxLetters = S.target and S.target:GetMaxLetters() or 0;
		if maxLetters > 0 and Utf8Length(newText) > maxLetters then
			return;
		end
	end
	SetTyped(newText, S.cursor + Utf8Length(characters));
end

local function ChooseSuggestion(button)
	if S.target and button.suggestion then
		local name = Ambiguate(button.suggestion, "none");
		SetTyped((S.target.command and (S.target.command .. " ") or "") .. name .. (S.target.addSpaceToAutoComplete and " " or ""));
	end
end

local function MoveCursor(step)
	if S.target then
		Sync();
		S.cursor = math.max(0, math.min(Utf8Length(S.text), S.cursor + step));
		UpdatePreview();
	end
end

-- The page's keys, the chat key only for chat; each row centred over the keys it shows.
local function Layout()
	local top = S.suggesting and 1 or 0;
	local nameWidth = (S.keyboard:GetWidth() - 2 * EDGE - (MAX_SUGGESTIONS - 1) * GAP) / MAX_SUGGESTIONS;
	for i, button in ipairs(suggestions) do
		button:SetSize(nameWidth, KEY_HEIGHT);
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", EDGE + (i - 1) * (nameWidth + GAP), -KEYS_TOP);
		button:SetShown(S.suggesting and button.suggestion ~= nil);
	end
	for name, rows in pairs(keys) do
		for r, row in ipairs(rows) do
			local width = 0;
			for _, button in ipairs(row) do
				button:SetShown(name == S.page and (button.key ~= CHAT or S.isChat));
				if button:IsShown() then
					width = width + button.width + (width > 0 and GAP or 0);
				end
			end
			local x = (S.keyboard:GetWidth() - width) / 2;
			for _, button in ipairs(row) do
				if button:IsShown() then
					button:ClearAllPoints();
					button:SetPoint("TOPLEFT", x, -KEYS_TOP - (r - 1 + top) * ROW);
					x = x + button.width + GAP;
				end
			end
		end
	end
	S.keyboard:SetHeight(KEYS_TOP + (#keys[S.page] + top) * ROW + FOOTER);
end

local function SetChat(entry)
	S.chat = EntryChat(entry);
	if (S.target:GetText() or "") ~= "" then
		-- The chat box's own line goes there too: its chat (attributes - what its send reads, and they come
		-- back clean) and its header (Blizzard's, which only redraws).
		S.target:SetAttribute("chatType", S.chat.chatType);
		S.target:SetAttribute("tellTarget", S.chat.tellTarget);
		S.target:SetAttribute("channelTarget", nil);
		S.target:UpdateHeader();
	end
	UpdatePreview();
end

-- The chat key opens a list of the chats over the keys - a dropdown of the keyboard's own buttons, the D-pad's
-- cursor on the line's chat (from anything else, a channel say: on Say): up / down, A takes one (held too),
-- B goes back. Not a Blizzard menu: one an addon opens runs the controller UI's menu callbacks as the addon's
-- doing (see the layout option).
local CHOICE_HEIGHT, CHOICE_STEP, LIST_PAD = 26, 28, 6;

-- A chat's name in its colour (in the text: a button's own colour changes with its highlight).
local function ChatChoiceText(to)
	local r, g, b = ChatColor(to);
	if not r then
		return ChatLabel(to);
	end
	local function Hex(value)
		return math.floor(value * 255 + 0.5);
	end
	return ("|cff%02x%02x%02x%s|r"):format(Hex(r), Hex(g), Hex(b), ChatLabel(to));
end

local function VisibleChatKey()
	for _, chatKey in ipairs(S.keyboard.ChatKeys) do
		if chatKey:IsVisible() then
			return chatKey;
		end
	end
end

local function HideChatList()
	S.picking = false;
	S.keyboard.ChatList:Hide();
	for _, choice in ipairs(chatChoices) do
		choice:Hide();
	end
end

-- Back to the keys, the cursor on the chat key.
local function CloseChatList()
	if S.picking then
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
	frame:SetSize(chatKey.width + 2 * LIST_PAD, #list * CHOICE_STEP - (CHOICE_STEP - CHOICE_HEIGHT) + 2 * LIST_PAD);
	frame:ClearAllPoints();
	frame:SetPoint("BOTTOMLEFT", chatKey, "TOPLEFT", -LIST_PAD, GAP); -- up from the key (kept on the screen)
	local current;
	for i, choice in ipairs(chatChoices) do
		local entry = list[i];
		choice.entry = entry;
		choice:SetShown(entry ~= nil);
		if entry then
			choice:SetFrameLevel(frame:GetFrameLevel() + 1);
			choice:SetSize(chatKey.width, CHOICE_HEIGHT);
			choice:ClearAllPoints();
			choice:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_PAD, -LIST_PAD - (i - 1) * CHOICE_STEP);
			choice:SetText(ChatChoiceText(EntryChat(entry)));
			current = current or (SameChat(entry) and choice);
		end
	end
	frame:Show();
	S.picking = true;
	RefreshNavigation();
	PointAt(current or chatChoices[1]);
	if CanSteer() and SmartNavigation_AddJumpNavigationOverride and SMART_NAV_INPUT_DIRECTION then
		Override(chatKey, "UP", current or chatChoices[1]); -- (the cursor left on the key: up into the list; back as it was after)
	end
end

local function PickChat(choice)
	if S.picking and choice.entry and OverChat() then
		SetChat(choice.entry);
	end
	CloseChatList();
end

local function Close()
	if IsOpen() then
		S.keyboard:Hide();
	end
end

-- A chat line closed unsent (B, combat, a real keyboard taking over, another box) waits for the next time the
-- keyboard opens on chat, in its chat; an empty one leaves nothing.
local function KeepChatDraft()
	if S.text == "" or not S.target then
		S.chatDraft = nil;
		return;
	end
	-- (and the chat box's own chat as the keyboard last took it in, and as it goes back to when it closes: its
	-- sticky type)
	S.chatDraft = { text = S.text, chat = S.chat, boxChats = {
		[S.seenChat] = true,
		[ChatKey({ chatType = S.target:GetAttribute("stickyType"), tellTarget = S.target:GetAttribute("tellTarget") })] = true,
	} };
end

local function Press(button)
	if InCombatLockdown() then
		return; -- (closed in combat: a click that gets here anyway changes nothing - its keys can't move then)
	end
	local key = button.key;
	if S.picking then
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
		S.shift = not S.shift;
		UpdateLabels();
	elseif key == SYMBOLS or key == LETTERS then
		S.page = key == SYMBOLS and "symbols" or LettersPage();
		Layout();
		RefreshNavigation();
	elseif key == CHAT then
		if OverChat() then
			OpenChatList(button);
		end
	else
		Insert(S.shift and key:upper() or key);
		if S.shift then
			S.shift = false;
			UpdateLabels();
		end
	end
end

ns.ChooseSuggestion, ns.Close, ns.CloseChatList = ChooseSuggestion, Close, CloseChatList;
ns.HideChatList, ns.Insert, ns.KeepChatDraft, ns.Layout = HideChatList, Insert, KeepChatDraft, Layout;
ns.LooksUpNames, ns.MAX_SUGGESTIONS, ns.MoveCursor = LooksUpNames, MAX_SUGGESTIONS, MoveCursor;
ns.PickChat, ns.Press, ns.Sync, ns.UpdateChatKey = PickChat, Press, Sync, UpdateChatKey;
ns.UpdateLabels, ns.UpdatePreview = UpdateLabels, UpdatePreview;
