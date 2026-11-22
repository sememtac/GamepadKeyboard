-- Edit Mode: the keyboard shows where it opens, to be dragged and resized there.

local ADDON_NAME, ns = ...;
local S = ns.S;
local Close, CreateKeyboard, LettersPage, Position = ns.Close, ns.CreateKeyboard, ns.LettersPage, ns.Position;
local Resize, SavePosition = ns.Resize, ns.SavePosition;

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
	S.previewing = true;
	S.target, S.isChat, S.suggesting = nil, false, false;
	S.text, S.cursor, S.page, S.shift = "", 0, LettersPage(), false;
	S.keyboard:SetFrameStrata(EDIT_MODE_STRATA);
	Position(nil);
	S.keyboard:Show();
	S.keyboard.EditModeOverlay:Show();
end

-- The preview goes - not in combat: the keyboard holds secure buttons, so only Blizzard's UI may hide it
-- then (finished as combat ends).
local function EndPreview()
	if not S.previewing or InCombatLockdown() then
		return;
	end
	S.previewing = false;
	S.keyboard.EditModeOverlay:Hide();
	S.keyboard:Hide();
	S.keyboard:SetFrameStrata("FULLSCREEN_DIALOG");
end

-- Combat over: Edit Mode left in it (the preview ends), or still open (the preview back).
local function EditModeAfterCombat()
	if not inEditMode then
		EndPreview();
	elseif not S.previewing then
		EditModeEnter();
	end
end

local function EditModeExit()
	inEditMode = false;
	EndPreview();
end

if EventRegistry then
	EventRegistry:RegisterCallback("EditMode.Enter", EditModeEnter, ADDON_NAME);
	EventRegistry:RegisterCallback("EditMode.Exit", EditModeExit, ADDON_NAME);
end

ns.EditModeAfterCombat, ns.EndPreview = EditModeAfterCombat, EndPreview;
