-- ============================================================
--  CYBERPUNK ENERGY HUD  v2  |  ComputerCraft 1.20.1
--  monitor_24=LEFT  monitor_22=CENTER  monitor_25=FLOOR
--  Data: modem ch.99 + meBridge_1
-- ============================================================

-- ============================================================
--  State
-- ============================================================
local data = {
    energyCore     = { stored=0, max=1, transferRate=0 },
    fissionReactor = { active=false, temperature=0, damage=0,
                       burnRate=0, fuelFilled=0, heatCapacity=0 },
    fusionReactor  = { caseTemp=0, plasmaTemp=0, ignited=false, productionRate=0 },
    boiler         = { temperature=0, water=0, steam=0, boilRate=0, maxBoilRate=1 },
    turbines       = {},
    sps            = { inputRate=0, outputRate=0 },
    chemTank       = { stored=0, max=1, gas="N/A" },
    tick           = 0,
}
local meData       = { antimatter=0, deuterium=0, tritium=0 }
local history      = {}   -- transferRate ring-buffer
local MAX_HIST     = 50
local alertActive  = false
local dataReceived = false
local blink        = false
local dotPos       = 0
local frameCount   = 0

-- ============================================================
--  Helpers
-- ============================================================
local function clamp(v,a,b) return math.max(a, math.min(b, v)) end

local function energyPct()
    if (data.energyCore.max or 0) <= 0 then return 0 end
    return data.energyCore.stored / data.energyCore.max
end

local function fmtBig(n)
    n = n or 0
    if     n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9  then return string.format("%.2fG", n/1e9)
    elseif n >= 1e6  then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3  then return string.format("%.1fK", n/1e3)
    else                  return tostring(math.floor(n)) end
end

local function fmtPct(v) return string.format("%d%%", math.floor(clamp(v,0,1)*100)) end

local function pushHistory(v)
    table.insert(history, v)
    if #history > MAX_HIST then table.remove(history, 1) end
end

local function reactorColor(temp)
    if     temp < 400  then return colors.green
    elseif temp < 1000 then return colors.yellow
    elseif temp < 2500 then return colors.orange
    else                    return colors.red end
end

-- ============================================================
--  Peripherals
-- ============================================================
local modem    = peripheral.find("modem")
local meBridge
local ok, err = pcall(function() meBridge = peripheral.wrap("meBridge_1") end)

local monL = peripheral.wrap("monitor_24")
local monC = peripheral.wrap("monitor_22")
local monF = peripheral.wrap("monitor_25")

for _, m in ipairs({monL, monC, monF}) do
    if m then
        m.setTextScale(0.5)
        m.setBackgroundColor(colors.black)
        m.clear()
    end
end

if modem then modem.open(99) end

-- ============================================================
--  Low-level draw primitives
-- ============================================================
local function put(mon, x, y, text, fg, bg)
    if not mon then return end
    mon.setCursorPos(x, y)
    if bg  then mon.setBackgroundColor(bg)  end
    if fg  then mon.setTextColor(fg)        end
    mon.write(text)
end

-- Horizontal line with single char
local function hline(mon, x, y, w, ch, fg, bg)
    put(mon, x, y, string.rep(ch, w), fg, bg)
end

-- Box with clean corners (no ugly E artifacts - use spaces + borders)
-- Style A: thin line box  +---------+
local function box(mon, x, y, w, h, fg, title)
    fg = fg or colors.cyan
    local bg = colors.black
    -- corners + top
    put(mon, x,       y, "+", fg, bg)
    put(mon, x+1,     y, string.rep("-", w-2), fg, bg)
    put(mon, x+w-1,   y, "+", fg, bg)
    -- sides
    for r = y+1, y+h-2 do
        put(mon, x,     r, "|", fg, bg)
        put(mon, x+w-1, r, "|", fg, bg)
    end
    -- bottom
    put(mon, x,     y+h-1, "+", fg, bg)
    put(mon, x+1,   y+h-1, string.rep("-", w-2), fg, bg)
    put(mon, x+w-1, y+h-1, "+", fg, bg)
    -- title
    if title then
        local lbl = " " .. title .. " "
        put(mon, x+2, y, lbl, colors.yellow, bg)
    end
end

-- Filled rectangle with a character
local function fillRect(mon, x, y, w, h, ch, fg, bg)
    for r = y, y+h-1 do
        put(mon, x, r, string.rep(ch, w), fg, bg)
    end
end

-- Progress bar  [####----]
local function pbar(mon, x, y, w, pct, fg, bg)
    pct = clamp(pct, 0, 1)
    local filled = math.floor(pct * w)
    put(mon, x, y, string.rep("\127", filled), fg or colors.cyan, colors.black)
    put(mon, x+filled, y, string.rep("\127", w-filled), colors.gray, colors.black)
end

-- Vertical bar (bottom to top)
local function vbar(mon, x, yBot, h, pct, fg)
    pct = clamp(pct, 0, 1)
    local filled = math.floor(pct * h)
    for i = 0, h-1 do
        local row = yBot - i
        if i < filled then
            put(mon, x, row, "\127", fg or colors.cyan, colors.black)
        else
            put(mon, x, row, ":", colors.gray, colors.black)
        end
    end
end

-- Small labeled value on one line
local function kv(mon, x, y, key, val, kfg, vfg)
    put(mon, x, y, key, kfg or colors.gray, colors.black)
    put(mon, x + #key, y, val, vfg or colors.white, colors.black)
end

-- ============================================================
--  ME Bridge
-- ============================================================
local function queryME()
    if not meBridge then return end
    local function gi(name)
        local ok2, res = pcall(function() return meBridge.getItem({name=name}) end)
        if ok2 and res then return res.amount or 0 end
        return 0
    end
    meData.antimatter = gi("mekanism:antimatter")
    meData.deuterium  = gi("mekanism:deuterium")
    meData.tritium    = gi("mekanism:tritium")
end

-- ============================================================
--  ALERT
-- ============================================================
local function triggerAlert(active)
    alertActive = active
    if not active then return end
    local function flash(mon)
        if not mon then return end
        local W, H = mon.getSize()
        mon.setBackgroundColor(colors.red)
        mon.clear()
        local msgs = {
            "!!! CRITICAL ALERT !!!",
            "SYSTEM INTEGRITY VIOLATED",
            "CHECK FISSION / ENERGY CORE",
        }
        for i, m in ipairs(msgs) do
            local px = math.max(1, math.floor((W-#m)/2)+1)
            local py = math.floor(H/2) - 1 + (i-1)
            mon.setCursorPos(px, py)
            mon.setTextColor(i==1 and colors.yellow or colors.white)
            mon.setBackgroundColor(colors.red)
            mon.write(m)
        end
    end
    flash(monL); flash(monC); flash(monF)
    local spk = peripheral.find("speaker")
    if spk then pcall(function() spk.playNote("harp", 3, 18) end) end
end

local function checkAlerts()
    if not dataReceived then return end
    local dmg = data.fissionReactor.damage or 0
    local pct = energyPct()
    local should = (dmg > 0) or (pct < 0.05)
    if should ~= alertActive then triggerAlert(should) end
end

-- ============================================================
--  CENTER MONITOR (monitor_22)
--  Energy core ring + transfer graph + ME resources
-- ============================================================

-- Draw ring of N steps around cx,cy with radius r (char-space r*2 wide, r tall)
local function drawRing(mon, cx, cy, r, pct)
    local N = 24
    for i = 0, N-1 do
        local a  = (i/N)*math.pi*2 - math.pi/2
        local px = math.floor(cx + r*2*math.cos(a) + 0.5)
        local py = math.floor(cy + r  *math.sin(a) + 0.5)
        if px >= 1 and py >= 1 then
            mon.setCursorPos(px, py)
            if (i/N) <= pct then
                mon.setTextColor(colors.cyan)
                mon.setBackgroundColor(colors.blue)
                mon.write("O")
            else
                mon.setTextColor(colors.gray)
                mon.setBackgroundColor(colors.black)
                mon.write("o")
            end
        end
    end
end

local function drawGraph(mon, x, y, w, h)
    box(mon, x, y, w, h, colors.cyan, "TRANSFER/t")
    local maxV = 1
    for _, v in ipairs(history) do if math.abs(v) > maxV then maxV = math.abs(v) end end
    local gw = w - 2
    local gh = h - 2
    local mid = y + 1 + math.floor(gh/2)
    -- zero line
    for c = x+1, x+w-2 do
        put(mon, c, mid, "-", colors.gray, colors.black)
    end
    -- bars
    local start = math.max(1, #history - gw + 1)
    for i = start, #history do
        local v   = history[i]
        local col = x + 1 + (i - start)
        local norm = math.abs(v)/maxV
        local bh  = math.max(1, math.floor(norm * (gh/2)))
        local fg  = v >= 0 and colors.lime or colors.red
        if v >= 0 then
            for rr = 0, bh-1 do put(mon, col, mid-rr, "|", fg, colors.black) end
        else
            for rr = 0, bh-1 do put(mon, col, mid+rr, "|", fg, colors.black) end
        end
    end
    -- current label
    local cur = history[#history] or 0
    local sign = cur >= 0 and "+" or ""
    put(mon, x+2, y+1, sign..fmtBig(cur).."/t", cur>=0 and colors.lime or colors.red, colors.black)
end

local function renderCenter()
    local mon = monC
    if not mon then return end
    local W, H = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Header bar
    fillRect(mon, 1, 1, W, 1, " ", colors.black, colors.black)
    put(mon, 2, 1, "ENERGY CORE", colors.cyan, colors.black)
    put(mon, W-9, 1, os.date and os.date("!%H:%M:%S") or "00:00:00", colors.gray, colors.black)

    -- Decorative corner accents (no full grid - just corners)
    put(mon, 1,   1,   "/", colors.blue, colors.black)
    put(mon, W,   1,   "\\",colors.blue, colors.black)
    put(mon, 1,   H,   "\\",colors.blue, colors.black)
    put(mon, W,   H,   "/", colors.blue, colors.black)

    -- Ring
    local pct = energyPct()
    local cx  = math.floor(W * 0.28)
    local cy  = math.floor(H * 0.38)
    local r   = math.min(cx-2, math.floor(H*0.25))
    drawRing(mon, cx, cy, r, pct)

    -- Center stats
    local pctStr = fmtPct(pct)
    put(mon, cx - math.floor(#pctStr/2), cy-1, pctStr, colors.white, colors.black)
    local stored = fmtBig(data.energyCore.stored)
    put(mon, cx - math.floor(#stored/2), cy, stored, colors.cyan, colors.black)
    -- blink dot
    if blink then put(mon, cx, cy+1, "*", colors.yellow, colors.black) end

    -- Charge bar below ring
    local barY = cy + r + 2
    put(mon, 2, barY, "PWR", colors.gray, colors.black)
    pbar(mon, 6, barY, math.floor(W*0.45)-6, pct,
         pct > 0.5 and colors.cyan or (pct > 0.2 and colors.yellow or colors.red))

    -- Transfer rate big display
    local tr = data.energyCore.transferRate or 0
    local trStr = (tr >= 0 and "+" or "") .. fmtBig(tr) .. "/t"
    put(mon, 2, barY+1, "NET ", colors.gray, colors.black)
    put(mon, 6, barY+1, trStr, tr >= 0 and colors.lime or colors.red, colors.black)

    -- Graph (right side)
    local gx = math.floor(W*0.55)
    local gw = W - gx
    local gh = math.floor(H*0.45)
    if gw > 10 then drawGraph(mon, gx, 2, gw, gh) end

    -- Separator
    local sepY = math.floor(H*0.6)
    hline(mon, 1, sepY, W, "-", colors.blue, colors.black)
    put(mon, 3, sepY, "[ ME RESOURCES ]", colors.yellow, colors.black)

    -- ME resources
    local items = {
        { label="Antimatter", val=meData.antimatter, max=1e6,  fg=colors.magenta },
        { label="Deuterium",  val=meData.deuterium,  max=1e7,  fg=colors.cyan    },
        { label="Tritium",    val=meData.tritium,    max=1e7,  fg=colors.lime    },
    }
    for i, item in ipairs(items) do
        local ry = sepY + 1 + (i-1)*3
        put(mon, 2, ry, item.label, colors.gray, colors.black)
        put(mon, 2+#item.label+1, ry, fmtBig(item.val), item.fg, colors.black)
        pbar(mon, 2, ry+1, math.floor(W*0.4), clamp(item.val/item.max,0,1), item.fg)
        -- right side: SPS
        if i == 1 then
            kv(mon, gx, ry,   "SPS IN  ", fmtBig(data.sps.inputRate),  colors.gray, colors.purple)
            kv(mon, gx, ry+1, "SPS OUT ", fmtBig(data.sps.outputRate), colors.gray, colors.purple)
        end
    end

    -- Status footer
    if not dataReceived then
        local wStr = "[ WAITING FOR TRANSMITTER... ]"
        put(mon, math.floor((W-#wStr)/2)+1, H, wStr, colors.yellow, colors.black)
    else
        put(mon, 2, H, "LIVE #"..data.tick, colors.green, colors.black)
    end
end

-- ============================================================
--  LEFT MONITOR (monitor_24)
--  Fission | Fusion | Boiler | Turbines
-- ============================================================

local noisePool = {"+","x","*","~","^","`","'","."}
local function noiseAt(mon, x, y)
    if x < 1 or y < 1 then return end
    local nc = noisePool[math.random(#noisePool)]
    put(mon, x, y, nc, colors.orange, colors.black)
end

local function renderLeft()
    local mon = monL
    if not mon then return end
    local W, H = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Header
    put(mon, 2, 1, "REACTOR TELEMETRY", colors.cyan, colors.black)
    put(mon, W-7, 1, dataReceived and "* LIVE" or "* WAIT", dataReceived and colors.lime or colors.yellow, colors.black)

    local halfW  = math.floor(W/2)
    local topH   = math.floor(H*0.52)
    local botH   = H - topH - 1

    -- ---- FISSION (top-left) ----
    local fr = data.fissionReactor
    local frBorder = fr.active and colors.lime or colors.gray
    box(mon, 1, 2, halfW-1, topH, frBorder, "FISSION")

    local frow = 3
    local stStr = fr.active and "ACTIVE" or "OFFLINE"
    put(mon, 3, frow, "Status: ", colors.gray, colors.black)
    put(mon, 11, frow, stStr, fr.active and colors.lime or colors.red, colors.black)
    frow = frow + 1

    put(mon, 3, frow, "Temp:   ", colors.gray, colors.black)
    local tc = fr.temperature > 800 and colors.red or fr.temperature > 400 and colors.yellow or colors.cyan
    put(mon, 11, frow, string.format("%.0fK", fr.temperature), tc, colors.black)
    if blink then put(mon, 11+#string.format("%.0fK", fr.temperature)+1, frow, "!", tc, colors.black) end
    frow = frow + 1

    -- Damage - blink red if > 0
    put(mon, 3, frow, "Damage: ", colors.gray, colors.black)
    local dmgFg = (fr.damage > 0) and (blink and colors.red or colors.orange) or colors.lime
    put(mon, 11, frow, string.format("%.2f%%", fr.damage), dmgFg, colors.black)
    frow = frow + 1

    put(mon, 3, frow, "Burn:   ", colors.gray, colors.black)
    put(mon, 11, frow, string.format("%.2f/t", fr.burnRate), colors.yellow, colors.black)
    frow = frow + 1
    pbar(mon, 3, frow, halfW-5, clamp(fr.burnRate/10,0,1), colors.orange)
    frow = frow + 1

    put(mon, 3, frow, "Fuel:   ", colors.gray, colors.black)
    put(mon, 11, frow, fmtPct(fr.fuelFilled), colors.cyan, colors.black)
    frow = frow + 1
    pbar(mon, 3, frow, halfW-5, fr.fuelFilled, colors.yellow)

    -- ---- FUSION (top-right) ----
    local fu = data.fusionReactor
    local fuBorder = fu.ignited and colors.orange or colors.gray
    box(mon, halfW+1, 2, W-halfW, topH, fuBorder, "FUSION")

    local urow = 3
    put(mon, halfW+3, urow, fu.ignited and "IGNITED" or "COLD", fu.ignited and colors.orange or colors.cyan, colors.black)
    urow = urow + 1

    kv(mon, halfW+3, urow, "Plasma: ", fmtBig(fu.plasmaTemp).."K", colors.gray,
       fu.plasmaTemp > 0 and colors.red or colors.cyan)
    urow = urow + 1
    kv(mon, halfW+3, urow, "Case:   ", fmtBig(fu.caseTemp).."K", colors.gray, colors.orange)
    urow = urow + 1
    kv(mon, halfW+3, urow, "Output: ", fmtBig(fu.productionRate), colors.gray, colors.lime)
    urow = urow + 1

    -- Plasma noise effect
    if fu.plasmaTemp > 0 then
        local ncx = halfW + math.floor((W-halfW)/2)
        local ncy = urow + 2
        for _ = 1, 5 do
            noiseAt(mon, ncx + math.random(-4,4), ncy + math.random(-1,2))
        end
        put(mon, ncx-1, ncy, "~PLASMA~", colors.red, colors.black)
    end

    -- Separator
    local sepRow = topH + 2
    hline(mon, 1, sepRow, W, "-", colors.blue, colors.black)

    -- ---- BOILER (bottom-left) ----
    local bo = data.boiler
    box(mon, 1, sepRow+1, halfW-1, botH-1, colors.blue, "BOILER")

    local brow = sepRow + 2
    kv(mon, 3, brow,   "Temp:  ", string.format("%.0fK", bo.temperature), colors.gray, colors.cyan)
    brow = brow + 1
    kv(mon, 3, brow,   "Water: ", fmtBig(bo.water).."mB",  colors.gray, colors.blue)
    brow = brow + 1
    kv(mon, 3, brow,   "Steam: ", fmtBig(bo.steam).."mB",  colors.gray, colors.white)
    brow = brow + 1
    local maxB = math.max(bo.maxBoilRate, 1)
    kv(mon, 3, brow,   "Boil:  ", fmtBig(bo.boilRate).."/"..fmtBig(bo.maxBoilRate), colors.gray, colors.orange)
    brow = brow + 1
    pbar(mon, 3, brow, halfW-5, clamp(bo.boilRate/maxB,0,1), colors.orange)

    -- ---- TURBINES (bottom-right) ----
    box(mon, halfW+1, sepRow+1, W-halfW, botH-1, colors.cyan, "TURBINES")

    local turbCount = #data.turbines
    if turbCount == 0 then
        put(mon, halfW+3, sepRow+3, "No turbines", colors.gray, colors.black)
    else
        local colW = math.floor((W-halfW-2) / turbCount)
        local barH = botH - 6
        for i, turb in ipairs(data.turbines) do
            local tx  = halfW + 2 + (i-1)*colW
            local pct = clamp((turb.steamFlow or 0)/math.max(turb.maxSteamFlow or 1, 1), 0, 1)
            -- label
            put(mon, tx, sepRow+2, "T"..i, colors.yellow, colors.black)
            -- vertical bar
            vbar(mon, tx, sepRow + 2 + barH, barH, pct, colors.cyan)
            -- values below
            put(mon, tx, H-2, fmtBig(turb.steamFlow or 0), colors.cyan, colors.black)
            put(mon, tx, H-1, fmtBig(turb.production or 0), colors.lime, colors.black)
        end
        put(mon, halfW+3, H-3, "STEAM  PWR", colors.gray, colors.black)
    end
end

-- ============================================================
--  FLOOR MONITOR (monitor_25)
--  Beautiful static base map with live status overlays
-- ============================================================

-- Draw a labeled zone box
local function zoneBox(mon, x, y, w, h, fg, bg, label, sub)
    -- fill
    for r = y, y+h-1 do
        mon.setCursorPos(x, r)
        mon.setBackgroundColor(bg)
        mon.write(string.rep(" ", w))
    end
    -- border
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    mon.setCursorPos(x, y);     mon.write("+" .. string.rep("-", w-2) .. "+")
    for r = y+1, y+h-2 do
        mon.setCursorPos(x, r);     mon.write("|")
        mon.setCursorPos(x+w-1, r); mon.write("|")
    end
    mon.setCursorPos(x, y+h-1); mon.write("+" .. string.rep("-", w-2) .. "+")
    -- label
    if label then
        local lx = x + math.floor((w-#label)/2)
        mon.setCursorPos(lx, y + math.floor(h/2) - (sub and 1 or 0))
        mon.setBackgroundColor(bg)
        mon.setTextColor(fg)
        mon.write(label)
    end
    if sub then
        local sx = x + math.floor((w-#sub)/2)
        mon.setCursorPos(sx, y + math.floor(h/2))
        mon.setBackgroundColor(bg)
        mon.setTextColor(colors.white)
        mon.write(sub)
    end
end

-- Draw a pipe/cable line (horizontal or vertical)
local function pipe(mon, x1, y1, x2, y2, fg)
    mon.setTextColor(fg or colors.gray)
    mon.setBackgroundColor(colors.black)
    if y1 == y2 then
        -- horizontal
        local xA, xB = math.min(x1,x2), math.max(x1,x2)
        for c = xA, xB do
            mon.setCursorPos(c, y1)
            mon.write("=")
        end
    elseif x1 == x2 then
        -- vertical
        local yA, yB = math.min(y1,y2), math.max(y1,y2)
        for r = yA, yB do
            mon.setCursorPos(x1, r)
            mon.write(":")
        end
    end
end

-- Animated energy packet running along a line
local function energyDot(mon, x1, y1, x2, y2, phase, fg)
    local steps
    if y1 == y2 then
        steps = math.abs(x2-x1)+1
        local idx  = math.floor(phase * steps) % steps
        local px   = math.min(x1,x2) + idx
        put(mon, px, y1, ">", fg or colors.yellow, colors.black)
    else
        steps = math.abs(y2-y1)+1
        local idx  = math.floor(phase * steps) % steps
        local py   = math.min(y1,y2) + idx
        put(mon, x1, py, "v", fg or colors.yellow, colors.black)
    end
end

local function renderFloor()
    local mon = monF
    if not mon then return end
    local W, H = mon.getSize()
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- ---- Outer platform border ----
    mon.setTextColor(colors.blue)
    mon.setBackgroundColor(colors.black)
    mon.setCursorPos(1,1); mon.write("/" .. string.rep("=", W-2) .. "\\")
    for r = 2, H-1 do
        mon.setCursorPos(1,r); mon.write("|")
        mon.setCursorPos(W,r); mon.write("|")
    end
    mon.setCursorPos(1,H); mon.write("\\" .. string.rep("=", W-2) .. "/")

    -- Title
    put(mon, 3, 1, " BASE MAP v2.0 ", colors.cyan, colors.black)
    put(mon, W-12, 1, " SECTOR MAP ", colors.blue, colors.black)

    -- ---- Zone layout ----
    -- We lay out zones proportionally to W,H
    -- Center-left: Energy Core
    -- Top-right: Fission + Fusion side by side
    -- Bottom-left: Boiler
    -- Bottom-right: Turbines x2
    -- Far right: SPS
    -- Center: pipes

    local pct  = energyPct()
    local coreBg = pct > 0.7 and colors.blue or (pct > 0.3 and colors.cyan or colors.gray)
    local coreFg = colors.white

    -- Calculate zone positions
    local coreX = math.floor(W*0.38)
    local coreY = math.floor(H*0.35)
    local coreW = 10
    local coreH = 5

    local frTemp = data.fissionReactor.temperature
    local fuTemp = data.fusionReactor.caseTemp

    local fisX = math.floor(W*0.62)
    local fisY = math.floor(H*0.12)
    local fisW = 10
    local fisH = 4
    local fisBg = reactorColor(frTemp)
    local fisFg = colors.black

    local fuX = math.floor(W*0.77)
    local fuY = math.floor(H*0.12)
    local fuW = 10
    local fuH = 4
    local fuBg = reactorColor(fuTemp)
    local fuFg = colors.black

    local boX = math.floor(W*0.10)
    local boY = math.floor(H*0.62)
    local boW = 9
    local boH = 4

    local t1X = math.floor(W*0.55)
    local t1Y = math.floor(H*0.65)
    local t2X = math.floor(W*0.70)
    local t2Y = math.floor(H*0.65)
    local tW  = 8
    local tH  = 4

    local spsX = math.floor(W*0.87)
    local spsY = math.floor(H*0.38)
    local spsW = 8
    local spsH = 4

    -- ---- Draw pipes first (behind zones) ----
    -- Core <-> Fission (horizontal then vertical)
    local coreMX = coreX + coreW - 1
    local coreMY = coreY + math.floor(coreH/2)
    local fisMX  = fisX
    local fisMY  = fisY + math.floor(fisH/2)
    pipe(mon, coreMX, coreMY, fisMX, coreMY, colors.gray)   -- horizontal segment
    pipe(mon, fisMX,  coreMY, fisMX, fisMY,  colors.gray)   -- vertical segment

    -- Core <-> Fusion
    local fuMX = fuX
    local fuMY = fuY + math.floor(fuH/2)
    pipe(mon, coreMX+1, coreMY-1, fuMX, fuMY, colors.gray)

    -- Boiler -> Core (steam line)
    local boMX = boX + boW - 1
    local boMY = boY + math.floor(boH/2)
    pipe(mon, boMX, boMY, coreX, coreMY, colors.blue)

    -- Core -> Turbines (energy out)
    local t1MX = t1X + math.floor(tW/2)
    local t1MY = t1Y
    pipe(mon, coreX + math.floor(coreW/2), coreMY+math.floor(coreH/2), t1MX, t1MY, colors.cyan)

    local t2MX = t2X + math.floor(tW/2)
    pipe(mon, t1MX, t1MY, t2MX, t2MY, colors.cyan)

    -- Core -> SPS
    local spsMX = spsX
    local spsMY = spsY + math.floor(spsH/2)
    pipe(mon, coreMX, coreMY-1, spsMX, spsMY, colors.purple)

    -- ---- Animated dots on pipes ----
    local ph = (dotPos % 30) / 30
    energyDot(mon, coreMX, coreMY, fisX-1, coreMY, ph, colors.yellow)
    energyDot(mon, boMX, boMY, coreX, coreMY, (ph+0.4)%1, colors.cyan)
    energyDot(mon, coreX+math.floor(coreW/2), coreMY+2, t1MX, t1MY, (ph+0.2)%1, colors.lime)
    energyDot(mon, coreMX, coreMY-1, spsMX, spsMY, (ph+0.6)%1, colors.purple)

    -- ---- Draw zones on top ----
    -- Energy Core
    zoneBox(mon, coreX, coreY, coreW, coreH, coreFg, coreBg,
            "CORE", fmtPct(pct))

    -- Fission
    zoneBox(mon, fisX, fisY, fisW, fisH, fisFg, fisBg,
            "FISS", string.format("%.0fK",frTemp))

    -- Fusion
    zoneBox(mon, fuX, fuY, fuW, fuH, fuFg, fuBg,
            "FUSI", string.format("%.0fK",fuTemp))

    -- Boiler
    local boilPct = clamp((data.boiler.boilRate or 0)/math.max(data.boiler.maxBoilRate or 1,1),0,1)
    local boBg = boilPct > 0.7 and colors.orange or colors.blue
    zoneBox(mon, boX, boY, boW, boH, colors.white, boBg, "BOIL", fmtPct(boilPct))

    -- Turbines
    local function turbBg(idx)
        local t = data.turbines[idx]
        if not t then return colors.gray end
        local p = clamp((t.steamFlow or 0)/math.max(t.maxSteamFlow or 1,1),0,1)
        return p > 0.5 and colors.teal or colors.blue
    end
    zoneBox(mon, t1X, t1Y, tW, tH, colors.white, turbBg(1) or colors.gray, "TURB", "T1")
    zoneBox(mon, t2X, t2Y, tW, tH, colors.white, turbBg(2) or colors.gray, "TURB", "T2")

    -- SPS
    local spsOnline = (data.sps.outputRate or 0) > 0
    zoneBox(mon, spsX, spsY, spsW, spsH, colors.white,
            spsOnline and colors.purple or colors.gray, "SPS",
            fmtBig(data.sps.outputRate))

    -- ---- Legend (bottom strip) ----
    local ly = H - 1
    put(mon, 3,  ly, "[BLUE]=CORE ",  colors.blue,   colors.black)
    put(mon, 15, ly, "[GRN]=OK ",     colors.green,  colors.black)
    put(mon, 24, ly, "[YLW]=WARN ",   colors.yellow, colors.black)
    put(mon, 34, ly, "[RED]=CRIT ",   colors.red,    colors.black)
    put(mon, 44, ly, "[PRP]=SPS",     colors.purple, colors.black)

    -- Status
    if not dataReceived then
        put(mon, 3, H-2, ">> WAITING FOR DATA...", colors.yellow, colors.black)
    else
        put(mon, W-14, H-2, "TICK #"..data.tick, colors.green, colors.black)
    end
end

-- ============================================================
--  Data update
-- ============================================================
local function updateData(raw)
    if type(raw) ~= "table" then return end
    local function merge(dst, src)
        if type(src) ~= "table" then return end
        for k, v in pairs(src) do dst[k] = v end
    end
    merge(data.energyCore,     raw.energyCore)
    merge(data.fissionReactor, raw.fissionReactor)
    merge(data.fusionReactor,  raw.fusionReactor)
    merge(data.boiler,         raw.boiler)
    merge(data.sps,            raw.sps)
    merge(data.chemTank,       raw.chemTank)
    if type(raw.turbines) == "table" then
        data.turbines = raw.turbines
    end
    if raw.tick then data.tick = raw.tick end
end

-- ============================================================
--  Main loops
-- ============================================================
local function modemLoop()
    while true do
        local _, _, ch, _, msg = os.pullEvent("modem_message")
        if ch == 99 and type(msg) == "table" then
            updateData(msg)
            dataReceived = true
        end
    end
end

local function tickLoop()
    while true do
        frameCount = frameCount + 1
        blink   = not blink
        dotPos  = dotPos + 1
        animIdx = (frameCount % 3) + 1

        pushHistory(data.energyCore.transferRate or 0)
        queryME()
        checkAlerts()

        if not alertActive then
            local ok1 = pcall(renderCenter)
            local ok2 = pcall(renderLeft)
            local ok3 = pcall(renderFloor)
        end

        os.sleep(0.5)
    end
end

-- ============================================================
--  Boot
-- ============================================================
print("CYBERPUNK HUD v2  |  Starting...")
print("L=monitor_24  C=monitor_22  F=monitor_25")
print("Modem ch:99   ME:meBridge_1")
print("Ctrl+T to quit.")

parallel.waitForAny(modemLoop, tickLoop)
