local command = [[node "${XDG_DATA_HOME:-$HOME/.local/share}/noctalia/plugins/screen-recording-status/status.mjs"]]
local pending = false
local recording = false
local initialized = false

local function showError()
    recording = false
    barWidget.setGlyph("alert-triangle")
    barWidget.setText("Recording status unavailable")
    barWidget.setColor("error", "script")
    barWidget.setGlyphColor("error", "script")
    barWidget.setTooltip("Could not check wf-recorder. Use Super+Alt+R to stop/start recording.")
end

local function showStatus(recordings)
    recording = #recordings > 0
    if not recording then
        barWidget.setGlyph("video-off")
        barWidget.setText("Not recording")
        barWidget.setColor("on_surface_variant", "script")
        barWidget.setGlyphColor("on_surface_variant", "script")
        barWidget.setTooltip("No screen recording active. Super+Alt+R records the focused monitor.")
        return
    end

    local screens = {}
    local files = {}
    for _, item in ipairs(recordings) do
        table.insert(screens, item.screen)
        if item.file then table.insert(files, item.file) end
    end
    barWidget.setGlyph("player-record")
    barWidget.setText("REC · " .. table.concat(screens, ", "))
    barWidget.setColor("#ff5252", "script")
    barWidget.setGlyphColor("#ff5252", "script")
    barWidget.setTooltip("Recording: " .. table.concat(screens, ", ")
        .. "\n" .. table.concat(files, "\n")
        .. "\nClick here or press Super+Alt+R to stop and save.")
end

function update()
    noctalia.setUpdateInterval(1000)
    if not initialized then
        initialized = true
        barWidget.setGlyph("video")
        barWidget.setText("Checking recording…")
    end
    if pending then return end
    pending = true
    local started = noctalia.runAsync(command, function(result)
        pending = false
        if result.exitCode ~= 0 then
            showError()
            return
        end
        local ok, recordings = pcall(noctalia.json.decode, result.stdout)
        if ok and type(recordings) == "table" then
            showStatus(recordings)
        else
            showError()
        end
    end)
    if not started then
        pending = false
        showError()
    end
end

function onClick()
    if recording then
        noctalia.runAsync([[pkill -INT -u "$(id -u)" -x wf-recorder]])
    end
end
