-- ============================================================
--  Mekanism + Draconic Evolution Telemetry Transmitter
--  ComputerCraft 1.20.1  |  Modem channel: 99
-- ============================================================

local CHANNEL    = 99
local INTERVAL   = 0.75   -- секунд между передачами

-- ============================================================
--  Утилиты
-- ============================================================

local function safe(fn, ...)
    local ok, val = pcall(fn, ...)
    if ok then return val end
    return nil
end

local function getNum(dev, method)
    if not dev then return 0 end
    local v = safe(dev[method], dev)
    return (type(v) == "number") and v or 0
end

local function getBool(dev, method)
    if not dev then return false end
    local v = safe(dev[method], dev)
    return (v == true)
end

local function getStr(dev, method)
    if not dev then return "N/A" end
    local v = safe(dev[method], dev)
    return (type(v) == "string") and v or "N/A"
end

-- ============================================================
--  Автопоиск устройств
-- ============================================================

local function findDevices()
    local devs = {}

    devs.energyCore     = peripheral.find("draconic_rf_storage")
    devs.fissionReactor = peripheral.find("fissionReactorLogicAdapter")
    devs.fusionReactor  = peripheral.find("fusionReactorLogicAdapter")
    devs.boiler         = peripheral.find("boilerValve")
    devs.sps            = peripheral.find("spsPort")
    devs.chemTank       = peripheral.find("ultimateChemicalTank")
    devs.modem          = peripheral.find("modem")

    -- Турбин может быть несколько — собираем все
    devs.turbines = {}
    local found = table.pack(peripheral.find("turbineValve"))
    for i = 1, found.n do
        table.insert(devs.turbines, found[i])
    end

    return devs
end

-- ============================================================
--  Отладочный вывод найденных устройств
-- ============================================================

local function printDeviceList(devs)
    print("============================================")
    print("  TELEMETRY TRANSMITTER  |  ch." .. CHANNEL)
    print("============================================")

    local function status(dev, label)
        if dev then
            local name = peripheral.getName(dev)
            print("  [OK] " .. label .. " -> " .. name)
        else
            print("  [--] " .. label .. " (не найдено)")
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
        print("  [--] Turbines (не найдено)")
    else
        for i, t in ipairs(devs.turbines) do
            local name = peripheral.getName(t)
            print("  [OK] Turbine #" .. i .. " -> " .. name)
        end
    end

    print("============================================")
end

-- ============================================================
--  Сбор телеметрии
-- ============================================================

local function collectTelemetry(devs)
    local t = {}
    t.timestamp = os.clock()

    -- --- Draconic Energy Core ---
    local ec = devs.energyCore
    t.energyCore = {
        stored      = getNum(ec, "getEnergyStored"),
        max         = getNum(ec, "getMaxEnergyStored"),
        transferRate = getNum(ec, "getTransferPerTick"),
    }

    -- --- Mekanism Fission Reactor ---
    local fr = devs.fissionReactor
    t.fissionReactor = {
        active          = getBool(fr, "isActive"),
        temperature     = getNum(fr, "getTemperature"),
        damage          = getNum(fr, "getDamagePercent"),
        burnRate        = getNum(fr, "getActualBurnRate"),
        heatCapacity    = getNum(fr, "getHeatCapacity"),
        fuelFilled      = getNum(fr, "getFuelFilledPercentage"),
    }

    -- --- Mekanism Fusion Reactor ---
    local fu = devs.fusionReactor
    t.fusionReactor = {
        caseTemp        = getNum(fu,  "getCaseTemperature"),
        plasmaTemp      = getNum(fu,  "getPlasmaTemperature"),
        ignited         = getBool(fu, "isIgnited"),
        productionRate  = getNum(fu,  "getProductionRate"),
    }

    -- --- Mekanism Boiler ---
    local bo = devs.boiler
    t.boiler = {
        temperature     = getNum(bo, "getTemperature"),
        water           = getNum(bo, "getWater"),
        steam           = getNum(bo, "getSteam"),
        boilRate        = getNum(bo, "getBoilRate"),
        maxBoilRate     = getNum(bo, "getMaxBoilRate"),
    }

    -- --- Mekanism Turbines ---
    t.turbines = {}
    for i, turb in ipairs(devs.turbines) do
        t.turbines[i] = {
            speed           = getNum(turb, "getFlowRate"),
            production      = getNum(turb, "getProductionRate"),
            steamFlow       = getNum(turb, "getSteamInput"),
            maxSteamFlow    = getNum(turb, "getMaxFlowRate"),
        }
    end

    -- --- Mekanism SPS ---
    местный sp = devs.sps
 t.sps = {
 inputRate = getNum(sp, "getInputRate"),
 outputRate = getNum(sp, "getOutputRate"),
    }

    -- --- Химический резервуар ---
    местный ct = devs.chemTank
 t.chemTank = {
 сохранено = getNum(ct, "getStored"),
 макс = getNum(ct, "getCapacity"),
 газ = getStr(ct, "getGas"),
    }

    возвращаться t
конец

-- ===================================================
-- Основной цикл
-- ===================================================

местный devs = findDevices()
printDeviceList(devs)

если нет devs.модем затем
 печать("[ФАТАЛ] Модем не найден. Скрипт остановлен.")
    возвращаться
конец

devs.modem.open(КАНАЛ)
печать("[СТАРТ] Передача запушена -> канал" .. КАНАЛ)
печать("------------------------------------------")

местный галочка = 0
пока истинный делать
 тик = тик + 1
    местный данные = collectTelemetry(devs)
 data.tick = тик

    местный ок, ошибка = pcall(функция()
 devs.modem.transmit(КАНАЛ, КАНАЛ, данные)
    конец)

    если нет хорошо затем
 печать("[ERR] Ошибка записи: " .. tostring(ошибка))
    еще
        -- Краткий статус в консоль
        местный ec = data.energyCore
        местный pct = (ec.max > 0)
            и math.floor(ec.stored / ec.max * 100)
            или 0
        местный fr = data.fissionReactor
 term.clearLine()
 io.write(строка.формат(
            "\r[#%04d] E:%d%% Fis:%s %.0f°C SPS-in:%.1f",
 тик, пкт,
 фр.активный и "НА" или "ВЫКЛ",
 фр.температура,
 data.sps.inputRate
 ))
    конец

 os.sleep(ИНТЕРВАЛ)
конец
