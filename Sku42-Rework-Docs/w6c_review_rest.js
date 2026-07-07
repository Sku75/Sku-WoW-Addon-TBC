export const meta = {
  name: 'w6c-per-file-review-rest',
  description: 'W6 Phase C per-file review: the 36 files the first run (wf_3972bcfa) did not reach before the session limit',
  phases: [{ title: 'Review', detail: 'one agent per remaining source file' }],
}

// The 36 files NOT completed by the first run (33/69 done, cached in
// Sku42-Rework-Docs/W6-PHASE-C-RAW-33.json). Small files first so a re-trip
// banks the most before the big ones (SkuZOptions/Core, SkuNav/Core, the audio
// libs, SkuQuest/Core, SkuAuras/Core, voiceOutput) consume the budget.
function mk(folder, srcFolder, names) {
  return names.map(function (n) {
    return { src: 'Sku/' + srcFolder + n + '.lua', idx: 'Sku42-Rework-Docs/index/' + folder + '/' + n + '.md', label: folder + '/' + n }
  })
}

const ITEMS = [].concat(
  mk('SkuDispatcher', 'SkuDispatcher/', ['Core']),
  mk('SkuMob', 'SkuMob/', ['Core', 'Options']),
  mk('SkuChat', 'SkuChat/', ['Options']),
  mk('SkuAdventureGuide', 'SkuAdventureGuide/', ['Core', 'Options']),
  mk('SkuNav', 'SkuNav/', ['Geo', 'Visited', 'importExport', 'specialNavigationTasks']),
  mk('SkuZOptions', 'SkuZOptions/', ['SkuKeyBinds', 'SkuSettings', 'Options', 'utilities']),
  mk('SkuAuras', 'SkuAuras/', ['sharing', 'Options']),
  mk('SkuDB', 'SkuDB/', ['ChunkLoader', 'Core']),
  mk('SkuCore', 'SkuCore/', ['minimapScanner', 'turnToUnit', 'visualAids', 'aqCombat', 'voiceOutput']),
  mk('SkuChat', 'SkuChat/', ['Core']),
  mk('SkuMob', 'SkuMob/', []),
  mk('SkuNav', 'SkuNav/', ['SkuMM', 'Options']),
  mk('SkuQuest', 'SkuQuest/', ['Options', 'Core']),
  mk('SkuAuras', 'SkuAuras/', ['Core']),
  mk('SkuZOptions', 'SkuZOptions/', ['templates', 'SkuMenu']),
  mk('SkuNav', 'SkuNav/', ['Core']),
  mk('SkuZOptions', 'SkuZOptions/', ['Core']),
  ['SkuBeacon-1.0', 'SkuTTS-1.0', 'SkuVoice-1.0'].map(function (n) {
    return { src: 'Sku/Libs/' + n + '/' + n + '.lua', idx: 'Sku42-Rework-Docs/index/Libs/' + n + '.md', label: 'Libs/' + n }
  })
)

log(ITEMS.length + ' remaining files queued (target 36)')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    file: { type: 'string' }, clean: { type: 'boolean' }, note: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        properties: {
          category: { type: 'string', enum: ['duplication', 'dead-code', 'naming', 'redundant-work', 'style', 'structure', 'localization', 'other'] },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          location: { type: 'string' }, summary: { type: 'string' }, detail: { type: 'string' },
          suggestion: { type: 'string' }, behaviorPreserving: { type: 'boolean' }, gain: { type: 'string' },
        },
        required: ['category', 'severity', 'confidence', 'location', 'summary', 'suggestion', 'behaviorPreserving', 'gain'],
      },
    },
  },
  required: ['file', 'clean', 'findings'],
}

function prompt(it) {
  return [
    'You are a code-cleanup reviewer for the Sku World of Warcraft addon (Lua 5.1, Ace3). This is a blind-accessibility screen-reader addon: audio, menu and voice-output behavior must never change.',
    '', 'Review EXACTLY ONE source file:', '  SOURCE: ' + it.src,
    'First read its index entry for context on purpose / public API / invariants:', '  INDEX:  ' + it.idx,
    'Then read the FULL source file (use Read; it is UTF-8 with a BOM). Review only this one file.',
    '', 'SCOPE — findings must be WITHIN THIS FILE ONLY. Cross-file architecture/coupling was already handled in Phase B — do NOT report cross-module concerns. Look for:',
    '  - duplicated or near-duplicate functions/methods/blocks in this file',
    '  - dead code: uncalled local/global functions, commented-out blocks, unreachable branches, unused locals/upvalues',
    '  - inconsistent naming or structure vs the rest of this same file',
    '  - redundant loops / repeated work / recomputation that could be hoisted (behavior identical)',
    '  - style inconsistencies within the file',
    '', 'HARD RULES:',
    '  - Behavior-preserving cleanups ONLY. If a change would alter runtime behavior, do not propose it as an action (at most note it with behaviorPreserving=false).',
    '  - Every finding needs a REAL concrete gain in the `gain` field (a specific bug-risk removed, real duplication a future edit would desync, measurable repeated work saved). Pure taste/style with no concrete gain: omit it, or if borderline mark severity=low AND confidence=low.',
    '  - Anything touching audio / menu navigation / voice output: be extra strict, mark behaviorPreserving precisely.',
    '  - Do NOT invent findings to fill the list. clean=true with findings=[] is the correct answer for a clean file. Quality over quantity.',
    '  - Cite exact line numbers or function names in `location`.',
    '', 'ALREADY KNOWN — do NOT re-report these specific ones (handled separately):',
    '  - SkuZOptions/templates.lua: the alphabetical-list duplication around lines 727-749 vs 760-779',
    '  - SkuZOptions/SkuMenu.lua: the resolveLabel / specLabel same-file duplication',
    '  - the inline GetLocale()=="deDE" label ternaries (a separate localization cleanup). If THIS file has them, report ONE aggregate `localization` finding with the count + line ranges — do not enumerate each.',
    '', 'Return the structured result for ' + it.src + '. Ranked most-valuable first.',
  ].join('\n')
}

phase('Review')

const results = await parallel(ITEMS.map(function (it) {
  return function () {
    return agent(prompt(it), { label: 'review:' + it.label, phase: 'Review', schema: SCHEMA, agentType: 'general-purpose' })
      .then(function (r) { if (r) { r._label = it.label; r._src = it.src } return r })
  }
}))

const ok = results.filter(Boolean)
let tot = 0; ok.forEach(function (r) { tot += (r.findings || []).length })
log('remaining review complete: ' + ok.length + '/' + ITEMS.length + ', ' + tot + ' findings')
return { reviewed: ok.length, queued: ITEMS.length, totalFindings: tot, results: ok }
