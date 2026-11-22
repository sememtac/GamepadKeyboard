-- Blizzard's gamepad UI: the keyboard as a popup over the window its text box belongs to - registering
-- with the focus manager, the D-pad's rows (jump overrides), the cursor.

local ADDON_NAME, ns = ...;
local S = ns.S;
local UsesGamepadUI, chatChoices, keys = ns.UsesGamepadUI, ns.chatChoices, ns.keys;
local suggestions = ns.suggestions;

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
	S.closing = true;
	local ok = pcall(manager.HandlePopupHide, manager, S.keyboard);
	S.closing = false;
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
	local rows = keys[S.page];
	if S.picking then
		rows = {}; -- the chat list, one under another (and nowhere else: the keys under it aren't reached)
		for _, choice in ipairs(chatChoices) do
			if choice:IsShown() then
				rows[#rows + 1] = { choice };
			end
		end
	elseif S.suggesting then
		rows = { suggestions, unpack(keys[S.page]) };
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

ns.CanSteer, ns.GetManager, ns.Override, ns.PointAt = CanSteer, GetManager, Override, PointAt;
ns.RefreshNavigation, ns.Register = RefreshNavigation, Register;
ns.SetUpFocusVisuals, ns.Unregister = SetUpFocusVisuals, Unregister;
