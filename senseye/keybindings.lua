--
-- Default keybindings for most features.
-- These should be kept short and sweet and for only the most common
-- things, and then let the different menu paths be bindable instead.
--

BINDINGS = {}
BINDINGS["META"]          = "LSHIFT"
BINDINGS["META_DETAIL"]   = "z" -- update position and motion markers

-- window-shared
BINDINGS["ZOOM"]          = "F3" -- + META zooms out
BINDINGS["RESIZE_X2"]     = "F2" -- + META shrinks
BINDINGS["PLAYPAUSE"]     = " "
BINDINGS["SELECT"]        = "RETURN"
BINDINGS["DESTROY"]       = "BACKSPACE" -- requires meta
BINDINGS["MODE_TOGGLE"]   = "c"
BINDINGS["CYCLE_MAPPING"] = "m"
BINDINGS["TRANSLATORS"]   = "t" -- requires meta
-- BINDINGS["HELPERS"]       = "x" -- for aligning zoom properly
BINDINGS["POPUP"]         = "TAB" -- meta cycles selected window
BINDINGS["FORWARD"]       = "RIGHT"
BINDINGS["BACKWARD"]      = "LEFT"

BINDINGS["CANCEL"]        = "ESCAPE"

-- 3d model based windows
BINDINGS["TOGGLE_3DSPIN"]  = " " -- model automatically spins around y
BINDINGS["TOGGLE_3DMOUSE"] = "m" -- change click/drag from rotate to move
BINDINGS["STEP_FORWARD"]   = "w"
BINDINGS["STEP_BACKWARD"]  = "s"
BINDINGS["STRAFE_LEFT"]    = "a"
BINDINGS["STRAFE_RIGHT"]   = "d"
BINDINGS["POINTSZ_INC"]   = "p"
BINDINGS["POINTSZ_DEC"]   = "o"

-- pattern finder
BINDINGS["PFIND_INC"] = "RIGHT" -- increase match threshold
BINDINGS["PFIND_DEC"] = "LEFT"  -- decrease match threshold

-- picture tuner
BINDINGS["AUTOTUNE"] = "a"

-- sensor specific
BINDINGS["PSENSE_PLAY_TOGGLE"] = " "
BINDINGS["PSENSE_STEP_FRAME"]  = "RIGHT"
