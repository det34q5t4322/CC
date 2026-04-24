-- PK1: PLANT SENSOR (FIXED)
peripheral.find("modem", rednet.open)
local HOST_ID = 5 -- ПРОВЕРЬ ID ДОМА!

while true do
    -- Ищем устройства
    local fission = peripheral.find("fissionReactorLogicAdapter")
    local fusion = peripheral.find("fusionReactorLogicAdapter")
    local boiler = peripheral.find("boilerValve")
    local turbine = peripheral.find("turbineValve")

    -- Собираем данные только если устройство найдено (проверка not nil)
    local data = {
        f_temp = 0, f_status = false, fu_temp = 0, fu_active = false,
        b_steam = 0, b_maxSteam = 1, t_flow = 0
    }

    if fission then
        data.f_temp = fission.getTemperature()
        data.f_status = fission.getStatus()
    else
        print("Wait: Fission not found!")
    end

    if fusion then
        data.fu_temp = fusion.getTemperature()
        data.fu_active = fusion.isIgnited()
    else
        print("Wait: Fusion not found!")
    end

    if boiler then
        data.b_steam = boiler.getSteam()
        data.b_maxSteam = boiler.getSteamCapacity()
    end
    
    if turbine then
        data.t_flow = turbine.getFlowRate()
    end

    -- Отправляем что есть
    rednet.send(HOST_ID, data, "PLANT_DATA")
    print("Heartbeat sent to ID " .. HOST_ID)
    
    sleep(1)
end