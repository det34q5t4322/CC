-- Авто-поиск периферии
local cores = {peripheral.find("draconic_rf_storage")}
local reactor = peripheral.find("fissionReactorLogicAdapter")
local sps = peripheral.find("spsPort")
local monitors = {peripheral.find("monitor")}

-- Сортировка мониторов по X координате (чтобы левый был левым)
table.sort(monitors, function(a, b) 
    local nameA = peripheral.getName(a)
    local nameB = peripheral.getName(b)
    return nameA < nameB -- Обычно модемы именуются по порядку подключения
end)

local monL, monC, monR = monitors[1], monitors[2], monitors[3]
local lastE = -1
local history = {}

-- Функция для красивых цифр (1000 -> 1k)
local function format(n)
    if n >= 1e12 then return string.format("%.2f T", n/1e12) end
    if n >= 1e9 then return string.format("%.2f G", n/1e9) end
    if n >= 1e6 then return string.format("%.2f M", n/1e6) end
    return tostring(math.floor(n))
end

local function drawInfo()
    -- 1. Собираем данные
    local totalEnergy = 0
    local maxEnergy = 0
    for _, c in pairs(cores) do
        totalEnergy = totalEnergy + c.getEnergyStored()
        maxEnergy = maxEnergy + c.getMaxEnergyStored()
    end

    local delta = 0
    if lastE ~= -1 then delta = (totalEnergy - lastE) / 20 end -- делим на тики
    lastE = totalEnergy

    -- 2. ЛЕВЫЙ: РЕАКТОР
    if monL then
        monL.clear()
        monL.setTextScale(1)
        monL.setCursorPos(1,1)
        monL.setTextColor(colors.yellow)
        monL.write(">> FISSION")
        local temp = reactor and reactor.getTemperature() or 0
        monL.setCursorPos(1,3)
        monL.setTextColor(temp > 1000 and colors.red or colors.white)
        monL.write("Temp: "..math.floor(temp).."K")
    end

    -- 3. ЦЕНТР: ЯДРО + ГРАФИК
    if monC then
        monC.clear()
        monC.setCursorPos(1,1)
        monC.setTextColor(colors.cyan)
        monC.write(">> CORE STATUS")
        monC.setCursorPos(1,3)
        monC.setTextColor(colors.white)
        monC.write("Stored: "..format(totalEnergy).."RF")
        
        -- Вывод Дельты
        monC.setCursorPos(1,5)
        if delta >= 0 then
            monC.setTextColor(colors.green)
            monC.write("NET: +"..format(delta).."/t")
        else
            monC.setTextColor(colors.red)
            monC.write("NET: "..format(delta).."/t")
        end
    end

    -- 4. ПРАВЫЙ: SPS
    if monR then
        monR.clear()
        monR.setCursorPos(1,1)
        monR.setTextColor(colors.magenta)
        monR.write(">> PRODUCTION")
        
        local usage = 0
        -- Безопасный вызов SPS
        if sps then
            pcall(function() usage = sps.getEnergyUsage() end)
        end
        
        monR.setCursorPos(1,3)
        monR.setTextColor(colors.white)
        monR.write("SPS: "..format(usage).."/t")
    end
end

-- Цикл
while true do
    drawInfo()
    sleep(1) -- Обновляем раз в секунду для стабильности
end