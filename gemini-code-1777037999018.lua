peripheral.find("modem", rednet.open)

local core0 = peripheral.wrap("draconic_rf_storage_0")
local core1 = peripheral.wrap("draconic_rf_storage_1")
local reactor = peripheral.wrap("fissionReactorLogicAdapter_7")
local sps = peripheral.wrap("spsPort_0")
local tank = peripheral.wrap("ultimateChemicalTank_0")

print("=> TRANSMITTER UPDATED: MIRROR MODE ONLINE <=")

while true do
    local data = {
        energy = 0, maxEnergy = 1,
        input = 0, output = 0, -- Новые поля
        temp = 0, reactorOn = false,
        spsUsage = 0, antimatter = 0, maxAntimatter = 8000000
    }

    pcall(function() 
        data.energy = (core0.getEnergyStored() or 0) + (core1.getEnergyStored() or 0)
        data.maxEnergy = (core0.getMaxEnergyStored() or 1) + (core1.getMaxEnergyStored() or 1)
        -- Берем данные потоков напрямую из ядра
        data.input = core0.getInputPerTick() or 0
        data.output = core0.getOutputPerTick() or 0
    end)
    
    pcall(function() 
        data.temp = reactor.getTemperature() or 0 
        data.reactorOn = reactor.getStatus() or false
    end)
    
    pcall(function() data.spsUsage = sps.getEnergyUsage() or 0 end)
    
    pcall(function()
        local gas = tank.getStored()
        if gas then data.antimatter = gas.amount end
    end)

    rednet.broadcast(data, "BASE_TELEMETRY")
    sleep(0.5) -- Ускоряем передачу для плавности графика
end