application = defines["application"]
background = defines["background"]
icon = defines["volume_icon"]

files = [(application, "Utter.app")]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    "Utter.app": (174, 250),
    "Applications": (506, 250),
}

window_rect = ((120, 120), (680, 440))
icon_size = 112
text_size = 13
label_pos = "bottom"
show_icon_preview = True

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
