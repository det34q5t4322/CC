-- PK1: MEGA-SAFE SENSOR
peripheral.find("modem", rednet.open)
local HOST_ID = 5 -- ПРОВЕРЬ ID ДОМА!

local function getSafeData(p, func, default)
    if p and p[func] then 
        local ok, result = pcall(p[func])
        if ok then return result end
    end
    return default
end

while true do
    term.clear()
    term.setCursorPos(1,1)
    print("PK1: SENDER ACTIVE")

    -- Поиск всех блоков
    local fission = peripheral.find("fissionReactorLogicAdapter")
    local fusion = peripheral.find("fusionReactorLogicAdapter")
    local boiler = peripheral.find("boilerValve")
    local turbine = peripheral.find("turbineValve")

    -- Сбор данных через безопасную проверку
    local data = {
        f_temp     = getSafeData(fission, "getTemperature", 0),
        f_status   = getSafeData(fission, "getStatus", false),
        fu_temp    = getSafeData(fusion, "getTemperature", 0),
        fu_active  = getSafeData(fusion, "isIgnited", false),
        b_steam    = getSafeData(boiler, "getSteam", 0),
        b_maxSteam = getSafeData(boiler, "getSteamCapacity", 1),
        t_flow     = getSafeData(turbine, "getFlowRate", 0)
    }

    -- Вывод статуса в консоль для тебя
    print("Fission: " .. (fission and "OK" or "MISSING"))
    print("Fusion:  " .. (fusion and "OK" or "MISSING"))
    print("Boiler:  " .. (boiler and "OK" or "MISSING"))
    print("Turbine: " .. (turbine and "OK" or "MISSING"))

    rednet.send(HOST_ID, data, "PLANT_DATA")
    print("\nData sent to ID " .. HOST_ID)
    
    sleep(1)
end