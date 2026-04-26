-- ===================================================
-- Меканизм + Драконья эволюция | Телеметрический передатчик
-- ComputerCraft 1.20.1 | Канал модема: 99
-- ===================================================

местный КАНАЛ = 99
местный ИНТЕРВАЛ = 0,75

-- ===================================================
-- Помощники по безопасному вызову
-- ===================================================

local функция безопасно(фн, ...)
    местный ок, val = pcall(fn, ...)
    если хорошо затем возвращаться вал конец
    возвращаться ноль
конец

местный функция getNum(dev, метод)
    если нет дев затем возвращаться 0 конец
    местный v = безопасно(dev[метод], dev)
    возвращаться (тип(v) == "число") и v или 0
конец

местный функция getBool(dev, метод)
    если нет дев затем возвращаться ложный конец
    местный v = безопасно(dev[метод], dev)
    возвращаться (в == истинный)
конец

местный функция getStr(dev, метод)
    если нет дев затем возвращаться "Н/Д" конец
    местный v = безопасно(dev[метод], dev)
    возвращаться (тип(v) == "струна") и v или "Н/Д"
конец

-- ===================================================
-- Обнаружение устройства
-- ===================================================

местный функция найтиУстройства()
    местный разработчики = {}

 devs.energyCore = периферийное устройство.find("draconic_rf_storage")
 devs.fissionReactor = периферийный.find("fissionReactorLogicAdapter")
 devs.fusionReactor = периферийное устройство.find("fusionReactorLogicAdapter")
 devs.boiler = периферийное устройство.find("клапан котла")
 devs.sps = периферийное устройство.find("spsPort")
 devs.chemTank = периферийное устройство.find("ultimateChemicalTank")
 devs.modem = периферийное устройство.find("модем")

 devs.turbines = {}
    местный найдено = таблица.пакет(периферийное.найти("турбинный клапан"))
    для я = 1, найдено.n делать
 table.insert(devs.turbines, найдено[i])
    конец

    возвращаться разработчики
конец

-- ===================================================
-- Отладка: распечатать найденные устройства
-- ===================================================

местный функция printDeviceList(devs)
 печать("==========================================)
 печать(" ТЕЛЕМЕТРИЧЕСКИЙ ПЕРЕДАТЧИК | гл." .. КАНАЛ)
 печать("==========================================)

    местный функция статус(dev, метка)
        если дев затем
            местный имя = periferic.getName(dev)
 печать(" [ОК]" .. этикетка .. " -> " .. имя)
        else
            print("  [--] " .. label .. " (not found)")
        end
    end

    status(devs.energyCore,     "Draconic Energy Core")
    status(devs.fissionReactor, "Fission Reactor")
    status(devs.fusionReactor,  "Fusion Reactor")
    status(devs.boiler,         "Boiler")
    status(devs.sps,            "SPS Port")
    status(devs.chemTank,       "Chemical Tank")
    status(devs.modem,          "Wireless Modem")

    if #devs.turbines == 0 then
        print("  [--] Turbines (not found)")
    else
        for i, t in ipairs(devs.turbines) do
            local name = peripheral.getName(t)
            print("  [OK] Turbine #" .. i .. " -> " .. name)
        end
    end

    print("============================================")
end

-- ============================================================
--  Telemetry collection
-- ============================================================

local function collectTelemetry(devs)
    local t = {}
    t.timestamp = os.clock()

    -- Draconic Energy Core
    local ec = devs.energyCore
    t.energyCore = {
        stored       = getNum(ec, "getEnergyStored"),
        max          = getNum(ec, "getMaxEnergyStored"),
        transferRate = getNum(ec, "getTransferPerTick"),
    }

    -- Mekanism Fission Reactor
    local fr = devs.fissionReactor
    t.fissionReactor = {
        active       = getBool(fr, "isActive"),
        temperature  = getNum(fr,  "getTemperature"),
        damage       = getNum(fr,  "getDamagePercent"),
        burnRate     = getNum(fr,  "getActualBurnRate"),
        heatCapacity = getNum(fr,  "getHeatCapacity"),
        fuelFilled   = getNum(fr,  "getFuelFilledPercentage"),
    }

    -- Mekanism Fusion Reactor
    local fu = devs.fusionReactor
    t.fusionReactor = {
        caseTemp     = getNum(fu,  "getCaseTemperature"),
        plasmaTemp   = getNum(fu,  "getPlasmaTemperature"),
        ignited      = getBool(fu, "isIgnited"),
        productionRate = getNum(fu, "getProductionRate"),
    }

    -- Mekanism Boiler
    local bo = devs.boiler
    t.boiler = {
        temperature  = getNum(bo, "getTemperature"),
        water        = getNum(bo, "getWater"),
        steam        = getNum(bo, "getSteam"),
        boilRate     = getNum(bo, "getBoilRate"),
        maxBoilRate  = getNum(bo, "getMaxBoilRate"),
    }

    -- Mekanism Turbines (all found)
    t.turbines = {}
    for i, turb in ipairs(devs.turbines) do
        t.turbines[i] = {
 скорость = getNum(turb, "getFlowRate"),
 производство = getNum(turb, "getProductionRate"),
 steamFlow = getNum(турб, "getSteamInput"),
 maxSteamFlow = getNum(turb, "getMaxFlowRate"),
        }
    конец

    -- Меканизм СПС
    местный sp = devs.sps
 t.sps = {
 inputRate = getNum(sp, "getInputRate"),
 outputRate = getNum(sp, "getOutputRate"),
    }

    -- Абсолютный химический резервуар
    местный ct = devs.chemTank
 t.chemTank = {
 сохранено = getNum(ct, "getStored"),
 макс = getNum(ct, "getCapacity"),
 газ = getStr(ct, "getGas"),
    }

    возвращаться t
конец

-- ==================================================
-- Основной цикл
-- ==================================================

местный devs = findDevices()
printDeviceList(devs)

если нет devs.модем затем
 печать(«[FATAL] Модем не найден. Остановка»)
    возвращаться
конец

devs.modem.open(КАНАЛ)
печать("[СТАРТ] Передача по каналу" .. КАНАЛ)
печать("-----------------------------------------")

местный галочка = 0
пока истинный делать
 тик = тик + 1
    местный данные = collectTelemetry(devs)
 data.tick = тик

    местный ок, ошибка = pcall(функция()
 devs.modem.transmit(КАНАЛ, КАНАЛ, данные)
    конец)

    если нет хорошо затем
 печать("[ERR] Передача не удалась:" .. tostring(ошибка))
    еще
        местный ec = data.energyCore
        местный fr = data.fissionReactor
        местный pct = (ec.max > 0) и math.floor(ec.stored / ec.max * 100) или 0
 term.clearLine()
 io.write(строка.формат(
            "\r[#%04d] E:%3d%% Fis:%-3s T:%.0fC SPS-in:%.1f",
 клещ,
 пкт,
 фр.активный и "ВКЛ" или "ВЫКЛ",
 фр.температура,
 data.sps.inputRate
 ))
    конец

 os.sleep(ИНТЕРВАЛ)
конец
