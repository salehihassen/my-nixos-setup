-- One persistent stream for the session, shared by every bar instance.
-- Noctalia terminates this entire process group on reload or plugin disable.
-- Restart only after an unexpected monitor exit, with an explicit unknown state.
local command = [[while :; do
    "$HOME/.local/bin/capture-target-monitor"
    printf '%s\n' '{"text":"Capture ?","tone":"error","tooltip":"Capture monitor exited; retrying. Capture may still be running."}'
    sleep 5
done]]
local started = false

local function unavailable()
    noctalia.state.set("status", {
        text = "Capture ?",
        tone = "error",
        tooltip = "Could not check capture targets. Capture may still be running.",
    })
end

function update()
    -- The host requires an update interval; this tick only retries a failed
    -- initial launch. Successful streams publish changes without timer polling.
    noctalia.setUpdateInterval(60000)
    if started then return end
    started = noctalia.runStream(command, function(line)
        local ok, status = pcall(noctalia.json.decode, line)
        if ok and type(status) == "table" and type(status.text) == "string" then
            noctalia.state.set("status", status)
        else
            unavailable()
        end
    end)
    if not started then unavailable() end
end
