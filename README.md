# UsxToCsv — Structured Verse-Level CSV Export from USX Scripture Files

`UsxToCsv.ps1` is a PowerShell script that converts **USX (Unified Scripture XML)** files into structured **CSV** for Bible publishing, translation workflows, linguistic analysis, and typesetting systems such as Adobe InDesign.

The resulting CSV contains **one row per verse**, with clean plain text, optional styled text for GREP styling, extracted footnotes and cross-references, and section headings (subtitles).

---

## ✨ Key Features

### ✔ Verse-level structured output
Each verse becomes a CSV row containing:

| Column | Meaning |
|--------|---------|
| **Book** | USX `<book code="XXX">` |
| **Chapter** | `<chapter number="N">` |
| **Verse** | `<verse sid="...">` milestone number |
| **TextPlain** | Clean verse text without inline styling |
| **TextStyled** | Inline styles converted to light GREP-friendly tags |
| **Footnotes** | Extracted FT-only footnotes (`<char style="ft">`) |
| **Crossrefs** | Extracted FT-only cross references |
| **Subtitle** | Nearest preceding section heading |

---

## ✔ Accurate handling of USX verse milestones

USX uses milestone-style verse markers:

```xml
<verse sid="JHN 1:1" number="1"/>
...
<verse eid="JHN 1:1"/>
```

This script:

- Starts verse capture at `sid`
- Ends capture at `eid`
- Aggregates inner text, notes, and inline markup
- Produces one complete row per verse

---

## ✔ Clean Text Extraction

### **TextPlain**
- All inline `<char>` tags stripped  
- Notes removed  
- Whitespace normalized  
- `<char style="sup">…</char>` **skipped entirely**

### **TextStyled**
Inline styles mapped for InDesign GREP use:

| USX style | Output tag |
|-----------|------------|
| `wj` | `<wj>` |
| `add` | `<add>` |
| `nd` | `<nd>` |
| `it` | `<i>` |
| `bd` | `<b>` |
| `bdit` | `<bdit>` |
| *(others)* | `<span>` |

---

## ✔ Footnotes & Cross-References (FT-only)

Only FT-text is extracted from notes:

```xml
<note style="f">
    <char style="fr">1:12</char>
    <char style="ft">Some manuscripts say...</char>
</note>
```

Classification:

- Styles beginning with **x** → Crossrefs  
- All others → Footnotes  

Multiple entries are joined with ` | `.

---

## ✔ Subtitle Handling

Recognized heading styles:

```
s, s1, s2, s3, sp
ms, mr
mt, mt1, mt2
```

Each verse row inherits the latest subtitle until another appears.

---

## 📁 Example CSV Row

```
Book,Chapter,Verse,TextPlain,TextStyled,Footnotes,Crossrefs,Subtitle
3JN,1,1,"The elder to the beloved Gaius...","<bdit>The elder</bdit> to the beloved...",,"","Greeting"
```

---

# 🚀 Usage

### Convert a single USX file

```powershell
.\UsxToCsv.ps1 -InputPath ".\JHN.usx"
```

### Convert all USX files in a folder

```powershell
.\UsxToCsv.ps1 -InputPath ".\USX"
```

### Specify output folder

```powershell
.\UsxToCsv.ps1 -InputPath ".\USX" -OutputFolder ".\CSV"
```

CSV files default to the same folder as the source.

---

# 🧠 Implementation Notes

### Verse milestones
- `sid` = start  
- `eid` = end  

### Inline superscripts removed
`<char style="sup">` content is intentionally **ignored**.

### Whitespace normalization
All internal spacing compressed to a clean single-space layout.

---

# 📦 Output Files

```
Input:  JHN.usx
Output: JHN.csv
```

---

# 🛠 Recommended Use Cases

- Bible typesetting pipelines
- Translation QA workflows
- Linguistic analysis tools
- Scripture content review systems
- Machine learning preprocessing

---

# 🤝 Contributing

Enhancements welcome! Particularly:

- Poetry-level tagging
- Multi-book USX support
- Custom inline-style mappings
- JSON/Parquet output options

---

# 📜 License

MIT License — Free for commercial and non‑commercial use.

---

# 🙌 Acknowledgements

Inspired by real-world Scripture publishing and translation workflows.  
Designed for compatibility with Paratext, DBL USX exports, and professional typesetting systems.
