-- ============================================================
--  CYBERPUNK ENERGY HUD  |  Basalt  |  ComputerCraft 1.20.1
--  Monitors: monitor_24 (left), monitor_22 (center), monitor_25 (floor)
--  Data source: modem ch.99 + meBridge_1
-- ============================================================

local basalt = require("basalt")

-- ============================================================
--  Russian charset (KOI-8 style mapping for CC fonts)
-- ============================================================
local RUS = {
    ["\192"]="A",["\193"]="B",["\194"]="V",["\195"]="G",
    ["\196"]="D",["\197"]="E",["\198"]="Zh",["\199"]="Z",
    ["\200"]="I",["\201"]="J",["\202"]="K",["\203"]="L",
    ["\204"]="M",["\205"]="N",["\206"]="O",["\207"]="P",
    ["\208"]="R",["\209"]="S",["\210"]="T",["\211"]="U",
    ["\212"]="F",["\213"]="Kh",["\214"]="Ts",["\215"]="Ch",
    ["\216"]="Sh",["\217"]="Shch",["\218"]="'",["\219"]="Y",
    ["\220"]="'",["\221"]="E",["\222"]="Yu",["\223"]="Ya",
    ["\224"]="a",["\225"]="b",["\226"]="v",["\227"]="g",
    ["\228"]="d",["\229"]="e",["\230"]="zh",["\231"]="z",
    ["\232"]="i",["\233"]="j",["\234"]="k",["\235"]="l",
    ["\236"]="m",["\237"]="n",["\238"]="o",["\239"]="p",
    ["\240"]="r",["\241"]="s",["\242"]="t",["\243"]="u",
    ["\244"]="f",["\245"]="kh",["\246"]="ts",["\247"]="ch",
    ["\248"]="sh",["\249"]="shch",["\250"]="'",["\251"]="y",
    ["\252"]="'",["\253"]="e",["\254"]="yu",["\255"]="ya",
}

local function rus(text)
    return (text:gsub("[\192-\255]", function(c) return RUS[c] or c end))
end

-- ============================================================
--  Shared state
-- ============================================================
local data = {
    energyCore     = { stored=0, max=1, transferRate=0 },
    fissionReactor = { active=false, temperature=0, damage=0, burnRate=0, fuelFilled=0 },
    fusionReactor  = { caseTemp=0, plasmaTemp=0, ignited=false, productionRate=0 },
    boiler         = { temperature=0, water=0, steam=0, boilRate=0, maxBoilRate=1 },
    turbines       = {},
    sps            = { inputRate=0, outputRate=0 },
    chemTank       = { stored=0, max=1, gas="N/A" },
    tick           = 0,
}

local meData = {
    antimatter = 0,
    deuterium  = 0,
    tritium    = 0,
}

local transferHistory = {}  -- ring buffer for graph
local MAX_HISTORY = 40
local alertActive = false
local blinkState  = false
local animDots    = { ".", "..", "..." }
local animIdx     = 1

-- ============================================================
--  Helpers
-- ============================================================
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t)    return a + (b - a) * t end

local function energyPct()
    if data.energyCore.max <= 0 then return 0 end
    return data.energyCore.stored / data.energyCore.max
end

local function fmtBig(n)
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9  then return string.format("%.2fG", n/1e9)
    elseif n >= 1e6  then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3  then return string.format("%.1fK", n/1e3)
    else return tostring(math.floor(n)) end
end

local function fmtTemp(t) return string.format("%.1f", t) end

local function pushHistory(val)
    table.insert(transferHistory, val)
    if #transferHistory > MAX_HISTORY then
        table.remove(transferHistory, 1)
    end
end

-- ============================================================
--  Peripherals
-- ============================================================
local modem    = peripheral.find("modem")
local meBridge = peripheral.wrap("meBridge_1")

local monLeft   = peripheral.wrap("monitor_24")
local monCenter = peripheral.wrap("monitor_22")
local monFloor  = peripheral.wrap("monitor_25")

for _, m in ipairs({monLeft, monCenter, monFloor}) do
    if m then
        m.setTextScale(0.5)
        m.setBackgroundColor(colors.black)
        m.clear()
    end
end

if modem then
    modem.open(99)
end

-- ============================================================
--  ME Bridge query
-- ============================================================
local function queryME()
    if not meBridge then return end
    local function getItem(name)
        local ok, res = pcall(function() return meBridge.getItem({name=name}) end)
        if ok and res then return res.amount or 0 end
        return 0
    end
    meData.antimatter = getItem("mekanism:antimatter")
    meData.deuterium  = getItem("mekanism:deuterium")
    meData.tritium    = getItem("mekanism:tritium")
end

-- ============================================================
--  Low-level drawing helpers (direct monitor API, no Basalt)
--  Basalt is used for the alert overlay only.
-- ============================================================

local function drawBox(mon, x, y, w, h, fg, bg, label)
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fg or colors.cyan)
    -- top
    mon.setCursorPos(x, y)
    mon.write("\149" .. string.rep("\140", w-2) .. "\149")
    -- sides
    for row = y+1, y+h-2 do
        mon.setCursorPos(x, row);   mon.write("\149")
        mon.setCursorPos(x+w-1, row); mon.write("\149")
    end
    -- bottom
    mon.setCursorPos(x, y+h-1)
    mon.write("\149" .. string.rep("\140", w-2) .. "\149")
    -- label
    if label then
        mon.setCursorPos(x+2, y)
        mon.setBackgroundColor(bg or colors.black)
        mon.setTextColor(colors.yellow)
        mon.write("[ " .. label .. " ]")
    end
end

local function drawText(mon, x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    if bg  then mon.setBackgroundColor(bg) end
    if fg  then mon.setTextColor(fg) end
    mon.write(text)
end

local function drawBar(mon, x, y, w, pct, fgFull, fgEmpty, bg)
    local filled = math.floor(clamp(pct, 0, 1) * w)
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fgFull or colors.green)
    mon.write(string.rep("\127", filled))
    mon.setTextColor(fgEmpty or colors.gray)
    mon.write(string.rep("\127", w - filled))
end

local function drawVBar(mon, x, yTop, h, pct, fgFull, fgEmpty)
    local filled = math.floor(clamp(pct, 0, 1) * h)
    for row = 0, h-1 do
        mon.setCursorPos(x, yTop + (h-1-row))
        if row < filled then
            mon.setTextColor(fgFull or colors.cyan)
            mon.write("\127")
        else
            mon.setTextColor(fgEmpty or colors.gray)
            mon.write("|")
        end
    end
end

local function gridLines(mon, W, H, stepX, stepY)
    mon.setTextColor(colors.gray)
    mon.setBackgroundColor(colors.black)
    for col = stepX, W, stepX do
        for row = 1, H do
            mon.setCursorPos(col, row)
            mon.write("\183")
        end
    end
    for row = stepY, H, stepY do
        mon.setCursorPos(1, row)
        mon.write(string.rep("\196", W))
    end
end

-- ============================================================
--  ALERT SYSTEM
-- ============================================================
local alertFrameCenter, alertFrameLeft, alertFrameFloor

local function setupAlerts()
    -- We use raw monitor writes for alert (simpler than Basalt frames here)
end

local function triggerAlert(active)
    alertActive = active
    local function flashMonitor(mon)
        if not mon then return end
        if active then
            mon.setBackgroundColor(colors.red)
            mon.clear()
            local W, H = mon.getSize()
            mon.setTextColor(colors.white)
            local msg1 = "!!! " .. rus("\192\197\231\238\239\208\237\238\209\242\254") .. " !!!"
            local msg2 = rus("\206\225\237\224\240\243\230\229\237\232\229")
            local msg3 = rus("\246\229\235\238\241\242\237\238\241\242\232 \241\232\241\242\229\236\251")
            mon.setCursorPos(math.floor((W - #msg1)/2)+1, math.floor(H/2)-1)
            mon.write(msg1)
            mon.setCursorPos(math.floor((W - #msg2)/2)+1, math.floor(H/2))
            mon.write(msg2)
            mon.setCursorPos(math.floor((W - #msg3)/2)+1, math.floor(H/2)+1)
            mon.write(msg3)
        end
    end
    if active then
        flashMonitor(monLeft)
        flashMonitor(monCenter)
        flashMonitor(monFloor)
        if peripheral.find("speaker") then
            local spk = peripheral.find("speaker")
            pcall(function() spk.playNote("harp", 3, 24) end)
        end
    end
end

-- ============================================================
--  CENTER MONITOR (monitor_22)
--  Energy ring + transfer graph + ME resources
-- ============================================================

-- Arc ring drawn with text chars, approximating a circle
local ringChars = {
    [0]="\183",[1]="\183",[2]="\186",[3]="\186",[4]="\186",
    [5]="\186",[6]="\186",[7]="\183",[8]="\183",[9]="\183",
}

local function drawEnergyRing(mon, cx, cy, r, pct)
    -- Draw 16-step ring using trig
    local steps = 32
    for i = 0, steps-1 do
        local angle = (i / steps) * math.pi * 2 - math.pi/2
        local px = math.floor(cx + r * math.cos(angle) * 2 + 0.5)
        local py = math.floor(cy + r * math.sin(angle) + 0.5)
        local filled = (i / steps) <= pct
        mon.setCursorPos(px, py)
        if filled then
            mon.setTextColor(colors.cyan)
            mon.setBackgroundColor(colors.blue)
        else
            mon.setTextColor(colors.gray)
            mon.setBackgroundColor(colors.black)
        end
        mon.write("\127")
    end
end

local function drawTransferGraph(mon, x, y, w, h)
    mon.setBackgroundColor(colors.black)
    -- frame
    drawBox(mon, x, y, w, h, colors.cyan, colors.black, "TRANSFER/t")
    local maxVal = 1
    for _, v in ipairs(transferHistory) do
        if math.abs(v) > maxVal then maxVal = math.abs(v) end
    end
    local graphW = w - 2
    local graphH = h - 2
    local midY = y + 1 + math.floor(graphH / 2)
    -- zero line
    mon.setTextColor(colors.gray)
    for col = x+1, x+w-2 do
        mon.setCursorPos(col, midY)
        mon.write("\196")
    end
    -- data
    local startIdx = math.max(1, #transferHistory - graphW + 1)
    for i = startIdx, #transferHistory do
        local val = transferHistory[i]
        local col = x + 1 + (i - startIdx)
        local norm = val / maxVal
        local barH = math.abs(math.floor(norm * (graphH/2)))
        if val >= 0 then
            mon.setTextColor(colors.green)
            for row = 0, barH-1 do
                mon.setCursorPos(col, midY - row)
                mon.write("\127")
            end
        else
            mon.setTextColor(colors.red)
            for row = 0, barH-1 do
                mon.setCursorPos(col, midY + row)
                mon.write("\127")
            end
        end
    end
    -- current value label
    local cur = transferHistory[#transferHistory] or 0
    local curStr = (cur >= 0 and "+" or "") .. fmtBig(cur) .. "/t"
    drawText(mon, x+2, y+1, curStr, cur >= 0 and colors.green or colors.red, colors.black)
end

local function drawMESection(mon, x, y, w)
    drawBox(mon, x, y, w, 8, colors.cyan, colors.black, rus("\202\240\232\242\232\247\229\241\234\232\229 \240\229\241\243\240\241\251"))
    local items = {
        { name="Antimatter", val=meData.antimatter, max=1e6,  col=colors.magenta },
        { name="Deuterium",  val=meData.deuterium,  max=1e7,  col=colors.cyan    },
        { name="Tritium",    val=meData.tritium,    max=1e7,  col=colors.lime    },
    }
    for i, item in ipairs(items) do
        local row = y + 1 + (i-1)*2
        drawText(mon, x+2, row, item.name .. ":", colors.yellow, colors.black)
        drawText(mon, x+2+#item.name+2, row, fmtBig(item.val), item.col, colors.black)
        local pct = clamp(item.val / item.max, 0, 1)
        drawBar(mon, x+2, row+1, w-4, pct, item.col, colors.gray, colors.black)
    end
end

local function renderCenter()
    local mon = monCenter
    if not mon then return end
    local W, H = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    gridLines(mon, W, H, 8, 4)

    -- Title
    drawText(mon, 2, 1, rus("\255\196\208\206 \255\206\224\228\240\238"), colors.cyan, colors.black)
    drawText(mon, W-8, 1, string.format("%02d:%02d", math.floor(os.clock()/60), math.floor(os.clock())%60), colors.gray, colors.black)

    local pct = energyPct()
    local cx = math.floor(W * 0.35)
    local cy = math.floor(H * 0.42)
    local r  = math.min(cx, cy) - 3

    -- Energy ring
    drawEnergyRing(mon, cx, cy, r, pct)

    -- Center text inside ring
    local pctStr = string.format("%d%%", math.floor(pct * 100))
    drawText(mon, cx - math.floor(#pctStr/2), cy - 1, pctStr, colors.white, colors.black)
    drawText(mon, cx - 3, cy, fmtBig(data.energyCore.stored), colors.cyan, colors.black)
    local blinkChar = blinkState and "\4" or " "
    drawText(mon, cx, cy+1, blinkChar, colors.yellow, colors.black)

    -- Transfer graph right side
    local gx = cx + r*2 + 3
    local gw = W - gx - 1
    local gh = math.floor(H * 0.5)
    if gw > 8 then
        drawTransferGraph(mon, gx, 2, gw, gh)
    end

    -- ME section bottom
    local meY = math.floor(H * 0.65)
    drawMESection(mon, 2, meY, W - 3)

    -- SPS info
    drawText(mon, 2, H-2, "SPS in:" .. fmtBig(data.sps.inputRate) .. " out:" .. fmtBig(data.sps.outputRate), colors.purple, colors.black)
end

-- ============================================================
--  LEFT MONITOR (monitor_24)
--  Fission + Fusion + Boiler + Turbines
-- ============================================================

local noiseChars = {"\7","\4","\5","\6","\15","\24","\25","\26","\27"}

local function plasmaNoiseEffect(mon, cx, cy, r)
    if data.fusionReactor.plasmaTemp <= 0 then return end
    for _ = 1, 4 do
        local angle = math.random() * math.pi * 2
        local dist  = math.random(1, r)
        local px = cx + math.floor(dist * math.cos(angle) * 2)
        local py = cy + math.floor(dist * math.sin(angle))
        local nc = noiseChars[math.random(#noiseChars)]
        mon.setCursorPos(px, py)
        mon.setTextColor(colors.orange)
        mon.setBackgroundColor(colors.black)
        mon.write(nc)
    end
end

local function drawFissionPanel(mon, x, y, w, h)
    local fr = data.fissionReactor
    local borderCol = fr.active and colors.green or colors.gray
    drawBox(mon, x, y, w, h, borderCol, colors.black, "FISSION REACTOR")

    local row = y + 1
    -- Status
    local statusStr = fr.active and "[ACTIVE]" or "[OFFLINE]"
    drawText(mon, x+2, row, "Status: " .. statusStr, fr.active and colors.lime or colors.red, colors.black)
    row = row + 1

    -- Temperature
    local blink = blinkState and "\4" or "\5"
    drawText(mon, x+2, row, "Temp: " .. fmtTemp(fr.temperature) .. "K " .. blink, colors.orange, colors.black)
    row = row + 1

    -- Damage (blink red if > 0)
    local dmgCol = fr.damage > 0 and (blinkState and colors.red or colors.orange) or colors.lime
    drawText(mon, x+2, row, "Damage: " .. string.format("%.2f%%", fr.damage), dmgCol, colors.black)
    row = row + 1

    -- Burn rate with intensity bar
    drawText(mon, x+2, row, "Burn: " .. string.format("%.2f", fr.burnRate) .. "/t", colors.yellow, colors.black)
    row = row + 1
    drawBar(mon, x+2, row, w-4, clamp(fr.burnRate/10, 0, 1), colors.red, colors.gray, colors.black)
    row = row + 1

    -- Fuel
    drawText(mon, x+2, row, "Fuel: " .. string.format("%.1f%%", fr.fuelFilled*100), colors.cyan, colors.black)
    drawBar(mon, x+2, row+1, w-4, fr.fuelFilled, colors.yellow, colors.gray, colors.black)
end

local function drawFusionPanel(mon, x, y, w, h)
    local fu = data.fusionReactor
    local borderCol = fu.ignited and colors.orange or colors.gray
    drawBox(mon, x, y, w, h, borderCol, colors.black, "FUSION REACTOR")

    local row = y + 1
    local statusStr = fu.ignited and "[IGNITED]" or "[COLD]"
    drawText(mon, x+2, row, statusStr, fu.ignited and colors.orange or colors.cyan, colors.black)
    row = row + 1

    drawText(mon, x+2, row, "Plasma: " .. fmtBig(fu.plasmaTemp) .. "K", colors.red, colors.black)
    row = row + 1
    drawText(mon, x+2, row, "Case:   " .. fmtBig(fu.caseTemp)   .. "K", colors.orange, colors.black)
    row = row + 1
    drawText(mon, x+2, row, "Output: " .. fmtBig(fu.productionRate), colors.lime, colors.black)
    row = row + 1

    -- Plasma noise effect
    if fu.plasmaTemp > 0 then
        local cx = x + math.floor(w/2)
        local cy = y + math.floor(h/2) + 1
        plasmaNoiseEffect(mon, cx, cy, math.floor(math.min(w,h)/4))
    end
end

local function drawBoilerPanel(mon, x, y, w, h)
    local bo = data.boiler
    drawBox(mon, x, y, w, h, colors.blue, colors.black, "BOILER")

    local row = y + 1
    drawText(mon, x+2, row, "Temp:  " .. fmtTemp(bo.temperature) .. "K", colors.cyan, colors.black)
    row = row + 1
    drawText(mon, x+2, row, "Water: " .. fmtBig(bo.water) .. " mB", colors.blue, colors.black)
    row = row + 1
    drawText(mon, x+2, row, "Steam: " .. fmtBig(bo.steam) .. " mB", colors.white, colors.black)
    row = row + 1
    local maxB = math.max(bo.maxBoilRate, 1)
    drawText(mon, x+2, row, "Boil:  " .. fmtBig(bo.boilRate) .. "/" .. fmtBig(bo.maxBoilRate), colors.orange, colors.black)
    drawBar(mon, x+2, row+1, w-4, clamp(bo.boilRate/maxB, 0, 1), colors.orange, colors.gray, colors.black)
end

local function drawTurbinePanel(mon, x, y, w, h)
    drawBox(mon, x, y, w, h, colors.cyan, colors.black, "TURBINES")
    local turbCount = math.max(#data.turbines, 1)
    local colW = math.floor((w-2) / turbCount)

    for i, turb in ipairs(data.turbines) do
        local tx = x + 1 + (i-1)*colW
        local maxFlow = math.max(turb.maxSteamFlow, 1)
        local pct = clamp(turb.steamFlow / maxFlow, 0, 1)

        -- Vertical steam bar
        local barH = h - 5
        drawVBar(mon, tx + math.floor(colW/2), y+2, barH, pct, colors.cyan, colors.gray)

        -- Label
        drawText(mon, tx, y+h-3, string.format("T%d", i), colors.yellow, colors.black)
        drawText(mon, tx, y+h-2, fmtBig(turb.steamFlow), colors.cyan, colors.black)
        drawText(mon, tx, y+h-1, fmtBig(turb.production), colors.lime, colors.black)
    end

    -- Header labels
    drawText(mon, x+2, y+h-3, "         STEAM   PWR", colors.gray, colors.black)
end

local function renderLeft()
    local mon = monLeft
    if not mon then return end
    local W, H = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    gridLines(mon, W, H, 6, 3)

    drawText(mon, 2, 1, rus("\210\229\235\229\236\229\242\240\232\255 \240\229\224\234\242\238\240\238\226"), colors.cyan, colors.black)

    local halfH    = math.floor(H / 2)
    local halfW    = math.floor(W / 2)
    local panelH   = halfH - 2

    drawFissionPanel(mon, 1,       3,        halfW,   panelH)
    drawFusionPanel (mon, halfW+1, 3,        W-halfW, panelH)
    drawBoilerPanel (mon, 1,       halfH+1,  halfW,   panelH-2)
    drawTurbinePanel(mon, halfW+1, halfH+1,  W-halfW, panelH-2)

    -- Bottom status bar
    drawText(mon, 2, H, animDots[animIdx] .. " LIVE", colors.green, colors.black)
end

-- ============================================================
--  FLOOR MONITOR (monitor_25)
--  Interactive base map with animated energy lines
-- ============================================================

local dotPos = 0  -- animation ticker

local function drawMapLine(mon, x1, y1, x2, y2, col)
    -- Bresenham line
    local dx = math.abs(x2-x1)
    local dy = math.abs(y2-y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy
    local x, y = x1, y1
    mon.setTextColor(col or colors.gray)
    mon.setBackgroundColor(colors.black)
    while true do
        mon.setCursorPos(x, y)
        mon.write("\183")
        if x == x2 and y == y2 then break end
        local e2 = 2*err
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx  then err = err + dx; y = y + sy end
    end
end

local function drawAnimDot(mon, x1, y1, x2, y2, pct, col)
    local px = math.floor(x1 + (x2-x1)*pct)
    local py = math.floor(y1 + (y2-y1)*pct)
    if px >= 1 and py >= 1 then
        mon.setCursorPos(px, py)
        mon.setTextColor(col or colors.white)
        mon.setBackgroundColor(colors.black)
        mon.write("\4")
    end
end

local function drawSquare(mon, x, y, w, h, fg, bg, label)
    for row = y, y+h-1 do
        for col = x, x+w-1 do
            mon.setCursorPos(col, row)
            mon.setBackgroundColor(bg or colors.black)
            mon.setTextColor(fg or colors.white)
            mon.write(" ")
        end
    end
    if label then
        mon.setCursorPos(x + math.floor((w-#label)/2), y + math.floor(h/2))
        mon.setTextColor(fg or colors.white)
        mon.setBackgroundColor(bg or colors.black)
        mon.write(label)
    end
end

local function reactorColor(temp)
    if temp < 500  then return colors.green
    elseif temp < 1200 then return colors.yellow
    elseif temp < 3000 then return colors.orange
    else return colors.red end
end

local function renderFloor()
    local mon = monFloor
    if not mon then return end
    local W, H = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    gridLines(mon, W, H, 10, 5)

    -- Title
    drawText(mon, 2, 1, rus("\202\224\240\242\224 \225\224\231\251"), colors.cyan, colors.black)

    -- Platform outline
    local padX, padY = 3, 3
    local padW, padH = W-4, H-4
    drawBox(mon, padX, padY, padW, padH, colors.blue, colors.black, nil)

    -- Sector dividers
    local midX = padX + math.floor(padW/2)
    local midY = padY + math.floor(padH/2)
    for row = padY+1, padY+padH-2 do
        mon.setCursorPos(midX, row)
        mon.setTextColor(colors.gray)
        mon.write("\179")
    end
    for col = padX+1, padX+padW-2 do
        mon.setCursorPos(col, midY)
        mon.setTextColor(colors.gray)
        mon.write("\196")
    end

    -- Energy core (center) — brightness depends on charge
    local pct = energyPct()
    local coreCol = pct > 0.6 and colors.blue or (pct > 0.2 and colors.cyan or colors.gray)
    local coreBg  = pct > 0.8 and colors.blue or colors.black
    local coreCX  = midX - 4
    local coreCY  = midY - 2
    drawSquare(mon, coreCX, coreCY, 8, 4, colors.white, coreBg, "CORE")
    drawText(mon, coreCX+1, coreCY+2, string.format("%d%%", math.floor(pct*100)), coreCol, coreBg)

    -- Fission reactor (top-right quadrant)
    local frTemp = data.fissionReactor.temperature
    local frCol  = reactorColor(frTemp)
    local frX, frY = padX + padW - 12, padY + 2
    drawSquare(mon, frX, frY, 8, 3, colors.black, frCol, "FISS")
    drawText(mon, frX+1, frY+2, fmtBig(frTemp), colors.white, frCol)

    -- Fusion reactor (top-left quadrant)
    local fuTemp = data.fusionReactor.caseTemp
    local fuCol  = reactorColor(fuTemp)
    local fuX, fuY = padX + 2, padY + 2
    drawSquare(mon, fuX, fuY, 8, 3, colors.black, fuCol, "FUSI")
    drawText(mon, fuX+1, fuY+2, fmtBig(fuTemp), colors.white, fuCol)

    -- Boiler (bottom-left)
    local boX, boY = padX + 2, padY + padH - 6
    drawSquare(mon, boX, boY, 8, 3, colors.white, colors.blue, "BOIL")

    -- Turbines (bottom-right)
    for i = 1, math.min(#data.turbines, 3) do
        local tX = padX + padW - 10 + (i-1)*3
        local tY = padY + padH - 5
        drawSquare(mon, tX, tY, 2, 2, colors.black, colors.cyan, "T")
    end

    -- ---- Animated connection lines ----
    local coreAnchorX = coreCX + 4
    local coreAnchorY = coreCY + 2

    -- Core <-> Fission
    drawMapLine(mon, coreAnchorX, coreAnchorY, frX, frY+1, colors.gray)
    local dp1 = ((dotPos % 20) / 20)
    drawAnimDot(mon, coreAnchorX, coreAnchorY, frX, frY+1, dp1, colors.yellow)

    -- Core <-> Fusion
    drawMapLine(mon, coreAnchorX, coreAnchorY, fuX+8, fuY+1, colors.gray)
    local dp2 = (((dotPos+7) % 20) / 20)
    drawAnimDot(mon, coreAnchorX, coreAnchorY, fuX+8, fuY+1, dp2, colors.orange)

    -- Boiler -> Core
    drawMapLine(mon, boX+4, boY, coreAnchorX, coreAnchorY, colors.gray)
    local dp3 = (((dotPos+13) % 20) / 20)
    drawAnimDot(mon, boX+4, boY, coreAnchorX, coreAnchorY, dp3, colors.cyan)

    -- Legend
    drawText(mon, padX+1, padY+padH-1, "[G]=ok [Y]=warn [R]=crit", colors.gray, colors.black)

    -- SPS bottom
    drawText(mon, 2, H, "SPS: " .. fmtBig(data.sps.outputRate) .. "/t", colors.purple, colors.black)
end

-- ============================================================
--  Main render & update loop
-- ============================================================

local function renderAll()
    if alertActive then return end
    renderCenter()
    renderLeft()
    renderFloor()
end

local function updateData(rawData)
    if type(rawData) ~= "table" then return end
    if rawData.energyCore     then data.energyCore     = rawData.energyCore     end
    if rawData.fissionReactor then data.fissionReactor = rawData.fissionReactor end
    if rawData.fusionReactor  then data.fusionReactor  = rawData.fusionReactor  end
    if rawData.boiler         then data.boiler         = rawData.boiler         end
    if rawData.turbines       then data.turbines       = rawData.turbines       end
    if rawData.sps            then data.sps            = rawData.sps            end
    if rawData.chemTank       then data.chemTank       = rawData.chemTank       end
    if rawData.tick           then data.tick           = rawData.tick           end
end

local function checkAlerts()
    local dmg = data.fissionReactor.damage or 0
    local pct = energyPct()
    local shouldAlert = (dmg > 0) or (pct < 0.05)
    if shouldAlert ~= alertActive then
        triggerAlert(shouldAlert)
    end
end

-- Modem listener (coroutine)
local function modemLoop()
    while true do
        local event, side, ch, rch, msg = os.pullEvent("modem_message")
        if ch == 99 and type(msg) == "table" then
            updateData(msg)
        end
    end
end

-- Tick loop (coroutine)
local function tickLoop()
    while true do
        blinkState  = not blinkState
        animIdx     = (animIdx % #animDots) + 1
        dotPos      = dotPos + 1

        pushHistory(data.energyCore.transferRate or 0)
        queryME()
        checkAlerts()
        renderAll()

        os.sleep(0.5)
    end
end

-- ============================================================
--  Boot
-- ============================================================

print("CYBERPUNK HUD  |  Starting...")
print("Monitors: L=monitor_24  C=monitor_22  F=monitor_25")
print("Modem ch: 99  |  ME: meBridge_1")
print("Press Ctrl+T to terminate.")

parallel.waitForAny(modemLoop, tickLoop)
