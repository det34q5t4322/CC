-- PK1: PLANT SENSOR
peripheral.find("modem", rednet.open)
local HOST_ID = 5 -- ID домашнего ПК (проверь командой 'id' дома)

while true do
    -- Авто-поиск периферии
    local fission = peripheral.find("fissionReactorLogicAdapter")
    local fusion = peripheral.find("fusionReactorLogicAdapter")
    local boiler = peripheral.find("boilerValve")
    local turbine = peripheral.find("turbineValve")

    local data = {
        f_temp = fission and fission.getTemperature() or 0,
        f_burn = fission and fission.getBurnRate() or 0,
        f_status = fission and fission.getStatus() or false,
        fu_temp = fusion and fusion.getTemperature() or 0,
        fu_active = fusion and fusion.isIgnited() or false,
        b_steam = boiler and boiler.getSteam() or 0,
        b_maxSteam = boiler and boiler.getSteamCapacity() or 1,
        t_flow = turbine and turbine.getFlowRate() or 0
    }

    rednet.send(HOST_ID, data, "PLANT_DATA")
    print("Plant data sent to " .. HOST_ID)
    sleep(1)
end