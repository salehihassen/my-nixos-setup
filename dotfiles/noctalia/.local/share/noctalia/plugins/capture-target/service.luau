-- One query per second for the whole session, shared by every bar instance.
local command = [[node "${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}/noctalia/plugins/capture-target/status.mjs"]]
local pending = false

local function unavailable()
    noctalia.state.set("status", {
        text = "Capture ?",
        tone = "error",
        tooltip = "Could not check capture targets. Capture may still be running.",
    })
end

function update()
    noctalia.setUpdateInterval(1000)
    if pending then return end
    pending = true
    local started = noctalia.runAsync(command, function(result)
        pending = false
        if result.exitCode ~= 0 then unavailable(); return end
        local ok, status = pcall(noctalia.json.decode, result.stdout)
        if ok and type(status) == "table" and type(status.text) == "string" then
            noctalia.state.set("status", status)
        else
            unavailable()
        end
    end)
    if not started then pending = false; unavailable() end
end
