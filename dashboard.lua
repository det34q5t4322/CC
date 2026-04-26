-- ============================================================
--  Mekanism + Draconic Evolution  |  Telemetry Transmitter
--  ComputerCraft 1.20.1  |  Wireless modem  |  Channel: 99
-- ============================================================

local CHANNEL  = 99
local INTERVAL = 0.75

-- ============================================================
--  Safe call helpers
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
--  Find WIRELESS modem (wired modems cannot transmit cross-computer)
-- ============================================================
local function findWirelessModem()
    for _, name in ipairs(peripheral.getNames()) do
        local p = peripheral.wrap(name)
        if peripheral.getType(name) == "modem" then
            -- wireless modems have isWireless method
            if p.isWireless and p.isWireless() then
                return p, name
            end
        end
    end
    -- fallback: try peripheral.find but warn user
    local m = peripheral.find("modem")
    if m then
        print("[WARN] Could not confirm wireless - using first modem found")
        return m, "unknown"
    end
    return nil, nil
end

-- ============================================================
--  Device discovery
-- ============================================================
local function findDevices()
    local devs = {}

    devs.energyCore     = peripheral.find("draconic_rf_storage")
    devs.fissionReactor = peripheral.find("fissionReactorLogicAdapter")
    devs.fusionReactor  = peripheral.find("fusionReactorLogicAdapter")
    devs.boiler         = peripheral.find("boilerValve")
    devs.sps            = peripheral.find("spsPort")
    devs.chemTank       = peripheral.find("ultimateChemicalTank")

    devs.turbines = {}
    local found = table.pack(peripheral.find("turbineValve"))
    for i = 1, found.n do
        table.insert(devs.turbines, found[i])
    end

    local modemDev, modemName = findWirelessModem()
    devs.modem     = modemDev
    devs.modemName = modemName or "none"

    return devs
end

-- ============================================================
--  Debug: print found devices
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
            print("  [--] " .. label .. " (not found)")
        end
    end
    status(devs.energyCore,     "Draconic Energy Core")
    status(devs.fissionReactor, "Fission Reactor")
    status(devs.fusionReactor,  "Fusion Reactor")
    status(devs.boiler,         "Boiler")
    status(devs.sps,            "SPS Port")
    status(devs.chemTank,       "Chemical Tank")
    if devs.modem then
        print("  [OK] Wireless Modem -> " .. devs.modemName)
    else
        print("  [!!] Wireless Modem -> NOT FOUND")
    end
    if #devs.turbines == 0 then
        print("  [--] Turbines (not found)")
    else
        for i, t in ipairs(devs.turbines) do
            print("  [OK] Turbine #" .. i .. " -> " .. peripheral.getName(t))
        end
    end
    print("============================================")
end

-- ============================================================
--  Telemetry collection
-- ============================================================
local function collectTelemetry(devs)
    local t = {}

    -- Энерго-ядро (Пробуем 3 варианта названия)
    local ec = devs.energyCore
    t.energyCore = {
        stored = getNum(ec, "getEnergyStored") or getNum(ec, "getEnergy") or getNum(ec, "getStored"),
        max    = getNum(ec, "getMaxEnergyStored") or getNum(ec, "getMaxEnergy") or getNum(ec, "getCapacity") or 1,
        transferRate = getNum(ec, "getTransferNet") or 0,
    }

    -- Реактор деления (Пробуем разные API Mekanism)
    local fr = devs.fissionReactor
    t.fissionReactor = {
        active      = getBool(fr, "getStatus") or getBool(fr, "isActive"),
        temperature = getNum(fr, "getTemperature"),
        damage      = getNum(fr, "getDamagePercent"),
        burnRate    = getNum(fr, "getBurnRate"),
        fuelFilled  = getNum(fr, "getFuelFilled"),
    }

    -- Бойлер
    local bl = devs.boiler
    t.boiler = {
        temperature = getNum(bl, "getTemperature"),
        water       = getNum(bl, "getWater"),
        steam       = getNum(bl, "getSteam"),
        boilRate    = getNum(bl, "getBoilRate"),
        maxBoilRate = getNum(bl, "getMaxBoilRate") or 1,
    }

    -- SPS (Антиматерия)
    local sp = devs.sps
    t.sps = {
        inputRate  = getNum(sp, "getInputRate") or getNum(sp, "getEnergyUsage"),
        outputRate = getNum(sp, "getOutputRate") or getNum(sp, "getProductionRate"),
    }

    return t
end

-- ============================================================
--  Main loop
-- ============================================================
local devs = findDevices()
printDeviceList(devs)

if not devs.modem then
    print("[FATAL] No wireless modem found!")
    print("  -> Attach an Ender Modem or Wireless Modem to this computer")
    print("  -> Wired modems (cables) do NOT work for cross-computer transmit")
    return
end

devs.modem.open(CHANNEL)
print("[START] Transmitting on channel " .. CHANNEL)
print("  Modem: " .. devs.modemName)
print("--------------------------------------------")

local tick = 0
while true do
    tick = tick + 1
    local data = collectTelemetry(devs)
    data.tick = tick

    local ok, err = pcall(function()
        devs.modem.transmit(CHANNEL, CHANNEL, data)
    end)

    if not ok then
        print("[ERR] Transmit failed: " .. tostring(err))
    else
        local ec  = data.energyCore
        local fr  = data.fissionReactor
        local pct = (ec.max > 0) and math.floor(ec.stored / ec.max * 100) or 0
        term.clearLine()
        io.write(string.format(
            "\r[#%04d] E:%3d%%  Fis:%-3s  T:%.0f  SPS:%.1f",
            tick, pct,
            fr.active and "ON" or "OFF",
            fr.temperature,
            data.sps.inputRate
        ))
    end

    os.sleep(INTERVAL)
end
