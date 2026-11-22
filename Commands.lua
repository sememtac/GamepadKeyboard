-- /gk.

local ADDON_NAME, ns = ...;
local S = ns.S;
local DB, DEFAULTS, LooksUpNames, MAX_SUGGESTIONS = ns.DB, ns.DEFAULTS, ns.LooksUpNames, ns.MAX_SUGGESTIONS;
local Print, SetOption, Setting, Utf8Length = ns.Print, ns.SetOption, ns.Setting, ns.Utf8Length;

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
		if S.lastNamesBox then
			DescribeNames(S.lastNamesBox);
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
