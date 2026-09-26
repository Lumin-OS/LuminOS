-- The LuminOS live session's Hyprland config. It's the live user's own,
-- so none of it reaches an installed system: an offline install deletes
-- the live user with its home, and installed systems get luminos-desktop's
-- defaults from /etc/skel.
--
-- Besides a minimal desktop, it starts Dawn, the installer, and keeps it
-- floating and centred at a fixed size. Started from here, Dawn inherits
-- the session's HYPRLAND_INSTANCE_SIGNATURE, which its Keyboard screen
-- needs to switch the session's layout.

local terminal = "alacritty"
local menu     = "rofi -show drun"
local mainMod  = "SUPER"

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

hl.config({
    input = {
        -- Dawn's Keyboard screen switches it to the layout being installed.
        kb_layout = "us",
    },
    misc = {
        -- The wallpaper below, not Hyprland's own.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
    -- Nothing should pop up over Dawn.
    ecosystem = {
        no_update_news   = true,
        no_donation_nag  = true,
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("swaybg --image /usr/share/wallpapers/temp.png --mode fill")
    -- Dawn checks once, as it starts, whether the repositories answer,
    -- and offers the Network screen and an offline install if not. So it
    -- waits until NetworkManager has brought up what it can (at most 30
    -- seconds), or a wired PC still getting its address looks offline.
    hl.exec_cmd("nm-online --wait-for-startup --quiet --timeout=30; dawn")
end)

-- Hyprland matches Dawn's Wayland app_id as its class. The size is the
-- preferred one Dawn's main window asks for.
hl.window_rule({
    name   = "dawn",
    match  = { class = "^luminos-dawn$" },
    float  = true,
    center = true,
    size   = "820 620",
})

hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("dawn"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))

hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

for i = 1, 10 do
    local key = i % 10 -- 10 is on the 0 key
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
