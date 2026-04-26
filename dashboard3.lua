-- ============================================================
--  FLOOR DISPLAY  |  monitor_25  |  Animated Energy Flow
--  Standalone module - included from dashboard or run solo
--  Call: renderFloor(mon, data, meData, blink, dotPos)
-- ============================================================

-- This file is the floor render module.
-- The full dashboard.lua already includes this logic inline.
-- See dashboard.lua for the complete system.

-- ============================================================
--  FULL STANDALONE DASHBOARD v3
--  monitor_24=LEFT  monitor_22=CENTER  monitor_25=FLOOR
-- ============================================================

local data = {
    energyCore     = { stored=0, max=1, transferRate=0 },
    fissionReactor = { active=false, temperature=0, damage=0,
                       burnRate=0, fuelFilled=0 },
    fusionReactor  = { caseTemp=0, plasmaTemp=0, ignited=false, productionRate=0 },
    boiler         = { temperature=0, water=0, steam=0, boilRate=0, maxBoilRate=1 },
    turbines       = {},
    sps            = { inputRate=0, outputRate=0 },
    chemTank       = { stored=0, max=1, gas="N/A" },
    tick           = 0,
}
local meData      = { antimatter=0, deuterium=0, tritium=0 }
local history     = {}
local MAX_HIST    = 50
local alertActive = false
local dataRcv     = false
local blink       = false
local frame       = 0   -- global animation counter

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function energyPct()
    if (data.energyCore.max or 0)<=0 then return 0 end
    return data.energyCore.stored/data.energyCore.max
end
local function fmtBig(n)
    n=n or 0
    if n>=1e12 then return string.format("%.1fT",n/1e12)
    elseif n>=1e9 then return string.format("%.1fG",n/1e9)
    elseif n>=1e6 then return string.format("%.1fM",n/1e6)
    elseif n>=1e3 then return string.format("%.1fK",n/1e3)
    else return tostring(math.floor(n)) end
end
local function fmtPct(v) return string.format("%d%%",math.floor(clamp(v,0,1)*100)) end
local function pushHist(v)
    table.insert(history,v)
    if #history>MAX_HIST then table.remove(history,1) end
end
local function reactorCol(t)
    if t<400 then return colors.green
    elseif t<1000 then return colors.yellow
    elseif t<2500 then return colors.orange
    else return colors.red end
end

-- ============================================================
--  Peripherals
-- ============================================================
local modem    = peripheral.find("modem")
local meBridge
pcall(function() meBridge = peripheral.wrap("meBridge_1") end)
local monL = peripheral.wrap("monitor_24")
local monC = peripheral.wrap("monitor_22")
local monF = peripheral.wrap("monitor_25")

for _,m in ipairs({monL,monC,monF}) do
    if m then m.setTextScale(0.5); m.setBackgroundColor(colors.black); m.clear() end
end
if modem then modem.open(99) end

-- ============================================================
--  Draw primitives
-- ============================================================
local function p(mon,x,y,txt,fg,bg)
    if not mon or x<1 or y<1 then return end
    mon.setCursorPos(x,y)
    if bg then mon.setBackgroundColor(bg) end
    if fg then mon.setTextColor(fg) end
    mon.write(txt)
end
local function hln(mon,x,y,w,ch,fg) p(mon,x,y,string.rep(ch,w),fg,colors.black) end
local function pbar(mon,x,y,w,pct,fg)
    pct=clamp(pct,0,1); local f=math.floor(pct*w)
    p(mon,x,y,string.rep("\127",f),fg,colors.black)
    p(mon,x+f,y,string.rep("\127",w-f),colors.gray,colors.black)
end
local function box(mon,x,y,w,h,fg,title)
    p(mon,x,y,"+"..string.rep("-",w-2).."+",fg,colors.black)
    for r=y+1,y+h-2 do p(mon,x,r,"|",fg,colors.black); p(mon,x+w-1,r,"|",fg,colors.black) end
    p(mon,x,y+h-1,"+"..string.rep("-",w-2).."+",fg,colors.black)
    if title then p(mon,x+2,y," "..title.." ",colors.yellow,colors.black) end
end
local function vbar(mon,x,yB,h,pct,fg)
    pct=clamp(pct,0,1); local f=math.floor(pct*h)
    for i=0,h-1 do
        if i<f then p(mon,x,yB-i,"\127",fg,colors.black)
        else p(mon,x,yB-i,":",colors.gray,colors.black) end
    end
end

-- ============================================================
--  ME Bridge
-- ============================================================
local function queryME()
    if not meBridge then return end
    local function gi(nm)
        local ok,res=pcall(function() return meBridge.getItem({name=nm}) end)
        if ok and res then return res.amount or 0 end; return 0
    end
    meData.antimatter=gi("mekanism:antimatter")
    meData.deuterium =gi("mekanism:deuterium")
    meData.tritium   =gi("mekanism:tritium")
end

-- ============================================================
--  ALERT
-- ============================================================
local function triggerAlert(active)
    alertActive=active
    if not active then return end
    local function flash(mon)
        if not mon then return end
        local W,H=mon.getSize()
        mon.setBackgroundColor(colors.red); mon.clear()
        local lines={"!!! CRITICAL ALERT !!!","SYSTEM INTEGRITY VIOLATED","CHECK FISSION / ENERGY CORE"}
        for i,m in ipairs(lines) do
            local px=math.max(1,math.floor((W-#m)/2)+1)
            mon.setCursorPos(px,math.floor(H/2)-1+(i-1))
            mon.setTextColor(i==1 and colors.yellow or colors.white)
            mon.setBackgroundColor(colors.red); mon.write(m)
        end
    end
    flash(monL); flash(monC); flash(monF)
    local spk=peripheral.find("speaker")
    if spk then pcall(function() spk.playNote("harp",3,18) end) end
end
local function checkAlerts()
    if not dataRcv then return end
    local dmg=data.fissionReactor.damage or 0
    local should=(dmg>0) or (energyPct()<0.05)
    if should~=alertActive then triggerAlert(should) end
end

-- ============================================================
--  CENTER MONITOR
-- ============================================================
local function drawRing(mon,cx,cy,r,pct)
    local N=28
    for i=0,N-1 do
        local a=(i/N)*math.pi*2-math.pi/2
        local px=math.floor(cx+r*2.1*math.cos(a)+0.5)
        local py=math.floor(cy+r*math.sin(a)+0.5)
        if px>=1 and py>=1 then
            mon.setCursorPos(px,py)
            if (i/N)<=pct then
                mon.setTextColor(colors.cyan); mon.setBackgroundColor(colors.blue); mon.write("O")
            else
                mon.setTextColor(colors.gray); mon.setBackgroundColor(colors.black); mon.write("o")
            end
        end
    end
end
local function drawGraph(mon,x,y,w,h)
    box(mon,x,y,w,h,colors.cyan,"NET FLOW /t")
    local maxV=1
    for _,v in ipairs(history) do if math.abs(v)>maxV then maxV=math.abs(v) end end
    local gw=w-2; local gh=h-2; local mid=y+1+math.floor(gh/2)
    for c=x+1,x+w-2 do p(mon,c,mid,"-",colors.gray) end
    local st=math.max(1,#history-gw+1)
    for i=st,#history do
        local v=history[i]; local col=x+1+(i-st)
        local bh=math.max(1,math.floor(math.abs(v)/maxV*(gh/2)))
        local fg=v>=0 and colors.lime or colors.red
        if v>=0 then for rr=0,bh-1 do p(mon,col,mid-rr,"|",fg) end
        else for rr=0,bh-1 do p(mon,col,mid+rr,"|",fg) end end
    end
    local cur=history[#history] or 0
    p(mon,x+2,y+1,(cur>=0 and "+" or "")..fmtBig(cur).."/t",cur>=0 and colors.lime or colors.red)
end

local function renderCenter()
    local mon=monC; if not mon then return end
    local W,H=mon.getSize()
    mon.setBackgroundColor(colors.black); mon.clear()
    p(mon,2,1,"ENERGY CORE",colors.cyan,colors.black)
    p(mon,W-7,1,dataRcv and "* LIVE" or "* WAIT",dataRcv and colors.lime or colors.yellow,colors.black)
    p(mon,1,1,"/",colors.blue,colors.black); p(mon,W,1,"\\",colors.blue,colors.black)
    p(mon,1,H,"\\",colors.blue,colors.black); p(mon,W,H,"/",colors.blue,colors.black)
    local pct=energyPct()
    local cx=math.floor(W*0.28); local cy=math.floor(H*0.38)
    local r=math.min(cx-2,math.floor(H*0.25))
    drawRing(mon,cx,cy,r,pct)
    local ps=fmtPct(pct); p(mon,cx-math.floor(#ps/2),cy-1,ps,colors.white,colors.black)
    local st=fmtBig(data.energyCore.stored); p(mon,cx-math.floor(#st/2),cy,st,colors.cyan,colors.black)
    if blink then p(mon,cx,cy+1,"*",colors.yellow,colors.black) end
    local barY=cy+r+2
    p(mon,2,barY,"PWR",colors.gray,colors.black)
    pbar(mon,6,barY,math.floor(W*0.45)-6,pct,pct>0.5 and colors.cyan or (pct>0.2 and colors.yellow or colors.red))
    local tr=data.energyCore.transferRate or 0
    local trS=(tr>=0 and "+" or "")..fmtBig(tr).."/t"
    p(mon,2,barY+1,"NET ",colors.gray,colors.black)
    p(mon,6,barY+1,trS,tr>=0 and colors.lime or colors.red,colors.black)
    local gx=math.floor(W*0.55); local gw=W-gx; local gh=math.floor(H*0.45)
    if gw>10 then drawGraph(mon,gx,2,gw,gh) end
    local sepY=math.floor(H*0.6)
    hln(mon,1,sepY,W,"-",colors.blue)
    p(mon,3,sepY,"[ ME RESOURCES ]",colors.yellow,colors.black)
    local items={
        {label="Antimatter",val=meData.antimatter,max=1e6,fg=colors.magenta},
        {label="Deuterium", val=meData.deuterium, max=1e7,fg=colors.cyan},
        {label="Tritium",   val=meData.tritium,   max=1e7,fg=colors.lime},
    }
    for i,item in ipairs(items) do
        local ry=sepY+1+(i-1)*3
        p(mon,2,ry,item.label,colors.gray,colors.black)
        p(mon,2+#item.label+1,ry,fmtBig(item.val),item.fg,colors.black)
        pbar(mon,2,ry+1,math.floor(W*0.4),clamp(item.val/item.max,0,1),item.fg)
        if i==1 then
            p(mon,gx,ry,"SPS IN  "..fmtBig(data.sps.inputRate),colors.purple,colors.black)
            p(mon,gx,ry+1,"SPS OUT "..fmtBig(data.sps.outputRate),colors.purple,colors.black)
        end
    end
    if not dataRcv then
        local w2="[ WAITING FOR TRANSMITTER ]"
        p(mon,math.floor((W-#w2)/2)+1,H,w2,colors.yellow,colors.black)
    else
        p(mon,2,H,"LIVE #"..data.tick,colors.green,colors.black)
    end
end

-- ============================================================
--  LEFT MONITOR
-- ============================================================
local noisePool={"+","x","*","~","^",".","'","`"}
local function renderLeft()
    local mon=monL; if not mon then return end
    local W,H=mon.getSize()
    mon.setBackgroundColor(colors.black); mon.clear()
    p(mon,2,1,"REACTOR TELEMETRY",colors.cyan,colors.black)
    p(mon,W-7,1,dataRcv and "* LIVE" or "* WAIT",dataRcv and colors.lime or colors.yellow,colors.black)
    local halfW=math.floor(W/2); local topH=math.floor(H*0.52); local botH=H-topH-1
    local fr=data.fissionReactor
    box(mon,1,2,halfW-1,topH,fr.active and colors.lime or colors.gray,"FISSION")
    local frow=3
    p(mon,3,frow,"Status: ",colors.gray,colors.black)
    p(mon,11,frow,fr.active and "ACTIVE" or "OFFLINE",fr.active and colors.lime or colors.red,colors.black)
    frow=frow+1
    p(mon,3,frow,"Temp:   ",colors.gray,colors.black)
    local tc=fr.temperature>800 and colors.red or fr.temperature>400 and colors.yellow or colors.cyan
    p(mon,11,frow,string.format("%.0fK",fr.temperature),tc,colors.black)
    if blink then p(mon,11+#string.format("%.0fK",fr.temperature)+1,frow,"!",tc,colors.black) end
    frow=frow+1
    p(mon,3,frow,"Damage: ",colors.gray,colors.black)
    local dfg=(fr.damage>0) and (blink and colors.red or colors.orange) or colors.lime
    p(mon,11,frow,string.format("%.2f%%",fr.damage),dfg,colors.black)
    frow=frow+1
    p(mon,3,frow,"Burn:   ",colors.gray,colors.black)
    p(mon,11,frow,string.format("%.2f/t",fr.burnRate),colors.yellow,colors.black)
    frow=frow+1; pbar(mon,3,frow,halfW-5,clamp(fr.burnRate/10,0,1),colors.orange); frow=frow+1
    p(mon,3,frow,"Fuel:   ",colors.gray,colors.black)
    p(mon,11,frow,fmtPct(fr.fuelFilled),colors.cyan,colors.black)
    frow=frow+1; pbar(mon,3,frow,halfW-5,fr.fuelFilled,colors.yellow)
    local fu=data.fusionReactor
    box(mon,halfW+1,2,W-halfW,topH,fu.ignited and colors.orange or colors.gray,"FUSION")
    local urow=3
    p(mon,halfW+3,urow,fu.ignited and "IGNITED" or "COLD",fu.ignited and colors.orange or colors.cyan,colors.black)
    urow=urow+1
    p(mon,halfW+3,urow,"Plasma: ",colors.gray,colors.black)
    p(mon,halfW+11,urow,fmtBig(fu.plasmaTemp).."K",fu.plasmaTemp>0 and colors.red or colors.cyan,colors.black)
    urow=urow+1
    p(mon,halfW+3,urow,"Case:   ",colors.gray,colors.black)
    p(mon,halfW+11,urow,fmtBig(fu.caseTemp).."K",colors.orange,colors.black)
    urow=urow+1
    p(mon,halfW+3,urow,"Output: ",colors.gray,colors.black)
    p(mon,halfW+11,urow,fmtBig(fu.productionRate),colors.lime,colors.black)
    urow=urow+1
    if fu.plasmaTemp>0 then
        local ncx=halfW+math.floor((W-halfW)/2); local ncy=urow+2
        for _=1,5 do
            p(mon,ncx+math.random(-4,4),ncy+math.random(-1,2),noisePool[math.random(#noisePool)],colors.orange,colors.black)
        end
        p(mon,ncx-3,ncy,"~PLASMA~",colors.red,colors.black)
    end
    local sepRow=topH+2; hln(mon,1,sepRow,W,"-",colors.blue)
    local bo=data.boiler
    box(mon,1,sepRow+1,halfW-1,botH-1,colors.blue,"BOILER")
    local brow=sepRow+2
    p(mon,3,brow,"Temp:  ",colors.gray,colors.black); p(mon,10,brow,string.format("%.0fK",bo.temperature),colors.cyan,colors.black)
    brow=brow+1; p(mon,3,brow,"Water: ",colors.gray,colors.black); p(mon,10,brow,fmtBig(bo.water).."mB",colors.blue,colors.black)
    brow=brow+1; p(mon,3,brow,"Steam: ",colors.gray,colors.black); p(mon,10,brow,fmtBig(bo.steam).."mB",colors.white,colors.black)
    brow=brow+1
    local maxB=math.max(bo.maxBoilRate,1)
    p(mon,3,brow,"Boil:  ",colors.gray,colors.black); p(mon,10,brow,fmtBig(bo.boilRate).."/"..fmtBig(bo.maxBoilRate),colors.orange,colors.black)
    brow=brow+1; pbar(mon,3,brow,halfW-5,clamp(bo.boilRate/maxB,0,1),colors.orange)
    box(mon,halfW+1,sepRow+1,W-halfW,botH-1,colors.cyan,"TURBINES")
    local tc2=#data.turbines
    if tc2==0 then p(mon,halfW+3,sepRow+3,"No turbines",colors.gray,colors.black)
    else
        local colW=math.floor((W-halfW-2)/tc2); local barH=botH-6
        for i,turb in ipairs(data.turbines) do
            local tx=halfW+2+(i-1)*colW
            local pct2=clamp((turb.steamFlow or 0)/math.max(turb.maxSteamFlow or 1,1),0,1)
            p(mon,tx,sepRow+2,"T"..i,colors.yellow,colors.black)
            vbar(mon,tx,sepRow+2+barH,barH,pct2,colors.cyan)
            p(mon,tx,H-2,fmtBig(turb.steamFlow or 0),colors.cyan,colors.black)
            p(mon,tx,H-1,fmtBig(turb.production or 0),colors.lime,colors.black)
        end
        p(mon,halfW+3,H-3,"STEAM  PWR",colors.gray,colors.black)
    end
end

-- ============================================================
--  FLOOR MONITOR  -  Animated Energy Flow Visualizer
-- ============================================================
--
--  The floor shows a stylized, animated ENERGY FLOW DIAGRAM:
--
--    [FISSION]-->[BOILER]-->[TURBINE 1]--+
--    [FUSION ]                [TURBINE 2]--+--> [CORE] --> [SPS]
--
--  Plus:
--    - Scrolling waveform at the bottom showing transferRate
--    - Particle streams flowing along pipes
--    - Pulsing nodes that breathe in/out
--    - Live numeric readouts on each node
--    - Star-field background (subtle, sparse)
-- ============================================================

-- Starfield: pre-generate fixed star positions
local stars = {}
local NSTARS = 35
math.randomseed(42)   -- fixed seed = same stars every run
for i = 1, NSTARS do
    stars[i] = { x=math.random(2,149), y=math.random(2,79), ch=math.random(3)>1 and "." or "*" }
end
math.randomseed(os.clock()*1000)

-- Particle positions along each pipe route
-- Each route is {x1,y1, x2,y2, phase_offset, color}
-- Particles are rendered as ">" or "^" moving along the line

local function renderFloor()
    local mon = monF
    if not mon then return end
    local W, H = mon.getSize()

    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- ---- 1. Starfield background ----
    mon.setTextColor(colors.gray)
    mon.setBackgroundColor(colors.black)
    for _, s in ipairs(stars) do
        if s.x <= W and s.y <= H then
            -- stars twinkle: some are invisible based on frame
            local twinkle = (frame + s.x*3 + s.y*7) % 7
            if twinkle > 1 then
                mon.setCursorPos(s.x, s.y)
                mon.write(s.ch)
            end
        end
    end

    -- ---- 2. Layout constants ----
    -- We scale everything to W x H
    -- Nodes:
    local nW, nH = 10, 4  -- node box size

    -- Node centers (col, row of center)
    local nFis = { x=math.floor(W*0.12), y=math.floor(H*0.22) }
    local nFu  = { x=math.floor(W*0.12), y=math.floor(H*0.62) }
    local nBoi = { x=math.floor(W*0.35), y=math.floor(H*0.22) }
    local nT1  = { x=math.floor(W*0.57), y=math.floor(H*0.15) }
    local nT2  = { x=math.floor(W*0.57), y=math.floor(H*0.38) }
    local nCor = { x=math.floor(W*0.75), y=math.floor(H*0.28) }
    local nSPS = { x=math.floor(W*0.88), y=math.floor(H*0.28) }

    -- ---- 3. Draw pipe routes ----
    -- Each pipe: from right edge of src node to left edge of dst node
    local function nodeRight(n) return n.x + math.floor(nW/2) end
    local function nodeLeft(n)  return n.x - math.floor(nW/2) end
    local function nodeTop(n)   return n.y - math.floor(nH/2) end
    local function nodeBot(n)   return n.y + math.floor(nH/2) end

    local pipes = {
        -- {x1,y1,x2,y2, fg, horizontal?}
        -- Fission -> Boiler
        { nodeRight(nFis), nFis.y, nodeLeft(nBoi), nBoi.y, colors.orange, true  },
        -- Fusion -> Boiler mid (vertical join)
        { nFu.x, nodeTop(nFu),  nFis.x, nodeBot(nFis), colors.orange, false },
        -- Boiler -> Turbine 1
        { nodeRight(nBoi), nBoi.y, nodeLeft(nT1),  nT1.y,  colors.cyan,   true  },
        -- Boiler -> Turbine 2 (go right then down)
        { nodeRight(nBoi), nBoi.y, nodeLeft(nT2),  nT2.y,  colors.cyan,   true  },
        -- Turbine1 -> Core
        { nodeRight(nT1),  nT1.y,  nodeLeft(nCor), nCor.y, colors.lime,   true  },
        -- Turbine2 -> Core
        { nodeRight(nT2),  nT2.y,  nodeLeft(nCor), nCor.y, colors.lime,   true  },
        -- Core -> SPS
        { nodeRight(nCor), nCor.y, nodeLeft(nSPS), nSPS.y, colors.purple, true  },
    }

    -- Draw pipe lines
    for _, pp in ipairs(pipes) do
        local x1,y1,x2,y2,fg,horiz = pp[1],pp[2],pp[3],pp[4],pp[5],pp[6]
        mon.setTextColor(colors.gray)
        mon.setBackgroundColor(colors.black)
        if horiz then
            -- horizontal pipe with zig if y differs
            local midX = math.floor((x1+x2)/2)
            -- first segment horizontal to midX
            for c = math.min(x1,midX), math.max(x1,midX) do
                if c>=1 and c<=W and y1>=1 and y1<=H then
                    mon.setCursorPos(c,y1); mon.write("-")
                end
            end
            -- vertical segment
            if y1 ~= y2 then
                for r = math.min(y1,y2), math.max(y1,y2) do
                    if midX>=1 and midX<=W and r>=1 and r<=H then
                        mon.setCursorPos(midX,r); mon.write("|")
                    end
                end
            end
            -- second horizontal segment
            for c = math.min(midX,x2), math.max(midX,x2) do
                if c>=1 and c<=W and y2>=1 and y2<=H then
                    mon.setCursorPos(c,y2); mon.write("-")
                end
            end
        else
            for r = math.min(y1,y2), math.max(y1,y2) do
                if x1>=1 and x1<=W and r>=1 and r<=H then
                    mon.setCursorPos(x1,r); mon.write(":")
                end
            end
        end
    end

    -- ---- 4. Animated particles on pipes ----
    local SPEED = 20  -- steps per full pipe traversal
    for pi, pp in ipairs(pipes) do
        local x1,y1,x2,y2,fg,horiz = pp[1],pp[2],pp[3],pp[4],pp[5],pp[6]
        local phase = (frame + pi*7) % SPEED
        local t = phase / SPEED

        local px, py
        if horiz then
            px = math.floor(x1 + (x2-x1)*t)
            py = math.floor(y1 + (y2-y1)*t)
        else
            px = x1
            py = math.floor(y1 + (y2-y1)*t)
        end
        local ch = horiz and ">" or "v"
        if px>=1 and px<=W and py>=1 and py<=H then
            mon.setCursorPos(px,py)
            mon.setTextColor(fg)
            mon.setBackgroundColor(colors.black)
            mon.write(ch)
        end
        -- second particle 180deg offset
        local t2 = (t + 0.5) % 1
        local px2 = math.floor(x1+(x2-x1)*t2)
        local py2 = math.floor(y1+(y2-y1)*t2)
        if px2>=1 and px2<=W and py2>=1 and py2<=H then
            mon.setCursorPos(px2,py2)
            mon.setTextColor(fg)
            mon.setBackgroundColor(colors.black)
            mon.write(ch)
        end
    end

    -- ---- 5. Draw nodes ----
    local function drawNode(n, label, sub, fg, bg)
        -- Pulsing: alternate between bg and slightly brighter on blink
        local nbg = (blink and bg==colors.blue) and colors.cyan or bg
        local bx = n.x - math.floor(nW/2)
        local by = n.y - math.floor(nH/2)
        -- fill
        for r = by, by+nH-1 do
            if r>=1 and r<=H and bx>=1 then
                mon.setCursorPos(bx,r)
                mon.setBackgroundColor(nbg)
                mon.write(string.rep(" ", math.min(nW, W-bx+1)))
            end
        end
        -- border
        mon.setTextColor(fg)
        mon.setBackgroundColor(nbg)
        if bx>=1 and by>=1 then
            mon.setCursorPos(bx,by);       mon.write("+"..string.rep("-",nW-2).."+")
            mon.setCursorPos(bx,by+nH-1); mon.write("+"..string.rep("-",nW-2).."+")
        end
        for r=by+1,by+nH-2 do
            if bx>=1 and r>=1 and r<=H then
                mon.setCursorPos(bx,r); mon.write("|")
                if bx+nW-1<=W then mon.setCursorPos(bx+nW-1,r); mon.write("|") end
            end
        end
        -- label
        local lx = bx + math.floor((nW-#label)/2)
        if lx>=1 and n.y-1>=1 then
            mon.setCursorPos(lx, n.y-1)
            mon.setTextColor(fg); mon.setBackgroundColor(nbg); mon.write(label)
        end
        -- sub
        local sx = bx + math.floor((nW-#sub)/2)
        if sx>=1 and n.y>=1 and n.y<=H then
            mon.setCursorPos(sx, n.y)
            mon.setTextColor(colors.white); mon.setBackgroundColor(nbg); mon.write(sub)
        end
    end

    local frTemp = data.fissionReactor.temperature
    local fuTemp = data.fusionReactor.caseTemp
    local pct    = energyPct()
    local boilP  = clamp((data.boiler.boilRate or 0)/math.max(data.boiler.maxBoilRate or 1,1),0,1)

    -- Fission node
    drawNode(nFis, "FISSION", string.format("%.0fK",frTemp),
             colors.black, reactorCol(frTemp))

    -- Fusion node
    drawNode(nFu, "FUSION", data.fusionReactor.ignited and "IGNIT" or "COLD",
             colors.black,
             data.fusionReactor.ignited and colors.orange or colors.gray)

    -- Boiler
    drawNode(nBoi, "BOILER", fmtPct(boilP),
             colors.white, boilP>0.5 and colors.blue or colors.gray)

    -- Turbine 1
    local t1p = 0
    if data.turbines[1] then
        t1p = clamp((data.turbines[1].steamFlow or 0)/math.max(data.turbines[1].maxSteamFlow or 1,1),0,1)
    end
    drawNode(nT1, "TURB-1", fmtPct(t1p),
             colors.black, t1p>0.3 and colors.teal or colors.gray)

    -- Turbine 2
    local t2p = 0
    if data.turbines[2] then
        t2p = clamp((data.turbines[2].steamFlow or 0)/math.max(data.turbines[2].maxSteamFlow or 1,1),0,1)
    end
    drawNode(nT2, "TURB-2", fmtPct(t2p),
             colors.black, t2p>0.3 and colors.teal or colors.gray)

    -- Core - pulses with energy level
    local coreBg = pct>0.7 and colors.blue or (pct>0.3 and colors.cyan or colors.gray)
    drawNode(nCor, "CORE", fmtPct(pct), colors.white, coreBg)
    -- Extra glow ring on core when charged
    if pct > 0.5 and blink then
        local bx=nCor.x-math.floor(nW/2)-1; local by=nCor.y-math.floor(nH/2)-1
        if bx>=1 and by>=1 then
            mon.setTextColor(colors.cyan); mon.setBackgroundColor(colors.black)
            mon.setCursorPos(bx,by); mon.write("*")
            mon.setCursorPos(bx+nW+1,by); mon.write("*")
            mon.setCursorPos(bx,by+nH+1); mon.write("*")
            mon.setCursorPos(bx+nW+1,by+nH+1); mon.write("*")
        end
    end

    -- SPS
    local spsOn = (data.sps.outputRate or 0)>0
    drawNode(nSPS, "SPS", fmtBig(data.sps.outputRate),
             colors.white, spsOn and colors.purple or colors.gray)

    -- ---- 6. Scrolling waveform strip at bottom ----
    local waveY = H - 3
    hln(mon, 1, waveY, W, "-", colors.blue)
    p(mon, 2, waveY, " ENERGY FLOW ", colors.cyan, colors.black)

    -- Waveform: sine wave + actual transfer overlay
    local waveH = 2
    local baseY = H - 1
    for c = 1, W do
        local sineVal = math.sin((c + frame*0.8) * 0.3) * waveH
        local rowOff  = math.floor(sineVal)
        local wy = baseY + rowOff
        if wy >= waveY+1 and wy <= H then
            -- color by transfer
            local tr = history[#history] or 0
            local wfg = tr >= 0 and colors.lime or colors.red
            mon.setCursorPos(c, wy)
            mon.setTextColor(wfg)
            mon.setBackgroundColor(colors.black)
            mon.write("|")
        end
    end

    -- ---- 7. Title & status ----
    p(mon, 3, 1, "[ ENERGY FLOW DIAGRAM ]", colors.cyan, colors.black)
    p(mon, W-14, 1, dataRcv and "LIVE #"..data.tick or "WAITING...",
      dataRcv and colors.lime or colors.yellow, colors.black)

    -- Transfer rate readout
    local tr = data.energyCore.transferRate or 0
    local trS = (tr>=0 and "+" or "")..fmtBig(tr).."/t"
    p(mon, 3, H-2, "NET: "..trS, tr>=0 and colors.lime or colors.red, colors.black)
    p(mon, math.floor(W/2), H-2, "CORE: "..fmtPct(pct), colors.cyan, colors.black)
    p(mon, math.floor(W*0.75), H-2, "SPS: "..fmtBig(data.sps.outputRate), colors.purple, colors.black)
end

-- ============================================================
--  Data update
-- ============================================================
local function updateData(raw)
    if type(raw)~="table" then return end
    local function mg(dst,src)
        if type(src)~="table" then return end
        for k,v in pairs(src) do dst[k]=v end
    end
    mg(data.energyCore,raw.energyCore)
    mg(data.fissionReactor,raw.fissionReactor)
    mg(data.fusionReactor,raw.fusionReactor)
    mg(data.boiler,raw.boiler)
    mg(data.sps,raw.sps)
    mg(data.chemTank,raw.chemTank)
    if type(raw.turbines)=="table" then data.turbines=raw.turbines end
    if raw.tick then data.tick=raw.tick end
end

-- ============================================================
--  Main loops
-- ============================================================
local function modemLoop()
    while true do
        local _,_,ch,_,msg=os.pullEvent("modem_message")
        if ch==99 and type(msg)=="table" then
            updateData(msg); dataRcv=true
        end
    end
end

local function tickLoop()
    while true do
        frame=frame+1; blink=not blink
        pushHist(data.energyCore.transferRate or 0)
        queryME(); checkAlerts()
        if not alertActive then
            pcall(renderCenter)
            pcall(renderLeft)
            pcall(renderFloor)
        end
        os.sleep(0.5)
    end
end

-- ============================================================
--  Boot
-- ============================================================
print("CYBERPUNK HUD v3  |  Starting...")
print("L=monitor_24  C=monitor_22  F=monitor_25")
print("Modem ch:99   ME:meBridge_1")
print("")
print("== WIRELESS MODEM CHECK ==")
print("On TRANSMITTER computer, run:")
print("  peripheral.getNames()")
print("Look for 'right','left','top','bottom','back','front'")
print("Then: peripheral.getType('<side>')")
print("Must say 'modem' AND isWireless()==true")
print("")
print("Ctrl+T to quit.")

parallel.waitForAny(modemLoop, tickLoop)
