-- Options: the addon's own page in Blizzard's Settings panel (Options > AddOns).

local ADDON_NAME, ns = ...;
local S = ns.S;
local DB, DEFAULTS, IsOpen, Layout, LettersPage = ns.DB, ns.DEFAULTS, ns.IsOpen, ns.Layout, ns.LettersPage;
local Position, RefreshNavigation, Setting = ns.Position, ns.RefreshNavigation, ns.Setting;
local UpdateLabels = ns.UpdateLabels;

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
	if IsOpen() and S.page ~= "symbols" and S.page ~= "numbers" and not InCombatLockdown() then
		S.page = LettersPage();
		Layout();
		UpdateLabels();
		RefreshNavigation();
	end
end

-- A change of size shows at once if the keyboard is up.
local function ApplySize()
	if IsOpen() and not InCombatLockdown() then
		Position(S.target);
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

ns.RegisterOptions, ns.Resize, ns.SetOption = RegisterOptions, Resize, SetOption;
