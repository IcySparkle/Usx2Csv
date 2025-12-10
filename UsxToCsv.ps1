param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- Validate Input Path ----
if (-not (Test-Path $InputPath)) {
    Write-Error "Input path not found: $InputPath"
    exit 1
}

# ---- Prepare Output Folder ----
if ($OutputFolder) {
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder | Out-Null
        Write-Host "Created output folder: $OutputFolder"
    }
}

# ---- Collect Input Files (.usx, .usfm, .sfm) ----
$files = @()

if ((Get-Item $InputPath).PSIsContainer) {
    $files = Get-ChildItem -Path $InputPath -File |
             Where-Object { $_.Extension.ToLowerInvariant() -in @('.usx','.usfm','.sfm') }
}
else {
    $ext = [System.IO.Path]::GetExtension($InputPath).ToLowerInvariant()
    if ($ext -in @('.usx','.usfm','.sfm')) {
        $files = ,(Get-Item $InputPath)
    }
    else {
        Write-Error "Input must be a .usx, .usfm, or .sfm file, or a folder containing them."
        exit 1
    }
}

if ($files.Count -eq 0) {
    Write-Error "No .usx, .usfm, or .sfm files found."
    exit 1
}

# ---- Common Helpers ----

function Normalize-Whitespace {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $t = [regex]::Replace($Text, '\s+', ' ')
    return $t.Trim()
}

function Get-AttrValue {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$Name
    )
    if (-not $Node -or -not $Node.Attributes) { return $null }
    $attr = $Node.Attributes[$Name]
    if ($attr) { return $attr.Value } else { return $null }
}

function Get-StyledTagName {
    param([string]$style)
    switch ($style) {
        'wj'   { 'wj' }
        'add'  { 'add' }
        'nd'   { 'nd' }
        'bdit' { 'bdit' }
        'it'   { 'i' }
        'bd'   { 'b' }
        default { 'span' }
    }
}

function Is-SubtitleStyle {
    param([string]$style)
    if (-not $style) { return $false }
    $subtitleStyles = @(
        's','s1','s2','s3','sp',
        'ms','mr',
        'mt','mt1','mt2'
    )
    return $subtitleStyles -contains $style
}

function Get-PlainInnerText {
    param([System.Xml.XmlNode]$node)
    if (-not $node) { return "" }
    $raw = $node.InnerText
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
    return (Normalize-Whitespace -Text $raw)
}

# ---- USX Note Helpers (FT-only) ----

function Find-FtNode {
    param([System.Xml.XmlNode]$node)

    if (-not $node) { return $null }

    if ($node.LocalName -eq 'char') {
        $style = Get-AttrValue -Node $node -Name 'style'
        if ($style -eq 'ft') { return $node }
    }

    foreach ($child in $node.ChildNodes) {
        $result = Find-FtNode -node $child
        if ($result) { return $result }
    }
    return $null
}

function ExtractFTFromNote {
    param([System.Xml.XmlNode]$noteNode)

    $ftNode = Find-FtNode -node $noteNode
    if (-not $ftNode) { return "" }

    $raw = $ftNode.InnerText
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
    return (Normalize-Whitespace -Text $raw)
}

# ---- USFM Note Helpers (FT-only) ----

function ExtractFtFromUsfmNoteText {
    param([string]$noteText)

    if ([string]::IsNullOrWhiteSpace($noteText)) { return "" }

    # Capture text after \ft until next backslash
    $m = [regex]::Match($noteText, '\\ft\b([^\\]*)')
    if (-not $m.Success) { return "" }

    $ftRaw = $m.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($ftRaw)) { return "" }
    return (Normalize-Whitespace -Text $ftRaw)
}

function ExtractNotesFromUsfmSegment {
    param(
        [string]$Segment,
        [ref]$FootnoteList,
        [ref]$CrossrefList
    )

    if ([string]::IsNullOrWhiteSpace($Segment)) {
        return $Segment
    }

    $text = $Segment

    # \f ... \f*  (footnotes)
    $text = [regex]::Replace(
        $text,
        '\\f\b(.*?\\f\*)',
        {
            param($m)
            $block = $m.Groups[1].Value
            $full  = '\f' + $block
            $ftText = ExtractFtFromUsfmNoteText -noteText $full
            if ($ftText) { $FootnoteList.Value.Add($ftText) }
            return ' '
        },
        'Singleline'
    )

    # \x ... \x*  (crossreferences)
    $text = [regex]::Replace(
        $text,
        '\\x\b(.*?\\x\*)',
        {
            param($m)
            $block = $m.Groups[1].Value
            $full  = '\x' + $block
            $ftText = ExtractFtFromUsfmNoteText -noteText $full
            if ($ftText) { $CrossrefList.Value.Add($ftText) }
            return ' '
        },
        'Singleline'
    )

    return $text
}

# ---- USFM Inline Content Processor ----
# Updates currentPlainText/currentStyledText and FT/Crossrefs

function Process-UsfmContentSegment {
    param(
        [string]$Segment,
        [ref]$CurrentPlain,
        [ref]$CurrentStyled,
        [ref]$FootnoteList,
        [ref]$CrossrefList
    )

    if ([string]::IsNullOrWhiteSpace($Segment)) { return }

    # 1) Remove superscript spans completely (\sup ... \sup*)
    $seg = [regex]::Replace($Segment, '\\\+?sup\b.*?\\\+?sup\*', ' ', 'Singleline')

    # 2) Extract notes (FT-only) and strip them out
    $seg = ExtractNotesFromUsfmSegment -Segment $seg `
                                       -FootnoteList $FootnoteList `
                                       -CrossrefList $CrossrefList

    if ([string]::IsNullOrWhiteSpace($seg)) { return }

    # 3) Build TextStyled by turning inline markers into tags
    $styled = $seg

    # Map open/close markers to tags
    $styleMap = @{
        'wj'   = 'wj'
        'add'  = 'add'
        'nd'   = 'nd'
        'it'   = 'i'
        'bd'   = 'b'
        'bdit' = 'bdit'
    }

    foreach ($key in $styleMap.Keys) {
        $tag = $styleMap[$key]

        # open markers: \key or \+key
        $styled = [regex]::Replace($styled, "\\\+?$key\b\s*", "<$tag>")
        # close markers: \key*
        $styled = [regex]::Replace($styled, "\\\+?$key\*\s*", "</$tag>")
    }

    # Remove any remaining backslash markers (unknown inline codes)
    $styled = [regex]::Replace($styled, '\\\+?[a-z0-9]+\*?', ' ')
    $styled = Normalize-Whitespace -Text $styled

    # 4) Build TextPlain: remove all backslash markers
    $plain = [regex]::Replace($seg, '\\\+?[a-z0-9]+\*?', ' ')
    $plain = Normalize-Whitespace -Text $plain

    if ($plain) {
        if ($CurrentPlain.Value.Length -gt 0) {
            $CurrentPlain.Value  += " "
            $CurrentStyled.Value += " "
        }
        $CurrentPlain.Value  += $plain
        $CurrentStyled.Value += $styled
    }
}

# ====================================================================
#                      USX → CSV CONVERSION
# ====================================================================

function Convert-UsxToCsv {
    param(
        [string]$UsxPath,
        [string]$CsvPath
    )

    Write-Host "Processing (USX) $UsxPath"

    [xml]$doc = Get-Content -LiteralPath $UsxPath -Encoding UTF8
    
    $nsUri = $doc.DocumentElement.NamespaceURI
    $nsMgr = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $nsMgr.AddNamespace("u", $nsUri)

    $bookNode = $doc.SelectSingleNode("/u:usx/u:book", $nsMgr)
    if (-not $bookNode) {
        Write-Error "No <book> found in $UsxPath"
        return
    }
    $bookCode = Get-AttrValue -Node $bookNode -Name "code"

    # Per-verse state
    $script:currentChapter     = $null
    $script:currentVerse       = $null
    $script:currentPlainText   = ""
    $script:currentStyledText  = ""
    $script:currentFootnotes   = New-Object System.Collections.Generic.List[string]
    $script:currentCrossrefs   = New-Object System.Collections.Generic.List[string]
    $script:currentSubtitle    = ""

    $rows = New-Object System.Collections.Generic.List[object]

    function Add-CurrentVerse {
        param($Book, $Chapter, $Verse)

        $plain   = $script:currentPlainText.Trim()
        $styled  = $script:currentStyledText.Trim()
        $subText = $script:currentSubtitle.Trim()

        if ($Book -and $Chapter -and $Verse -and $plain) {
            $rows.Add([pscustomobject]@{
                Book       = $Book
                Chapter    = $Chapter
                Verse      = $Verse
                TextPlain  = $plain
                TextStyled = $styled
                Footnotes  = ($script:currentFootnotes -join " | ")
                Crossrefs  = ($script:currentCrossrefs -join " | ")
                Subtitle   = $subText
            })
        }
    }

    function Process-NoteNode {
        param([System.Xml.XmlNode]$noteNode)

        $style = Get-AttrValue -Node $noteNode -Name "style"
        $ft    = ExtractFTFromNote -noteNode $noteNode
        if (-not $ft) { return }

        if ($style -and $style.StartsWith("x")) {
            $script:currentCrossrefs.Add($ft)
        }
        else {
            $script:currentFootnotes.Add($ft)
        }
    }

    function Process-Node {
        param(
            [System.Xml.XmlNode]$node,
            [System.Xml.XmlNamespaceManager]$nsMgr
        )

        switch ($node.NodeType) {
            'Element' {
                switch ($node.LocalName) {

                    'chapter' {
                        $script:currentChapter = Get-AttrValue -Node $node -Name "number"
                        # Optionally: reset subtitle here if desired
                        # $script:currentSubtitle = ""
                    }

                    'verse' {
                        $sid = Get-AttrValue -Node $node -Name "sid"
                        $eid = Get-AttrValue -Node $node -Name "eid"

                        if ($sid) {
                            $script:currentVerse       = Get-AttrValue -Node $node -Name "number"
                            $script:currentPlainText   = ""
                            $script:currentStyledText  = ""
                            $script:currentFootnotes.Clear()
                            $script:currentCrossrefs.Clear()
                        }
                        elseif ($eid) {
                            Add-CurrentVerse -Book $bookCode `
                                             -Chapter $script:currentChapter `
                                             -Verse $script:currentVerse

                            $script:currentVerse       = $null
                            $script:currentPlainText   = ""
                            $script:currentStyledText  = ""
                            $script:currentFootnotes.Clear()
                            $script:currentCrossrefs.Clear()
                        }
                    }

                    'note' {
                        Process-NoteNode -noteNode $node
                        return
                    }

                    'para' {
                        $style = Get-AttrValue -Node $node -Name "style"

                        if (Is-SubtitleStyle -style $style) {
                            $subtitleText = Get-PlainInnerText -node $node
                            if ($subtitleText) {
                                $script:currentSubtitle = $subtitleText
                            }
                        }

                        foreach ($child in $node.ChildNodes) {
                            Process-Node -node $child -nsMgr $nsMgr
                        }
                    }

                    'char' {
                        $style = Get-AttrValue -Node $node -Name "style"

                        # Skip superscript text completely
                        if ($style -eq 'sup') {
                            return
                        }

                        $tag = $null
                        if ($style) {
                            $tag = Get-StyledTagName -style $style
                        }

                        if ($script:currentVerse -and $tag) {
                            $script:currentStyledText += "<$tag>"
                        }

                        foreach ($child in $node.ChildNodes) {
                            Process-Node -node $child -nsMgr $nsMgr
                        }

                        if ($script:currentVerse -and $tag) {
                            $script:currentStyledText += "</$tag>"
                        }
                    }

                    default {
                        foreach ($child in $node.ChildNodes) {
                            Process-Node -node $child -nsMgr $nsMgr
                        }
                    }
                }
            }

            'Text' {
                if ($script:currentVerse) {
                    $t = $node.Value
                    if (-not [string]::IsNullOrWhiteSpace($t)) {
                        $t = Normalize-Whitespace -Text $t
                        if ($script:currentPlainText.Length -gt 0) {
                            $script:currentPlainText  += " "
                            $script:currentStyledText += " "
                        }
                        $script:currentPlainText  += $t
                        $script:currentStyledText += $t
                    }
                }
            }

            default { }
        }
    }

    $root = $doc.SelectSingleNode("/u:usx", $nsMgr)
    foreach ($child in $root.ChildNodes) {
        Process-Node -node $child -nsMgr $nsMgr
    }

    $rows |
        Sort-Object Book, {[int]$_.Chapter}, Verse |
        Export-Csv -Path $CsvPath -Encoding UTF8 -NoTypeInformation

    Write-Host "Created CSV: $CsvPath" -ForegroundColor Green
}

# ====================================================================
#                  USFM / SFM → CSV CONVERSION
# ====================================================================

function Convert-UsfmToCsv {
    param(
        [string]$UsfmPath,
        [string]$CsvPath
    )

    Write-Host "Processing (USFM/SFM) $UsfmPath"

    $rawLines = Get-Content -LiteralPath $UsfmPath -Encoding UTF8

    # Book code: try \id first, fallback to file basename
    $bookCode = [System.IO.Path]::GetFileNameWithoutExtension($UsfmPath)
    foreach ($line in $rawLines) {
        $l = $line.Trim()
        if ($l -match '^[\\]id\s+(\S+)') {
            $bookCode = $matches[1]
            break
        }
    }

    # Verse state (shared logic with USX)
    $currentChapter    = $null
    $currentVerse      = $null
    $currentPlainText  = ""
    $currentStyledText = ""
    $currentFootnotes  = New-Object System.Collections.Generic.List[string]
    $currentCrossrefs  = New-Object System.Collections.Generic.List[string]
    $currentSubtitle   = ""

    $rows = New-Object System.Collections.Generic.List[object]

    function Add-CurrentVerseUsfm {
        param($Book, $Chapter, $Verse,
              [ref]$Plain, [ref]$Styled,
              [ref]$Fts, [ref]$Xrefs,
              [ref]$Subtitle,
              [ref]$Rows)

        $plain   = $Plain.Value.Trim()
        $styled  = $Styled.Value.Trim()
        $subText = $Subtitle.Value.Trim()

        if ($Book -and $Chapter -and $Verse -and $plain) {
            $Rows.Value.Add([pscustomobject]@{
                Book       = $Book
                Chapter    = $Chapter
                Verse      = $Verse
                TextPlain  = $plain
                TextStyled = $styled
                Footnotes  = ($Fts.Value -join " | ")
                Crossrefs  = ($Xrefs.Value -join " | ")
                Subtitle   = $subText
            })
        }
    }

    foreach ($line in $rawLines) {

        $l = $line.Trim()
        if (-not $l) { continue }

        # Chapter: \c N
        if ($l -match '^[\\]c\s+(\d+)\b') {
            # End current verse (if any)
            if ($currentVerse) {
                Add-CurrentVerseUsfm -Book $bookCode `
                                     -Chapter $currentChapter `
                                     -Verse $currentVerse `
                                     -Plain ([ref]$currentPlainText) `
                                     -Styled ([ref]$currentStyledText) `
                                     -Fts ([ref]$currentFootnotes) `
                                     -Xrefs ([ref]$currentCrossrefs) `
                                     -Subtitle ([ref]$currentSubtitle) `
                                     -Rows ([ref]$rows)
            }

            $currentVerse     = $null
            $currentPlainText = ""
            $currentStyledText= ""
            $currentFootnotes.Clear()
            $currentCrossrefs.Clear()

            $currentChapter = $matches[1]
            continue
        }

        # Headings / subtitles
        if ($l -match '^[\\](s[0-3]?|sp|ms|mr|mt[12]?)\s*(.*)$') {
            $headText = $matches[2]
            $headText = ExtractNotesFromUsfmSegment -Segment $headText `
                                                    -FootnoteList ([ref]$currentFootnotes) `
                                                    -CrossrefList ([ref]$currentCrossrefs)
            $headText = [regex]::Replace($headText, '\\\+?[a-z0-9]+\*?', ' ')
            $headText = Normalize-Whitespace -Text $headText
            if ($headText) {
                $currentSubtitle = $headText
            }
            continue
        }

        # Verse line: \v N text...
        if ($l -match '^[\\]v\s+(\d+)\s*(.*)$') {

            # Flush previous verse
            if ($currentVerse) {
                Add-CurrentVerseUsfm -Book $bookCode `
                                     -Chapter $currentChapter `
                                     -Verse $currentVerse `
                                     -Plain ([ref]$currentPlainText) `
                                     -Styled ([ref]$currentStyledText) `
                                     -Fts ([ref]$currentFootnotes) `
                                     -Xrefs ([ref]$currentCrossrefs) `
                                     -Subtitle ([ref]$currentSubtitle) `
                                     -Rows ([ref]$rows)
            }

            $currentVerse      = $matches[1]
            $currentPlainText  = ""
            $currentStyledText = ""
            $currentFootnotes.Clear()
            $currentCrossrefs.Clear()

            $rest = $matches[2]
            if ($rest) {
                Process-UsfmContentSegment -Segment $rest `
                                           -CurrentPlain ([ref]$currentPlainText) `
                                           -CurrentStyled ([ref]$currentStyledText) `
                                           -FootnoteList ([ref]$currentFootnotes) `
                                           -CrossrefList ([ref]$currentCrossrefs)
            }
            continue
        }

        # Paragraph markers: m, p, pi, q*, qt* etc.
        if ($l -match '^[\\](m|p|pi|q[0-4]?|qt[0-4]?)\s*(.*)$') {
            $rest = $matches[2]
            if ($currentVerse -and $rest) {
                Process-UsfmContentSegment -Segment $rest `
                                           -CurrentPlain ([ref]$currentPlainText) `
                                           -CurrentStyled ([ref]$currentStyledText) `
                                           -FootnoteList ([ref]$currentFootnotes) `
                                           -CrossrefList ([ref]$currentCrossrefs)
            }
            continue
        }

        # Any other line: if in a verse, treat as continuation
        if ($currentVerse) {
            Process-UsfmContentSegment -Segment $l `
                                       -CurrentPlain ([ref]$currentPlainText) `
                                       -CurrentStyled ([ref]$currentStyledText) `
                                       -FootnoteList ([ref]$currentFootnotes) `
                                       -CrossrefList ([ref]$currentCrossrefs)
        }
    }

    # Flush last verse if any
    if ($currentVerse) {
        Add-CurrentVerseUsfm -Book $bookCode `
                             -Chapter $currentChapter `
                             -Verse $currentVerse `
                             -Plain ([ref]$currentPlainText) `
                             -Styled ([ref]$currentStyledText) `
                             -Fts ([ref]$currentFootnotes) `
                             -Xrefs ([ref]$currentCrossrefs) `
                             -Subtitle ([ref]$currentSubtitle) `
                             -Rows ([ref]$rows)
    }

    $rows |
        Sort-Object Book, {[int]$_.Chapter}, Verse |
        Export-Csv -Path $CsvPath -Encoding UTF8 -NoTypeInformation

    Write-Host "Created CSV: $CsvPath" -ForegroundColor Green
}

# ====================================================================
#                              ENTRY
# ====================================================================

foreach ($f in $files) {
    $ext = $f.Extension.ToLowerInvariant()

    if ($OutputFolder) {
        $csvPath = Join-Path $OutputFolder ($f.BaseName + ".csv")
    } else {
        $csvPath = [System.IO.Path]::ChangeExtension($f.FullName, ".csv")
    }

    switch ($ext) {
        '.usx'  { Convert-UsxToCsv  -UsxPath  $f.FullName -CsvPath $csvPath }
        '.usfm' { Convert-UsfmToCsv -UsfmPath $f.FullName -CsvPath $csvPath }
        '.sfm'  { Convert-UsfmToCsv -UsfmPath $f.FullName -CsvPath $csvPath }
    }
}

Write-Host "All conversions completed."
