-- https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "",
    kb_model = "",
    kb_options = "",
    kb_rules = "",

    follow_mouse = 1,
    -- force_no_accel = 1,

    sensitivity = 0, -- -1.0 to 1.0, 0 = no modification.

    touchpad = {
      natural_scroll = true,
    },
  },
})

-- Gestures (currently disabled; uncomment to enable workspace swipe)
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Per-device tweak (preserved from input.conf)
hl.device({
  name = "epic-mouse-v1",
  sensitivity = -0.5,
})
