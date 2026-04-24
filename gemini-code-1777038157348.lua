peripheral.find("modem", rednet.open)

local monC = peripheral.wrap("monitor_5")
local monL = peripheral.wrap("monitor_6")
local monR = peripheral.wrap("monitor_7")

-- Две истории для зеркального графика
local inHistory = {}
local outHistory = {}
local maxHistory = 22 -- Уменьшил, так как рисуем через один (палочками)

for _, m in pairs({monC, monL, monR}) do
    if m then m.setTextScale(0.5) m.clear() end
end

local function format(n)
    if not n or n < 0 then return "0" end
    if n >= 1e12 then return string.format("%.2f T", n/1e12) end
    if n >= 1e9 then return string.format("%.2f G", n/1e9) end
    if n >= 1e6 then return string.format("%.2f M", n/1e6) end
    return tostring(math.floor(n))
end

local function drawBox(m, title, frameColor, titleColor)
    local w, h = m.getSize()
    m.setBackgroundColor(frameColor)
    m.setCursorPos(1,1) m.clearLine()
    m.setCursorPos(1,h) m.clearLine()
    for y=1, h do
        m.setCursorPos(1,y) m.write(" ")
        m.setCursorPos(w,y) m.write(" ")
    end
    m.setCursorPos(4, 1)
    m.setBackgroundColor(colors.black)
    m.setTextColor(titleColor)
    m.write(" [ " .. title .. " ] ")
end

local function drawBar(m, x, y, width, percent, colorFull, colorEmpty)
    m.setCursorPos(x, y)
    local fill = math.floor((width * percent) / 100)
    for i=1, width do
        m.setBackgroundColor(i <= fill and colorFull or colorEmpty)
        m.write(" ")
    end
    m.setBackgroundColor(colors.black)
end

-- Обновленный рендер Ядра с зеркальным графиком
local function renderCenter(data)
    if not monC then return end
    monC.clear()
    drawBox(monC, "DRACONIC CORE", colors.cyan, colors.lightBlue)
    
    local ePct = (data.energy / data.maxEnergy) * 100
    monC.setCursorPos(3, 3)
    monC.setTextColor(colors.white)
    monC.write("STORED: " .. format(data.energy) .. " RF  (" .. string.format("%.1f", ePct) .. "%)")
    drawBar(monC, 3, 5, 45, ePct, colors.cyan, colors.gray)

    -- Статистика текстом
    monC.setCursorPos(3, 7)
    monC.setTextColor(colors.lime)
    monC.write("IN:  +" .. format(data.input) .. " RF/t")
    monC.setCursorPos(3, 8)
    monC.setTextColor(colors.red)
    monC.write("OUT: -" .. format(data.output) .. " RF/t")

    -- ЗЕРКАЛЬНЫЙ ГРАФИК «ПАЛОЧКАМИ»
    local gX, gY, gW, gH = 4, 15, 42, 12
    local midY = gY -- Линия нуля
    
    -- Авто-масштаб (ищем макс. в истории)
    local maxIn, maxOut = 100000, 100000
    for i=1, #inHistory do 
        maxIn = math.max(maxIn, inHistory[i])
        maxOut = math.max(maxOut, outHistory[i])
    end

    -- Рисуем палочки через одну (шаг 2)
    for i=1, #inHistory do
        local xPos = gX + (i-1) * 2
        
        -- Верхняя палочка (Input)
        local hIn = math.floor((inHistory[i] / maxIn) * 6)
        monC.setBackgroundColor(colors.green)
        for h=0, hIn do
            monC.setCursorPos(xPos, midY - h)
            monC.write(" ")
        end
        
        -- Нижняя палочка (Output)
        local hOut = math.floor((outHistory[i] / maxOut) * 6)
        monC.setBackgroundColor(colors.red)
        for h=1, hOut do
            monC.setCursorPos(xPos, midY + h)
            monC.write(" ")
        end
        monC.setBackgroundColor(colors.black)
    end
    
    -- Подписи масштаба
    monC.setTextColor(colors.gray)
    monC.setCursorPos(gX + gW - 8, midY - 6)
    monC.write("max:"..format(maxIn))
    monC.setCursorPos(gX + gW - 8, midY + 6)
    monC.write("max:"..format(maxOut))
end

-- Остальные функции рендера (Reactor и SPS) остаются такими же
local function renderLeft(data)
    if not monL then return end
    monL.clear()
    drawBox(monL, "FISSION REACTOR", colors.gray, colors.yellow)
    monL.setCursorPos(3, 4)
    monL.setTextColor(colors.white)
    monL.write("STATUS: ")
    if data.reactorOn then monL.setTextColor(colors.lime) monL.write("ONLINE")
    else monL.setTextColor(colors.red) monL.write("OFFLINE") end
    monL.setCursorPos(3, 7)
    monL.setTextColor(colors.white)
    monL.write("CORE TEMP: " .. math.floor(data.temp) .. " K")
    local tPct = math.min((data.temp / 1200) * 100, 100)
    drawBar(monL, 3, 9, 30, tPct, colors.orange, colors.gray)
end

local function renderRight(data)
    if not monR then return end
    monR.clear()
    drawBox(monR, "ANTIMATTER PROD", colors.gray, colors.magenta)
    monR.setCursorPos(3, 4)
    monR.setTextColor(colors.white)
    monR.write("SPS: " .. format(data.spsUsage) .. " RF/t")
    monR.setCursorPos(3, 7)
    monR.setTextColor(colors.lightBlue)
    monR.write("TANK: " .. format(data.antimatter) .. " mB")
    local aPct = math.min((data.antimatter / data.maxAntimatter) * 100, 100)
    drawBar(monR, 3, 9, 30, aPct, colors.magenta, colors.gray)
end

while true do
    local senderId, message = rednet.receive("BASE_TELEMETRY", 2)
    if message and type(message) == "table" then
        -- Добавляем в историю
        table.insert(inHistory, message.input)
        table.insert(outHistory, message.output)
        if #inHistory > maxHistory then 
            table.remove(inHistory, 1) 
            table.remove(outHistory, 1)
        end

        renderLeft(message)
        renderRight(message)
        renderCenter(message)
    end
end