местный базальт = требуется("базальт")

-- Ищем монитор
местный mon = периферийный.найти("монитор")

местный основной
если мон затем
    -- В новых версиях создаем фрейм именно для монитора так:
 main = basalt.addMonitor():setMonitor(mon)
еще
    -- Если монитора нет, рисуем на самом компе
 main = basalt.createFrame()
конец

main:addLabel()
 :setPosition(2, 2)
 :setText("СИСТЕМА СТАРТ")
 :setForeground(цвета.жельные)

main:addButton()
 :setPosition(2, 4)
 :setSize(15, 3)
 :setText("ПРОВЕРКА")
 :setBackground(цвета.синий)
 :onClick(функция(себя)
 self:setText("ОК!")
 self:setBackground(цвета.зеленый)
 конец)

-- Самый надежный способ запуска для новых версий
базальт.автоОбновление()
