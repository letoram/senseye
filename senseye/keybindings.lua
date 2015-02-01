--
-- Default keybindings for most features. To disable a specific
-- binding, remap it to some nonsense- keysym (right-hand value)
-- as other parts of the codebase expects the index keys to exist.
--

BINDINGS = {}
BINDINGS["META"]          = "RSHIFT"

-- window-shared
BINDINGS["FULLSCREEN"]    = "F1"
BINDINGS["ZOOM"]          = "F3" -- + META zooms out
BINDINGS["RESIZE_X2"]     = "F2" -- + META shrinks
BINDINGS["PLAYPAUSE"]     = " "
BINDINGS["DESTROY"]       = "BACKSPACE" -- requires meta
BINDINGS["CYCLE_SHADER"]  = "c"

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

-- sensor specific
BINDINGS["PSENSE_PLAY_TOGGLE"] = " "
BINDINGS["PSENSE_STEP_FRAME"]  = "RIGHT"
BINDINGS["FSENSE_STEP_BACKWARD"] = "LEFT"

BINDINGS["MSENSE_MAIN_UP"] = "UP"
BINDINGS["MSENSE_MAIN_DOWN"] = "DOWN"
BINDINGS["MSENSE_MAIN_LEFT"] = "LEFT"
BINDINGS["MSENSE_MAIN_RIGHT"] = "RIGHT"
BINDINGS["MSENSE_MAIN_SELECT"] = "RETURN"

BINDINGS["MSENSE_REFRESH"] = "r"
