local basalt = require("basalt")

-- Находим монитор и "оборачиваем" его
local mon = peripheral.find("monitor")

-- Если монитор есть, перенаправляем весь вывод на него принудительно
if mon then
    term.redirect(mon)
end

-- Теперь просто создаем фрейм, он автоматически появится на мониторе
local main = basalt.createFrame()

main:addLabel()
    :setPosition(2, 2)
    :setText("СИСТЕМА СТАРТ")
    :setForeground(colors.yellow)

main:addButton()
    :setPosition(2, 4)
    :setSize(15, 3)
    :setText("ПРОВЕРКА")
    :setBackground(colors.blue)
    :onClick(function(self)
        self:setText("ОК!")
        self:setBackground(colors.green)
    end)

-- Используем обычный цикл обновления
while true do
    basalt.update()
end
