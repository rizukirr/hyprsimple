-- Environment and ecosystem settings hyprsimple owns. These were in vars.lua,
-- which is now a user-overridable module, so they moved here where changing
-- them reaches everyone.

-- There was an hl.env("XCOMPOSEFILE", "$HOME/.XCompose") here. Nothing in
-- hyprsimple creates that file: upstream writes one in its own install step,
-- and only the environment variable was carried over.
--
-- The variable was redundant even when the file does exist. man 5 Compose gives
-- the search order as $XCOMPOSEFILE, then ~/.XCompose, then the locale's
-- system compose file, so ~/.XCompose is already found without being named.
-- Pointing the first rule at a file that is not there is what stops the third
-- rule from being reached.
--
-- Nothing binds a compose key either: input.lua leaves kb_options empty, so no
-- key produces Multi_key. Someone who wants compose sequences writes
-- ~/.XCompose and sets kb_options, and both work without this line.

hl.config({
  xwayland = {
    force_zero_scaling = true,
  },
  ecosystem = {
    no_update_news = true,
  },
})
