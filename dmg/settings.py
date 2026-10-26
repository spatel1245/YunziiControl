# dmgbuild settings: drag-to-Applications window for Yunzii Control.
import os
here = defines.get("here", ".")  # noqa: F821
app = defines.get("app", "/Applications/YunziiControl.app")  # noqa: F821 (provided by dmgbuild)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(here, "..", "AppIcon.icns")
background = os.path.join(here, "background.tiff")
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 120), (640, 428))
default_view = "icon-view"
arrange_by = None
icon_size = 112
text_size = 13
icon_locations = {"YunziiControl.app": (170, 200), "Applications": (470, 200)}
