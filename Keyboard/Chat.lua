-- Chats: which there are, their names and colours, the line a macro sends for one, and the chat the keyboard
-- opens in over a chat box.

local ADDON_NAME, ns = ...;
local S = ns.S;
local Utf8Length = ns.Utf8Length;

-- The chats the chat key's list offers. Reply: a whisper to whoever whispered last (Blizzard's own getter,
-- which only reads).
local function LastTell()
	if ChatFrameUtil and ChatFrameUtil.GetLastTellTarget then
		return ChatFrameUtil.GetLastTellTarget();
	end
end

-- Every chat, in a group or a guild or not - one you aren't in gets the game's own "you aren't in a party";
-- then the whispers (see ChatTypesToUse).
local CHAT_TYPES = {
	{ chatType = "SAY" }, { chatType = "PARTY" }, { chatType = "RAID" }, { chatType = "INSTANCE_CHAT" },
	{ chatType = "GUILD" }, { chatType = "OFFICER" }, { chatType = "YELL" },
};
local CHAT_LABELS = {
	SAY = "Say", PARTY = "Party", RAID = "Raid", INSTANCE_CHAT = "Instance", GUILD = "Guild", OFFICER = "Officer",
	YELL = "Yell", EMOTE = "Emote", RAID_WARNING = "Warning",
};

local function IsWhisper(chatType)
	return chatType == "WHISPER" or chatType == "BN_WHISPER";
end

-- A chat's name: "Guild", "To Bob", "/2".
local function ChatLabel(to)
	local chatType = to.chatType;
	if IsWhisper(chatType) then
		local name = tostring(to.tellTarget or ""):gsub("%-.*$", "");
		if Utf8Length(name) > 9 then
			name = name:sub(1, 8) .. "..";
		end
		return "To " .. name;
	elseif chatType == "CHANNEL" then
		return "/" .. tostring(to.channelTarget or "?");
	end
	return CHAT_LABELS[chatType] or "Chat";
end

-- A chat box's chat type as it is (its attributes: reading them is all the keyboard does to the box).
local function ChatOf(box)
	return { chatType = box:GetAttribute("chatType"), tellTarget = box:GetAttribute("tellTarget"),
		channelTarget = box:GetAttribute("channelTarget") };
end

-- A chat told from another by its type and who it's to (a change in the box: a whisper started there).
local function ChatKey(to)
	return tostring(to.chatType) .. " " .. tostring(to.tellTarget);
end

-- The macro line that says a message in a chat (a command - "/dance" - runs as typed); nil if no slash
-- command can say it. Not Battle.net whispers: their name can be a protected string, which a macro line
-- can't be trusted to keep - and Blizzard sends them only from its own chat box.
local CHAT_COMMANDS = {
	SAY = "/s", YELL = "/y", EMOTE = "/e", PARTY = "/p", RAID = "/ra", RAID_WARNING = "/rw",
	INSTANCE_CHAT = "/i", GUILD = "/g", OFFICER = "/o",
};
local MAX_LINE = 255;

local function ChatLine(message, to)
	if message:sub(1, 1) == "/" then
		return message;
	elseif to.chatType == "WHISPER" then
		return to.tellTarget and ("/w " .. to.tellTarget .. " " .. message);
	elseif to.chatType == "CHANNEL" then
		local channel = tonumber(to.channelTarget);
		return channel and ("/" .. channel .. " " .. message);
	elseif CHAT_COMMANDS[to.chatType] then
		return CHAT_COMMANDS[to.chatType] .. " " .. message;
	end
end

local function Sayable(to)
	return ChatLine("x", to) ~= nil;
end

-- The chat the keyboard opens in over a chat box: an unsent line's own, unless a whisper was started in the
-- box since the line was left (a name's menu, the reply key) - not the box still in, or sticking to, the
-- whisper it had then - else the box's.
local function ChatFor(box)
	local boxChat = ChatOf(box);
	if S.chatDraft and not (IsWhisper(boxChat.chatType) and not S.chatDraft.boxChats[ChatKey(boxChat)]) then
		return S.chatDraft.chat;
	end
	return boxChat;
end

-- The chat types there are to use, then the whispers: the one this chat was in (opened from a name, say)
-- and a reply to whoever whispered last (not a Battle.net one: see ChatLine), once each.
local function ChatTypesToUse()
	local list = {};
	for _, entry in ipairs(CHAT_TYPES) do
		list[#list + 1] = entry;
	end
	local lastTell, lastTellType = LastTell();
	if S.whisperedTo and S.whisperedTo.target ~= lastTell then
		list[#list + 1] = S.whisperedTo;
	end
	if lastTell and (lastTellType or "WHISPER") == "WHISPER" then
		list[#list + 1] = { chatType = "WHISPER", target = lastTell };
	end
	return list;
end

-- One of those as a chat (a whisper's target is who it's to).
local function EntryChat(entry)
	return { chatType = entry.chatType, tellTarget = entry.target };
end

-- Whether it's the line's own chat (a whisper: by who it's to).
local function SameChat(entry)
	if entry.target then
		return S.chat.chatType == "WHISPER" and entry.target == S.chat.tellTarget;
	end
	return entry.chatType == S.chat.chatType;
end

ns.CHAT_TYPES, ns.ChatFor, ns.ChatKey, ns.ChatLabel = CHAT_TYPES, ChatFor, ChatKey, ChatLabel;
ns.ChatLine, ns.ChatOf, ns.ChatTypesToUse, ns.EntryChat = ChatLine, ChatOf, ChatTypesToUse, EntryChat;
ns.IsWhisper, ns.LastTell, ns.MAX_LINE, ns.SameChat = IsWhisper, LastTell, MAX_LINE, SameChat;
ns.Sayable = Sayable;
