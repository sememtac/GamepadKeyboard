-- Watching for text boxes: when the keyboard opens and for which box, following it to another, the focus
-- hooks, the per-frame watcher, combat and the game's block reports.

local ADDON_NAME, ns = ...;
local S = ns.S;
local CanType, ChatFor, ChatKey, ChatOf = ns.CanType, ns.ChatFor, ns.ChatKey, ns.ChatOf;
local ClearShortcuts, Close, CreateKeyboard = ns.ClearShortcuts, ns.Close, ns.CreateKeyboard;
local EditModeAfterCombat, EndPreview, GetManager = ns.EditModeAfterCombat, ns.EndPreview, ns.GetManager;
local HideChatList, Insert, IsOpen, IsWhisper = ns.HideChatList, ns.Insert, ns.IsOpen, ns.IsWhisper;
local KeepChatDraft, Layout, LettersPage = ns.KeepChatDraft, ns.Layout, ns.LettersPage;
local LooksUpNames, OverChat, Position, Print = ns.LooksUpNames, ns.OverChat, ns.Position, ns.Print;
local RebindShortcuts, RefreshNavigation = ns.RebindShortcuts, ns.RefreshNavigation;
local RegisterOptions, Reviewed, Sayable, Setting = ns.RegisterOptions, ns.Reviewed, ns.Sayable, ns.Setting;
local Sync, TellCantType, Unregister = ns.Sync, ns.TellCantType, ns.Unregister;
local UpdateChatKey, UpdateHoldHint, UpdateLabels = ns.UpdateChatKey, ns.UpdateHoldHint, ns.UpdateLabels;
local UpdatePreview, UpdateShortcuts, UsesGamepadUI = ns.UpdatePreview, ns.UpdateShortcuts, ns.UsesGamepadUI;
local Utf8Length = ns.Utf8Length;

local seenBoxText; -- the chat box's own text last frame (a line Blizzard put there: the preview follows)
local lastBoxName; -- the last box typed into (for a report if the game blocks the addon)
local lastInput = "gamepad"; -- what the player pressed last: "gamepad", "keyboard" or "mouse"
local chatHadFocus; -- while open over chat: whether the chat box had typing focus last frame

local function SetTarget(box)
	S.target = box;
	local parent = box:GetParent();
	local reviewed = not box:GetName() and Reviewed(box); -- (one of Blizzard's without a name: where it is)
	lastBoxName = reviewed and table.concat(reviewed.box, ".")
		or (box:GetName() or "an unnamed text box") .. " in " .. tostring(parent and parent:GetName() or "an unnamed frame");
	chatHadFocus = nil; -- a new box: no focus seen yet
	S.whisperedTo = nil; -- (the box's own, if it's in one, at the next preview)
	HideChatList();
	S.isChat = box.chatFrame ~= nil;
	S.suggesting = Setting("names") and LooksUpNames(box);
	if S.isChat then
		-- The chat box empties and goes back to its usual chat as the controller moves to the keyboard; the
		-- line and its chat stay here.
		S.chat = ChatFor(box);
		S.text = S.chatDraft and S.chatDraft.text or "";
		S.chatDraft = nil;
		local boxChat = ChatOf(box);
		S.seenChat = ChatKey(boxChat);
	else
		S.lastNamesBox = box;
		S.text = box:GetText() or "";
	end
	S.cursor = Utf8Length(S.text);
	S.page = box:IsNumeric() and "numbers" or LettersPage();
	S.shift = S.isChat and S.text == "" and Setting("chatCapital");
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

local function ShouldOpen(box)
	if not (not box:IsForbidden() -- (first: a forbidden box answers nothing else)
		and Setting("autoOpen")
		and ControllerAsked()
		and not InCombatLockdown()
		and UsesGamepadUI()
		and GetManager() ~= nil
		and not IsOpen()
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
	if S.isChat then
		KeepChatDraft(); -- (the chat line waits)
	end
	SetTarget(box);
	Layout();
	UpdateLabels();
	UpdatePreview();
	RefreshNavigation();
end

-- Asked for again on a box that already has focus (A on a name box again, Chat chosen again on the menu
-- dial): no focus change to watch, so these are hooked. Not while closing, which focuses the box itself.
local function Requested(box)
	if S.closing or not box or box:IsForbidden() or not box:HasFocus() then
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
		if IsOpen() and OverChat() and type(link) == "string" and link ~= ""
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

-- One check per frame: what the player is pressing, the chat box taken back, and the keyboard opens when
-- typing focus moves to a text box.
local lastFocus;
local function CloseIfBoxGone()
	-- Its box gone (the window closed, Enter hid it; for chat its window - the chat box itself can hide as it
	-- empties): the keyboard goes too.
	if IsOpen() and S.target and not (S.isChat and S.target.chatFrame or S.target):IsVisible() then
		Close();
	end
end

local function FollowChatBoxChat()
	if IsOpen() and OverChat() then
		-- A whisper started elsewhere while the keyboard is up (a name's menu, the reply key): the line goes
		-- there. Other changes are the chat box's own (emptied as it lost focus: back to its usual chat).
		local boxChat = ChatOf(S.target);
		local seen = ChatKey(boxChat);
		if seen ~= S.seenChat then
			if IsWhisper(boxChat.chatType) and boxChat.tellTarget and not Sayable(boxChat) then
				local box = S.target;
				Close(); -- (the line waits, in its own chat: this one is new to it)
				TellCantType(box);
			else
				S.seenChat = seen;
				if IsWhisper(boxChat.chatType) and boxChat.tellTarget then
					S.chat = boxChat;
					UpdatePreview();
				end
			end
		end
	end
end

local function FollowChatBox()
	if IsOpen() and OverChat() then
		UpdateChatKey();
		local boxText = S.target:GetText() or "";
		if boxText ~= seenBoxText then
			seenBoxText = boxText;
			UpdatePreview(); -- (a link put in the chat box's own line)
		end
		-- The chat box has no typing focus while the controller is on the keyboard. Getting it back from a real
		-- keyboard (Enter, /) or the mouse: this keyboard steps aside, its line waits. From the controller (LT
		-- to the chat window): it stays.
		local hasFocus = S.target:HasFocus();
		if chatHadFocus == false and hasFocus and not ControllerAsked() then
			Close();
		end
		chatHadFocus = hasFocus;
	end
end

local function FollowBoxText()
	-- Its box changed under it (the mail sent and its boxes cleared, a box's Enter, a link put in): the
	-- preview, cursor and name keys follow at once, not at the next key.
	if IsOpen() and S.target then
		local before = S.text;
		Sync();
		if S.text ~= before then
			UpdatePreview();
		end
	end
end

-- Typing focus moved: the keyboard follows it to another box, or opens for one asked for.
local function FollowFocus()
	local focus = GetCurrentKeyBoardFocus();
	if focus == lastFocus then
		return;
	end
	lastFocus = focus;
	if IsOpen() then
		if focus and focus ~= S.target then
			SwitchTo(focus);
		end
		return;
	end
	if focus ~= S.handedBack then
		S.handedBack = nil;
		if focus and ShouldOpen(focus) then
			Open(focus);
		end
	end
end

local watcher = CreateFrame("Frame");
watcher:SetScript("OnUpdate", function()
	if lastInput ~= "gamepad" and PadButtonDown() then
		lastInput = "gamepad";
	end
	UpdateShortcuts();
	UpdateHoldHint();
	if S.previewing then
		lastFocus = GetCurrentKeyBoardFocus(); -- in Edit Mode: not typing anywhere, and nothing to open after it
		return;
	end
	CloseIfBoxGone();
	FollowChatBoxChat();
	FollowChatBox();
	FollowBoxText();
	FollowFocus();
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
			Unregister(); -- (if registered still) a hide Blizzard refused as combat started
		else
			RebindShortcuts(); -- (still up: the controller UI may have bound its buttons over them in combat)
		end
		EditModeAfterCombat();
	end
end);
