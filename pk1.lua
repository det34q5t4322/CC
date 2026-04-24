-- Настройка Rednet
local modemSide = "top" -- Поменяй на сторону, где стоит модем
if peripheral.isPresent(modemSide) then
    rednet.open(modemSide)
else
    peripheral.find("modem", rednet.open)
end

-- Периферия (ID из твоих прошлых скринов)
local fission = peripheral.wrap("fissionReactorLogicAdapter_7")
local fusion  = peripheral.wrap("fusionReactorLogicAdapter_0")
local boiler  = peripheral.wrap("boilerValve_0")
local turbine = peripheral.wrap("turbineValve_0")
local sps     = peripheral.wrap("spsPort_0")
local tank    = peripheral.wrap("ultimateChemicalTank_0")

print("PK1: PLANT MONITOR ONLINE")

while true do
    local data = {
        -- Fission Reactor
        f_temp = 0, f_burn = 0, f_status = false,
        -- Fusion Reactor
        fu_temp = 0, fu_active = false,
        -- Boiler & Turbine
        b_steam = 0, b_maxSteam = 1, b_water = 0,
        t_flow = 0,
        -- SPS & Antimatter
        anti_amount = 0, anti_rate = 0
    }

    -- Безопасный сбор данных
    pcall(function()
        if fission then
            data.f_temp = fission.getTemperature()
            data.f_burn = fission.getBurnRate()
            data.f_status = fission.getStatus()
        end
        if fusion then
            data.fu_temp = fusion.getTemperature()
            data.fu_active = fusion.getStatus()
        end
        if boiler then
            local steam = boiler.getSteam()
            data.b_steam = steam.amount
            data.b_maxSteam = boiler.getSteamCapacity()
            data.b_water = boiler.getWater().amount
        end
        if turbine then
            data.t_flow = turbine.getFlowRate()
        end
        if sps then
            data.anti_rate = sps.getEnergyUsage()
        end
        if tank then
            local gas = tank.getStored()
            if gas then data.anti_amount = gas.amount end
        end
    end)

    -- Отправляем пакет "PLANT_DATA"
    rednet.broadcast(data, "PLANT_DATA")
    
    print("Data sent at " .. os.time())
    sleep(0.5) -- Частота обновления
end