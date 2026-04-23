-- FINAL CYBER-HUD v6.0
local m = peripheral.find("monitor")
local net = nil

-- Инициализация беспроводной связи
for _, s in ipairs(peripheral.getNames()) do
    if peripheral.getType(s) == "modem" and peripheral.call(s, "isWireless") then
        net = s
        rednet.open(s)
        break
    end
end

if not m or not net then error("Check Hardware!") end

local history = {}
local lastE = 0

-- Красивая отрисовка статических элементов
local function drawUI(d, diff)
    m.setBackgroundColor(colors.black)
    m.clear()
    m.setTextScale(0.5)
    local W, H = m.getSize()

    -- 1. СЕТКА ГРАФИКА
    m.setTextColor(colors.gray)
    for gy = 14, H-3, 2 do
        m.setCursorPos(4, gy)
        m.write(string.rep(".", W-10))
    end

    -- 2. ВЕРХНИЕ ИНФО-БОКСЫ
    -- Draconic Core
    m.setTextColor(colors.cyan)
    m.setCursorPos(4, 4)
    m.write(">> DRACONIC STORAGE")
    m.setCursorPos(4, 6)
    m.setTextColor(colors.white)
    m.write("STORED: " .. string.format("%.2f", d.energy/10^12) .. " TRF")
    m.setCursorPos(4, 7)
    m.write("CHARGE: " .. math.floor((d.energy/d.maxE)*100) .. "%")

    -- Thermal System (Reactor & Boiler)
    m.setTextColor(colors.orange)
    m.setCursorPos(35, 4)
    m.write(">> THERMAL STATUS")
    m.setCursorPos(35, 6)
    m.setTextColor(d.status and colors.lime or colors.red)
    m.write("FISSION: " .. (d.status and "ONLINE" or "OFFLINE"))
    m.setCursorPos(35, 7)
    m.setTextColor(colors.white)
    m.write("TEMP: " .. math.floor(d.temp) .. " K")
    m.setCursorPos(35, 8)
    m.write("STEAM: " .. math.floor(d.steam*100) .. "%")

    -- Production & SPS
    m.setTextColor(colors.magenta)
    m.setCursorPos(66, 4)
    m.write(">> PRODUCTION")
    m.setCursorPos(66, 6)
    m.setTextColor(colors.white)
    m.write("TURBINE: " .. math.floor(d.prod) .. " RF/t")
    m.setCursorPos(66, 7)
    m.write("SPS IN:  " .. math.floor(d.sps) .. " RF/t")

    -- 3. ОТРИСОВКА ГРАФИКА (PULSE)
    local midY = H - 8
    local maxVal = 1
    for _, v in ipairs(history) do if math.abs(v) > maxVal then maxVal = math.abs(v) end end

    for x, val in ipairs(history) do
        local hgt = math.floor((val / maxVal) * 6)
        m.setTextColor(val >= 0 and colors.lime or colors.red)
        for j = 0, math.abs(hgt) do
            m.setCursorPos(4 + x, midY - (hgt > 0 and j or -j))
            m.write("|")
        end
    end

    -- Нижний статус
    m.setCursorPos(4, H-1)
    m.setTextColor(colors.gray)
    m.write("NET: SECURE | DELTA: " .. string.format("%+d", diff) .. " RF/t | " .. os.date("%H:%M:%S"))
end

-- Основной цикл приема
while true do
    local id, payload = rednet.receive("MEGABASE_DATA", 5)
    
    if payload and type(payload) == "table" then
        -- Считаем разницу энергии для графика
        local diff = 0
        if lastE > 0 then diff = payload.energy - lastE end
        lastE = payload.energy

        -- Добавляем в историю
        table.insert(history, diff)
        local W, _ = m.getSize()
        if #history > W-15 then table.remove(history, 1) end

        drawUI(payload, diff)
    else
        -- Если сигнал пропал
        m.clear()
        m.setCursorPos(10, 10)
        m.setTextColor(colors.red)
        m.write("SIGNAL LOST - CHECK REPEATER")
    end
end