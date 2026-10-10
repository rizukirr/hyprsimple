-- Everything hyprsimple owns, loaded before the user's files so their settings
-- override on shared keys. Adding a module here reaches every user through
-- hyprsimple-update with no migration.
require("default.hypr.env")
require("default.hypr.input")
require("default.hypr.looknfeel")
require("default.hypr.windows")
require("default.hypr.bindings")
require("default.hypr.autostart")
