-- ========================================================================= --
-- OS: DRACONIC & MEKANISM TELEMETRY SYSTEM v3.0 (PRO)
-- ARCHITECTURE: EVENT-DRIVEN, MULTI-MONITOR, ASYNC NETWORKING
-- ========================================================================= --

local M_CORE_ID  = "monitor_8"
local M_REACT_ID = "monitor_9"
local M_PLANT_ID = "monitor_10"
local SCALE      = 0.5

local THEME = {
    bg      = colors.black,
    header  = colors.blue,
    border  = colors.cyan,
    ok      = colors.lime,
    warn    = colors.orange,
    bad     = colors.red,
    text    = colors.white,
    dim     = colors.lightGray,
    barBack = colors.gray,
    yellow  = colors.yellow,
    fusion  = colors.lightBlue,
    steam   = colors.white
}

-- Инициализация периферии
peripheral.find("modem", rednet.open)
local mCore = peripheral.wrap(M_CORE_ID)
local mReact = peripheral.wrap(M_REACT_ID)
local mPlant = peripheral.wrap(M_PLANT_ID)

if mCore then mCore.setTextScale(SCALE) end
if mReact then mReact.setTextScale(SCALE) end
if mPlant then mPlant.setTextScale(SCALE) end

-- Глобальный стейт данных (обновляется по Rednet)
local state = {
    core = { energy = 0, maxEnergy = 1, input = 0, output = 0 },
    plant = {
        f_temp = 0, f_burn = 0, f_status = false,
        fu_temp = 0, fu_active = false,
        b_steam = 0, b_maxSteam = 1, b_water = 0,
        t_flow = 0, anti_amount = 0, anti_rate = 0
    }
}

-- История для графиков
local graphData = {}
local GRAPH_HISTORY = 200
local graphMaxAbs = 1
local peakIn, peakOut = 0, 0

-- ========================================================================= --
-- БИБЛИОТЕКА ОТРИСОВКИ (Из оригинального кода + расширения)
-- ========================================================================= --

local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

local function formatNumber(n)
    local absn = math.abs(n)
    if absn >= 1e12 then return string.format("%.2f T", n / 1e12)
    elseif absn >= 1e9 then return string.format("%.2f G", n / 1e9)
    elseif absn >= 1e6 then return string.format("%.2f M", n / 1e6)
    elseif absn >= 1e3 then return string.format("%.2f K", n / 1e3)
    else return string.format("%.0f", n) end
end

local function formatTime(s)
    if s == math.huge or s < 0 then return "CALCULATING..." end
    if s > 86400 * 365 then return "> 1 YEAR" end
    local d = math.floor(s / 86400)
    local h = math.floor((s % 86400) / 3600)
    local m = math.floor((s % 3600) / 60)
    local sc = math.floor(s % 60)
    if d > 0 then return string.format("%dd %02d:%02d:%02d", d, h, m, sc) end
    return string.format("%02d:%02d:%02d", h, m, sc)
end

local function writeAt(mon, x, y, s, fg, bg)
    if bg then mon.setBackgroundColor(bg) end
    if fg then mon.setTextColor(fg) end
    mon.setCursorPos(x, y)
    mon.write(s)
end

local function fillRect(mon, x, y, w, h, bg)
    mon.setBackgroundColor(bg)
    local row = string.rep(" ", w)
    for dy = 0, h - 1 do
        mon.setCursorPos(x, y + dy)
        mon.write(row)
    end
end

local function drawBox(mon, x, y, w, h, borderColor, title)
    fillRect(mon, x, y, w, h, THEME.bg)
    fillRect(mon, x, y, w, 1, borderColor)
    fillRect(mon, x, y + h - 1, w, 1, borderColor)
    mon.setBackgroundColor(borderColor)
    for dy = 0, h - 1 do
        mon.setCursorPos(x, y + dy); mon.write(" ")
        mon.setCursorPos(x + w - 1, y + dy); mon.write(" ")
    end
    if title and #title > 0 then
        local t = " " .. title .. " "
        writeAt(mon, x + 2, y, t:sub(1, w - 4), THEME.text, THEME.bg)
    end
end

local function drawVerticalBar(mon, x, y, width, height, percent, color)
    percent = clamp(percent, 0, 100)
    local filled = math.floor(height * percent / 100 + 0.0001)
    fillRect(mon, x, y, width, height, THEME.barBack)
    mon.setBackgroundColor(color)
    local row = string.rep(" ", width)
    for i = 0, filled - 1 do
        mon.setCursorPos(x, y + height - 1 - i)
        mon.write(row)
    end
end

local function drawHorizBar(mon, x, y, w, percent, color, label, valStr)
    percent = clamp(percent, 0, 100)
    local fw = math.floor((w - 2) * (percent / 100))
    fillRect(mon, x, y, w, 1, THEME.bg)
    writeAt(mon, x, y, "[", THEME.dim, THEME.bg)
    writeAt(mon, x + w - 1, y, "]", THEME.dim, THEME.bg)
    if fw > 0 then fillRect(mon, x + 1, y, fw, 1, color) end
    
    if label then writeAt(mon, x, y - 1, label, THEME.dim, THEME.bg) end
    if valStr then writeAt(mon, x + w - #valStr, y - 1, valStr, THEME.text, THEME.bg) end
end

-- ========================================================================= --
-- ЛОГИКА ГРАФИКОВ (Зеркальный график для ядра)
-- ========================================================================= --

local function drawGraphBars(mon, gx, gy, gw, gh, data, maxAbs)
    maxAbs = math.max(maxAbs or 1, 1)
    local top, bot = gy, gy + gh - 1
    local mid = gy + math.floor(gh / 2)
    fillRect(mon, gx, gy, gw, gh, THEME.bg)
    
    mon.setBackgroundColor(THEME.dim)
    mon.setCursorPos(gx, mid)
    mon.write(string.rep(" ", gw))

    local upMax = mid - top
    local downMax = bot - mid
    local start = math.max(1, #data - gw + 1)

    for col = 1, gw do
        local v = data[start + col - 1] or 0
        local n = clamp(v / maxAbs, -1, 1)
        local x = gx + col - 1

        if n > 0 and upMax > 0 then
            local bh = math.max(1, math.ceil(n * upMax))
            mon.setBackgroundColor(THEME.ok)
            for k = 1, bh do mon.setCursorPos(x, mid - k); mon.write(" ") end
        elseif n < 0 and downMax > 0 then
            local bh = math.max(1, math.ceil((-n) * downMax))
            mon.setBackgroundColor(THEME.bad)
            for k = 1, bh do mon.setCursorPos(x, mid + k); mon.write(" ") end
        end
    end
end

-- ========================================================================= --
-- РЕНДЕР МОНИТОРА 8: DRACONIC CORE
-- ========================================================================= --

local function renderCore(mon)
    local d = state.core
    local w, h = mon.getSize()
    mon.setBackgroundColor(THEME.bg); mon.clear()

    -- Расчеты энергии
    local energy, maxE = d.energy, math.max(1, d.maxEnergy)
    local percent = clamp((energy / maxE) * 100, 0, 100)
    local netRF = d.input - d.output

    -- Обновление статистики и истории
    if d.input > peakIn then peakIn = d.input end
    if d.output > peakOut then peakOut = d.output end
    
    table.insert(graphData, netRF)
    if #graphData > GRAPH_HISTORY then table.remove(graphData, 1) end
    graphMaxAbs = math.max(graphMaxAbs, math.abs(netRF))
    if graphMaxAbs < 1 then graphMaxAbs = 1 else graphMaxAbs = graphMaxAbs * 0.999 end -- Авто-масштаб

    local barColor = percent < 20 and THEME.bad or (percent < 50 and THEME.warn or (percent < 75 and THEME.yellow or THEME.ok))

    -- Координаты блоков (адаптировано под большие экраны)
    local bx1w, bx1h = 19, 21
    local bx2w, bx2h = 24, 8
    local bx3w, bx3h = 32, 8
    
    drawBox(mon, 2, 2, bx1w, bx1h, THEME.header, "Energy Buffer")
    drawVerticalBar(mon, 5, 4, 13, 14, percent, barColor)
    writeAt(mon, 9, 19, string.format("%.1f%%", percent), THEME.text, THEME.bg)

    drawBox(mon, 23, 2, bx2w, bx2h, THEME.border, "Capacity")
    writeAt(mon, 25, 4, "Stored: " .. formatNumber(energy) .. " RF", THEME.text, THEME.bg)
    writeAt(mon, 25, 6, "Max:    " .. formatNumber(maxE) .. " RF", THEME.text, THEME.bg)

    drawBox(mon, 23 + bx2w + 1, 2, bx3w, bx3h, THEME.border, "Peak Flow")
    writeAt(mon, 23 + bx2w + 3, 4, "IN:  " .. formatNumber(peakIn) .. " RF/t", THEME.text, THEME.bg)
    writeAt(mon, 23 + bx2w + 3, 6, "OUT: " .. formatNumber(peakOut) .. " RF/t", THEME.text, THEME.bg)

    -- Потоки
    drawBox(mon, 23, 11, bx2w, 12, THEME.border, "Live Flow")
    if netRF > 100 then
        writeAt(mon, 25, 13, "STATUS: CHARGING", THEME.ok, THEME.bg)
        writeAt(mon, 25, 15, "+" .. formatNumber(math.abs(netRF)) .. " RF/t", THEME.ok, THEME.bg)
    elseif netRF < -100 then
        writeAt(mon, 25, 13, "STATUS: DRAINING", THEME.bad, THEME.bg)
        writeAt(mon, 25, 15, "-" .. formatNumber(math.abs(netRF)) .. " RF/t", THEME.bad, THEME.bg)
    else
        writeAt(mon, 25, 13, "STATUS: STABLE", THEME.dim, THEME.bg)
        writeAt(mon, 25, 15, "~0 RF/t", THEME.dim, THEME.bg)
    end

    -- График
    local gx, gy, gw, gh = 23 + bx2w + 1, 11, bx3w, 12
    drawBox(mon, gx, gy, gw, gh, THEME.border, "Net Graph")
    drawGraphBars(mon, gx + 2, gy + 2, gw - 4, gh - 4, graphData, graphMaxAbs)

    -- Новый блок: ETA (Время)
    local etaStr = "N/A"
    local etaPrefix = "ETA: "
    local etaColor = THEME.dim
    if netRF > 10 then
        local secToFull = (maxE - energy) / (netRF * 20)
        etaStr = formatTime(secToFull)
        etaPrefix = "TIME TO FULL: "
        etaColor = THEME.ok
    elseif netRF < -10 then
        local secToEmpty = energy / (math.abs(netRF) * 20)
        etaStr = formatTime(secToEmpty)
        etaPrefix = "CRITICAL IN: "
        etaColor = THEME.bad
    end

    drawBox(mon, 23, 24, bx2w + bx3w + 1, 5, etaColor, "Time Estimation")
    writeAt(mon, 25, 26, etaPrefix, THEME.text, THEME.bg)
    writeAt(mon, 25 + #etaPrefix, 26, etaStr, etaColor, THEME.bg)
end

-- ========================================================================= --
-- РЕНДЕР МОНИТОРА 9: REACTORS
-- ========================================================================= --

local function renderReactors(mon)
    local d = state.plant
    local w, h = mon.getSize()
    mon.setBackgroundColor(THEME.bg); mon.clear()
    fillRect(mon, 1, 1, w, 1, THEME.header)
    writeAt(mon, 2, 1, "NUCLEAR & FUSION DIVISION", THEME.text, THEME.header)

    -- FISSION
    drawBox(mon, 2, 3, w - 2, 12, THEME.ok, "Fission Reactor")
    local f_status = d.f_status and "ONLINE" or "OFFLINE"
    local f_color = d.f_status and THEME.ok or THEME.bad
    writeAt(mon, 4, 5, "Status: ", THEME.dim, THEME.bg)
    writeAt(mon, 12, 5, f_status, f_color, THEME.bg)
    writeAt(mon, 4, 7, "Burn Rate: " .. formatNumber(d.f_burn) .. " mB/t", THEME.yellow, THEME.bg)
    
    local f_temp_pct = math.min((d.f_temp / 1200) * 100, 100) -- Предполагаем 1200K как 100% опасности
    local tColor = f_temp_pct > 80 and THEME.bad or THEME.ok
    drawHorizBar(mon, 4, 11, w - 6, f_temp_pct, tColor, "Core Temperature", formatNumber(d.f_temp) .. " K")

    -- FUSION
    drawBox(mon, 2, 16, w - 2, 12, THEME.fusion, "Fusion Reactor")
    local fu_status = d.fu_active and "IGNITED" or "PASSIVE"
    local fu_color = d.fu_active and THEME.ok or THEME.dim
    writeAt(mon, 4, 18, "Status: ", THEME.dim, THEME.bg)
    writeAt(mon, 12, 18, fu_status, fu_color, THEME.bg)
    
    local fu_temp_pct = math.min((d.fu_temp / 500e6) * 100, 100) -- Макс шкала ~500M K
    drawHorizBar(mon, 4, 24, w - 6, fu_temp_pct, THEME.fusion, "Plasma Heat", formatNumber(d.fu_temp) .. " K")
end

-- ========================================================================= --
-- РЕНДЕР МОНИТОРА 10: BOILER & SPS
-- ========================================================================= --

local function renderPlant(mon)
    local d = state.plant
    local w, h = mon.getSize()
    mon.setBackgroundColor(THEME.bg); mon.clear()
    fillRect(mon, 1, 1, w, 1, THEME.header)
    writeAt(mon, 2, 1, "THERMODYNAMICS & SPS", THEME.text, THEME.header)

    -- BOILER & TURBINE
    drawBox(mon, 2, 3, w - 2, 12, THEME.warn, "Turbine & Boiler Loop")
    local st_pct = math.min((d.b_steam / math.max(1, d.b_maxSteam)) * 100, 100)
    
    -- Пар (Критический показатель)
    local stColor = st_pct > 90 and THEME.bad or THEME.steam
    drawHorizBar(mon, 4, 7, w - 6, st_pct, stColor, "Steam Pressure", formatNumber(d.b_steam) .. " mB")
    
    -- Турбина
    writeAt(mon, 4, 11, "Turbine Flow: ", THEME.dim, THEME.bg)
    writeAt(mon, 18, 11, formatNumber(d.t_flow) .. " mB/t", THEME.text, THEME.bg)

    -- SPS
    drawBox(mon, 2, 16, w - 2, 10, THEME.border, "Supercritical Phase Shifter")
    writeAt(mon, 4, 18, "Antimatter Prod: ", THEME.dim, THEME.bg)
    writeAt(mon, 21, 18, formatNumber(d.anti_rate) .. " mB/t", THEME.ok, THEME.bg)
    
    writeAt(mon, 4, 21, "Tank Volume: ", THEME.dim, THEME.bg)
    writeAt(mon, 17, 21, formatNumber(d.anti_amount) .. " mB", THEME.text, THEME.bg)
end

-- ========================================================================= --
-- АСИНХРОННЫЕ ПОТОКИ (Твоя защита от зависаний)
-- ========================================================================= --

local function networkLoop()
    while true do
        local id, msg, proto = rednet.receive()
        if type(msg) == "table" then
            if proto == "CORE_DATA" then
                state.core = msg
            elseif proto == "PLANT_DATA" then
                state.plant = msg
            end
        end
    end
end

local function renderLoop()
    while true do
        pcall(function()
            if mCore then renderCore(mCore) end
            if mReact then renderReactors(mReact) end
            if mPlant then renderPlant(mPlant) end
        end)
        sleep(0.5) -- 2 FPS для мониторов, чтобы не нагружать сервер
    end
end

-- Запуск двух потоков одновременно (если один упадет, система остановится с ошибкой, а не зависнет в тишине)
print("PK3 [HOME TERMINAL] ONLINE.")
print("Listening on REDNET...")
parallel.waitForAny(networkLoop, renderLoop)