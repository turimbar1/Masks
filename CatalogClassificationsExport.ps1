$PSVersionTable
$authToken = "NzAwNTQzODY2ODcyMjY2NzUyOjNhOGZmOWY1LWMyMTctNDljYy1hOTU5LWViMjJiNWJkNGQxZA=="
Invoke-WebRequest -Uri 'http://us-lt-andrewp:15156/powershell' -OutFile 'data-catalog.psm1' -Headers @{"Authorization" = "Bearer $authToken" }
Import-Module .\data-catalog.psm1 -Force
# connect to your SQL Data Catalog instance 
Connect-SqlDataCatalog -ServerUrl 'http://us-lt-andrewp:15156' -AuthToken $authToken 
$instanceName = 'US-LT-ANDREWP\SQL2016'
$databaseName = 'WidgetDev'
# export all columns to a .csv file, swapping the native sensitivity label to 'sensitive' where needed
Get-ClassificationColumn -InstanceName $instanceName -DatabaseName $databaseName | `
    Select-Object  schemaName, tableName, columnName, @{Name = "Sensitivity"; Expression = { switch ($_.sensitivityLabel) {
            { $_ -match "Confidential - GDPR" -or "Confidential" } { "Sensitive" }
            { $_ -match "Public" } { "Nonsensitive" }
            Default { "Check" }
        } }
} , @{Name = "Comments"; Expression = { $_.sensitivityLabel } } | `
    ConvertTo-Csv -NoTypeInformation | `
    ForEach-Object { $_ -replace '"' } | `
    Out-File "C:\Users\andrew.pierce\Documents\DataMaskingSets_New\$databaseName-Classification.csv" -Encoding Unicode


    
    