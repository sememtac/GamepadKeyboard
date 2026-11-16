# Gamepad Keyboard

An on-screen keyboard for typing with a controller in WoW: Forever (Interface 16001). Local addon.

When a text box gets typing focus in the game's controller UI - the chat, a name box, a search box - the
keyboard opens on top of the window the box belongs to. It joins Blizzard's gamepad UI like the game's own
panels: the D-pad moves between keys (left / right along a row, up / down between rows), A types,
**Enter** does what the Enter key does, B goes back without it, LT / RT switch windows. Each key types
straight into the text box.

## Chat

Type the message and press **Enter**: it's sent and the chat closes, as with the Enter key. Whispers and
replies keep their target, `/p` and the other prefixes switch the chat as when typing, numbered channels
work, and a line starting with `/` runs as a command (`/dance`, `/cast`, `/target`). The chat type you
sent in sticks for the next line, as it does with Enter. Enter with nothing typed just closes the chat.
A chat line starts with Shift on.

**B** goes back to the chat box with the text instead, unsent; the chat's own **A Send** sends it from
there. Enter does that too, with a note in the chat, for the few lines it can't send itself: Battle.net
whispers, chat types with no slash prefix, channels picked by name
rather than number, and lines too long to fit with their prefix.

## Good to know

- **Not in combat**: Blizzard's gamepad UI takes no addon windows in combat, so the keyboard doesn't open
  then; a real keyboard types as always. If combat starts while it's open, it closes and the text stays.
- **Where it opens**: beside the chat window for chat, near the text box otherwise. Drag it with the mouse
  and it opens there from then on; `/gk reset` puts it back.
- **Bringing it back** after going back to a text box: A on the box again, or Chat on the menu dial again.
- `/gk off` stops it opening by itself; `/gk on` turns it back on.
- No `|` key: the game reads it as the start of an escape code.

## How it works

`GetCurrentKeyBoardFocus()` is checked once per frame, and `SetFocus` on any text box and the chat
frames' `SetGamepadFocus` are post-hooked (`hooksecurefunc`) for a box that is asked for again while it
already has focus; the refocus that closing the keyboard causes is ignored. The keyboard is a popup in Blizzard's gamepad UI
(`HandlePopupShown` / `HandlePopupHide`, the functions it wraps for addons), so closing it returns the
controller to the window the box belongs to. For a chat box, a single space is put in before the keyboard
takes the controller: that keeps Blizzard from closing the empty box and resetting its chat type (a whisper
target, say). The D-pad rows are SmartNavigation jump overrides.

Enter never calls the chat's send code: addon code there would leave chat state that secure slash commands
read later. The Enter key is a `SecureActionButtonTemplate` button with `type = "macro"`. Its PreClick turns
the box's text and chat type into the line Enter would send (`/w Bob ...`, `/p ...`, `/2 ...`, or a typed
command as is), and Blizzard's secure macro action runs it when A is released. Macro lines go through
Blizzard's own macro chat box (`MacroExecutionManager`), so they're parsed like typed lines. PostClick then
does what Enter does after sending: the chat type sticks (for sticky types), the box is cleared, and the
chat closes. In any other text box, Enter runs that box's own `OnEnterPressed`. Because the Enter key is
secure, the keyboard is a protected frame; it only opens out of combat and closes when combat starts.

## Tests

`luajit tests/keyboard_test.lua` (or `nvim -l`) from the repo root: 61 checks, with the focus manager and
the chat box following Blizzard's code, every chat send function poisoned, and the Enter key clicked the
way Blizzard's secure action button runs a click. Only the game can confirm:

- [ ] Chat (from the menu dial's Chat, or the chat binding): the keyboard opens; A on a key types into the
      chat box.
- [ ] Enter: the message is sent and the chat closes; with nothing typed, the chat just closes.
- [ ] A whisper reply sent with Enter reaches the right player; `/p hello` goes to party and party is
      still the chat type next time; `/2 hello` goes to channel 2; `/dance` dances; `/cast` a spell
      casts it.
- [ ] B: back on the chat box with the text and "A Send" showing; A sends it.
- [ ] LT / RT move between the keyboard and other open windows.
- [ ] The keyboard can be dragged and reopens where it was left; for chat it doesn't cover the chat window.
- [ ] After B, Chat on the menu dial (or A on a name box) brings the keyboard back.
- [ ] Gesture Commands' Name & icon: A on the name box opens the keyboard; Enter or B returns to the
      picker with the name kept.
- [ ] Combat starting while typing: the keyboard closes without an "Interface action failed" or "blocked"
      message, and the text is still in the chat box.
