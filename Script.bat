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
$TempZipBase = Join-Path -Path $env:TEMP -ChildPath ("ExtratorZIP_$([guid]::NewGuid())")
$ScriptName = $env:SCRIPT_NAME

$Writer = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.Encoding]::UTF8)
$Writer.WriteLine("$(Split-Path $BasePath -Leaf)/")

function Test-IsTextFile {
    param([string]$Path)
    try {
        if ((Get-Item -LiteralPath $Path).Length -eq 0) { return $false }
        
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $Bytes = Get-Content -LiteralPath $Path -AsByteStream -TotalCount 1024 -ErrorAction Stop
        } else {
            $Bytes = Get-Content -LiteralPath $Path -Encoding Byte -TotalCount 1024 -ErrorAction Stop
        }
        
        return ($Bytes -notcontains 0)
    } catch {
        return $false
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
        } elseif (Test-IsTextFile -Path $Item.FullName) {
            $Writer.WriteLine("$Indent$($Item.Name) =")
            try {
                $Lines = @(Get-Content -LiteralPath $Item.FullName -Encoding UTF8 -ErrorAction Stop)
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

[void](New-Item -ItemType Directory -Path $TempZipBase -ErrorAction SilentlyContinue)
Process-Directory -Path $BasePath -Indent "`t"
[void](Remove-Item -LiteralPath $TempZipBase -Recurse -Force -ErrorAction SilentlyContinue)

$Writer.Flush()
$Writer.Close()