-- Инициализация устройств
local core0 = peripheral.wrap("draconic_rf_storage_0")
local core1 = peripheral.wrap("draconic_rf_storage_1")
local reactor = peripheral.wrap("fissionReactorLogicAdapter_7")
local sps = peripheral.wrap("spsPort_0")

-- Мониторы по твоим ID
local monC = peripheral.wrap("monitor_5") -- Центр
local monL = peripheral.wrap("monitor_6") -- Лево
local monR = peripheral.wrap("monitor_7") -- Право

local lastE = -1

-- Красивое форматирование (1000 -> 1k)
local function format(n)
    if not n then return "0" end
    if n >= 1e12 then return string.format("%.2f T", n/1e12) end
    if n >= 1e9 then return string.format("%.2f G", n/1e9) end
    if n >= 1e6 then return string.format("%.2f M", n/1e6) end
    return tostring(math.floor(n))
end

while true do
    -- Сбор энергии с обоих хранилищ
    local energy = (core0 and core0.getEnergyStored() or 0) + (core1 and core1.getEnergyStored() or 0)
    
    -- Расчет нашей «честной» дельты (раз в секунду)
    local delta = 0
    if lastE ~= -1 then delta = (energy - lastE) / 20 end
    lastE = energy

    -- ЦЕНТР (ЯДРО)
    if monC then
        monC.clear()
        monC.setTextScale(1)
        monC.setCursorPos(1,1)
        monC.setTextColor(colors.cyan)
        monC.write(">> CORE STATUS")
        monC.setCursorPos(1,3)
        monC.setTextColor(colors.white)
        monC.write("Stored: "..format(energy).."RF")
        monC.setCursorPos(1,5)
        if delta >= 0 then
            monC.setTextColor(colors.green)
            monC.write("NET: +"..format(delta).."/t")
        else
            monC.setTextColor(colors.red)
            monC.write("NET: "..format(delta).."/t")
        end
    end

    -- ЛЕВО (РЕАКТОР)
    if monL then
        monL.clear()
        monL.setCursorPos(1,1)
        monL.setTextColor(colors.yellow)
        monL.write(">> FISSION")
        local temp = reactor and reactor.getTemperature() or 0
        monL.setCursorPos(1,3)
        monL.setTextColor(temp > 1000 and colors.red or colors.white)
        monL.write("Temp: "..math.floor(temp).."K")
    end

    -- ПРАВО (SPS)
    if monR then
        monR.clear()
        monR.setCursorPos(1,1)
        monR.setTextColor(colors.magenta)
        monR.write(">> PRODUCTION")
        
        local usage = 0
        if sps then
            -- Безопасный вызов, чтобы не было ошибки "nil value"
            pcall(function() usage = sps.getEnergyUsage() end)
        end
        
        monR.setCursorPos(1,3)
        monR.setTextColor(colors.white)
        monR.write("SPS: "..format(usage).."/t")
    end

    sleep(1)
end