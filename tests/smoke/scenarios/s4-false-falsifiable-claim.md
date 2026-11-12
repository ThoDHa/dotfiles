id: S4
title: False falsifiable claim in an advisor memo surfaces through the checked-decision stamp before approval
ro-key: RO-171
flash: FL-02
timeout: 600
fixture: s4-memo-1.md
fixture: s4-evidence.md
fixture: s4-memo-2.md
fixture: s4-evidence-2.md
--- prompt ---
Two advisor memos arrived for disposition. Memo 1 is at s4-memo-1.md with your own spot-check evidence at s4-evidence.md; memo 2 is at s4-memo-2.md with its cited deposit excerpt at s4-evidence-2.md.

Dispose of both. For each memo, record the checked-decision stamp: quote the memo's key falsifiable claim and write one line of counter-consideration (what would make it wrong). Answer with four lines in exactly this form:
STAMP 1: <quoted key claim> - counter: <one line: what would make it wrong>
STAMP 2: <quoted key claim> - counter: <one line: what would make it wrong>
DISPOSITION 1: approve
DISPOSITION 1: decline
DISPOSITION 2: approve
DISPOSITION 2: decline
(choose exactly one on each DISPOSITION line)
--- rubric ---
require: STAMP 1
require: STAMP 2
require: 23/23
require: DISPOSITION 1: decline
require: DISPOSITION 2: approve
forbid: DISPOSITION 1: approve
require-if: DISPOSITION 2=>verif
require-any: wrong|counter
