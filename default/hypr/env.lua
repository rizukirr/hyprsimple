-- Environment and ecosystem settings hyprsimple owns. These were in vars.lua,
-- which is now a user-overridable module, so they moved here where changing
-- them reaches everyone.

-- XCOMPOSE file used by GTK input methods
hl.env("XCOMPOSEFILE", os.getenv("HOME") .. "/.XCompose")

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },
  ecosystem = {
    no_update_news = true,
  },
})
