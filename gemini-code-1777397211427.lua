local monitor = peripheral.find("monitor")
monitor.setTextScale(0.5)
local w, h = monitor.getSize()

local frames = {
    {
        "  00 00  ",
        " 0000000 ",
        " 0000000 ",
        "  00000  ",
        "   000   ",
        "    0    "
    },
    {
        "         ",
        "   0 0   ",
        "  00000  ",
        "   000   ",
        "    0    ",
        "         "
    }
}

local function drawFrame(frame)
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    for y, line in ipairs(frame) do
        for x = 1, #line do
            if line:sub(x, x) == "0" then
                monitor.setCursorPos(x + math.floor((w-#line)/2), y + math.floor((h-#frame)/2))
                monitor.setBackgroundColor(colors.red)
                monitor.write(" ")
            end
        end
    end
end

while true do
    for _, frame in ipairs(frames) do
        drawFrame(frame)
        sleep(0.5)
    end
end