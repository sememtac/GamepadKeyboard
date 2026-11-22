-- The secure buttons - the Enter keys and A - and what they do around Blizzard's secure action; the hold
-- of A; the controller's buttons bound to the keyboard's while it has the controller. Every
-- SecureActionButtonTemplate frame is made here.

local ADDON_NAME, ns = ...;
local S = ns.S;
local BACK, ChatLabel, ChatLine, Close = ns.BACK, ns.ChatLabel, ns.ChatLine, ns.Close;
local CloseChatList, ENTER, EnterButton = ns.CloseChatList, ns.ENTER, ns.EnterButton;
local GetManager, Insert, IsOpen, KEY_HEIGHT = ns.GetManager, ns.Insert, ns.IsOpen, ns.KEY_HEIGHT;
local KeyUnits, KeyWidth, MAX_LINE, Press, Print = ns.KeyUnits, ns.KeyWidth, ns.MAX_LINE, ns.Press, ns.Print;
local Reviewed, SPACE, SPECIAL_KEYS, Setting = ns.Reviewed, ns.SPACE, ns.SPECIAL_KEYS, ns.Setting;
local Sync, UpdateLabels, UpdatePreview = ns.Sync, ns.UpdateLabels, ns.UpdatePreview;

local toldBoxLine = false; -- said once: a line in the chat box is sent from there

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
	if S.target and S.isChat and S.text ~= "" then
		line = ChatLine(S.text, S.chat);
		if line and #line > MAX_LINE then
			line = nil; -- (the chat key moved it to a longer whisper)
		end
	end
	SetPressAction(button, line, S.target and EnterButton(S.target));
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
	local box, overChat = S.target, S.isChat;
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
		if sentLine == "" and S.text == "" and (box:GetText() or "") ~= "" then
			Close(); -- back on the chat box, its line still in it, in the chat the chat key picked
			if not toldBoxLine then
				toldBoxLine = true;
				Print("the line is in the chat box: A sends it.");
			end
			return;
		end
		if sentLine == "" and S.text ~= "" then
			Print(("too long to send to %s - a chat line is at most %d letters with its command."):format(ChatLabel(S.chat), MAX_LINE));
			return;
		end
		local sent = sentLine ~= "" and S.text:sub(1, 1) ~= "/";
		if sent and ChatTypeInfo and ChatTypeInfo[S.chat.chatType] and ChatTypeInfo[S.chat.chatType].sticky == 1 then
			-- As Blizzard's own send leaves the box: the chat it goes back to, and who or which channel that is
			-- (going back, it takes only the type - a whisper with someone else's name, or none, otherwise).
			box:SetAttribute("stickyType", S.chat.chatType);
			if S.chat.chatType == "WHISPER" then
				box:SetAttribute("tellTarget", S.chat.tellTarget);
			elseif S.chat.chatType == "CHANNEL" then
				box:SetAttribute("channelTarget", S.chat.channelTarget);
			end
		end
		S.text, S.cursor = "", 0; -- sent: no line to keep
		if not Setting("closeOnEnter") then
			-- Staying open: the next line, in the same chat.
			S.shift = Setting("chatCapital");
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
		if not S.picking then
			HoldRing(true);
		end
		return;
	end
	HoldRing(false);
	local current = SmartNavigation and SmartNavigation.GetCurrentButton and SmartNavigation:GetCurrentButton();
	local held = not S.picking and aDownAt and GetTime() - aDownAt >= HoldTime(); -- (in the chat list: a pick)
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
	local units = KeyUnits(key, pageUnits);
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
	button.width = KeyWidth(units);
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

-- A hold of A ended without its release reaching the keyboard (closed under it, the controller gone).
local function ResetHold()
	aDownAt = nil;
	HoldRing(false);
end

local function ClearShortcuts()
	if shortcutsBound and not InCombatLockdown() then
		ClearOverrideBindings(S.keyboard);
		shortcutsBound = false;
		ResetHold(); -- (A held as the controller left: its release goes to the controller UI now)
	end
end

-- Bound again (if they are): after combat, the controller UI may have bound its buttons over them.
local function RebindShortcuts()
	if shortcutsBound then
		BindShortcuts();
	end
end

local function UpdateShortcuts()
	if InCombatLockdown() then
		return;
	end
	local manager = GetManager();
	if IsOpen() and manager and manager.focusedFrame == S.keyboard then
		if not shortcutsBound then
			BindShortcuts();
		end
	else
		ClearShortcuts();
	end
end

-- Held long enough: the Enter keys light up (letting go sends).
local function UpdateHoldHint()
	local lit = not S.picking and aDownAt ~= nil and GetTime() - aDownAt >= HoldTime();
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

local function CreateAButton()
	-- A presses this one (hidden, secure: Enter's macro line runs from it).
	local aButton = CreateFrame("Button", "GamepadKeyboardAButton", S.keyboard, "SecureActionButtonTemplate");
	aButton:RegisterForClicks("AnyDown", "AnyUp");
	aButton:SetAttribute("type", "macro");
	aButton:SetAttribute("useOnKeyDown", false);
	aButton:SetAttribute("macrotext", "");
	aButton:SetScript("PreClick", APreClick);
	aButton:SetScript("PostClick", APostClick);
	aButton:Hide();
end

ns.ClearShortcuts, ns.CreateAButton, ns.CreateKey = ClearShortcuts, CreateAButton, CreateKey;
ns.RebindShortcuts, ns.ResetHold, ns.UpdateHoldHint = RebindShortcuts, ResetHold, UpdateHoldHint;
ns.UpdateShortcuts = UpdateShortcuts;
