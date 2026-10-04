-- Presentation only; recording and sharing controls remain with their apps.
local function applyStatus(status)
    if type(status) ~= "table" then
        barWidget.setText("Checking…")
        return
    end
    local color = "on_surface_variant"
    if status.tone == "recording" then color = "#ff5252"
    elseif status.tone == "sharing" then color = "#ffb74d"
    elseif status.tone == "error" then color = "error" end
    barWidget.setText(status.text)
    barWidget.setColor(color, "script")
    barWidget.setTooltip(status.tooltip or "")
end

applyStatus(noctalia.state.get("status"))
noctalia.state.watch("status", applyStatus)
