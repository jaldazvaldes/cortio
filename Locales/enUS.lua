Interruptio = Interruptio or {}
Interruptio.L = Interruptio.L or {}

local L = Interruptio.L

-- =========================================================
-- ENGLISH BASE (Default Fallback)
-- =========================================================

-- UI Headers
L["PANEL_HEADER"] = "INTERRUPTIO"
L["READY"] = "READY"
L["CD_REMAINING"] = " - cd %s s"
L["READY_SUFFIX"] = " - READY"

-- Settings Categories
L["CAT_GENERAL"] = "General"
L["CAT_PANEL"] = "Floating Panel"
L["CAT_NAMEPLATES"] = "Nameplates"

-- General Settings
L["OPT_SCALE"] = "Global Scale"
L["OPT_SCALE_DESC"] = "Adjusts the size of the interface."
L["OPT_ANNOUNCE"] = "Announce Assignments"
L["OPT_ANNOUNCE_DESC"] = "Send a message to party chat (/p) whenever you change your assignment."
L["OPT_ANNOUNCE_CD"] = "Announce Your CD"
L["OPT_ANNOUNCE_CD_DESC"] = "Includes your interrupt's remaining cooldown when announcing an assignment."
L["OPT_AUTO_FOCUS"] = "Auto Focus Mode"
L["OPT_AUTO_FOCUS_DESC"] = "Choose how to automatically set your focus when assigning a mark."
L["VAL_NONE"] = "None (Off)"
L["VAL_TARGET"] = "Current Target"
L["VAL_MOUSEOVER"] = "Mouseover"
L["OPT_DEBUG"] = "Debug Logs"
L["OPT_DEBUG_DESC"] = "Enable debug prints in the chat frame."

-- Panel Settings
L["OPT_MODERN"] = "Modern UI (Fluid & Translucent)"
L["OPT_MODERN_DESC"] = "Enable translucent 'glass' backgrounds, movement animations, and soft bright flashes."
L["OPT_EMPHASIZE"] = "Emphasize Ready (Dim & Pulse)"
L["OPT_EMPHASIZE_DESC"] = "Cooldown bars fade to 60% and their icons turn gray. Ready bars pulse at 100%."
L["OPT_CLASS_BARS"] = "Classic Progress Bars (Class Color)"
L["OPT_CLASS_BARS_DESC"] = "Cooldown bars will fill their entire height with the classic class color, replacing the dynamic color strip."
L["OPT_HIDE_PANEL"] = "Hide Floating Panel"
L["OPT_HIDE_PANEL_DESC"] = "Hides the floating list panel, leaving only the icons on the nameplates active."
L["OPT_HIDE_FRAME"] = "Transparent Background (Hide Frame)"
L["OPT_HIDE_FRAME_DESC"] = "Completely hides the panel's background and borders, leaving the bars floating freely without a frame."
L["OPT_ONLY_DUNGEONS"] = "Show Only in Dungeons/Raid"
L["OPT_ONLY_DUNGEONS_DESC"] = "The panel will only be visible automatically when you are inside a Dungeon, Party, or Raid (and in Test Mode)."
L["OPT_BAR_TEXTURE"] = "Bar Texture"
L["OPT_BAR_TEXTURE_DESC"] = "Choose the bar texture. Automatically detects options from Addons like ElvUI/Plater via LibSharedMedia."
L["OPT_SPELL_ICON"] = "Show Spell Icon"
L["OPT_SPELL_ICON_DESC"] = "Show the interrupt spell icon on the left side of the player's name."
L["BTN_TEST_MODE"] = "Toggle Test Mode"
L["BTN_TEST_MODE_DESC"] = "Generates a fake party to test the interface."
L["BTN_UNLOCK"] = "Unlock / Setup Panel"
L["BTN_UNLOCK_DESC"] = "Shows a visible backdrop on the panel so you can freely drag and position it."
L["UNLOCK_DRAG_ME"] = "DRAG ME"

-- Nameplate Settings
L["OPT_NP_GLOW"] = "Nameplate Glow"
L["OPT_NP_GLOW_DESC"] = "Highlights the assigned mob's nameplate with a glowing border."
L["OPT_NP_FRONT"] = "Bring Nameplate to Front LAYER"
L["OPT_NP_FRONT_DESC"] = "Forces your assigned target's health bar to render on top of others."
L["OPT_NP_SCALE"] = "Assigned Mob Bar Scale"
L["OPT_NP_SCALE_DESC"] = "Scale of the assigned mob's health bar."
L["OPT_ICON_SIDE"] = "Icon Anchor Point"
L["OPT_ICON_SIDE_DESC"] = "Anchor point for the icons relative to the health bar (Left, Right, Top, Bottom)."
L["OPT_ICON_H_OFFSET"] = "Horizontal Icon Separation"
L["OPT_ICON_H_OFFSET_DESC"] = "Horizontal distance from the health bar's edge."
L["OPT_ICON_V_OFFSET"] = "Vertical Icon Alignment"
L["OPT_ICON_V_OFFSET_DESC"] = "Vertical distance from the health bar's center."
L["VAL_LEFT"] = "Left"
L["VAL_RIGHT"] = "Right"
L["VAL_TOP"] = "Top"
L["VAL_BOTTOM"] = "Bottom"

-- Chat Messages
L["MSG_ASSIGNED_PARTY"] = "Interrupt %s assigned %s" -- 1: Player, 2: Target
L["MSG_ASSIGNED_SELF"] = "[Interruptio] Assigned %s (%s)" -- 1: Icon, 2: Target

-- Keybindings
_G["BINDING_HEADER_INTERRUPTIO"] = "Interruptio"
_G["BINDING_NAME_CLICK InterruptioMarkSABT:LeftButton"] = "Assign / Clear Interrupt Mark"
