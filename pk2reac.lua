-- Настройка Rednet
local modemSide = "top" -- Поменяй на сторону, где стоит модем
if peripheral.isPresent(modemSide) then
    rednet.open(modemSide)
else
    peripheral.find("modem", rednet.open)
end

local core0 = peripheral.wrap("draconic_rf_storage_0")
local core1 = peripheral.wrap("draconic_rf_storage_1")

print("PK2: CORE MONITOR ONLINE")

while true do
    local coreData = {
        energy = 0,
        maxEnergy = 1,
        input = 0,
        output = 0
    }

    pcall(function()
        -- Суммируем данные с двух портов/хранилищ ядра
        coreData.energy = (core0.getEnergyStored() or 0) + (core1.getEnergyStored() or 0)
        coreData.maxEnergy = (core0.getMaxEnergyStored() or 1) + (core1.getMaxEnergyStored() or 1)
        coreData.input = core0.getInputPerTick() or 0
        coreData.output = core0.getOutputPerTick() or 0
    end)

    -- Отправляем пакет "CORE_DATA"
    rednet.broadcast(coreData, "CORE_DATA")
    
    print("Core metrics broadcasted...")
    sleep(0.2) -- Ядро обновляем чаще для плавного графика
end