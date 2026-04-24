-- Инициализация периферии
local core = peripheral.wrap("draconic_rf_storage_0")
local reactor = peripheral.wrap("fissionReactorLogicAdapter_7")
local sps = peripheral.wrap("spsPort_0")
local turbine = peripheral.wrap("turbineValve_0") -- если есть

-- Мониторы (ЗАМЕНИ ID НА СВОИ)
local monL = peripheral.wrap("monitor_10") -- Левый
local monC = peripheral.wrap("monitor_11") -- Центр
local monR = peripheral.wrap("monitor_12") -- Правый

local lastE = -1
local history = {}

-- Функция отрисовки центрального экрана (Ядро)
local function drawCore(m, energy, maxE)
    m.clear()
    m.setTextScale(1)
    
    -- Расчет дельты (наша фишка)
    local delta = 0
    if lastE ~= -1 then delta = (energy - lastE) / 10 end
    lastE = energy

    m.setCursorPos(1,1)
    m.setTextColor(colors.cyan)
    m.write(">> DRACONIC CORE")
    
    m.setCursorPos(1,3)
    m.setTextColor(colors.white)
    local perc = math.floor((energy/maxE)*100)
    m.write("Charge: "..perc.."%")
    
    -- Отрисовка графика дельты
    -- (Тут будет упрощенная версия, позже расширим)
    m.setCursorPos(1,5)
    if delta >= 0 then 
        m.setTextColor(colors.green)
        m.write("NET: +"..math.floor(delta).." RF/t")
    else
        m.setTextColor(colors.red)
        m.write("NET: "..math.floor(delta).." RF/t")
    end
end

-- Функция для Реактора (Левый)
local function drawReactor(m)
    m.clear()
    m.setCursorPos(1,1)
    m.setTextColor(colors.yellow)
    m.write(">> FISSION SYSTEM")
    
    local temp = reactor.getTemperature()
    m.setCursorPos(1,3)
    m.setTextColor(temp > 1000 and colors.red or colors.white)
    m.write("Temp: "..math.floor(temp).." K")
end

-- Основной цикл
while true do
    local energy = core.getEnergyStored()
    local maxE = core.getMaxEnergyStored()
    
    -- Обновляем каждый монитор по очереди
    if monC then drawCore(monC, energy, maxE) end
    if monL then drawReactor(monL) end
    -- if monR then drawSPS(monR) end -- допишем по аналогии
    
    sleep(0.5)
end