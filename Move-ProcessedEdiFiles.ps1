$Source = "z:\ISOFT\inbox\walmart\102826"
$Destination = "z:\ISOFT\outbox\walmart\102826\batch1"
function Compare-FileItems {
    $csvRecords = Import-Csv -Path "C:\Users\Tarun\col\20261027_115622\Output\edi_po_so_20261028_073004.csv"
    $processedFiles = $csvRecords | select-Object -ExpandProperty "Source File" | sort -Unique
    $sourceFile = Get-ChildItem -Path $Source
    Write-host "$($processedFiles.Count) processed files found."
    $count = 0
    foreach ($file in $sourceFile) {
        Try {
            $matchingFile = $processedFiles | Where-Object { $_ -eq $file.name }
            if ($matchingFile) {
                #$DestinationPath = "$Destination\$($matchingFile.Name)"
                #Write-Host "Moving file $($matchingFile.FullName) to $DestinationPath"
                #Move-Item -Path $matchingFile.FullName -Destination $DestinationPath -ErrorAction Stop
                $count++
            }else{
                Write-Host "No matching file found for $file"
            }
        }
        Catch {
            Write-Host "Error processing file $($file): $_"
        }
    }
    Write-Host "$count files moved to $Destination."
}


Compare-FileItems