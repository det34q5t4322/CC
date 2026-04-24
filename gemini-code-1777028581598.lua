peripheral.find("modem", rednet.open)

local monC = peripheral.wrap("monitor_5") -- Центр
local monL = peripheral.wrap("monitor_6") -- Лево
local monR = peripheral.wrap("monitor_7") -- Право

local history = {}
local maxHistory = 40 -- Ширина графика
local lastEnergy = -1

-- Подготовка мониторов
for _, m in pairs({monC, monL, monR}) do
    if m then
        m.setTextScale(0.5) -- Мелкий текст для крутой графики
        m.setBackgroundColor(colors.black)
        m.clear()
    end
end

-- Красивые сокращения
local function format(n)
    if not n or n < 0 then return "0" end
    if n >= 1e12 then return string.format("%.2f T", n/1e12) end
    if n >= 1e9 then return string.format("%.2f G", n/1e9) end
    if n >= 1e6 then return string.format("%.2f M", n/1e6) end
    return tostring(math.floor(n))
end

-- Функция отрисовки рамки с заголовком
local function drawBox(m, title, frameColor, titleColor)
    local w, h = m.getSize()
    m.setBackgroundColor(frameColor)
    for x=1, w do
        m.setCursorPos(x,1) m.write(" ")
        m.setCursorPos(x,h) m.write(" ")
    end
    for y=1, h do
        m.setCursorPos(1,y) m.write(" ")
        m.setCursorPos(w,y) m.write(" ")
    end
    m.setCursorPos(4, 1)
    m.setBackgroundColor(colors.black)
    m.setTextColor(titleColor)
    m.write(" [ " .. title .. " ] ")
end

-- Прогресс-бар
local function drawBar(m, x, y, width, percent, colorFull, colorEmpty)
    m.setCursorPos(x, y)
    local fill = math.floor((width * percent) / 100)
    for i=1, width do
        if i <= fill then m.setBackgroundColor(colorFull) else m.setBackgroundColor(colorEmpty) end
        m.write(" ")
    end
    m.setBackgroundColor(colors.black)
end

-- Отрисовка левого экрана (РЕАКТОР)
local function renderLeft(data)
    if not monL then return end
    monL.clear()
    drawBox(monL, "FISSION REACTOR", colors.gray, colors.yellow)
    
    monL.setCursorPos(3, 4)
    monL.setTextColor(colors.white)
    monL.write("STATUS: ")
    if data.reactorOn then
        monL.setTextColor(colors.lime) monL.write("ONLINE")
    else
        monL.setTextColor(colors.red) monL.write("OFFLINE")
    end

    monL.setCursorPos(3, 7)
    monL.setTextColor(colors.white)
    monL.write("CORE TEMP: " .. math.floor(data.temp) .. " K")
    
    -- Шкала температуры (до 1200K)
    local tPct = math.min((data.temp / 1200) * 100, 100)
    local tColor = colors.lime
    if data.temp > 800 then tColor = colors.orange end
    if data.temp > 1000 then tColor = colors.red end
    drawBar(monL, 3, 9, 30, tPct, tColor, colors.gray)
end

-- Отрисовка правого экрана (SPS)
local function renderRight(data)
    if not monR then return end
    monR.clear()
    drawBox(monR, "ANTIMATTER PROD", colors.gray, colors.magenta)
    
    monR.setCursorPos(3, 4)
    monR.setTextColor(colors.white)
    monR.write("SPS USAGE: " .. format(data.spsUsage) .. " RF/t")

    monR.setCursorPos(3, 7)
    monR.setTextColor(colors.lightBlue)
    monR.write("ANTIMATTER TANK: " .. format(data.antimatter) .. " mB")
    
    local aPct = math.min((data.antimatter / data.maxAntimatter) * 100, 100)
    drawBar(monR, 3, 9, 30, aPct, colors.magenta, colors.gray)
end

-- Отрисовка центрального экрана (ЯДРО + ГРАФИК)
local function renderCenter(data, delta)
    if not monC then return end
    monC.clear()
    drawBox(monC, "DRACONIC CORE", colors.cyan, colors.lightBlue)
    
    -- Заряд в цифрах и бар
    local ePct = (data.energy / data.maxEnergy) * 100
    monC.setCursorPos(3, 3)
    monC.setTextColor(colors.white)
    monC.write("STORED: " .. format(data.energy) .. " RF  (" .. string.format("%.1f", ePct) .. "%)")
    drawBar(monC, 3, 5, 45, ePct, colors.cyan, colors.gray)

    -- Дельта
    monC.setCursorPos(3, 8)
    if delta >= 0 then
        monC.setTextColor(colors.lime)
        monC.write("NET FLOW: +" .. format(delta) .. " RF/t")
    else
        monC.setTextColor(colors.red)
        monC.write("NET FLOW: " .. format(delta) .. " RF/t")
    end

    -- Отрисовка графика (Динамический)
    local gX, gY, gW, gH = 3, 11, 45, 14
    local maxDelta = 10000 -- Минимальный порог для шкалы
    for _, v in ipairs(history) do maxDelta = math.max(maxDelta, math.abs(v)) end

    -- Рисуем ось нуля
    monC.setBackgroundColor(colors.gray)
    monC.setTextColor(colors.black)
    for i=0, gW-1 do
        monC.setCursorPos(gX + i, gY + math.floor(gH/2))
        monC.write("-")
    end
    monC.setBackgroundColor(colors.black)

    -- Рисуем столбцы
    for i, val in ipairs(history) do
        local xPos = gX + gW - #history + i - 1
        local hOffset = math.floor((math.abs(val) / maxDelta) * (gH/2))
        if val > 0 then
            monC.setBackgroundColor(colors.green)
            for h=1, hOffset do
                monC.setCursorPos(xPos, gY + math.floor(gH/2) - h)
                monC.write(" ")
            end
        elseif val < 0 then
            monC.setBackgroundColor(colors.red)
            for h=1, hOffset do
                monC.setCursorPos(xPos, gY + math.floor(gH/2) + h)
                monC.write(" ")
            end
        end
    end
    monC.setBackgroundColor(colors.black)
end

-- Основной цикл приема данных
while true do
    local senderId, message, protocol = rednet.receive("BASE_TELEMETRY", 3)
    
    if senderId and type(message) == "table" then
        -- Считаем дельту
        local delta = 0
        if lastEnergy ~= -1 then delta = (message.energy - lastEnergy) / 20 end
        lastEnergy = message.energy

        -- Порог шума, чтобы график не дергался от копеек
        if math.abs(delta) < 50 then delta = 0 end

        -- Пишем в историю графика
        table.insert(history, delta)
        if #history > maxHistory then table.remove(history, 1) end

        -- Рендер
        renderLeft(message)
        renderRight(message)
        renderCenter(message, delta)
    end
end