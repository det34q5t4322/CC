-- ==========================================
-- SENDER: REACTOR DATA BROADCASTER v3.0
-- ==========================================

-- 1. Автоматический поиск и включение беспроводного модема
local modemName = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and peripheral.call(name, "isWireless") then
        modemName = name
        break
    end
end

if modemName then
    rednet.open(modemName)
    print("Wireless link opened on: " .. modemName)
else
    error("CRITICAL: Advanced Wireless Modem not found!")
end

-- 2. Безопасное чтение данных (чтобы комп не крашнулся, если блок пропадет)
local function safeRead(func, default)
    local success, result = pcall(func)
    if success and result ~= nil then return result else return default end
end

-- Основной цикл отправки
while true do
    -- Подключаем устройства каждый тик (если кабель отпадет и вернется, комп это поймет)
    local cIn = peripheral.wrap("draconic_rf_storage_0")
    local cOut = peripheral.wrap("draconic_rf_storage_1")
    local r = peripheral.wrap("fissionReactorPort_0")
    local b = peripheral.wrap("boilerValve_0")
    local t = peripheral.wrap("turbineValve_0")
    local s = peripheral.wrap("spsPort_0")

    -- Собираем пакет данных
    local payload = {
        coreEnergy = cIn and safeRead(cIn.getEnergyStored, 0) or 0,
        coreMax = cIn and safeRead(cIn.getMaxEnergyStored, 1) or 1,
        
        reactorStatus = r and safeRead(r.getStatus, false) or false,
        reactorTemp = r and safeRead(r.getTemperature, 0) or 0,
        
        boilerSteam = b and safeRead(b.getSteamFilledPercentage, 0) or 0,
        
        turbineProd = t and safeRead(t.getProductionRate, 0) or 0,
        
        spsUsage = s and safeRead(s.getEnergyUsage, 0) or 0
    }

    -- Отправляем в эфир (протокол "MEGABASE_DATA")
    rednet.broadcast(payload, "MEGABASE_DATA")
    print("Data packet sent... " .. os.time())
    
    sleep(0.5) -- Отправляем 2 раза в секунду для плавности графиков
end