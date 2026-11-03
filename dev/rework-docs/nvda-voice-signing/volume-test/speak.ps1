# Child of run-test.ps1: speaks each test case through the SAPI2SR voice
# with SAPI's XML flag, the way WoW hands utterances to SAPI. The engine the
# voice loads is whatever run-test.ps1 registered for this user. Before each
# case a "CASE <name>" line goes into the record file, so the stand-in's
# lines that follow belong to that case.
$ErrorActionPreference = 'Stop'
$rec = $env:S2SR_REC
$nb = [string][char]0xA0

# One part of the group health monitor (WowVision retail/groupHealth,
# GroupHealth.segment): words at a volume, a rate and a pitch.
function Part($volume, $rate, $pitch, $words) {
    '<volume level="' + $volume + '"><rate absspeed="' + $rate + '"><pitch absmiddle="' + $pitch + '">' + $words + '</pitch></rate></volume>'
}
# What WowVision's queue adds (core/ttsCacheBust.lua: no-break spaces after
# the text) and what WoW wraps around every utterance (start/end bookmarks).
function Wow($text) { '<bookmark mark="start"/>' + $text + $nb + $nb + $nb + '<bookmark mark="end"/>' }
# The monitor's pad on the low copy (GroupHealth.uniquePad).
$pad = ' ' + $nb + $nb

$cases = [ordered]@{
    'plain text, no markup'               = Wow 'eins zwei drei'
    'Alt+H, member at full health'        = Wow ((Part 0 10 -4 ('1' + $pad)) + (Part 0 10 -4 '1') + (Part 100 7 6 '1 full'))
    'Alt+H, member low (low copy heard)'  = Wow ((Part 100 7 -4 ('1' + $pad)) + (Part 0 10 -4 '1') + (Part 0 10 6 '1 full'))
    'repeat, member hurt (high copy heard)' = Wow ((Part 0 10 3 ('2' + $pad)) + (Part 100 7 3 '2'))
    'repeat, member healthy (all silent)' = Wow ((Part 0 10 3 ('3' + $pad)) + (Part 0 10 3 '3'))
    'all silent, after a stop (skuint)'   = Wow ((Part 0 10 3 ('4' + $pad)) + (Part 0 10 3 '4') + '<bookmark mark="skuint"/>')
    'half volume stays spoken'            = Wow ('<volume level="50">halbe lautstaerke</volume> und voll')
}

$voice = New-Object -ComObject SAPI.SpVoice
$token = $voice.GetVoices('Name=SAPI2SR').Item(0)
$voice.Voice = $token
foreach ($name in $cases.Keys) {
    [IO.File]::AppendAllText($rec, "CASE $name`n", (New-Object Text.UTF8Encoding $false))
    [void]$voice.Speak($cases[$name], 8)   # SVSFIsXML, synchronous
}
