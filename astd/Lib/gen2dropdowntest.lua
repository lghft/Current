-- Modified Version of Rayfield Gen2 v1.2.0 - FIXED
-- loadstring(game:HttpGet("https://sirius.menu/gen2"))()
--
-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

local a local aa,ab,ac,ad,ae,af,ag,ah,ai,aj,ak,al,am,b,c,d,e,f,g,h,i={function()local b,c,d=a(1)local e return(function(
...)local f,g,h,i,j=d(c.utility.variables),d(c.utility.image),d(c.utility.locale),d(c.utility.constants),d(c.types)
export type Theme=j.Theme export type Translator=j.Translator export type Translations=j.Translations export type
WindowConfiguration=j.WindowConfiguration export type WindowProps=j.WindowProps export type TabProps=j.TabProps export
type TagProps=j.TagProps export type SectionProps=j.SectionProps export type GroupProps=j.GroupProps export type
ButtonProps=j.ButtonProps export type ToggleProps=j.ToggleProps export type SliderProps=j.SliderProps export type
DropdownProps=j.DropdownProps export type InputProps=j.InputProps export type KeybindProps=j.KeybindProps export type
ColorPickerProps=j.ColorPickerProps export type StatProps=j.StatProps export type ProgressProps=j.ProgressProps export
type ConsoleProps=j.ConsoleProps export type TextProps=j.TextProps export type DividerProps=j.DividerProps export type
NotifyProps=j.NotifyProps export type ToastProps=j.ToastProps export type PopupBox=j.PopupBox export type PopupOption=j.
PopupOption export type PopupProps=j.PopupProps export type Moveable=j.Moveable export type Lockable=j.Lockable export
type Window=j.Window export type Tab=j.Tab export type Group=j.Group export type Button=j.Button export type Toggle=j.
Toggle export type Slider=j.Slider export type Dropdown=j.Dropdown export type Input=j.Input export type Keybind=j.
Keybind export type ColorPicker=j.ColorPicker export type Stat=j.Stat export type Progress=j.Progress export type
Console=j.Console export type Section=j.Section export type TabSection=j.TabSection export type Text=j.Text export type
Divider=j.Divider export type Tag=j.Tag export type Popup=j.Popup export type Rayfield=j.Rayfield export type DropdownWithInputs=j.DropdownWithInputs type WindowModule={new
:(j.WindowProps)->j.Window}local k={}::Rayfield local function l()local m=Instance.new'ScreenGui'm.Name=f.httpService:
GenerateGUID(false)m.ClipToDeviceSafeArea=false m.DisplayOrder=i.displayOrder.banner m.IgnoreGuiInset=true m.
ResetOnSpawn=false m.Enabled=true m.SafeAreaCompatibility=Enum.SafeAreaCompatibility.None m.ScreenInsets=Enum.
ScreenInsets.DeviceSafeInsets m.ZIndexBehavior=Enum.ZIndexBehavior.Sibling m.Parent=f.guiContainer local n=Instance.new
'ImageLabel'n.Name='Banner'n.AnchorPoint=Vector2.new(0.5,0.5)n.BackgroundColor3=Color3.fromRGB(255,255,255)n.
BackgroundTransparency=1 n.BorderColor3=Color3.fromRGB(0,0,0)n.BorderSizePixel=0 n.Image=g.resolve(i.icons.banner)n.
Position=UDim2.fromScale(0.5,0.5)n.Size=UDim2.fromOffset(262,60)n.Parent=m return m end function k.CreateWindow(m,n:j.
WindowProps):j.Window local o,p:j.Window?,q:(()->())?=(l())if f.secureMode then g.preload(function(r)if r<=0 then return
end local function s()if not p or p.unloaded then return end p:Notify{title=h.resolve'Secure mode',content=if r==1 then
h.resolve"An asset couldn't be cached and won't appear."else h.resolve"Some assets couldn't be cached and won't appear."
}end if p then s()else q=s end end)end local r,s=pcall(function()return(d(c.components.window)::WindowModule).new(n)end)
if not r then o:Destroy()error(s,0)end local t=s::j.Window p=t if q then task.spawn(q)q=nil end if f.secureMode then
task.spawn(function()local u,v=f.fontManager:loadFont(i.fontAsset,Enum.FontWeight.Medium),f.fontManager:loadFont(i.
fontAsset,Enum.FontWeight.SemiBold)if not t.unloaded and u and v and u~=f.fallbackFont and v~=f.fallbackFont then t:
ChangeTheme{Font=u,TitleFont=v}end end)end task.spawn(function()task.wait(0.5)o:Destroy()task.wait(0.5)if not t.unloaded
then t:Show()end end)return t end return k end)()end,[3]=function()local b,c,d=a(3)local e return(function(...)local f={
}f.__index=f f.__type='Action'local g=c.Parent.Parent.utility local h,i,j=d(g.variables),d(g.log),d(g.HapticEngine)
function f.new(k,l)l=if typeof(l)=='table'then l else{}local m=setmetatable({window=assert(k,
'Missing argument #1 (Window expected)'),name=l.name or l.Name or'Action',icon=assert(l.icon or l.Icon,
'Missing argument (Icon expected)'),callback=assert(l.callback or l.Callback,'Missing argument (Function expected)'),
linkedTab=l.linkedTab or l.LinkedTab},f)m.action=m.window:Create('Frame',{Name=m.name,BorderSizePixel=0,LayoutOrder=-(l.
order or 0),Size=UDim2.fromOffset(24,24),BackgroundTransparency=1,Parent=m.window.actionContainer})m.iconLabel=m.window:
Create('ImageLabel',{Image=m.icon,Size=UDim2.fromOffset(20,20),BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),
Position=UDim2.fromScale(0.5,0.5),BackgroundTransparency=1,ImageTransparency=1,Parent=m.action},{ImageColor3=
'ActionColor'})m.interact=m.window:Create('TextButton',{BackgroundTransparency=1,Size=UDim2.fromScale(1,1),
BorderSizePixel=0,Position=UDim2.fromScale(0.5,0.5),AnchorPoint=Vector2.new(0.5,0.5),TextTransparency=1,Parent=m.action}
)local function n()if not m.window:_settled()then return end if m.linkedTab and m.window.selectedTab==m.linkedTab then
return end if m.isLit and m:isLit()then return end h.tweenService:Create(m.iconLabel,TweenInfo.new(0.25,Enum.EasingStyle
.Quint,Enum.EasingDirection.Out),{ImageTransparency=0.6}):Play()end m.window:Connect(m.interact.MouseButton1Click,
function()j.click()task.spawn(function()local o,p=pcall(m.callback)if not o then i.warn(`Rayfield encountered an error, with the callback for a {
m.__type} component named '{m.name}':`)i.print(p)end n()end)end)m.window:Connect(m.interact.MouseEnter,function()if not
m.window:_interactive()then return end h.tweenService:Create(m.iconLabel,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.
EasingDirection.Out),{ImageTransparency=0.2}):Play()end)m.window:Connect(m.interact.MouseLeave,n)return m end return f
end)()end,[4]=function()local b,c,d=a(4)local e return(function(...)local f={}f.__index=f f.__type='Button'local g=c.
Parent.Parent.utility local h,i,j,k,l,m=d(g.variables),d(g.functions),d(g.moveable),d(g.lockable),d(g.locale),d(g.
HapticEngine)function f.new(n,o)o=if typeof(o)=='table'then o else{}local p=setmetatable({tab=assert(n,
'Missing argument #1 (Tab expected)'),window=n.window,name=o.name or o.Name or'Button',icon=o.icon or o.Icon,description
=o.description or o.Description,compact=n.compact or false,callback=o.callback or o.Callback or function()end},f)if p.
compact then p:_buildCompact()else p:_buildFull()end if p.description and not p.compact then p.descriptor=d(c.Parent.
descriptor).new(p.tab,{description=p.description})end return p end function f._runCallback(n)n.window:_runGuarded(n,n.
callback)end function f._buildFull(n)n.main=n.window:Create('Frame',{Size=UDim2.new(1,-20,0,43),BorderSizePixel=0,Name=n
.name,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Parent=n.tab.tabPage},{
BackgroundTransparency='ElementTransparency'})n.stroke=n.window:StyleElementBody(n.main)n.hoverOverlay=n.window:
CreateHoverOverlay(n.main)n.container=n.window:Create('Frame',{BorderSizePixel=0,Parent=n.main,Size=UDim2.new(0,170,0,16
),Position=UDim2.new(0,20,0.5,0),AnchorPoint=Vector2.new(0,0.5),BackgroundTransparency=1})n.containerLayout=n.window:
Create('UIListLayout',{Padding=UDim.new(0,5),FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.
VerticalAlignment.Center,BackgroundTransparency=1})n.icon=n.window:Create('ImageLabel',{Size=UDim2.fromOffset(16,16),
BorderSizePixel=0,BackgroundTransparency=1,Image=n.icon or'',ImageColor3=Color3.fromRGB(255,255,255),
ImageTransparency=0.5,Parent=n.container})n.title=n.window:Create('TextLabel',{Name=n.name,BackgroundTransparency=1,
BorderSizePixel=0,Text=n.name,TextColor3=Color3.fromRGB(255,255,255),TextSize=14,TextXAlignment=Enum.TextXAlignment
.Left,Size=UDim2.new(0,0,1,0),Parent=n.container})n.window:Create('UISizeConstraint',{MinSize=Vector2.new(0,0),Parent=n
.title})end function f._buildCompact(n)n.main=n.window:Create('Frame',{Size=UDim2.new(1,-20,0,31),BorderSizePixel=0,Name=
n.name,BackgroundTransparency=1,Parent=n.tab.tabPage})n.container=n.window:Create('Frame',{BorderSizePixel=0,Parent=n
.main,Size=UDim2.new(1,-20,1,0),Position=UDim2.new(0,20,0,0),BackgroundTransparency=1})end return f end)()end,[11]=function()local b,c,d=a(11)local e return(function(...)local f={}f.__index=f f.__type='DropdownWithInputs'local g=c.Parent.Parent.utility local h,i,j,k,l=d(g.variables),d(g.functions),d(g.locale),d(g.HapticEngine),d(g.lockable)function f.new(m,n)n=if typeof(n)=='table'then n else{}local o=setmetatable({tab=assert(m,'Missing argument #1 (Tab expected)'),window=m.window,name=n.name or n.Name or'Dropdown',options=assert(n.options or n.Options,'Missing argument (Options expected)'),default=n.default or n.Default or 1,callback=n.callback or n.Callback or function()end,inputFields=n.inputFields or n.InputFields or{},compact=m.compact or false},f)o:_build()return o end function f._build(m)m.main=m.window:Create('Frame',{Size=UDim2.new(1,-20,0,43),BorderSizePixel=0,Name=m.name,BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=1,Parent=m.tab.tabPage},{BackgroundTransparency='ElementTransparency'})m.stroke=m.window:StyleElementBody(m.main)m.hoverOverlay=m.window:CreateHoverOverlay(m.main)m.container=m.window:Create('Frame',{BorderSizePixel=0,Parent=m.main,Size=UDim2.new(1,-40,0,35),Position=UDim2.new(0,20,0.5,-17.5),AnchorPoint=Vector2.new(0,0.5),BackgroundTransparency=1})m.containerLayout=m.window:Create('UIListLayout',{Padding=UDim.new(0,5),FillDirection=Enum.FillDirection.Horizontal,VerticalAlignment=Enum.VerticalAlignment.Center})m.title=m.window:Create('TextLabel',{BackgroundTransparency=1,BorderSizePixel=0,Text=m.name,TextColor3=Color3.fromRGB(255,255,255),TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,Size=UDim2.new(0,0,1,0),Parent=m.container})m.window:Create('UISizeConstraint',{MinSize=Vector2.new(0,0),Parent=m.title})m.dropdown=m.window:Create('Frame',{Size=UDim2.fromOffset(120,32),BorderSizePixel=1,BorderColor3=Color3.fromRGB(55,55,55),BackgroundColor3=Color3.fromRGB(30,30,30),Parent=m.container})m.dropdownLabel=m.window:Create('TextLabel',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Text=m.options[m.default],TextColor3=Color3.fromRGB(255,255,255),TextSize=12,Parent=m.dropdown})m.selectedValue=m.options[m.default]m.inputContainer=m.window:Create('Frame',{Size=UDim2.new(0,200,0,0),BorderSizePixel=0,BackgroundTransparency=1,Parent=m.main,Position=UDim2.new(0,20,1,5)})m.inputLayout=m.window:Create('UIListLayout',{Padding=UDim.new(0,8),FillDirection=Enum.FillDirection.Vertical})m.inputLayout.Parent=m.inputContainer m.inputData={}for p=1,#m.inputFields do local q=m.inputFields[p]local r=m.window:Create('TextBox',{Name='Input_'..p,Size=UDim2.new(1,-10,0,28),BackgroundColor3=Color3.fromRGB(40,40,40),BorderColor3=Color3.fromRGB(70,70,70),BorderSizePixel=1,TextColor3=Color3.fromRGB(255,255,255),PlaceholderColor3=Color3.fromRGB(150,150,150),PlaceholderText=q.placeholder or'Input '..p,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Padding=UDim.new(0,8),Parent=m.inputContainer,Text=''})table.insert(m.inputData,{name=q.name or'field_'..p,textbox=r,value=''})m.window:Connect(r.FocusLost,function()m.inputData[p].value=r.Text end)end m.window:Connect(m.dropdown.MouseButton1Click,function()k.click()m:_toggleDropdown()end)end function f._toggleDropdown(m)local n=m.dropdown:FindFirstChild('OptionsList')if n then n:Destroy()m.isOpen=false else local o=m.window:Create('Frame',{Name='OptionsList',Size=UDim2.fromOffset(120,#m.options*28+6),BackgroundColor3=Color3.fromRGB(25,25,25),BorderColor3=Color3.fromRGB(55,55,55),BorderSizePixel=1,Parent=m.dropdown,Position=UDim2.new(0,0,1,2)})local p=m.window:Create('UIListLayout',{Padding=UDim.new(0,2),Parent=o})for q=1,#m.options do local r=m.window:Create('TextButton',{Size=UDim2.fromOffset(120,24),BackgroundColor3=Color3.fromRGB(30,30,30),BorderSizePixel=0,Text=m.options[q],TextColor3=Color3.fromRGB(255,255,255),TextSize=11,Parent=o})m.window:Connect(r.MouseButton1Click,function()m.selectedValue=m.options[q]m.dropdownLabel.Text=m.options[q]m:_toggleDropdown()m.callback(m.selectedValue)end)m.window:Connect(r.MouseEnter,function()r.BackgroundColor3=Color3.fromRGB(50,50,50)end)m.window:Connect(r.MouseLeave,function()r.BackgroundColor3=Color3.fromRGB(30,30,30)end)end m.isOpen=true end end function f.GetValue(m)local n={}for o=1,#m.inputData do table.insert(n,m.inputData[o].value)end return{dropdown=m.selectedValue,inputs=n}end return f end)()end},{{1,2,{'Rayfield'},{{31,1,{'themes'},{{37,2,{'rose'}},{35,2,{'ember'}},{36,2,{
'frost'}},{34,2,{'default'}},{32,2,{'amethyst'}},{33,2,{'cobalt'}}}},{39,1,{'utility'},{{56,2,{'moveable'}},{44,2,{
'enums'}},{70,2,{'windowSizing'}},{69,2,{'variables'}},{68,2,{'textMetrics'}},{53,2,{'locale'}},{61,2,{'persistence'}},{
58,2,{'odometer'}},{42,2,{'colors'}},{54,2,{'lockable'}},{47,2,{'flagNames'}},{67,2,{'services'}},{66,2,{'runtime'}},{46
,2,{'filesystemManager'}},{50,2,{'image'}},{49,2,{'functions'}},{65,2,{'persistenceWrite'}},{62,2,{'persistenceConfig'}}
,{64,2,{'persistenceSettings'}},{41,2,{'assetResolver'}},{48,2,{'fontManager'}},{45,2,{'filesystem'}},{60,2,{'path'}},{
59,2,{'ordering'}},{43,2,{'constants'}},{40,2,{'HapticEngine'}},{57,2,{'network'}},{51,2,{'imageCache'}},{63,2,{
'persistencePaths'}},{55,2,{'log'}},{52,2,{'layouts'}}}},{38,2,{'types'}},{2,1,{'components'},{{17,2,{'progress'}},{25,2
,{'tabSelector'}},{6,2,{'colorpicker'}},{15,2,{'notification'}},{26,2,{'tag'}},{20,2,{'sidebar'}},{9,2,{'divider'}},{16,
2,{'popup'}},{30,2,{'window'}},{11,2,{'dropdownWithInputs'}},{23,2,{'tab'}},{29,2,{'toggle'}},{4,2,{'button'}},{28,2,{'toast'}},{7
,2,{'console'}},{19,2,{'section'}},{3,2,{'action'}},{18,2,{'search'}},{27,2,{'text'}},{13,2,{'input'}},{12,2,{'group'}},
{10,2,{'drag'}},{21,2,{'slider'}},{8,2,{'descriptor'}},{24,2,{'tabSection'}},{5,2,{'chrome'}},{14,2,{'keybind'}},{22,2,{
'stat'}}}}}}},'0.4.2','Rayfield',string,task,setmetatable,error,next,table,unpack,coroutine,script,type,require,pcall,
xpcall,tostring,tonumber,_VERSION local j,k,l,m,n,o,p=aj.insert,aj.remove,aj.freeze or function(j)return j end,al.wrap,
ae.sub,ae.match,ae.gmatch if h and n(h,1,4)=='Lune'then local q,r=d(c,'@lune/task')if q and r then af=r end end local q=
af and af.defer local r,s,t,u,v,w,x,y,z=q or function(r,...)m(r)(...)end,{[1]='Folder',[2]='ModuleScript',[3]='Script',[
4]='LocalScript',[5]='StringValue'},{},{},{},{},{},{},{}local A,B={GetFullName={{},function(A)local B,C=A.Name,A.Parent
while C do B=C.Name..'.'..B C=C.Parent end return B end},GetChildren={{},function(A)local B={}for C in ai,z[A]do j(B,C)
end return B end},GetDescendants={{},function(A)local B={}for C in ai,z[A]do j(B,C)for D,E in ai,C:GetDescendants()do j(
B,E)end end return B end},FindFirstChild={{'string','boolean?'},function(A,B,C)local D=z[A]for E in ai,D do if E.Name==B
then return E end end if C then for E in ai,D do return E:FindFirstChild(B,true)end end end},FindFirstAncestor={{
'string'},function(A,B)local C=A.Parent while C do if C.Name==B then return C end C=C.Parent end end},WaitForChild={{
'string','number?'},function(A,B)return A:FindFirstChild(B)end}},{}for C,D in ai,A do local E,F,G=D[1],D[2],{}for H,I in
ai,E do local J,K=o(I,'^([^%?]+)(%??)')G[H]={J,K}end B[C]=function(H,...)if not z[H]then ah(
"Expected ':' not '.' calling member function "..C,2)end local I={...}for J,K in ai,G do local L=I[J]local M,N,O=b(L),K[
1],K[2]if L==nil and not O then ah('Argument '..L..' missing or nil',3)end if N~='any'and M~=N and not(M=='nil'and O)
then ah('Argument '..J..' expects type "'..N..'", got "'..M..'"',2)end end return F(H,...)end end local function C(D,E,F
)local G,H=(ag({},{__mode='k'}))local function I(J)ah(J..' is not a valid (virtual) member of '..D..' "'..E..'"',3)end
local function J(K)ah('Unable to assign (virtual) property '..K..'. Property is read only',3)end local K,L={},{}L.
__metatable=false L.__index=function(M,N)if N=='ClassName'then return D elseif N=='Name'then return E elseif N=='Parent'
then return F elseif D=='StringValue'and N=='Value'then return H else local O=B[N]if O then return O end end for O in ai
,G do if O.Name==N then return O end end I(N)end L.__newindex=function(M,N,O)if N=='ClassName'then J(N)elseif N=='Name'
then E=O elseif N=='Parent'then if O==K then return end if F~=nil then z[F][K]=nil end F=O if O~=nil then z[O][K]=true
end elseif D=='StringValue'and N=='Value'then H=O else I(N)end end L.__tostring=function()return E end ag(K,L)z[K]=G if
F~=nil then z[F][K]=true end return K end local function D(E,F)local G,H,I,J=E[1],E[2],E[3],E[4]local K=s[H]local L=I
and k(I,1)or K local M=C(K,L,F)t[G]=M if I then for N,O in ai,I do M[N]=O end end if J then for N,O in ai,J do D(O,M)end
end return M end local E=C('Folder','['..ad..']')for F,G in ai,ab do D(G,E)end for F,G in ai,aa do local H=t[F]u[H]=G v[
H]=F local I=H.ClassName if I=='LocalScript'or I=='Script'then j(x,H)end end local function F(G)local H,I=G.ClassName,w[
G]if I and H=='ModuleScript'then return ak(I)end local J=u[G]local function K(L)local M,N,O=nil,d(function()return debug
.traceback(nil,2)end)if N then M=O end return{Message=L,Traceback=M}end local function L(M)local N,O=f(M.Message),G:
GetFullName()local P,Q=o(N,'[^:]+:(%d+): (.+)')local R if not P or not i then R=O..':*: '..(Q or N)else P=g(P)local S=v[
G]local T=i[S]local U=P-T+1 if U<0 then U='?'end R=O..':'..U..': '..Q end local S=M.Traceback if S and S~=''then R=R..
'\n'..S end return R end if H=='LocalScript'or H=='Script'then local M,N=e(J,K)if not M then ah(L(N),0)end else local M=
{e(J,K)}local N=k(M,1)if not N then local O=k(M,1)ah(L(O),0)end w[G]=M return ak(M)end end function a(G)local H=t[G]
local function I(J,...)local K={d(J,...)}local L=k(K,1)if not L then ah(K[1],3)end return ak(K)end local J=l(ag({},{
__index=y,__newindex=function(J,K,L)y[K]=L end,__len=function()return#y end,__iter=function()return ai,y end}))local K,L
=l{version=ac,envname=ad,shared=J,script=am,require=c},H local function M(N,...)local O,P,Q=b(N),
'Attempted to call require with a non-ModuleScript','Attempted to call require with self'if O=='table'and z[N]then if N.
ClassName~='ModuleScript'then ah(P,2)elseif N==H then ah(Q,2)end return F(N)elseif O=='string'and n(N,1,1)~='@'then if#N
==0 then ah('Attempted to call require with empty string',2)end local R=H if n(N,1,1)=='/'then R=E elseif n(N,1,2)=='./'
then N=n(N,3)end local S for T in p(N,'([^/]*)/?')do local U=T if T=='..'then U='Parent'end if U~=''then local V=R:
FindFirstChild(U)if not V then local W=R.Parent if W then V=W:FindFirstChild(U)end end if V then R=V elseif T~=S and T~=
'init'and T~='init.server'and T~='init.client'then ah('Virtual script path "'..N..'" not found',2)end end S=T end if R.
ClassName~='ModuleScript'then ah(P,2)elseif R==H then ah(Q,2)end return F(R)end return I(c,N,...)end return K,L,M end
for G,H in ai,x do r(F,H)end return F(E:GetChildren()[1])
