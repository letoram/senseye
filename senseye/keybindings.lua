--
-- Default keybindings for most features. To disable a specific
-- binding, remap it to some nonsense- keysym (right-hand value)
-- as other parts of the codebase expects the index keys to exist.
--

BINDINGS = {}
BINDINGS["META"]          = "RSHIFT"
BINDINGS["META_DETAIL"]   = "p" -- update position and motion markers

-- window-shared
BINDINGS["FULLSCREEN"]    = "F1"
BINDINGS["ZOOM"]          = "F3" -- + META zooms out
BINDINGS["RESIZE_X2"]     = "F2" -- + META shrinks
BINDINGS["PLAYPAUSE"]     = " "
BINDINGS["SELECT"]        = "RETURN"
BINDINGS["DESTROY"]       = "BACKSPACE" -- requires meta
BINDINGS["CYCLE_SHADER"]  = "c"
BINDINGS["TRANSLATORS"]   = "t" -- requires meta

-- global
BINDINGS["POINTSZ_INC"]   = "F7"
BINDINGS["POINTSZ_DEC"]   = "F8"
BINDINGS["CANCEL"]        = "ESCAPE"
BINDINGS["POPUP"]         = "TAB" -- meta cycles selected window

-- 3d model based windows
BINDINGS["TOGGLE_3DSPIN"]  = " " -- model automatically spins around y
BINDINGS["TOGGLE_3DMOUSE"] = "m" -- change click/drag from rotate to move
BINDINGS["STEP_FORWARD"] = "w"
BINDINGS["STEP_BACKWARD"] = "s"
BINDINGS["STRAFE_LEFT"] = "a"
BINDINGS["STRAFE_RIGHT"] = "d"

-- pattern finder
BINDINGS["PFIND_INC"] = "RIGHT" -- increase match threshold
BINDINGS["PFIND_DEC"] = "LEFT" -- decrease match threshold

-- sensor specific
BINDINGS["PSENSE_PLAY_TOGGLE"] = " "
BINDINGS["PSENSE_STEP_FRAME"]  = "RIGHT"

BINDINGS["FSENSE_STEP_BACKWARD"] = "LEFT"
BINDINGS["FSENSE_STEP_SIZE_BYTE"] = "1"
BINDINGS["FSENSE_STEP_SIZE_ROW"] = "2"
BINDINGS["FSENSE_STEP_SIZE_HALFPAGE"] = "3"
BINDINGS["FSENSE_STEP_ALIGN"] = "a"

BINDINGS["MSENSE_MAIN_UP"] = "UP"
BINDINGS["MSENSE_MAIN_DOWN"] = "DOWN"
BINDINGS["MSENSE_MAIN_LEFT"] = "LEFT"
BINDINGS["MSENSE_MAIN_RIGHT"] = "RIGHT"
BINDINGS["MSENSE_MAIN_SELECT"] = "RETURN"

BINDINGS["MSENSE_REFRESH"] = "r"
