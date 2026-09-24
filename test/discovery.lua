local root=assert(app.params.root)
local helper=root..'/extension/Probe.ps1'
local pipe,error=io.popen('powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'..helper..'"','r')
assert(pipe,error or 'io.popen failed')
for line in pipe:lines() do assert(json.decode(line).protocol==1) end
pipe:close()
print('PASS: Aseprite kann den mitgelieferten Suchhelfer starten')
