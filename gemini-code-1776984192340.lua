-- ==========================================
-- RECEIVER: COMMAND CENTER UI v3.0
-- ==========================================

-- 1. Настройка оборудования
local mon = peripheral.find("monitor")
if not mon then error("CRITICAL: Monitor not found!") end

local modemName = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and peripheral.call(name, "isWireless") then
        modemName = name
        break
    end
end

if modemName then
    rednet.open(modemName)
else
    error("CRITICAL: Advanced Wireless Modem not found!")
end

mon.setTextScale(0.5)

-- 2. Функции отрисовки интерфейса
local function drawBox(x, y, w, h, title, color)
    mon.setTextColor(color)
    mon.setCursorPos(x, y)
    mon.write("+"..string.rep("-", w-2).."+")
    for i=1, h-2 do
        mon.setCursorPos(x, y+i)
        mon.write("|")
        mon.setCursorPos(x+w-1, y+i)
        mon.write("|")
    end
    mon.setCursorPos(x, y+h-1)
    mon.write("+"..string.rep("-", w-2).."+")
    mon.setCursorPos(x+2, y)
    mon.write(" "..title.." ")
end

local function drawStat(x, y, label, val, unit, color)
    mon.setCursorPos(x, y)
    mon.setTextColor(colors.gray)
    mon.write(label..": ")
    mon.setTextColor(color)
    mon.write(val.." "..unit)
end

-- Экран ошибки при потере связи
local function drawLostSignal()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    local W, H = mon.getSize()
    mon.setCursorPos(W/2 - 10, H/2 - 1)
    mon.setTextColor(colors.red)
    mon.write("!!! SIGNAL LOST !!!")
    mon.setCursorPos(W/2 - 15, H/2 + 1)
    mon.setTextColor(colors.gray)
    mon.write("CHECK REACTOR COMM-LINK STATUS")
end

-- 3. Главный цикл приемника
while true do
    -- Ждем данные максимум 3 секунды. Если нет - считаем, что связь потеряна.
    local id, data, protocol = rednet.receive("MEGABASE_DATA", 3)
    
    if data then
        mon.setBackgroundColor(colors.black)
        mon.clear()
        local W, H = mon.getSize()

        -- ЗАГОЛОВОК
        mon.setTextColor(colors.white)
        mon.setCursorPos(W/2 - 16, 2)
        mon.write("GLOBAL INFRASTRUCTURE COMMAND TERMINAL")
        
        -- БЛОК 1: ДРАКОНИЕВОЕ ЯДРО
        drawBox(2, 4, 35, 8, "DRACONIC CORE", colors.cyan)
        drawStat(4, 6, "Stored", string.format("%.2f", data.coreEnergy/10^12), "TRF", colors.cyan)
        drawStat(4, 8, "Fill", math.floor((data.coreEnergy/data.coreMax)*100), "%", colors.white)

        -- БЛОК 2: ТЕРМАЛЬНЫЕ СИСТЕМЫ (Реактор и Бойлер)
        drawBox(38, 4, 35, 8, "THERMAL SYSTEM", colors.orange)
        drawStat(40, 6, "Fission", data.reactorStatus and "ONLINE" or "OFFLINE", "", data.reactorStatus and colors.lime or colors.red)
        drawStat(40, 7, "Temp", math.floor(data.reactorTemp), "K", colors.yellow)
        drawStat(40, 9, "Boiler", math.floor(data.boilerSteam*100), "% Steam", colors.lightBlue)

        -- БЛОК 3: ПРОИЗВОДСТВО И ПОТРЕБЛЕНИЕ
        drawBox(2, 13, 71, 6, "ENERGY I/O GRID", colors.magenta)
        drawStat(4, 15, "Turbine Yield", math.floor(data.turbineProd), "RF/t", colors.lime)
        drawStat(4, 17, "SPS Demand", math.floor(data.spsUsage), "RF/t", colors.magenta)

        -- ФУТЕР (СТАТУС И ВРЕМЯ)
        mon.setCursorPos(2, H-1)
        mon.setTextColor(colors.gray)
        mon.write("DATA LINK: ")
        mon.setTextColor(colors.lime)
        mon.write("SECURE [PING: " .. id .. "]")
        
        mon.setCursorPos(W-15, H-1)
        mon.setTextColor(colors.gray)
        mon.write("TIME: " .. textutils.formatTime(os.time(), true))
    else
        -- Если данные не пришли (таймаут)
        drawLostSignal()
    end
end