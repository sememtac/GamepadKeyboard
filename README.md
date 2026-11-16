# Gamepad Keyboard

An on-screen keyboard for typing with a controller in WoW: Forever (Interface 16001). Local addon.

When a text box gets typing focus in the game's controller UI - the chat, a name box, a search box - the
keyboard opens on top of the window the box belongs to. It joins Blizzard's gamepad UI like the game's own
panels: the D-pad moves between keys (left / right along a row, up / down between rows), A types, B or
Done goes back, LT / RT switch windows. Each key types straight into the text box.

## Chat

The keyboard doesn't send. Type the message, press B (or Done), and you're back on the chat box with the
text; the chat's own **A Send** sends it. That's Blizzard's send, so whispers and replies, channels, `/p`
style prefixes and emotes work as they do when typing on a keyboard. A chat line starts with Shift on.

## Good to know

- **Not in combat**: Blizzard's gamepad UI takes no addon windows in combat, so the keyboard doesn't open
  then; a real keyboard types as always. If combat starts while it's open, it closes and the text stays.
- **Slash commands that cast spells** (`/cast` and the like) only work typed on a real keyboard.
- `/gk off` stops it opening by itself; `/gk on` turns it back on.
- No `|` key: the game reads it as the start of an escape code.

## How it works

`GetCurrentKeyBoardFocus()` is checked once per frame. The keyboard is a popup in Blizzard's gamepad UI
(`HandlePopupShown` / `HandlePopupHide`, the functions it wraps for addons), so closing it returns the
controller to the window the box belongs to. For a chat box, a single space is put in before the keyboard
takes the controller: that keeps Blizzard from closing the empty box and resetting its chat type (a whisper
target, say). The D-pad rows are SmartNavigation jump overrides. Nothing of the addon runs in the chat's
send path.

## Tests

`luajit tests/keyboard_test.lua` (or `nvim -l`) from the repo root: 41 checks, with the focus manager and
the chat box following Blizzard's code and every chat send function poisoned. Only the game can confirm:

- [ ] Chat (from the menu dial's Chat, or the chat binding): the keyboard opens; A on a key types into the
      chat box.
- [ ] B or Done: back on the chat box with "A Send" showing; A sends the message.
- [ ] A whisper reply keeps its target; `/p hello` goes to party; `/dance` dances.
- [ ] LT / RT move between the keyboard and other open windows.
- [ ] Gesture Commands' Name & icon: A on the name box opens the keyboard; Done returns to the picker.
- [ ] Combat starting while typing: the keyboard closes without an "Interface action failed" or "blocked"
      message, and the text is still in the chat box.
