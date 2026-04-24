-- ПК №1: ЗАВОД (ВЕРСИЯ "АНТИ-НИЛ")
peripheral.find("modem", rednet.open)
local HOST_ID = 5 -- УБЕДИСЬ, ЧТО ЭТО ID ТВОЕГО КОМПА ДОМА

while true do
    -- Ищем блоки заново каждый цикл (на случай, если провод отвалится)
    local fission = peripheral.find("fissionReactorLogicAdapter")
    local fusion = peripheral.find("fusionReactorLogicAdapter")
    local boiler = peripheral.find("boilerValve")
    local turbine = peripheral.find("turbineValve")

    local data = {
        f_temp = 0, f_status = false,
        fu_temp = 0, fu_active = false,
        b_steam = 0, b_maxSteam = 1, t_flow = 0
    }

    -- Проверяем ЯДЕРНЫЙ
    if fission then
        data.f_temp = fission.getTemperature()
        data.f_status = fission.getStatus()
    else
        print("Wait: Fission reactor NOT connected")
    end

    -- Проверяем ТЕРМОЯДЕРНЫЙ
    if fusion then
        data.fu_temp = fusion.getTemperature()
        data.fu_active = fusion.isIgnited()
    end

    -- Проверяем БОЙЛЕР
    if boiler then
        data.b_steam = boiler.getSteam()
        data.b_maxSteam = boiler.getSteamCapacity()
    end

    -- Проверяем ТУРБИНУ
    if turbine then
        data.t_flow = turbine.getFlowRate()
    end

    -- Шлем пакет (теперь программа точно не вылетит)
    rednet.send(HOST_ID, data, "PLANT_DATA")
    print("Data packet sent to ID " .. HOST_ID)
    
    sleep(1)
end