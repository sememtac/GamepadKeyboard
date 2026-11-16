# Gamepad Keyboard

An on-screen keyboard for typing with a controller in WoW: Forever (Interface 16001). Local addon.

When you go to a text box with the controller - A on a name box or a search box, Chat on the menu dial -
the keyboard opens on top of the window the box belongs to. It joins Blizzard's gamepad UI like the game's own
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

## Controller or real keyboard

Whichever you're using has the text box:

- The keyboard opens only when the **controller** asked for the text box. Enter on a real keyboard opens
  the chat for that keyboard, and a mouse click that puts focus in some box (a ctrl-click that shows a link
  to copy, say) doesn't bring it up either. Chat on the menu dial brings it up whenever you want it.
- While it's open, **typing on a real keyboard takes over**: the letter goes into the text box, the
  on-screen keyboard steps aside, and you carry on typing on the real one. Backspace deletes. Enter on the
  real keyboard is the on-screen Enter (sends, closes the chat). Keys that don't type (F1, Tab, arrows),
  Shift / Ctrl / Alt and the controller's buttons work as usual and leave it open; Escape closes it.

## Good to know

- **Not in combat**: Blizzard's gamepad UI takes no addon windows in combat, so the keyboard doesn't open
  then; a real keyboard types as always. If combat starts while it's open, it closes and the text stays.
- **Where it opens**: beside the chat window for chat, near the text box otherwise. Drag it with the mouse
  and it opens there from then on; `/gk reset` puts it back.
- **Bringing it back** after going back to a text box (or after the real keyboard took over): A on the box
  again, or Chat on the menu dial again.
- `/gk off` stops it opening by itself; `/gk on` turns it back on.
- No `|` key: the game reads it as the start of an escape code.

## How it works

`GetCurrentKeyBoardFocus()` is checked once per frame, and `SetFocus` on any text box and the chat
frames' `SetGamepadFocus` are post-hooked (`hooksecurefunc`) for a box that is asked for again while it
already has focus; the refocus that closing the keyboard causes is ignored. It opens only if the controller
asked: one of its buttons is down (`IsKeyDown("PAD1")` and the rest, as Blizzard's class-action flyout
checks them) or was what the player pressed last. A frame that hears every key and passes it on
(`SetPropagateKeyboardInput(true)`), and `GLOBAL_MOUSE_DOWN`, note a real keyboard or the mouse in between;
Shift and Ctrl don't count, since Forever's controller modifiers are those too.

While it's open the keyboard listens for keys itself. A typing key (a character, Space, Backspace, the
number pad) is kept from the game's key bindings, its character (`OnChar`) goes into the box, and on its
release the keyboard closes, back to the box with typing focus. Every other key is passed on; Enter and the
number pad's Enter are bound (`SetOverrideBindingClick`, out of combat, cleared when it closes) to the
secure Enter key, so the real Enter sends through the same secure macro line. The keyboard reads the box
before each key, so text typed into it on a real keyboard is carried on, not overwritten. The keyboard is a popup in Blizzard's gamepad UI
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

`luajit tests/keyboard_test.lua` (or `nvim -l`) from the repo root: 90 checks, with the focus manager and
the chat box following Blizzard's code, every chat send function poisoned, the Enter key clicked the way
Blizzard's secure action button runs a click, the controller pressing as it does (A held as a box takes
focus, the menu dial's button already up), and real-keyboard keys delivered as the game delivers them
(focused box first, then key listeners from the top strata down, then bindings). Only the game can confirm:

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
- [ ] Enter on the real keyboard (in controller mode): the chat opens with no on-screen keyboard, and the
      real keyboard types and sends as usual.
- [ ] Ctrl-click on an item: no on-screen keyboard.
- [ ] With the on-screen keyboard open in chat, typing a letter on the real keyboard: the letter is in the
      chat box, the on-screen keyboard is gone, the next letters land in the box, nothing else happens
      (no walking on W, no reply on R). Enter on the real keyboard while it's open sends.
- [ ] Walking, keybinds and Escape on the real keyboard work as before when the on-screen keyboard is
      closed.
- [ ] Combat starting while typing: the keyboard closes without an "Interface action failed" or "blocked"
      message, and the text is still in the chat box.
