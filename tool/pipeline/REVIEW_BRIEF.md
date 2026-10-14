# Review brief
You review quotes for a "wisdom from history" app. Input: one chunk file (JSONL; id, category, text, author, speaker, reference, locator). Read it fully (use Read with offset/limit in pieces).
For each quote decide:
- DROP if it is not wisdom a reader can take on its own: plain narrative of events ("He marched to...", "At first, when his friends would have persuaded him..."), depends on an unclear "he/she/they/this" referent or on the surrounding story, is a fragment, is about a specific historical situation with no general lesson, is trivial, garbled, or offensive by modern standards (slavery approval, contempt for women or ethnic groups, cruelty praised). Keep quotes that are old-fashioned in wording but wise. A named person in the text is fine if the lesson is clear.
- RECAT if the category is clearly wrong; categories: relations (friendship, love, trust, kindness, how to treat people), leadership (ruling, command, example, duty, power), team (cooperation, unity, groups working together, delegation, helpers), family (parents, children, marriage, siblings, home), strategy (planning, war, timing, foresight, negotiation, prudence).
- otherwise KEEP (no output).
Be strict but fair: expect to drop roughly 10-25 percent.
Output: write a file with the Write tool, one decision per line, tab separated:
  DROP<TAB>id<TAB>short reason
  RECAT<TAB>id<TAB>newcategory
Final message: counts of DROP and RECAT only.
