# Kinfall menu design

How Kinfall's menus look and behave, and the helpers in `scripts/ui/ui.gd` that build them. The
in-match HUD (`scripts/ui/hud.gd`) has its own Supervive-style layout and isn't covered here; it
shares the colours and fonts.

## 1. Audit (October 2026, before this pass)

What made the menus feel blocky, samey and hard to get through:

**Everything looked the same.**
- Every panel was the same night-blue box with a heavy gilded border and a gold ornament under the
  title. Cards inside panels were more boxes, often with their own borders (save slots, challenge
  cards, armory tiles, results notes). Boxes in boxes in boxes.
- Every button was the same chunky raised slab with a dark lip, so "Close", "Delete", "Sell", "Hear
  it" and the one thing you came to do all had the same weight. Only the orange Primary stood out,
  and some screens had two or three of them (shrine, feeders, armory).
- Selected tabs and selected options used the same "Chosen" slab as any other button, so a tab row
  looked like a row of actions.

**Unclear hierarchy.**
- Titles were big but had nothing under them; context ("what is this screen for?") was a paragraph
  in the body or missing.
- Body text came in five or six sizes (12, 13, 14, 15, 16, 17, 18) with no rule, and a lot of it was
  long muted sentences (settings rows like "Abilities fire the moment you press them (off: hold to
  aim, release to cast)" as the row label).
- The kin card crammed three dense columns of bars, labels and ten buttons into one page.
- The results screen showed eight separate stat boxes of equal weight.

**Navigation was inconsistent.**
- Closing was a "Close" or "Back" text button in the title row on some panels, "Back to the farm" on
  the lobby, nothing visible on others. Esc worked in most places but nothing said so.
- Actions were scattered: the expedition panel's Start sat at the bottom left among Training, Duel
  and Online; the rack's Equip/Buy sat beside the preview; the shop's page arrows were jammed into
  the tab row; the armory's upgrades shared a row with currency counters.
- Settings tabs were part of the scrolling body; long Gameplay and Controls lists scrolled their own
  tabs away.
- Nothing had keyboard or pad focus by default, focus rings showed on mouse clicks, and arrow keys
  only did anything on the title screen.
- At home, every panel was reached by walking to a thing in the world. There was no quick way to
  open your kin, your bag or the expedition panel.

**Panels popped in without context.**
- Home panels appeared over the farm with no dimming: the world kept competing with the menu.
- Overlay menus used a flat 60% black rectangle.
- Destructive things (delete a save, leave a match, sell an Epic weapon, reset all settings) either
  had an inline "Really delete?" swap or no confirmation at all, while harmless toggles rebuilt the
  whole panel.

**Small things.**
- Empty lists were a single grey sentence.
- Arrows were "‹" and "›" characters in full-size buttons.
- Key bindings in Controls were gold text, not keycaps.
- The loading bar was a hard-edged rectangle with a dot; the tip floated without a container.

## 2. Rules

1. **One strong title per panel**, with at most one short subtitle line under it (what the screen is
   for, or the one number that matters). No ornaments.
2. **Three type sizes.** `T_TITLE` 30 (Lilita One) for the panel title, `T_HEAD` 19 (Lilita One) for
   card and item names, `T_BODY` 15 (Rubik) for everything you read, `T_SMALL` 13 for secondary
   lines. Section eyebrows are `section()` (12, bold, spaced caps).
3. **Fewer boxes.** Panels are soft sheets (radius 20, hairline edge, long shadow, a faint light from
   the top). Cards inside them have no border unless they are *selected*. Group with spacing and
   eyebrows before reaching for a card.
4. **Three button tiers.** `primary()` (filled accent, dark text): the one thing the screen is for,
   at most one per screen, usually in the footer. `button()` (outline): normal actions.
   `ghost()` (text only): rare or small actions. `danger()` (red outline) for things that can't be
   undone, always behind `confirm()`.
5. **Colour roles.** `ACCENT` (amber) means "act here" and "selected". `GOLD` means gems and rewards.
   `GOOD` owned/ready/success, `BAD` danger/loss/locked, `TEAL` info and extraction. Item rarity uses
   `rarity_col(r)`. Never use ACCENT for decoration.
6. **Same shell everywhere.** Title (+subtitle) top left, extras (chips, tags) and a close X top
   right, tabs under the title, body, footer actions bottom right with the primary last and an Enter
   keycap on it. Esc always closes or goes back.
7. **Tabs, not long lists.** Group options into tabs (`shell_tabs`) and groups (`section`). Tabs are a
   segmented control, visibly different from buttons.
8. **Sensible defaults.** The panel opens with the primary focused (or the first control), the last
   tab you used, and the current choice highlighted.
9. **Confirm only what can't be undone** (delete a save, leave a match, sell or salvage an Epic or
   Legendary, reset all settings). Everything else happens immediately.
10. **Motion is short.** Buttons lift 3% on hover and sink to 97% on press (70-110 ms). Panels fade and
    rise in (140-220 ms). Modals blur the screen behind them (160 ms). Nothing bounces.
11. **Icons next to labels** where they help scanning (hub, pause menu, footers, empty states), drawn
    with `draw_icon` so they stay crisp at any size.
12. **Keyboard and pad.** Every panel has something focused; arrows, Enter and Esc work; focus rings
    show for keyboard and pad only (`gui/common/show_focus_state_on_pointer_event=false`).

## 3. Home flow

- **Hub bar** (bottom left): Expedition, Kin, Bag, Market, (Build), Settings, on number keys 1-6.
  Pressing the same number again closes that panel. Hidden while a panel is open and when visiting.
- **Prompts**: walking up to anything shows a glass pill with keycaps for what you can do (F use; for
  a kin, F pet, V fetch, T talk, C details).
- **Panels** open over a blurred, dimmed farm; clicking the dimmed area or pressing Esc closes them;
  Enter presses the panel's primary when nothing else has focus.

## 4. Helper API (`scripts/ui/ui.gd`, class `UI`)

Everything is static. Set `root.theme = UI.theme()` on the root Control of a screen once.

### Colours and sizes
`INK MUTED FAINT BG SURFACE CARD WELL LINE ACCENT ACCENT_HI GOOD BAD GOLD TEAL INFO DARK_INK`,
`T_TITLE T_HEAD T_BODY T_SMALL T_CAPS`, `GAP GAP_BIG PAD`, `rarity_col(r)`. Fonts: `UI.big` (Lilita
One), `UI.body` (Rubik), `UI.semi` (Rubik 560), `UI.caps` (Rubik 700, spaced).

### Text
- `title(text, size=34, col=INK)` - Lilita One, one line.
- `label(text, size=16, col=INK, font=null)` - wraps only past 48 characters.
- `para(text, size=T_SMALL, col=MUTED)` - always wraps.
- `section(text, col)` - a spaced caps eyebrow over a group (pages keep it with what follows).
- `kv(key, value, col)` - a muted key on the left, the value on the right.

### Buttons
- `primary(text, cb, minw=0, icon="")`, `button(...)`, `ghost(...)`, `danger(...)` - the tiers.
- `choice(text, chosen, cb, minw, icon)` - an option in a row; the chosen one is lit (Chosen).
- `icon_button(icon, cb, tip, px=16)` - round, icon only (close, back, arrows).
- `set_icon(button, icon, px=16)` - adds a drawn icon to any button's left.
- `with_key(button, "Enter")` - shows a keycap at the button's right end (it doesn't bind the key).
- Theme variations you can set directly: `Primary`, `Ghost`, `Danger`, `Chosen`, `IconBtn`, `Seg`,
  `SegOn`, `Tile`, `TileOn`, `MenuItem`, `MenuMain`.

### Containers and pieces
- `card(col=CARD, pad=14, rad=12)` - a raised card (shadow and top light when opaque).
- `set_card_border(card, col, w)` - only for the selected or the warning card.
- `tile_card(on, cb, pad=12, col=ACCENT)` - a selectable card (hover, focus, click, Enter); add your
  content to it. For tiers, skins, items.
- `glass(pad, rad)` - dark glass for things over the world (prompts, hint rows, hover cards, hub).
- `sheet(width)` - a plain panel without the shell.
- `chip(icon, text, col, tip, size=14)` - a pill with an icon and a value (gems, scrap, counts).
- `tag(text, col)` - a small coloured caps tag (Partner, Equipped, Kin at risk).
- `tabs(names, cur, cb(name), counts={}, minw=0)` - a segmented control.
- `empty_state(icon, head, sub)` - what an empty list shows.
- `bar(frac, col, w, h)`, `keycap(key, size)`, `key_hints([[key, what], ...])`, `spacer(h)`,
  `fill()`, `vbox(sep)`, `hbox(sep)`.
- `draw_icon(canvas_item, id, at, half_size, col)` and `IconDot.new(id, col, px)` - any `Icons` id
  plus the menu's own: close, back, next, check, plus, lock, gear, home, bag, shop, portal, hammer,
  info.

### The panel shell
```gdscript
var pb := UI.scroll_panel("Market stall", 800, close_cb)   # or (title, width, close_cb, "Back", true) to scroll
var panel: PanelContainer = pb[0]
var v: VBoxContainer = pb[1]                     # the body: add your content here
UI.subtitle(v, "Seeds, food and things for the farm")
UI.head_extra(v).add_child(UI.chip("gem", "120", UI.GOLD, "Your gems"))
UI.shell_tabs(v, ["Seeds", "Food", "Sell"], cur_tab, func(t): cur_tab = t; reopen())
UI.footer_left(v).add_child(UI.ghost("Hear it", play_sound))
UI.footer(v).add_child(UI.button("Brush", brush))
UI.footer_primary(v, "Buy", buy, 160, "gem")      # primary + Enter keycap; UI.press_primary(host) presses it
```
- The body pages (or scrolls, with `scroll = true`) whenever it's taller than the window.
- At home use `_new_panel(title, width, scroll)` in `home.gd`: it builds this shell, blurs the farm,
  hides the hub, pops the panel in, and Esc / Enter / clicking outside work.
- In overlay menus use `_page(name, title, width, scroll)` in `overlay.gd` (it keeps a back stack:
  the X becomes a back arrow).
- `confirm(host, head, text, yes_text, on_yes, dangerous=true)` - a small modal over `host` with
  Cancel and a danger (or primary) button; Esc cancels it.
- `backdrop()` + `show_backdrop(rect, on)` - the blurred, dimmed layer behind modals
  (`shaders/ui_backdrop.gdshader`).
- `pop_in(control, delay)` - the open animation. `focus_first(control)` - focus the first button.

### Hooks for other systems
- **Hub entries** come from `home.gd`'s `hub_items()`: `[id, label, icon, Callable]`. If the home
  screen has `open_build()` a Build entry appears; if it has `open_kin_box()` the Kin entry opens it
  instead of the partner's card. Hide the bar with `hub.visible = false` while a mode (build mode)
  owns the bottom of the screen.
- New home panels: `var v := _new_panel("Kin Box", 900)` then fill `v` with the helpers above.
