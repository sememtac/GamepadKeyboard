# Gamepad Keyboard

An on-screen keyboard for typing with a controller in WoW: Forever (Interface 16001). Local addon.

When you go to a text box with the controller - A on a name box or a search box, Chat on the menu dial -
the keyboard opens on top of the window the box belongs to. It joins Blizzard's gamepad UI like the game's own
panels: the D-pad moves between keys (left / right along a row, up / down between rows), A types,
**Enter** does what the Enter key does, B goes back without it, LT / RT switch windows. Each key types
straight into the text box, at the cursor (the gold bar in the preview line).

While the keyboard has the controller:

| Button | Does |
| --- | --- |
| A | the key it's on |
| X | Del (the letter before the cursor) |
| Y | Space |
| LB / RB | move the cursor left / right |
| B | back, without Enter |

The footer shows these. On another window (LT / RT) or with the keyboard closed, X, Y, LB and RB are
the game's again.

## Chat

Type the message and press **Enter**: it's sent and the chat closes, as with the Enter key. Whispers and
replies keep their target, `/p` and the other prefixes switch the chat as when typing, numbered channels
work, and a line starting with `/` runs as a command (`/dance`, `/cast`, `/target`). The chat type you
sent in sticks for the next line, as it does with Enter. Enter with nothing typed just closes the chat.
A chat line starts with Shift on.

The **chat key** (bottom row, beside Space) shows who you're talking to - Say, Party, To Bob, /2 - and
steps on to the next chat type there is to use: Say, Party (in a group), Raid (in a raid), Instance (in an
instance group), Guild (in a guild), and a reply to whoever whispered you last. What you've typed stays.
It switches as typing `/p ` does - the type's slash command goes in front of the text and the chat box's
own parsing switches the chat - so it's the same as typing the prefix yourself.

**B** goes back to the chat box with the text instead, unsent; the chat's own **A Send** sends it from
there. Enter does that too, with a note in the chat, for the few lines it can't send itself: Battle.net
whispers, chat types with no slash prefix, channels picked by name
rather than number, and lines too long to fit with their prefix.

## Controller or real keyboard

Whichever you're using has the text box:

- The keyboard opens only when the **controller** asked for the text box. Enter, `/` or reply on a real
  keyboard opens the chat for that keyboard, and a mouse click that puts focus in some box (a ctrl-click
  that shows a link to copy, say) doesn't bring it up either. Chat on the menu dial brings it up whenever
  you want it.
- While it's open over chat, **Enter on a real keyboard (or a click in the chat box) takes the chat back**:
  the on-screen keyboard steps aside, and the text and its whisper target stay for the real keyboard to
  carry on. Other keys do what they always do.
- The addon never listens to your keys, so the real keyboard always works as usual.

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
checks them) or was what the player pressed last. A real keyboard is seen only by a chat key being held as
the box takes focus (`IsKeyDown` on the keys bound to Open Chat, Open Chat Slash and the two replies, not
the controller's); the mouse by `GLOBAL_MOUSE_DOWN`.

Keys are only ever looked at, never listened to: a frame with `EnableKeyboard(true)` keeps every key it
isn't allowed to pass on, and `SetPropagateKeyboardInput` is restricted in Forever (in combat at least).
Text-box focus is hooked on the method table all text boxes share, taken from Blizzard's chat box: a text
box made with `CreateFrame` is shown with auto-focus on and takes the real keyboard at login (0.2 to 0.4.1
did that, so after a reload no key worked until something else took focus). Open over chat, the chat box has no typing focus; when it gets it back (Blizzard's Enter
binding is `OpenChat(nil)`, which keeps the text), the keyboard closes. It reads the box before each key,
so text typed into a box that kept focus is carried on, not overwritten.

X, Y, LB and RB are override bindings (`SetOverrideBindingClick`, owner: the keyboard) that click its Del
and Space keys and two hidden cursor buttons - the way the game's controller UI binds its own buttons
(priority override bindings, owner `UIParent`; the latest binding of a button wins). They're bound while
the keyboard has the controller (`focusedFrame`), bound again if the controller UI binds one of those
buttons over them (post-hooks on `SetOverrideBindingClick` / `SetOverrideBinding`), and cleared when the
controller leaves the keyboard or it closes - before combat locks bindings. The keyboard is a popup in Blizzard's gamepad UI
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

`luajit tests/keyboard_test.lua` (or `nvim -l`) from the repo root: 125 checks, with the focus manager and
the chat box following Blizzard's code, every chat send function poisoned, the Enter key clicked the way
Blizzard's secure action button runs a click, the controller pressing as it does (A held as a box takes
focus, the menu dial's button already up), and real-keyboard keys delivered as the game delivers them
(focused box first, then key listeners from the top strata down, then bindings), with
`SetPropagateKeyboardInput` refused to addon code and auto-focus text boxes taking focus when shown. Only the game can confirm:

- [ ] Chat (from the menu dial's Chat, or the chat binding): the keyboard opens; A on a key types into the
      chat box.
- [ ] Enter: the message is sent and the chat closes; with nothing typed, the chat just closes.
- [ ] A whisper reply sent with Enter reaches the right player; `/p hello` goes to party and party is
      still the chat type next time; `/2 hello` goes to channel 2; `/dance` dances; `/cast` a spell
      casts it.
- [ ] B: back on the chat box with the text and "A Send" showing; A sends it.
- [ ] X deletes, Y types a space, LB / RB move the gold cursor, and keys type at the cursor. With the
      controller on another window (LT / RT) or the keyboard closed, X / Y / LB / RB do what they did before
      (crossbar, the window's own actions).
- [ ] The chat key: in a group it goes Say -> Party (-> Raid / Instance / Guild / To <last whisperer>) and
      back to Say, the chat box's header changes with it, the text stays, and Enter sends to that chat.
- [ ] LT / RT move between the keyboard and other open windows.
- [ ] The keyboard can be dragged and reopens where it was left; for chat it doesn't cover the chat window.
- [ ] After B, Chat on the menu dial (or A on a name box) brings the keyboard back.
- [ ] Gesture Commands' Name & icon: A on the name box opens the keyboard; Enter or B returns to the
      picker with the name kept.
- [ ] Enter on the real keyboard (in controller mode): the chat opens with no on-screen keyboard, and the
      real keyboard types and sends as usual.
- [ ] Ctrl-click on an item: no on-screen keyboard.
- [ ] With the on-screen keyboard open in chat, Enter on the real keyboard: the on-screen keyboard is gone,
      the text is in the chat box, the real keyboard types on and sends.
- [ ] Every key on the real keyboard works as before (walking, Escape, Ctrl, keybinds), with the on-screen
      keyboard open or closed.
- [ ] Combat starting while typing: the keyboard closes without an "Interface action failed" or "blocked"
      message, and the text is still in the chat box.
