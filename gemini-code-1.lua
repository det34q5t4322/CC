-- ==========================================
-- CYBER-TERMINAL: ADVANCED GRID MONITOR v4.0
-- ==========================================

local m = peripheral.find("monitor")
local net = nil

for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" and peripheral.call(side, "isWireless") then
        net = side
        rednet.open(side)
        break
    end
end

if not m or not net then error("HARDWARE ERROR: Monitor or Modem missing!") end

m.setTextScale(0.5)

-- ================= STATE & DATA =================
local history = {}     -- Буфер для графика
local lastEnergy = nil -- Для расчета Дельты (Вход/Выход)
local maxHistory = 0   -- Вычислится динамически
local scanLine = 0     -- Позиция бегущего сканера

-- ================= FORMATTERS =================
local function formatNumber(n)
    if n >= 10^12 then return string.format("%.2f T", n/10^12) end
    if n >= 10^9 then return string.format("%.2f B", n/10^9) end
    if n >= 10^6 then return string.format("%.2f M", n/10^6) end
    if n >= 10^3 then return string.format("%.1f k", n/10^3) end
    return tostring(math.floor(n))
end

-- ================= RENDER ENGINE =================
local function drawShadowText(x, y, text, color)
    m.setCursorPos(x+1, y)
    m.setTextColor(colors.gray)
    m.write(text) -- Тень
    m.setCursorPos(x, y)
    m.setTextColor(color)
    m.write(text) -- Основной текст
end

local function drawBox(x, y, w, h, title, col)
    m.setTextColor(col)
    m.setCursorPos(x, y)
    m.write("+"..string.rep("-", w-2).."+")
    for i=1, h-2 do
        m.setCursorPos(x, y+i)
        m.write("|")
        m.setCursorPos(x+w-1, y+i)
        m.write("|")
    end
    m.setCursorPos(x, y+h-1)
    m.write("+"..string.rep("-", w-2).."+")
    drawShadowText(x+2, y, " " .. title .. " ", colors.white)
end

-- ================= ADVANCED GRAPH =================
local function drawPulseGraph(x, y, w, h)
    -- Отрисовка фона и сетки
    for i = 0, h-1 do
        m.setCursorPos(x, y+i)
        m.setTextColor(colors.gray)
        if i % 2 == 0 then
            m.write(string.rep(".", w))
        else
            m.write(string.rep(" ", w))
        end
    end

    if #history < 2 then return end

    -- Авто-масштабирование
    local maxVal = 1
    for _, val in ipairs(history) do
        if math.abs(val) > maxVal then maxVal = math.abs(val) end
    end

    local zeroY = y + math.floor(h/2)
    
    -- Отрисовка нулевой линии (баланс)
    m.setCursorPos(x, zeroY)
    m.setTextColor(colors.white)
    m.write(string.rep("-", w))
    m.setCursorPos(x+w+1, zeroY)
    m.write("0 RF/t")

    -- Макс/Мин маркеры
    m.setCursorPos(x+w+1, y)
    m.setTextColor(colors.lime)
    m.write("+" .. formatNumber(maxVal))
    m.setCursorPos(x+w+1, y+h-1)
    m.setTextColor(colors.red)
    m.write("-" .. formatNumber(maxVal))

    -- Отрисовка самого графика (заполненный)
    for i = 1, #history do
        local val = history[i]
        local plotX = x + i - 1
        
        -- Нормализация значения под высоту графика
        local normalized = math.floor((val / maxVal) * (h/2))
        local plotY = zeroY - normalized
        
        -- Эффект "заполнения"
        if val > 0 then
            m.setTextColor(colors.lime)
            for fillY = plotY, zeroY-1 do
                m.setCursorPos(plotX, fillY)
                m.write("|")
            end
            m.setCursorPos(plotX, plotY)
            m.write("*")
        elseif val < 0 then
            m.setTextColor(colors.red)
            for fillY = zeroY+1, plotY do
                m.setCursorPos(plotX, fillY)
                m.write("|")
            end
            m.setCursorPos(plotX, plotY)
            m.write("*")
        end
    end

    -- Эффект бегущего сканера
    scanLine = (scanLine + 1) % w
    for i = 0, h-1 do
        m.setCursorPos(x + scanLine, y + i)
        m.setTextColor(colors.lightBlue)
        m.write("|")
    end
end

-- ================= MAIN LOOP =================
while true do
    local sw, sh = m.getSize()
    maxHistory = sw - 20 -- Оставляем место для цифр справа

    local senderID, payload, prot = rednet.receive("MEGABASE_DATA", 5)

    m.setBackgroundColor(colors.black)
    m.clear()

    if payload then
        -- Вычисление потока (Delta)
        local currentEnergy = payload.coreEnergy
        local netFlow = 0
        if lastEnergy then
            netFlow = currentEnergy - lastEnergy
        end
        lastEnergy = currentEnergy

        -- Обновление буфера
        table.insert(history, netFlow)
        if #history > maxHistory then
            table.remove(history, 1)
        end

        -- ВЕРХНЯЯ ПАНЕЛЬ (Статистика)
        drawShadowText(math.floor(sw/2) - 15, 2, "GLOBAL INFRASTRUCTURE TERMINAL", colors.cyan)
        
        drawBox(2, 4, 38, 7, "DRACONIC CORE", colors.blue)
        m.setCursorPos(4, 6) m.setTextColor(colors.white) m.write("Stored: " .. formatNumber(currentEnergy) .. "RF")
        m.setCursorPos(4, 7) m.write("Status: ")
        m.setTextColor((currentEnergy/payload.coreMax) > 0.1 and colors.lime or colors.red)
        m.write(math.floor((currentEnergy/payload.coreMax)*100) .. "% SECURE")
        
        drawBox(42, 4, 38, 7, "THERMAL SYSTEM", colors.orange)
        m.setCursorPos(44, 6) m.setTextColor(colors.white) m.write("Fission: ")
        m.setTextColor(payload.reactorStatus and colors.lime or colors.red)
        m.write(payload.reactorStatus and "ACTIVE" or "OFFLINE")
        m.setCursorPos(44, 7) m.setTextColor(colors.white) m.write("Temp: " .. math.floor(payload.reactorTemp) .. " K")
        m.setCursorPos(44, 8) m.write("Steam: " .. math.floor(payload.boilerSteam*100) .. "%")

        drawBox(82, 4, sw-84, 7, "USAGE GRID", colors.magenta)
        m.setCursorPos(84, 6) m.setTextColor(colors.white) m.write("Turbine: " .. formatNumber(payload.turbineProd) .. "RF/t")
        m.setCursorPos(84, 7) m.write("SPS: " .. formatNumber(payload.spsUsage) .. "RF/t")

        -- НИЖНЯЯ ПАНЕЛЬ (График Пульса)
        drawBox(2, 12, sw-3, sh-14, "REALTIME ENERGY FLOW (NET DELTA)", colors.cyan)
        
        -- Опасный режим (Мигание рамки)
        if netFlow < 0 and math.abs(netFlow) > payload.turbineProd then
            if os.epoch("utc") % 1000 > 500 then
                drawBox(2, 12, sw-3, sh-14, "CRITICAL DRAIN DETECTED", colors.red)
            end
        end

        drawPulseGraph(4, 14, maxHistory, sh-18)

        -- ФУТЕР
        m.setCursorPos(2, sh)
        m.setTextColor(colors.gray)
        m.write("NET LINK: ") m.setTextColor(colors.lime) m.write("SECURE [PING: "..senderID.."]")
        m.setCursorPos(sw-15, sh)
        m.setTextColor(colors.gray)
        m.write(os.date("%H:%M:%S"))

    else
        -- ОШИБКА СВЯЗИ
        drawBox(sw/2 - 20, sh/2 - 3, 40, 7, "SYSTEM FAILURE", colors.red)
        m.setCursorPos(sw/2 - 16, sh/2)
        m.setTextColor(colors.white)
        m.write("CONNECTION TIMEOUT")
        m.setCursorPos(sw/2 - 16, sh/2 + 1)
        m.setTextColor(colors.gray)
        m.write("AWAITING RELAY RESP...")
    end
end