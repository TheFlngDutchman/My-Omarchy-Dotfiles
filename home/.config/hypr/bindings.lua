-- ~/.config/hypr/bindings.lua — personal keybinding overrides
--
-- Loaded by hyprland.lua AFTER `require("default.hypr.omarchy")`, so anything
-- here wins over Omarchy's defaults. Hyprland reloads on save.
--
-- Rule of thumb: to take over a key that Omarchy already uses, hl.unbind() it
-- first, then o.bind() it. Binding without unbinding leaves BOTH binds active.
--
-- ============================================================================
-- HOW TO FIND OUT WHAT'S ALREADY BOUND AND WHICH DISPATCHERS EXIST
-- ============================================================================
--
-- 1. Every active binding, with descriptions (defaults + these overrides):
--      omarchy menu keybindings --print
--
-- 2. What Hyprland actually has loaded right now — the ground truth. Use this
--    to confirm an unbind worked; if the old description is still listed, the
--    key string didn't match:
--      hyprctl binds
--      hyprctl binds | grep -i -B2 'key: F$'
--    modmask decoding: 1=SHIFT  4=CTRL  8=ALT  64=SUPER (add them together,
--    e.g. 65 = SUPER+SHIFT, 68 = SUPER+CTRL, 69 = SUPER+CTRL+SHIFT,
--    72 = SUPER+ALT, 73 = SUPER+ALT+SHIFT, 76 = SUPER+CTRL+ALT).
--
-- 3. Omarchy's default bindings, as source — split by topic:
--      ls /usr/share/omarchy/default/hypr/bindings/
--        applications.lua  clipboard.lua  media.lua
--        tiling.lua        utilities.lua  voxtype.lua
--    Look up one key (this is how the unbinds below were verified):
--      grep -rn '"SUPER + SHIFT + F"' /usr/share/omarchy/default/hypr/bindings/
--    NOTE: mind the exact spacing — keys are matched as written. Minus and
--    equals appear as code:20 / code:21, not as MINUS / EQUAL.
--
-- 4. Which dispatchers Omarchy itself uses (good starting vocabulary):
--      grep -rho 'hl\.dsp\.[a-z_.]*' /usr/share/omarchy/default/hypr/ | sort -u
--
-- 5. The full hl.* API — every dispatcher that exists, not just the used ones:
--      less +/HL.DspNamespace /usr/share/hypr/stubs/hl.meta.lua
--    Namespaces: hl.dsp.* plus hl.dsp.window.*, .workspace.*, .group.*,
--    .cursor.*. Arg shapes aren't in the stub — copy a working call from
--    default/hypr/bindings/tiling.lua, or check the Hyprland wiki dispatcher
--    list: https://wiki.hypr.land/Configuring/Dispatchers/
--
-- 6. What the o.bind() shorthands expand to ({ omarchy = }, { launch = },
--    { webapp = }, { tui = }, focus = true):
--      cat /usr/share/omarchy/default/hypr/helpers.lua
--
-- 7. Stock version of this file, if you ever want to diff or start over:
--      diff /usr/share/omarchy/config/hypr/bindings.lua ~/.config/hypr/bindings.lua
--      omarchy refresh config hypr/bindings.lua   # resets it (backs up first)
--
-- Escape hatches, set in hyprland.lua before require("default.hypr.omarchy"):
--   omarchy_default_bindings = false        -- drop ALL Omarchy defaults
--   omarchy_preinstalled_bindings = false   -- drop only app/webapp bindings
--
-- ============================================================================

-- ============================================================================
-- UNBINDS — Omarchy defaults being retired
-- Each comment records what the key did upstream. Verified 2026-07-25 against
-- Omarchy 4.0.0 / Hyprland 0.56.0.
-- ============================================================================

-- Keys moved elsewhere (replacements in the BINDS section below)
hl.unbind("SUPER + W") --                was: Close window          -> now SUPER + Q
hl.unbind("SUPER + ALT + SPACE") --      was: Apps menu             -> already on SUPER + D
--                                       (new default added upstream; it loads
--                                       before this file and shadowed the
--                                       Omarchy menu rebind below)
hl.unbind("SUPER + CTRL + T") --         was: Activity (btop)       -> now CTRL + SHIFT + ESCAPE
hl.unbind("SUPER + SHIFT + F") --        was: File manager          -> now SUPER + E
hl.unbind("SUPER + SHIFT + RETURN") --   was: Browser               -> now SUPER + B
hl.unbind("SUPER + SHIFT + B") --        was: Browser               -> now SUPER + SHIFT + B (private)
hl.unbind("SUPER + SHIFT + ALT + B") --  was: Browser (private)     -> folded into SUPER + SHIFT + B
hl.unbind("SUPER + SHIFT + S") --        was: Google Maps           -> now Vaultwarden
hl.unbind("SUPER + SHIFT + SLASH") --    was: Passwords (1Password) -> now SUPER + SHIFT + S

-- Free SUPER + CTRL + arrows (was: move focus between grouped windows) so the
-- arrow-based resize scheme below can use them.
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")

-- Retire the stock minus/equals resize scheme entirely — replaced by the
-- arrow scheme below. code:20 = minus, code:21 = equals.
-- (defaults live in default/hypr/bindings/tiling.lua:52-65)
hl.unbind("SUPER + code:20") --                 fine  / normal step
hl.unbind("SUPER + code:21")
hl.unbind("SUPER + SHIFT + code:20")
hl.unbind("SUPER + SHIFT + code:21")
hl.unbind("SUPER + ALT + code:20") --           small step
hl.unbind("SUPER + ALT + code:21")
hl.unbind("SUPER + SHIFT + ALT + code:20")
hl.unbind("SUPER + SHIFT + ALT + code:21")
hl.unbind("SUPER + CTRL + code:20") --          large step
hl.unbind("SUPER + CTRL + code:21")
hl.unbind("SUPER + CTRL + SHIFT + code:20")
hl.unbind("SUPER + CTRL + SHIFT + code:21")

-- ============================================================================
-- BINDS — menus and launchers
-- ============================================================================

o.bind("SUPER + D", "Launch apps", "omarchy-shell shell toggle io.github.theflngdutchman.app-grid '{}'")

-- ============================================================================
-- BINDS — applications
-- ============================================================================

o.bind( -- browser
	"SUPER + B",
	"Browser",
	{ omarchy = "browser" }
)
o.bind( -- browser private
	"SUPER + SHIFT + B",
	"Browser (private)",
	{ omarchy = "browser --private" }
)
o.bind( -- file manager
	"SUPER + E",
	"File manager",
	{ omarchy = "nautilus" }
)
o.bind( -- btop
	"CTRL + SHIFT + ESCAPE",
	"Activity",
	{ tui = "btop" }
)
o.bind( -- custom vaultwarden (vault.swh-tech.pro)
	"SUPER + SHIFT + S",
	"Passwords",
	{ webapp = "https://vault.swh-tech.pro", focus = true }
)

-- ============================================================================
-- BINDS — window management
-- ============================================================================

o.bind( -- close window
	"SUPER + Q",
	"Close window",
	hl.dsp.window.close()
)

-- ============================================================================
-- BINDS — window resize (arrow scheme)
--
-- Direction is geometric, not directional-intent: right/down grow the window,
-- left/up shrink it. Three step sizes, distinguished by modifier:
--
--   SUPER + CTRL + ALT   + arrows ->  25px   fine
--   SUPER + CTRL         + arrows -> 100px   normal
--   SUPER + SHIFT + CTRL + arrows -> 300px   coarse
-- ============================================================================

-- Fine — 25px
o.bind( -- 25px - shrink width
	"SUPER + CTRL + ALT + left",
	"Retract window left a little",
	hl.dsp.window.resize({ x = -25, y = 0, relative = true })
)
o.bind( -- 25px - grow width
	"SUPER + CTRL + ALT + right",
	"Expand window right a little",
	hl.dsp.window.resize({ x = 25, y = 0, relative = true })
)
o.bind( -- 25px - shrink height
	"SUPER + CTRL + ALT + up",
	"Retract window up a little",
	hl.dsp.window.resize({ x = 0, y = -25, relative = true })
)
o.bind( -- 25px - grow height
	"SUPER + CTRL + ALT + down",
	"Expand window down a little",
	hl.dsp.window.resize({ x = 0, y = 25, relative = true })
)

-- Normal — 100px
o.bind( -- 100px - shrink width
	"SUPER + CTRL + left",
	"Retract window left",
	hl.dsp.window.resize({ x = -100, y = 0, relative = true })
)
o.bind( -- 100px - grow width
	"SUPER + CTRL + right",
	"Expand window right",
	hl.dsp.window.resize({ x = 100, y = 0, relative = true })
)
o.bind( -- 100px - shrink height
	"SUPER + CTRL + up",
	"Retract window up",
	hl.dsp.window.resize({ x = 0, y = -100, relative = true })
)
o.bind( -- 100px - grow height
	"SUPER + CTRL + down",
	"Expand window down",
	hl.dsp.window.resize({ x = 0, y = 100, relative = true })
)

-- Coarse — 300px
o.bind( -- 300px · shrink width
	"SUPER + SHIFT + CTRL + left",
	"Retract window left a lot",
	hl.dsp.window.resize({ x = -300, y = 0, relative = true })
)
o.bind( -- 300px · grow width
	"SUPER + SHIFT + CTRL + right",
	"Expand window right a lot",
	hl.dsp.window.resize({ x = 300, y = 0, relative = true })
)
o.bind( -- 300px · shrink height
	"SUPER + SHIFT + CTRL + up",
	"Retract window up a lot",
	hl.dsp.window.resize({ x = 0, y = -300, relative = true })
)
o.bind( -- 300px · grow height
	"SUPER + SHIFT + CTRL + down",
	"Expand window down a lot",
	hl.dsp.window.resize({ x = 0, y = 300, relative = true })
)

-- ============================================================================
-- NOT BOUND HERE — universal clipboard (SUPER + C / SUPER + V)
--
-- Between 2026-07-25 and 2026-08-09 this file carried a local override of both
-- keys. Omarchy's copy/paste used to decide "is this a terminal?" from a fixed
-- class list, which missed the org.omarchy.* app-ids that omarchy-launch-tui
-- gives floating TUIs — so SUPER + C sent them a literal CTRL+C and the TUI
-- exited on SIGINT instead of copying.
--
-- Fixed upstream, so the override is gone and Omarchy's defaults apply again:
--   d9bc38a9 (#6561) defines a +terminal window tag in
--     default/hypr/apps/terminals.lua covering org.omarchy.* and TUI.*, and
--     clipboard.lua now reads that tag instead of keeping its own class list.
--   e4a8e014 adds org.codeberg.dnkl.foot, foot's other app-id — Hyprland
--     matches the class in full, so a bare "foot" alternative never hit it.
-- Reported as basecamp/omarchy#6379.
--
-- Nothing to do here. Kept as a note so the override isn't reintroduced.
-- ============================================================================
