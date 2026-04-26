local basalt = require("basalt")

-- Создаем основной фрейм (окно)
local main = basalt.createFrame()

-- Настраиваем монитор, если он есть
local mon = peripheral.find("monitor")
if mon then
    main:setMonitor(mon)
end

main:addLabel()
    :setPosition(2, 2)
    :setText("СИСТЕМА ОК")
    :setForeground(colors.yellow)

main:addButton()
    :setPosition(2, 4)
    :setSize(15, 3)
    :setText("ПРОВЕРКА")
    :setBackground(colors.blue)
    :onClick(function(self)
        self:setText("РАБОТАЕТ")
        self:setBackground(colors.green)
    end)

-- Вместо autoUpdate используем ручной цикл
while true do
    basalt.update()
end