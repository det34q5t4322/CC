-- Ищем модем и открываем сеть
peripheral.find("modem", rednet.open)

local core0 = peripheral.wrap("draconic_rf_storage_0")
local core1 = peripheral.wrap("draconic_rf_storage_1")
local reactor = peripheral.wrap("fissionReactorLogicAdapter_7")
local sps = peripheral.wrap("spsPort_0")
local tank = peripheral.wrap("ultimateChemicalTank_0") -- Бак с антиматерией!

print("=> DATA TRANSMITTER ONLINE <=")
print("Broadcasting to BASE_TELEMETRY...")

while true do
    -- Собираем сырые данные
    local data = {
        energy = 0,
        maxEnergy = 1,
        temp = 0,
        reactorOn = false,
        spsUsage = 0,
        antimatter = 0,
        maxAntimatter = 8000000 -- Емкость Ultimate бака (поменяй если другая)
    }

    -- Безопасный опрос. Если блок отвалится, скрипт не крашнется.
    pcall(function() 
        data.energy = (core0 and core0.getEnergyStored() or 0) + (core1 and core1.getEnergyStored() or 0)
        data.maxEnergy = (core0 and core0.getMaxEnergyStored() or 1) + (core1 and core1.getMaxEnergyStored() or 1)
    end)
    pcall(function() 
        data.temp = reactor and reactor.getTemperature() or 0 
        data.reactorOn = reactor and reactor.getStatus() or false
    end)
    pcall(function() data.spsUsage = sps and sps.getEnergyUsage() or 0 end)
    pcall(function()
        local gas = tank and tank.getStored()
        if gas then data.antimatter = gas.amount end
    end)

    -- Отправляем в эфир по протоколу
    rednet.broadcast(data, "BASE_TELEMETRY")
    sleep(1) -- Тик обновления. Чаще не нужно, забьет сеть.
end