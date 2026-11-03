# Child of run-test.ps1 (-SpeakScript): the seven lines of WowVision's
# /wv vprobe (WowVision tbc/bridgeProbe.lua), with WoW's start/end
# bookmarks and trailing no-break spaces like the buster's, so the offline
# result says in advance what each bridge reads in game.
$ErrorActionPreference = 'Stop'
$rec = $env:S2SR_REC
$nb = [string][char]0xA0
function Wow($text) { '<bookmark mark="start"/>' + $text + $nb + $nb + '<bookmark mark="end"/>' }

$cases = [ordered]@{
    '1' = Wow 'one. plain line.'
    '2' = Wow 'two, <volume level="0">silent</volume> ok.'
    '3' = Wow 'three, ok, <volume level="0">silent</volume>'
    '4' = Wow ('<volume level="0"><rate absspeed="10"><pitch absmiddle="-4">four, silent</pitch></rate></volume>' +
        '<volume level="100"><rate absspeed="0"><pitch absmiddle="3">four, ok.</pitch></rate></volume>' +
        '<volume level="0"><rate absspeed="10"><pitch absmiddle="6">silent, full</pitch></rate></volume>')
    '5' = Wow '<volume level="0">five, silent</volume>'
    '6' = Wow '<volume level="50">six, half volume, ok.</volume>'
    '7' = Wow 'seven. probe done.'
}

$voice = New-Object -ComObject SAPI.SpVoice
$voice.Voice = $voice.GetVoices('Name=SAPI2SR').Item(0)
foreach ($name in $cases.Keys) {
    [IO.File]::AppendAllText($rec, "CASE $name`n", (New-Object Text.UTF8Encoding $false))
    [void]$voice.Speak($cases[$name], 8)
}
