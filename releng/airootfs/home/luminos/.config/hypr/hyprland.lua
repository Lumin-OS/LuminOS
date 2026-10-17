-- Use the desktop installed by luminos-desktop, including its bar, apps
-- and wallpaper. Only Dawn's launcher and window rule are live-only.
package.path = "/etc/skel/.config/hypr/?.lua;" .. package.path
dofile("/etc/skel/.config/hypr/hyprland.lua")

hl.config({ ecosystem = { no_donation_nag = true, no_update_news = true } })
hl.window_rule({
    name = "dawn",
    match = { class = "^luminos-dawn$" },
    float = true,
    center = true,
    size = "820 620",
})
hl.bind("SUPER + I", hl.dsp.exec_cmd("dawn"))
hl.on("hyprland.start", function()
    -- Give wired networking time to settle before Dawn's startup probe.
    hl.exec_cmd("nm-online --wait-for-startup --quiet --timeout=30; dawn")
end)
