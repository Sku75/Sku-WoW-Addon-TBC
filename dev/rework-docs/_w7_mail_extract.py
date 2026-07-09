#!/usr/bin/env python3
# W7 step 1: lift the inline Mail build closure out of SkuCore:MenuBuilder into a
# file-scope function SkuCore.MailMenuBuilder(self), so Mail can be a Local window
# contributor. Pure line surgery with boundary assertions; preserves BOM + LF.
import io, sys

path = "Sku/SkuCore/Options.lua"
raw = open(path, "rb").read()
text = raw.decode("utf-8-sig")
lines = text.split("\n")

def L(n):  # 1-based line -> string
    return lines[n-1]

# --- assert boundaries (fail loudly, write nothing on mismatch) ---
assert L(1541).strip() == "function SkuCore:MenuBuilder(aParentEntry)", repr(L(1541))
assert L(1545).strip().startswith('tSpecs[#tSpecs+1] = { kind = "list", label = L["Mail"]'), repr(L(1545))
assert L(1548).strip() == "build = function(self)", repr(L(1548))
assert L(1998).strip() == "end", repr(L(1998))
assert L(1999).strip() == "end }", repr(L(1999))

# indices (0-based)
pre              = lines[0:1540]      # lines 1..1540
menubuilder_head = lines[1540:1544]   # 1541..1544 (def, dprint, local tSpecs, blank)
mail_body        = lines[1548:1998]   # 1549..1998 (the build closure body; its own
                                      # closing `end` is line 1999's `end }`)
post             = lines[1999:]       # 2000..end

func_block = [
    "",
    "-- W7: Mail menu lifted to file scope so it can be a Local window contributor",
    "-- (opened via the contextual \"Local\" menu when the mailbox is shown) instead",
    "-- of a permanent Core \"Mail\" child. Body is the unchanged inline build closure.",
    "function SkuCore.MailMenuBuilder(self)",
] + mail_body + [
    "end",
    "",
]

mail_replacement = "\t-- Mail: now a Local window contributor (SkuCore.MailMenuBuilder) -- W7"

new_lines = pre + func_block + menubuilder_head + [mail_replacement] + post
out = "\n".join(new_lines)

open(path, "wb").write(("﻿" + out).encode("utf-8"))
print("OK: wrote", path, "lines", len(lines), "->", len(new_lines))
