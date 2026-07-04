# --- CONFIGURATION ---
$TargetRoot = "C:\Users\Hogan\AppData\Local\Temp"
$WhatIf     = $false # Change to $false to actually delete the folders change to $true to test
# ---------------------

# 1. Fetch all sub-directories recursively, including hidden ones
$Directories = Get-ChildItem -Path $TargetRoot -Recurse -Directory -Force

# 2. Sort by FullName descending so deepest "leaf" folders are processed first
$SortedDirectories = $Directories | Sort-Object -Property FullName -Descending

# 3. Iterate and safely check each folder
foreach ($Dir in $SortedDirectories) {
    # Check if the directory contains any items (files or subfolders)
    # FIXED: Removed the '$_ |' pipeline input and passed path directly
    $IsEmpty = (Get-ChildItem -Path $Dir.FullName -Force | Select-Object -First 1).Count -eq 0


    
    if ($IsEmpty) {
        if ($WhatIf) {
            Write-Host "[WHAT-IF] Would delete empty folder: $($Dir.FullName)" -ForegroundColor Yellow
        } else {
            Write-Host "[DELETING] Removing folder: $($Dir.FullName)" -ForegroundColor Cyan
            Remove-Item -LiteralPath $Dir.FullName -Force
        }
    }
}