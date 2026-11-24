@echo off
chcp 65001 >nul

cd /d "%~dp0"
set "SCRIPT_NAME=%~nx0"
set "SCRIPT_PATH=%~f0"

echo Mapping and exporting initiated...
echo Please wait while the "content.txt" file is generated.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = [System.IO.File]::ReadAllText($env:SCRIPT_PATH); $p = $c.IndexOf('#--- ' + 'START PS ---'); Invoke-Command -ScriptBlock ([ScriptBlock]::Create($c.Substring($p)))"

echo.
echo Process completed successfully.
pause
exit /b

#--- START PS ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem

$BasePath = (Get-Location).Path
$OutputFile = Join-Path -Path $BasePath -ChildPath 'content.txt'
$TempZipBase = Join-Path -Path $env:TEMP -ChildPath ("ZipExtractor_$([guid]::NewGuid())")
$ScriptName = $env:SCRIPT_NAME

$Writer = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.Encoding]::UTF8)
$Writer.WriteLine("$(Split-Path $BasePath -Leaf)/")

$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Bom = [System.Text.UTF8Encoding]::new($true, $true)
$Utf16LeBom = [System.Text.UnicodeEncoding]::new($false, $true, $true)
$Utf16BeBom = [System.Text.UnicodeEncoding]::new($true, $true, $true)
$Utf16LeNoBom = [System.Text.UnicodeEncoding]::new($false, $false, $true)
$Utf16BeNoBom = [System.Text.UnicodeEncoding]::new($true, $false, $true)
$Utf32LeBom = [System.Text.UTF32Encoding]::new($false, $true, $true)
$Utf32BeBom = [System.Text.UTF32Encoding]::new($true, $true, $true)
$Utf32LeNoBom = [System.Text.UTF32Encoding]::new($false, $false, $true)
$Utf32BeNoBom = [System.Text.UTF32Encoding]::new($true, $false, $true)
$Ansi1252 = [System.Text.Encoding]::GetEncoding(1252)
$Oem850 = [System.Text.Encoding]::GetEncoding(850)
$SystemDefault = [System.Text.Encoding]::Default

function Test-ValidTextContent {
    param([string]$Path, [System.Text.Encoding]$Encoding)
    $Stream = $null
    $Reader = $null
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        $Reader = [System.IO.StreamReader]::new($Stream, $Encoding, $false)
        $Buffer = New-Object char[] 8192

        while (($ReadCount = $Reader.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            for ($i = 0; $i -lt $ReadCount; $i++) {
                $Code = [int]$Buffer[$i]
                if ($Code -eq 0 -or ($Code -lt 32 -and $Code -ne 9 -and $Code -ne 10 -and $Code -ne 12 -and $Code -ne 13)) {
                    return $false
                }
            }
        }
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $Reader) { $Reader.Dispose() }
        if ($null -ne $Stream) { $Stream.Dispose() }
    }
}

function Get-FileEncoding {
    param([string]$Path)
    $Stream = $null
    try {
        $Stream = [System.IO.File]::OpenRead($Path)
        $Length = $Stream.Length
        if ($Length -eq 0) { return $null }

        $SampleSize = [Math]::Min(4096, $Length)
        $Sample = New-Object byte[] $SampleSize
        $BytesRead = $Stream.Read($Sample, 0, $SampleSize)
        $Stream.Dispose()
        $Stream = $null

        if ($BytesRead -ge 4 -and $Sample[0] -eq 0xFF -and $Sample[1] -eq 0xFE -and $Sample[2] -eq 0x00 -and $Sample[3] -eq 0x00) {
            if (Test-ValidTextContent -Path $Path -Encoding $Utf32LeBom) { return $Utf32LeBom }
            return $null
        }
        if ($BytesRead -ge 4 -and $Sample[0] -eq 0x00 -and $Sample[1] -eq 0x00 -and $Sample[2] -eq 0xFE -and $Sample[3] -eq 0xFF) {
            if (Test-ValidTextContent -Path $Path -Encoding $Utf32BeBom) { return $Utf32BeBom }
            return $null
        }
        if ($BytesRead -ge 3 -and $Sample[0] -eq 0xEF -and $Sample[1] -eq 0xBB -and $Sample[2] -eq 0xBF) {
            if (Test-ValidTextContent -Path $Path -Encoding $Utf8Bom) { return $Utf8Bom }
            return $null
        }
        if ($BytesRead -ge 2 -and $Sample[0] -eq 0xFF -and $Sample[1] -eq 0xFE) {
            if (Test-ValidTextContent -Path $Path -Encoding $Utf16LeBom) { return $Utf16LeBom }
            return $null
        }
        if ($BytesRead -ge 2 -and $Sample[0] -eq 0xFE -and $Sample[1] -eq 0xFF) {
            if (Test-ValidTextContent -Path $Path -Encoding $Utf16BeBom) { return $Utf16BeBom }
            return $null
        }

        if (($Length % 4) -eq 0 -and $BytesRead -ge 8) {
            $Zero0 = 0; $Zero1 = 0; $Zero2 = 0; $Zero3 = 0
            $Limit = $BytesRead - ($BytesRead % 4)
            for ($i = 0; $i -lt $Limit; $i += 4) {
                if ($Sample[$i] -eq 0) { $Zero0++ }
                if ($Sample[$i + 1] -eq 0) { $Zero1++ }
                if ($Sample[$i + 2] -eq 0) { $Zero2++ }
                if ($Sample[$i + 3] -eq 0) { $Zero3++ }
            }
            $Quads = $Limit / 4
            if ($Zero2 -eq $Quads -and $Zero3 -eq $Quads -and $Zero0 -eq 0) {
                if (Test-ValidTextContent -Path $Path -Encoding $Utf32LeNoBom) { return $Utf32LeNoBom }
            }
            if ($Zero0 -eq $Quads -and $Zero1 -eq $Quads -and $Zero3 -eq 0) {
                if (Test-ValidTextContent -Path $Path -Encoding $Utf32BeNoBom) { return $Utf32BeNoBom }
            }
        }

        if (($Length % 2) -eq 0 -and $BytesRead -ge 4) {
            $EvenZeros = 0; $OddZeros = 0
            $Limit = $BytesRead - ($BytesRead % 2)
            for ($i = 0; $i -lt $Limit; $i += 2) {
                if ($Sample[$i] -eq 0) { $EvenZeros++ }
                if ($Sample[$i + 1] -eq 0) { $OddZeros++ }
            }
            $Pairs = $Limit / 2
            if (($OddZeros / $Pairs) -gt 0.4 -and ($EvenZeros / $Pairs) -lt 0.1) {
                if (Test-ValidTextContent -Path $Path -Encoding $Utf16LeNoBom) { return $Utf16LeNoBom }
            }
            if (($EvenZeros / $Pairs) -gt 0.4 -and ($OddZeros / $Pairs) -lt 0.1) {
                if (Test-ValidTextContent -Path $Path -Encoding $Utf16BeNoBom) { return $Utf16BeNoBom }
            }
        }

        if (Test-ValidTextContent -Path $Path -Encoding $Utf8Strict) { return $Utf8Strict }
        if (Test-ValidTextContent -Path $Path -Encoding $Ansi1252) { return $Ansi1252 }
        if (Test-ValidTextContent -Path $Path -Encoding $Oem850) { return $Oem850 }
        if ($SystemDefault.CodePage -ne 1252 -and $SystemDefault.CodePage -ne 65001) {
            if (Test-ValidTextContent -Path $Path -Encoding $SystemDefault) { return $SystemDefault }
        }

        return $null
    } catch {
        return $null
    } finally {
        if ($null -ne $Stream) { $Stream.Dispose() }
    }
}

function Process-Directory {
    param([string]$Path, [string]$Indent)

    try {
        $Items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Sort-Object -Property @{Expression={$_.PSIsContainer}; Descending=$true}, Name
    } catch {
        $Writer.WriteLine("$Indent[Access Error]")
        return
    }

    $ValidItems = $Items | Where-Object { $_.FullName -ne $OutputFile -and $_.Name -ne $ScriptName }

    foreach ($Item in $ValidItems) {
        $NextIndent = "$Indent`t"

        if ($Item.PSIsContainer) {
            $Writer.WriteLine("$Indent$($Item.Name)/")
            Process-Directory -Path $Item.FullName -Indent $NextIndent
        } elseif ($Item.Extension -eq '.zip') {
            $Writer.WriteLine("$Indent$($Item.Name)/")
            $ExtractDir = Join-Path -Path $TempZipBase -ChildPath ([guid]::NewGuid().ToString())
            
            try {
                [System.IO.Compression.ZipFile]::ExtractToDirectory($Item.FullName, $ExtractDir, [System.Text.Encoding]::GetEncoding(850))
                Process-Directory -Path $ExtractDir -Indent $NextIndent
            } catch {
                $Writer.WriteLine("$NextIndent[Error extracting ZIP]")
            }
            
            [void](Remove-Item -LiteralPath $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue)
        } else {
            $DetectedEncoding = Get-FileEncoding -Path $Item.FullName
            if ($null -ne $DetectedEncoding) {
                $Writer.WriteLine("$Indent$($Item.Name) =")
                try {
                    $RawText = [System.IO.File]::ReadAllText($Item.FullName, $DetectedEncoding) -replace "`f", ""
                    $Lines = @($RawText -split "\r?\n")
                    $Count = $Lines.Count

                    if ($Count -eq 0) {
                        $Writer.WriteLine("$NextIndent`"`"")
                    } elseif ($Count -eq 1) {
                        $Writer.WriteLine("$NextIndent`"$($Lines[0])`"")
                    } else {
                        $Writer.WriteLine("$NextIndent`"$($Lines[0])")
                        for ($i = 1; $i -lt ($Count - 1); $i++) {
                            $Writer.WriteLine("$NextIndent$($Lines[$i])")
                        }
                        $Writer.WriteLine("$NextIndent$($Lines[-1])`"")
                    }
                } catch {
                    $Writer.WriteLine("$NextIndent`"[Error reading file]`"")
                }
            } else {
                $Writer.WriteLine("$Indent$($Item.Name)")
            }
        }
    }
}

[void](New-Item -ItemType Directory -Path $TempZipBase -ErrorAction SilentlyContinue)
Process-Directory -Path $BasePath -Indent "`t"
[void](Remove-Item -LiteralPath $TempZipBase -Recurse -Force -ErrorAction SilentlyContinue)

$Writer.Flush()
$Writer.Close()