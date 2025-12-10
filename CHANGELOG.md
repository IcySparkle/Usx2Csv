# Changelog — UsxToCsv.ps1

All notable changes to **UsxToCsv.ps1** are documented here.  
This project follows a simple semantic versioning style: **MAJOR.MINOR.PATCH**.

---

## **0.6.0 — 2025-12-10**
### 💥 Major Release — Unified USX + USFM + SFM Engine
**Highlights**
- Added **full USFM (`.usfm`) and SFM (`.sfm`) support**.
- Unified verse handling across USX & USFM.
- Shared CSV schema: *Book, Chapter, Verse, TextPlain, TextStyled, Footnotes, Crossrefs, Subtitle*.
- Footnotes & cross‑refs now extracted using **FT-only logic** in both formats.
- Introduced **subtitle recognition** for USFM: `\s`, `\s1–3`, `\sp`, `\m`, `\ms`, `\mr`, `\mt` etc.
- Inline USFM formatting (`\bd`, `\it`, `\add`, `\nd`, `\wj`, `\qt`, `\q1`–`\q4`, etc.) mapped to the same styled tags used in USX.
- Superscripts removed consistently:
  - USX: `<char style="sup">...</char>`
  - USFM: `\sup...\sup*`, `\+sup...\+sup*`
- Improved backslash marker stripping and whitespace normalization.
- Output matches USX behavior even for complex USFM.

---

## **0.5.0 — 2025-12-09**
### 🚀 Feature Release — UsxToPlainText Integration Concepts
- Added requirements and alignment with the new **UsxToPlainText.ps1** parser.
- Improved removal of `<char style="sup">` during CSV generation.
- Added preliminary USFM hooks, preparing for unified handling.

---

## **0.4.0 — 2025-12-08**
### ➕ Enhancements
- Added recognition of `qt`, `qt1–4`, `+qt`, `+qt*` inline quotation markers.
- Improved subtitle detection logic.
- Normalized whitespace in `TextPlain` and `TextStyled`.

---

## **0.3.0 — 2025-12-07**
### ✨ Structured Output Improvements
- Introduced `Subtitle` column.
- Improved footnote extraction: FT-only now enforced.
- Added GREP-friendly inline tag mapping for `TextStyled`.

---

## **0.2.0 — 2025-12-06**
### 📦 Multi-file Support & Output Controls
- Added support for folders and batch processing.
- Added `-OutputFolder` parameter.

---

## **0.1.0 — 2025-12-05**
### 🎉 Initial Version
- Basic USX → CSV converter.
- Verse milestone handling (`sid` / `eid`).
- Footnotes and cross-references extracted from `<note>` elements.
- Basic plain vs styled text output.

---

If you'd like **auto-generated release notes**, GitHub Actions integration, or a **CHANGELOG for UsxToPlainText**, I can create those too.
