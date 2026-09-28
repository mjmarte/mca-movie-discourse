# Main Concept Inventory (MCI) from Multimodal Clip

You will propose a Main Concept Inventory (MCI) for a short film clip.

This task follows **Main Concept Analysis** as defined by Nicholas & Brookshire (1995) and classic **story grammar** (Stein & Glenn, 1979).

Main concepts are **gist-level propositions** that capture the essential information of a narrative.  
Each concept should be scorable for:
- **Presence** – whether the idea appears at all in a retelling.  
- **Completeness** – whether the idea is conveyed fully (not fragmentary).  
- **Accuracy** – whether the idea is correct relative to what actually occurred.  
Grammatical errors are irrelevant to scoring if the idea is intact.

---

## EVIDENCE BOUNDARIES (use only what is provided)
Use **only**: (1) metadata JSON, (2) **SPOKEN** transcript (speaker names removed), (3) optional **ANON speaker turns** (`S1:`, `S2:`) for turn-taking, (4) audio (16 kHz mono), (5) sampled keyframe images (1-based order).  
No prior knowledge beyond these inputs.

> **Important:** Main concepts may be conveyed **purely visually** (e.g., physical actions, facial expressions, crowd reactions, montage sequences) even when not described in the transcript. If the visual evidence is strong and coherent, you **must** include such concepts and mark their `support.sources` to include `"frames"` (and optionally `"audio"` if relevant).

---

## REFERENTS & ROLES (human-like but evidence-bound)
1) **Proper names**  
   - If a name is **spoken** in the transcript, you may use it (quote it in `support.transcript_quotes`).  
   - Do **not** use names that appear only in metadata/speaker labels.

2) **Roles (e.g., coach, clerk, psychologist)**  
   - Allowed if **either**:  
     a) the noun appears **verbatim** in the spoken transcript (quote it), **or**  
     b) it is **strongly implied** by **both** visual and verbal cues. In that case, **hedge** the label (“appears to be”, “seems like”) **and** provide evidence.

3) **Descriptors (e.g., man/woman, boy/girl, older/younger, uniformed person)**  
   - Allowed if supported by visuals and/or wording/pronouns in the transcript.  
   - Prefer natural, concise phrasing (“the coach gives a pep talk”, “an older man confronts another”).  
   - Avoid speculation about protected attributes.

4) **Directionality** (who said what)  
   - Must be grounded in transcript quotes. If ambiguous, use neutral phrasing.

5) **Over-generic labels**  
   - Avoid repetitive “a person / one person” when a **supported** name/role/descriptor is available.

Include referent evidence explicitly (see schema).

---

## COVERAGE REQUIREMENTS (beginning–middle–end, include non-verbal resolution if present)
Your MCI must represent the **whole narrative arc**:
- Include at least one concept from the **beginning**, one from the **middle**, and one from the **end** of the clip.
- The **end** must include a **Resolution concept** if any outcome is visually evident (e.g., applause, cheering, embraces, fighting, choking, or montage sequences).
- Include at least one **visual-only main concept** if any major event is depicted without being verbalized.
---

## WHAT COUNTS AS A “MAIN CONCEPT”
- One self-contained, gist-bearing proposition (setting, initiating event, attempt, consequence, resolution, theme, internal response).  
- Scorable for presence/completeness/accuracy (Nicholas & Brookshire, 1995).  
- Canonical phrasing a typical reteller would use.  
- Keep concepts independent; avoid duplications and over-detailed minutiae.

---

## HARD LIMITS
- Produce **at least M** and **at most N** concepts (caller sets M/N).  
- Keep paraphrase lists concise (≤3 positives, ≤3 negatives).  
- Avoid long quotes; keep fields ≲200 characters when possible.

---

## OUTPUT FORMAT (JSON only)
Return **only** a valid JSON **array** of objects. No commentary.

Each object **must** include:
- `id`: `"MC-01"`, `"MC-02"`, …
- `label`: short, sentence-like proposition (e.g., `"the coach gives a pep talk to his team"`)
- `definition`: why this is gist-level (1 sentence)
- `role`: one of `["Setting","InitiatingEvent","InternalResponse","Plan/Attempt","Consequence","Resolution","Theme","Other"]`
- `positives`: up to **3** paraphrases that **should** count
- `negatives`: up to **3** likely confusions that **should not** count
- `support`:
  - `sources`: subset of `["frames","transcript","audio"]`  
    - Visual-only concepts are allowed; include `"frames"` (and `"audio"` if relevant) even if `"transcript"` is absent.
  - `transcript_quotes`: short verbatim quotes that justify the concept (omit if not applicable to a visual-only concept).  
    - If you use a **name** or **role** that isn’t verbatim in the quote, include the **cue lines** you relied on.
  - `frame_ids`: 1-based indices of frames that visually support it (omit if none)
  - `audio_note`: optional (tone, crowd noise, laughter, applause, etc.)
- `referents` (optional): array of specific referents used in the `label`. Each item:  
  - `{"type":"name|role|descriptor","value":"coach|older man|…","confidence":"low|medium|high","evidence":{"visual_frame_ids":[...],"verbal_quotes":[...]}}`

**Important:** If a **role** is not spoken verbatim, you must hedge (e.g., “appears to be the coach”) and include both visual and verbal evidence in `support` and/or `referents`.

---

## PROCESS YOU SHOULD FOLLOW (internally)
1. Skim inputs (metadata, spoken transcript, anon turns, audio, frames).  
2. Identify candidate gists across the story grammar. Ensure **beginning–middle–end** coverage, including **Resolution** if present.  
3. Include **non-verbal** gist (e.g., physical actions, montages, crowd reactions) when visually evident.  
4. Choose **specific, justified referents** when supported; otherwise stay neutral.  
5. Write independent concepts; add sources + short quotes + frame ids.  
6. Add up to 3 positives/negatives to aid downstream scoring.

---

## INPUT ORDER
1) Metadata JSON  
2) SPOKEN transcript (no names from labels)  
3) SPEAKER TURNS (ANON) `S1:`, `S2:` (optional)  
4) Audio (16 kHz mono)  
5) Keyframe images (1-based)

---

## GUIDELINES
- Base concepts primarily on what is explicitly shown or spoken in the clip.
- You may include limited schema-based inferences if they are obvious and help clarify the scene (e.g., recognizing a hockey coach giving a motivational speech, or that a historical sports match is the 1980 Miracle on Ice).
- Do NOT add actor names, production trivia, or outside details not clearly inferable from the scene.

---

## REMINDERS
- No prior knowledge; no inventions.  
- Be neutral if directionality is unclear.  
- Prefer supported specificity over generic “person”.  
- Concepts must be scorable for presence/completeness/accuracy (Nicholas & Brookshire, 1995).  
- Ensure at least one **visual-only** concept when appropriate, and at least one **Resolution** concept if the ending shows a clear outcome.  
- Return only the JSON array.