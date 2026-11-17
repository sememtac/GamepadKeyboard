# Gamepad Keyboard

An on-screen keyboard for typing with a controller in WoW: Forever (Interface 16001). Local addon.

When you go to a text box with the controller - A on a name box or a search box, Chat on the menu dial -
the keyboard opens on top of the window the box belongs to. It joins Blizzard's gamepad UI like the game's own
panels: the D-pad moves between keys (left / right along a row, up / down between rows, wrapping round at
the ends), A types,
**Enter** does what the Enter key does, B goes back without it, LT / RT switch windows. Each key types
straight into the text box, at the cursor (the gold bar in the preview line).

While the keyboard has the controller:

| Button | Does |
| --- | --- |
| A | the key it's on (on release) |
| hold A | Enter, from any key - the footer's A with a ring fills as you hold (Blizzard's press-and-hold glyph), and the Enter key lights up once it's long enough (half a second) |
| X | Del (the letter before the cursor) |
| Y | Space |
| LB / RB | move the cursor left / right |
| B | back, without Enter |

The footer shows these. On another window (LT / RT) or with the keyboard closed, A, X, Y, LB and RB are
the game's again.

## Chat

Type the message and press **Enter**: it's sent and the chat closes, as with the Enter key. Whispers and
replies keep their target, `/p` and the other prefixes switch the chat as when typing, numbered channels
work, and a line starting with `/` runs as a command (`/dance`, `/cast`, `/target`). The chat type you
sent in sticks for the next line, as it does with Enter. Enter with nothing typed just closes the chat.
A chat line starts with Shift on. With **Close after Enter** off (Options), Enter sends and the keyboard
stays on a fresh line in the same chat; B closes it.

The **chat key** (bottom row, beside Space) shows who you're talking to - Say, Party, To Bob, /2 - and
steps on to the next chat type there is to use: Say, Party (in a group), Raid (in a raid), Instance (in an
instance group), Guild (in a guild), the whisper the chat was in (opened from a name or the friends
list, or typed with `/w`), and a reply to whoever whispered you last. What you've typed stays.
It switches as typing `/p ` does - the type's slash command goes in front of the text and the chat box's
own parsing switches the chat - so it's the same as typing the prefix yourself. A whisper is set as the
chat's parser sets it (tell target, type, header): a name can't be typed in for it reliably, and a
Battle.net name can't be typed at all.

**B** goes back to the chat box with the text instead, unsent; the chat's own **A Send** sends it from
there. Enter does that too, with a note in the chat, for the few lines it can't send itself: Battle.net
whispers, chat types with no slash prefix, channels picked by name
rather than number, and lines too long to fit with their prefix.

## Boxes of several lines

In a box of several lines - the mail's text - Enter (the key, or holding A) starts a **new line** at the
cursor; the Enter key and the footer say so. The preview shows the line the cursor is on ("line 2 of 3").
B is the way out. Every other box gets Enter as its Enter - which can mean "next box": Enter in the mail's
To: moves on to Subject: (the box's own Enter), and the keyboard follows it there.

## Options

Options > AddOns > **Gamepad Keyboard** (or `/gk`) - checkboxes, a dropdown with < > like the ones in
Options, and - / + for the numbers; the panel's Defaults button puts them all back:

| Option | Does |
| --- | --- |
| Open with the controller | opens when you go to a text box with the controller (`/gk on` / `/gk off`) |
| Keyboard layout | QWERTY or Dvorak (the letters; numbers, symbols and the bottom row are the same) |
| Close after Enter | Enter closes the keyboard (chat: sends and closes the chat); off: it stays for the next line |
| Capital letter to start a chat line | a chat line starts with Shift on |
| Name suggestions | name keys for a box that looks names up (the mail's To:) |
| Hold A for Enter | how long to hold A for Enter, 0.3 - 1.5 s in tenths |
| Size | 60 - 150% in 5% steps |

## Where it goes, and its size: Edit Mode

In **Edit Mode** the keyboard shows (in the middle of the screen until it's been placed), with a blue
selection: drag it with the mouse to where it should open, and use the mouse wheel over it to resize it in
5% steps. It opens there from then on, for every text box - placed once, the "beside the chat window"
default is gone; `/gk reset` brings back the usual place and size. Size is also in Options.

This is the keyboard's own selection, not one of Edit Mode's systems: Forever's Edit Mode takes no addon
frames (adding one to its list would taint it, and it lays out the action bars), so there's no Edit Mode
settings dialog for it, the layout isn't per Edit Mode layout, and Edit Mode's Revert Changes doesn't undo
it (dragging and the mouse wheel take effect at once; `/gk reset` is the undo).

## Names

A text box that looks names up as you type - the mail's **To:**, say - gets a row of name keys above the
keyboard: up to four players the game knows (friends, guild, group, people you've mailed or met) that start
with what you've typed. D-pad up to them, A puts the name in. Blizzard's own list under the box only follows
typing on a real keyboard and is picked with Tab or the mouse, so it doesn't show for the on-screen keyboard.

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
- **Where it opens**: beside the chat window for chat, near the text box otherwise - until it's placed in
  Edit Mode (or dragged with the mouse); `/gk reset` puts it back.
- **Another text box in the same window** (the mail's Subject:): LT / RT to the window, D-pad to the box,
  A on it - the keyboard types there from then on; LT / RT back to the keyboard. A real keyboard or a
  mouse click in another box makes it step aside instead.
- **A whisper started from a menu** (a name's Whisper, the chat's channels) while the keyboard is up: LT /
  RT between the chat window and the keyboard keeps the chat to that person, and the chat key shows it.
- **Which text boxes**: chat, the mail's To: / Subject: / text, and other addons' text boxes. Not the
  game's other text boxes - the bag search, the Options search, confirmation popups, the Auction House
  and so on: what an addon types into one runs the game's own code as the addon's doing, and some of
  that goes on into things only the game's UI may do, so the game blocks the addon (it did for the bag
  search and the Options search). A real keyboard types there as usual; the first time, it says so.
- **If the game ever blocks it anyway**, it prints what was blocked and which text box it last typed into -
  worth reporting. A `/reload` clears it.
- **No names showing** in a box that should have them: type a few letters in it with the keyboard, then
  `/gk names` says what the game's name lookup finds for it (or why it doesn't run).
- **Bringing it back** after going back to a text box (or after the real keyboard took over): A on the box
  again, or Chat on the menu dial again.
- `/gk` opens its options; `/gk off` stops it opening by itself, `/gk on` turns it back on.
- No `|` key: the game reads it as the start of an escape code.

## How it works

`GetCurrentKeyBoardFocus()` is checked once per frame, and `SetFocus` on any text box and the chat
frames' `SetGamepadFocus` are post-hooked (`hooksecurefunc`) for a box that is asked for again while it
already has focus; the refocus that closing the keyboard causes is ignored. It opens only if the controller
asked: one of its buttons is down (`IsKeyDown("PAD1")` and the rest, as Blizzard's class-action flyout
checks them) or was what the player pressed last. A real keyboard is seen only by a chat key being held as
the box takes focus (`IsKeyDown` on the keys bound to Open Chat, Open Chat Slash and the two replies, not
the controller's); the mouse by `GLOBAL_MOUSE_DOWN`.

Typing runs the box's own handlers as this addon's doing (tainted): a Blizzard box's can reach calls only
Blizzard's UI may make (the bag search fires a synchronous inventory event whose listeners reach the
gamepad action bar's `SetPreferredGamepadInteractTarget`; the Options search keeps its text for the
panel's close, which then calls `SaveBindings`). So it types only into chat boxes (made for it), the mail's
three boxes (looked through), and boxes none of whose text, Enter or focus handlers are Blizzard's
(`issecurevalue`). A tapped A only ever clicks the keyboard's own keys.

Keys are only ever looked at, never listened to: a frame with `EnableKeyboard(true)` keeps every key it
isn't allowed to pass on, and `SetPropagateKeyboardInput` is restricted in Forever (in combat at least).
Text-box focus is hooked on the method table all text boxes share, taken from Blizzard's chat box: a text
box made with `CreateFrame` is shown with auto-focus on and takes the real keyboard at login (0.2 to 0.4.1
did that, so after a reload no key worked until something else took focus). Open over chat, the chat box has no typing focus; when it gets it back (Blizzard's Enter
binding is `OpenChat(nil)`, which keeps the text), the keyboard closes. It reads the box before each key,
so text typed into a box that kept focus is carried on, not overwritten - and checks it every frame while
open, so when the game changes the box (the mail sent and cleared, a link put in) the preview follows at once.

A, X, Y, LB and RB are override bindings (`SetOverrideBindingClick`, owner: the keyboard) that click a
hidden secure A button, its Del and Space keys, and two hidden cursor buttons - the way the game's controller UI binds its own buttons
(priority override bindings, owner `UIParent`; the latest binding of a button wins). They're bound while
the keyboard has the controller (`focusedFrame`), bound again if the controller UI binds one of those
buttons over them (post-hooks on `SetOverrideBindingClick` / `SetOverrideBinding`), and cleared when the
controller leaves the keyboard or it closes - before combat locks bindings.

The A button is registered for the press and the release. The press notes the time; the release either
presses the key the D-pad is on (`SmartNavigation:GetCurrentButton()`, a getter) or, after a hold or on
the Enter key, runs the Enter key's own PreClick / PostClick around Blizzard's secure macro action - a
binding's click is a real press, so a held A sends just as A on the Enter key does. (Blizzard's own A
clicks on the press, so a hold can't be told apart there: by then the key is typed.) The keyboard is a popup in Blizzard's gamepad UI
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

Names come from the box's own lookup - only when it's Blizzard's `C_AutoComplete.GetAutoCompleteResults`
(read-only) with the box's include / exclude flags, never a box's own function or completion handler, and
not for chat. Blizzard's list (`AutoCompleteBox`) isn't touched: its update runs only on user input, and
calling it from here would leave addon-written state (its parent, selection) that the chat's Enter reads.
A picked name goes in as Blizzard's list puts it (`Ambiguate(name, "none")`, the box's command and space).

The options are the addon's own page in Blizzard's Settings panel (`Settings.RegisterCanvasLayoutCategory`,
at `ADDON_LOADED`), not Blizzard's list of controls: the panel keeps a list control's data (and calls its
functions - a dropdown's choices, a slider's label) as the addon gave them, and as it hides it clears its
search box - which redraws the page - and then saves key bindings, which only Blizzard's UI may do. With
the addon's controls on that page, that was "blocked from an action only available to the Blizzard UI".
A canvas page the panel only shows, and calls its refresh and defaults isolated; this one has no OnShow.
The layout dropdown is Blizzard's own (`SettingsDropdownWithButtonsTemplate`, the frame the Options
dropdowns use) on that page: the menu system runs the addon's choices and their picks isolated, and the
controller's A on it calls the control's `OnSmartNavClick` isolated too. A pick doesn't redraw the menu it
was made in (that rebuilds the open menu under its own click); Defaults and the steppers redraw it. Edit Mode is followed through
`EventRegistry` (`EditMode.Enter` / `EditMode.Exit`); in it the keyboard is a preview on the HIGH layer
(under Edit Mode's DIALOG panels) that never registers with the gamepad UI or follows typing focus. Saved
positions are kept in UIParent's units - a frame's offsets are in its own scaled units, so they're
multiplied by its scale when kept and divided when used - so it stays put at any size.

## Tests

`luajit tests/keyboard_test.lua` (or `nvim -l`) from the repo root: 276 checks, with the focus manager and
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
- [ ] Tapping A types the key the D-pad is on; holding A (on any key) fills the ring on the footer's second
      A and lights the Enter key, and letting go sends (chat) or runs the box's Enter. After closing, A works as before everywhere.
- [ ] X deletes, Y types a space, LB / RB move the gold cursor, and keys type at the cursor. With the
      controller on another window (LT / RT) or the keyboard closed, X / Y / LB / RB do what they did before
      (crossbar, the window's own actions).
- [ ] Mail: To:, then LT, down to Subject:, A, LT back: the keys type into Subject:; back to To: the same
      way, they type into To: again.
- [ ] Mail To:: typing a few letters shows up to four names above the keys; D-pad up and A puts one in, and
      the mail can be sent to it.
- [ ] Options > AddOns > Gamepad Keyboard shows the seven options (Keyboard layout: Dvorak switches the letters at once);
      A on the Options search box or the bag search: no keyboard (a note the first time); no "blocked" dialog; each works (Close after Enter off: chat
      stays open for the next line). The panel is usable with the controller.
- [ ] Keyboard layout dropdown: looks like the Options dropdowns; with the controller, A on it opens the
      menu, the D-pad walks it, A picks (the menu closes, the dropdown shows the pick), B closes it unpicked;
      the cursor sits sensibly on the row; with the mouse, < and > step it. No "blocked" dialog after.
- [ ] Mail: after Send, the keyboard's preview (and the name row) is empty too.
- [ ] Mail text (several lines): Enter / holding A start a new line; the preview shows "line 2 of 2".
- [ ] Edit Mode: the keyboard shows with a blue selection, under Edit Mode's panels; dragging moves it, the
      mouse wheel resizes it; after Edit Mode it opens there at that size.
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
