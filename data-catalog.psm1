<#
  For more information and worked examples refer to https://www.red-gate.com/data-catalog/automation .
#>

#Requires -Version 5.1

<#
.SYNOPSIS
  Connect to SQL Data Catalog.
.DESCRIPTION
  Allows other commandlets to authenticate with the API.
  This cmdlet should be called once, before any other functions are called.
  This function takes an auth token as a parameter and temporarily stores it,
  to allow the other functions to authenticate with the API.
.PARAMETER ServerUrl
  Url of the server where SQL Data Catalog is hosted.
.PARAMETER AuthToken
  Authentication token which can be obtained from the Web Client. Please refer to https://www.red-gate.com/data-catalog/working-with-rest-api for more information.
.EXAMPLE
  Import-Module .\RedgateDataCatalog.psm1
  $server="http://localhost:15156"
  $authToken="NjIzODE1Mjk5MjgzNTUwMjA4OjVhNzkyNWE0LGA4OjQtNGM1ZC1hOGY4LTJhMzM2ODk0M2NaBc=="
  Connect-SqlDataCatalog -ServerUrl $server -AuthToken $authToken

  Allows other commandlets to authenticate with the API using $AuthToken parameter.
#>

function Connect-SqlDataCatalog {
    param(
        [Alias("Url")]
        [Parameter(Mandatory, Position = 0)][uri] $ServerUrl,
        [Alias("ClassificationAuthToken", "Token")]
        [Parameter(Mandatory, Position = 1)] $AuthToken
    )

    $Script:ClassificationURL = $ServerUrl
    $expectedServerVersion = '1.7.9.14249'

    $OsInfo = [Environment]::OSVersion.VersionString
    $PowerShellVersion = $PSVersionTable.PSVersion
    $PowerShellInfo = "$($PSVersionTable.PSEdition), $PSSessionApplicationName"

    $UserAgent = "SqlDataCatalog-PSModule ($OsInfo) SqlDataCatalog-WebAPI/$expectedServerVersion PowerShell/$PowerShellVersion ($PowerShellInfo)"

    $Script:ClassificationHeader = @{
        'Authorization' = "Bearer $AuthToken"
        'User-Agent' = $UserAgent
    }

    $status = InvokeApiCall -Uri 'api/status' -Method Get
    if (!$status.IsOk) {
        throw "The Data Catalog server has encountered an error. $($status.ErrorMessage)"
    }
    if ($status.Version -ne $expectedServerVersion) {
        throw "Expected version $($expectedServerVersion) but found version $($status.Version). Re-download this PowerShell module from the server."
    }

    $Script:allTagCategories = ArrayToNameBasedHashtable((Get-ClassificationTaxonomy).TagCategories)
}

<#
.SYNOPSIS
  Registers a single SQL Server instance.
.DESCRIPTION
  Registers a single SQL Server instance to make it available within the SQL Data Catalog.
.PARAMETER FullyQualifiedInstanceName
  The fully-qualified name of the SQL Server instance to be registered. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER UserId
  Used only for SQL Server Authentication. Known also as "user name". Optional, do not provide for Windows Authentication.
.PARAMETER Password
  Used only for SQL Server Authentication. Optional, do not provide for Windows Authentication.
.EXAMPLE
  Register-ClassificationInstance -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename'

  Registers an instance of SQL Server named "myinstancename" running on the "mysqlserver.mydomain.com" machine. Windows Authentication will be used to connect to this intance.
.EXAMPLE
  Register-ClassificationInstance -FullyQualifiedInstanceName 'mysqlserver.mydomain.com'

  Registers the default instance of SQL Server running on the "mysqlserver.mydomain.com" machine. Windows Authentication will be used to connect to this intance.
.EXAMPLE
  Register-ClassificationInstance -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename' -UserId 'somebody' -Password 'myPassword'

  Registers an instance of SQL Server named "myinstancename" running on the "mysqlserver.mydomain.com" machine. SQL Server Authentication will be used to connect to this intance.
.EXAMPLE
  @('dbserver1.mydomain.com', 'dbserver2.mydomain.com') | Register-ClassificationInstance

  Demonstrates how multiple SQL Server instances in a list can be registered.
.EXAMPLE
  Get-Content -Path '.\myinstances.txt' | Register-ClassificationInstance

  Demonstrates how the names of the instances to be registered can be taken from a simple text file. The file should contain one instance name per line.
#>

function Register-ClassificationInstance {
    [CmdletBinding()]
    param (
        [Alias("InstanceName", "Name")]
        [Parameter(Mandatory, Position = 0, ValueFromPipeLine)]
        [string] $FullyQualifiedInstanceName,

        [string] $UserId = $null,
        [string] $Password = $null
    )

    process {
        $AddUrl = "api/v1.0/instances"

        $PostData = @{
            InstanceFqdn   = $FullyQualifiedInstanceName
            DatabaseEngine = 'SqlServer'
            UserId         = $UserId
            Password       = $Password
        }
        $PostJson = $PostData | ConvertTo-Json

        InvokeApiCall -Uri $AddUrl -Method Post -Body $PostJson | Out-Null
    }
}

<#
.SYNOPSIS
  Updates authentication details for a single SQL Server instance.
.DESCRIPTION
  Updates authentication details for a single SQL Server instance, i.e. userId and password for SQL Server authentication.
.PARAMETER FullyQualifiedInstanceName
  The fully-qualified name of the SQL Server instance to be registered. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER UserId
  Used only for SQL Server Authentication. Known also as "user name". Optional, do not provide for Windows Authentication.
.PARAMETER Password
  Used only for SQL Server Authentication. Optional, do not provide for Windows Authentication.
.EXAMPLE
  Set-ClassificationInstanceCredential -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename'

  Sets an authentication method to Windows Authentication for a registered instance of SQL Server named "myinstancename" running on the "mysqlserver.mydomain.com" machine.
.EXAMPLE
  Set-ClassificationInstanceCredential -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename' -UserId 'somebody' -Password 'myPassword'

  Sets an authentication method to SQL Server Authentication with given userId and password for a registered instance of SQL Server named "myinstancename" running on the "mysqlserver.mydomain.com" machine.
#>

function Set-ClassificationInstanceCredential {
    [CmdletBinding()]
    param (
        [Alias("InstanceName", "Name")]
        [Parameter(Mandatory, Position = 0, ValueFromPipeLine)]
        [string] $FullyQualifiedInstanceName,

        [string] $UserId = $null,
        [string] $Password = $null
    )

    process {
        $instanceId = GetInstanceIdByName $FullyQualifiedInstanceName
        $url = "api/v1.0/instances/" + $instanceId + "/update"

        $PostData = @{
            UserId   = $UserId
            Password = $Password
        }
        $PostJson = $PostData | ConvertTo-Json

        InvokeApiCall -Uri $url -Method Patch -Body $PostJson | Out-Null
    }
}


function InvokeApiCall {
    param(
        $Uri,
        $Method,
        $Body,
        $OutFile,
        [switch] $ForLocation
    )

    if ($null -eq $Script:ClassificationURL) {
        throw 'Run Connect-SqlDataCatalog before using any other cmdlet. For help run: Get-Help Connect-SqlDataCatalog'
    }

    $Uri = [uri]::new($Script:ClassificationURL, $Uri)

    try {
        if (-not $ForLocation) {
            Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Script:ClassificationHeader `
                -Body $Body -ContentType 'application/json; charset=utf-8' -OutFile $OutFile
        }
        else {
            $result = Invoke-WebRequest -Uri $Uri -Method $Method -Headers $Script:ClassificationHeader `
                -Body $Body -ContentType 'application/json; charset=utf-8' -UseBasicParsing

            if ($result.StatusDescription -eq "Accepted") {
                $result.Headers.Location
            }
        }
    }
    catch {
        $ErrorObject = $_.Exception
        $Response = $_.Exception.Response
        if ($Response) {
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd();
            if ($Response.StatusDescription -eq 'Unauthorized') {
                throw 'SQL Data Catalog server is not able to authorize you. Check if the Auth Token provided is valid.'
            }
            Write-Error "$($ErrorObject.Message) $responseBody"
        }
        elseif ($ErrorObject) {
            Write-Error $ErrorObject
        }
        else {
            Write-Error $_
        }
    }
}


<#
.SYNOPSIS
  Gets taxonomy.
.DESCRIPTION
  Gets taxonomy: tag categories with tags, as well as free-text attributes.
.EXAMPLE
  Get-ClassificationTaxonomy

  Gets all tag categories and their tags, as well as free-text attributes.
#>
function Get-ClassificationTaxonomy {
    $url = "api/v1.0/taxonomy/tag-categories"
    $tagCategories = InvokeApiCall -Uri $url -Method Get

    $url = "api/v1.0/taxonomy/free-text-attributes"
    $freeTextAttributes = InvokeApiCall -Uri $url -Method Get

    $taxonomy = [pscustomobject]@{
        TagCategories      = $tagCategories;
        FreeTextAttributes = $freeTextAttributes
    }

    return $taxonomy
}

<#
.SYNOPSIS
  Gets all registered SQL Server instances.
.DESCRIPTION
  Gets all registered SQL Server instances.
.EXAMPLE
  Get-ClassificationInstance

  Gets all registered SQL Server instances.
#>
function Get-ClassificationInstance {
    $url = "api/v1.0/instances"
    $instances = InvokeApiCall -Uri $url -Method Get

    foreach ($instance in $instances) {
        [pscustomobject]@{
            InstanceId = $instance.instance.id;
            Name       = $instance.instance.name
        }
    }
}

function GetInstanceIdByName {
    param(
        $instanceName
    )

    $instances = @( Get-ClassificationInstance | Where-Object { $_.Name -eq $instanceName })

    if ($instances.Length -eq 0) {
        Write-Error "Instance '$instanceName' not found."
        return
    }

    return $instances[0].InstanceId
}

<#
.SYNOPSIS
  Gets the databases for a given instance.
.DESCRIPTION
  Gets all databases for a given instance.

.PARAMETER InstanceName
  The fully-qualified name of the SQL Server instance. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.EXAMPLE
  Get-ClassificationDatabase -instanceName "sqlserver\sql2016"

  Fetches all databases from instance "sqlserver\sql2016".
#>
function Get-ClassificationDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeLine)]
        [string] $InstanceName
    )
    $instanceId = GetInstanceIdByName $InstanceName

    $url =
    "api/v1.0/instances/" + $instanceId +
    "/databases"
    $databaseResult = InvokeApiCall -Uri $url -Method Get
    return $databaseResult.database
}

<#
.SYNOPSIS
  Gets all columns for a given database.
.DESCRIPTION
  Gets all columns for a given database.

  Available column properties:
  - ColumnName
  - TableName
  - SchemaName
  - Description
  - InformationType
  - SensitivityLabel
  - Tags
  - FreeTextAttributes
  - TableRowCount
  - DataType

.PARAMETER InstanceName
  The fully-qualified name of the SQL Server instance. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER DatabaseName
  Database name to fetch columns from.
.EXAMPLE
  Get-ClassificationColumn -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters"

  Fetches all columns from instance "sqlserver\sql2016" database "WideWorldImporters".
#>
function Get-ClassificationColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string] $InstanceName,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [string] $DatabaseName
    )
    $instanceId = GetInstanceIdByName $InstanceName

    $url =
    "api/v1.0/instances/" + $instanceId +
    "/databases/" + [uri]::EscapeDataString($databaseName) +
    "/columns"
    $columnResult = InvokeApiCall -Uri $url -Method Get

    foreach ($classifiedColumn in $columnResult.ClassifiedColumns) {
        $classifiedColumn | Add-Member NoteProperty 'InstanceId' $instanceId
        $classifiedColumn | Add-Member NoteProperty 'InstanceName' $InstanceName
        $classifiedColumn | Add-Member NoteProperty 'DatabaseName' $DatabaseName
    }
    return $columnResult.ClassifiedColumns
}

function GetColumnTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)] [object] $column
    )

    $url = "api/v1.0/columns/" + [uri]::EscapeDataString($column.id) + "/tags"

    return InvokeApiCall -Uri $url -Method GET
}

<#
.SYNOPSIS
  Add tags to a column for a given category.
.DESCRIPTION
  Update column with the tags specified. Only one tag category will be updated.

  - For a single-tag category, it will throw an error if the column has been assigned with a different tag.
  - For a multi-tag category, tags provided will be added to already assigned tags.
.PARAMETER Column
  Column to update tags.
.PARAMETER Category
  Name of tag category e.g. "Sensitivity".
.PARAMETER Tags
  Names of tags e.g. @("Confidential - GDPR")
  Can be used with multi tags e.g. @("GDPR", "HIPPA")
.EXAMPLE
  $allColumns = Get-ClassificationColumn -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters"
  $emailColumns  = $allColumns | Where-Object {$_.ColumnName -like "email"}
  $emailColumns | Add-ClassificationColumnTag -category "Sensitivity" -tags @("Confidential - GDPR")
  $emailColumns | Add-ClassificationColumnTag -category "Information Type" -tags @("Contact Info")

  Updates all columns with name like email to "Sensitivity": "Confidential - GDPR" and "Information Type": "Contact Info".
#>
function Add-ClassificationColumnTag {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)] [object] $Column,
        [Parameter(Mandatory)] [string] $Category,
        [string[]] $Tags
    )
    process {
        UpdateColumnTagsInternal -column $Column -category $Category -tags $Tags
    }
}

<#
.SYNOPSIS
  Update column with the tags specified (with override).
.DESCRIPTION
  Update column with the tags specified. Only one tag category will be updated.
  It removes any existing tags in that category on that column before assigning the given tags.
.PARAMETER Column
  Column to update tags.
.PARAMETER Category
  Name of tag category e.g. "Sensitivity".
.PARAMETER Tags
  Names of tags e.g. @("Confidential - GDPR")
  Can be used with multi tags e.g. @("GDPR", "HIPPA")
.EXAMPLE
  $allColumns = Get-ClassificationColumn -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters"
  $emailColumns  = $allColumns | Where-Object {$_.ColumnName -like "email"}
  $emailColumns | Set-ClassificationColumnTag -category "Sensitivity" -tags @("Confidential - GDPR")
  $emailColumns | Set-ClassificationColumnTag -category "Information Type" -tags @("Contact Info")

  Updates all columns with name like email to "Sensitivity": "Confidential - GDPR" and "Information Type": "Contact Info".
#>
function Set-ClassificationColumnTag {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)] [object] $Column,
        [Parameter(Mandatory)] [string] $Category,
        [string[]] $Tags
    )
    process {
        UpdateColumnTagsInternal -column $Column -category $Category -tags $Tags -forceUpdate
    }
}

function UpdateColumnTagsInternal {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)] [object] $column,
        [Parameter(Mandatory)] [string] $category,
        [string[]] $tags,
        [switch] $forceUpdate
    )
    begin {
        $tagCategory = $Script:allTagCategories[$category]
        if (-not $tagCategory) {
            $errorMessage = "Cannot find a tag category '" + $category + "'. Make sure that your taxonomy contains it. If you added this tag just a moment ago, rerun Connect-SqlDataCatalog."
            Write-Error -Message $errorMessage -Category InvalidArgument
            return
        }
        $tagsForCategory = ArrayToNameBasedHashtable($tagCategory.Tags)
    }

    process {
        $columnTags = $column | GetColumnTags
        $columnTagIds = $columnTags.Tags
        $tagIds = New-Object System.Collections.ArrayList(, @( $columnTagIds | ForEach-Object { $_.id } ))

        if ($tagCategory.IsMultiValued -eq $true) {
            # clear tag category for multi tag
            if ($forceUpdate) {
                foreach ($tagIdToRemove in $tagsForCategory.Values.id) {
                    if ($tagIds -contains $tagIdToRemove) {
                        $tagIds.Remove($tagIdToRemove)
                    }
                }
            }

            foreach ($tag in $tags) {
                $tagId = $tagsForCategory[$tag].id
                if (-not $tagId) {
                    $errorMessage = "Cannot find a tag '" + $tag + "' in category '" + $tagCategory.Name + "'. Make sure that your taxonomy contains it. If you added this tag just a moment ago, rerun Connect-SqlDataCatalog."
                    Write-Error -Message $errorMessage -Category InvalidArgument
                    return
                }
                if ( -Not ($tagIds.id -contains $tagId)) {
                    $tagIds.Add($tagId) | Out-Null
                }
            }
            if ($tagIds.Count -eq 0) {
                return
            }
        }
        else {
            if ($tags.Count -gt 1) {
                $errorMessage = "Tag category '" + $tagCategory.Name + "' can accept only a single tag."
                Write-Error -Message $errorMessage -Category InvalidArgument
                return
            }

            $tagId = $tagsForCategory[$tags].id
            if (-not $tagId) {
                $errorMessage = "Cannot find a tag '" + $tags + "' in category '" + $tagCategory.Name + "'. Make sure that your taxonomy contains it. If you added this tag just a moment ago, rerun Connect-SqlDataCatalog."
                Write-Error -Message $errorMessage -Category InvalidArgument
                return
            }
            $singleValueCategory = $columnTagIds | Where-Object { $_.categoryId -eq $tagCategory.id }
            if ($singleValueCategory) {
                if ($singleValueCategory.id -eq $tagId ) {
                    return
                }
                else {
                    if ($forceUpdate) {
                        $tagIds.Remove($singleValueCategory.id)
                        $tagIds.Add($tagId) | Out-Null
                    }
                    else {
                        $errorMessage = "Error :" +
                        " database: " + $column.databaseName +
                        ", schema: " + $column.schemaName +
                        ", table: " + $column.tableName +
                        ", column: " + $column.columnName +
                        " - category '" + $tagCategory.Name + "' already assigned."
                        Write-Error -Message $errorMessage -Category InvalidArgument
                        return
                    }
                }
            }
            else {
                $tagIds.Add($tagId) | Out-Null
            }
        }

        UpdateColumnWithTagIds -column $column -tagIds $tagIds.ToArray()
    }
}

function UpdateColumnWithTagIds {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)] [object] $column,
        [string[]] $tagIds
    )
    process {
        $url = "api/v1.0/columns/" + [uri]::EscapeDataString($column.id) + "/tags"
        $body = @{
            TagIds = $tagIds
        }
        $body = $body | ConvertTo-Json;
        InvokeApiCall -Uri $url -Method PUT -Body $body | Out-Null
    }
}

<#
.SYNOPSIS
  Copy classification across databases with the same schema.
.DESCRIPTION
  Copy classification across databases with the same schema. The classification is stored in SQL Data Catalog only, no live database is modified.
.PARAMETER SourceInstanceName
  The fully-qualified name of the source SQL Server instance. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER SourceDatabaseName
  Source database name.
.PARAMETER DestinationInstanceName
  The fully-qualified name of the destination SQL Server instance. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER DestinationDatabaseName
  Destination database name.
.EXAMPLE
  Copy-Classification -sourceInstanceName "(local)\MSSQL2017" -sourceDatabaseName "sourceDB" -destinationInstanceName "(local)\MSSQL2017" -destinationDatabaseName "destinationDB"

  Duplicates classification for the source database and assigns it to the target database.
#>
function Copy-Classification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceInstanceName,
        [Parameter(Mandatory)] [string] $SourceDatabaseName,
        [Parameter(Mandatory)] [string] $DestinationInstanceName,
        [Parameter(Mandatory)] [string] $DestinationDatabaseName
    )
    $classifiedColumns = Get-ClassificationColumn -instanceName $SourceInstanceName -databaseName $SourceDatabaseName
    $targetColumns = Get-ClassificationColumn -instanceName $DestinationInstanceName -databaseName $DestinationDatabaseName
    foreach ($sourceColumn in $classifiedColumns) {
        $column = $targetColumns `
            | Where-Object {$_.schemaName -eq $sourceColumn.schemaName -and $_.tableName -eq $sourceColumn.tableName -and $_.columnName -eq $sourceColumn.columnName} `
            | Select-Object -First 1
        if ($null -eq $column) {
            continue
        }
        if ($null -eq $sourceColumn.tags.id) {
            $tagIds = New-Object System.Collections.ArrayList(, @())
        }
        else {
            $tagIds = $sourceColumn.tags.id
        }
        UpdateColumnWithTagIds -column $column -tagIds $tagIds | Out-Null

        $percentComplete = [int]($i++ * 100 / $classifiedColumns.Length)
        Write-Progress -Activity "Copying classification in progress" -Status "$percentComplete% Complete" -PercentComplete $percentComplete;
    }
}

<#
.SYNOPSIS
  Bulk update columns with tags supplied.
.DESCRIPTION
  Bulk assigns a collection of tags to a collection of columns, clearing or overwriting any existing tags.
.PARAMETER Columns
  Array of columns to bulk update.
.PARAMETER Categories
  Hashtable of categories with their tags e.g.
  $categories = @{
    "Sensitivity" = @("Confidential - GDPR")
    "Information Type" = @("Contact Info")
  }
.EXAMPLE
  $allColumns = Get-ClassificationColumn -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters"
  $peopleTableColumns = $allColumns | Where-Object {$_.SchemaName -eq "Application" -and $_.TableName -eq "People" }
  $tagCategories = @{
    "Sensitivity" =  @("Confidential - GDPR")
    "Information Type" = @("Contact Info")
  }
  Set-Classification -columns $peopleTableColumns -categories $tagCategories

  Overwrites all tag categories for given columns.
#>
function Set-Classification {
    [CmdletBinding()]
    param(
        [object[]] $Columns,
        [Parameter(Mandatory)] [hashtable] $Categories
    )

    if (-not $Columns) {
        return
    }

    $tagIds = New-Object System.Collections.ArrayList(, @( ))
    foreach ($category in $categories.Keys) {

        $tags = $Categories[$category]
        $tagCategory = $Script:allTagCategories[$category]
        if (-not $tagCategory) {
            $errorMessage = "Cannot find a tag category '" + $category + "'. Make sure that your taxonomy contains it. If you added this tag just a moment ago, rerun Connect-SqlDataCatalog."
            Write-Error -Message $errorMessage -Category InvalidArgument
            return
        }
        $tagsForCategory = ArrayToNameBasedHashtable($tagCategory.Tags)

        foreach ($tag in $tags) {
            $tagId = $tagsForCategory[$tag].id
            if (-not $tagId) {
                $errorMessage = "Cannot find a tag '" + $tag + "' in category '" + $category + "'. Make sure that your taxonomy contains it. If you added this tag just a moment ago, rerun Connect-SqlDataCatalog."
                Write-Error -Message $errorMessage -Category InvalidArgument
                return
            }
            $tagIds.Add($tagId) | Out-Null
        }

        if ($tagIds.Count -eq 0) {
            return
        }
        if ($tagCategory.IsMultiValued -eq $false -and $tags.Count -gt 1) {
            $errorMessage = "Tag category '" + $tagCategory.Name + "' can accept only a single tag."
            Write-Error -Message $errorMessage -Category InvalidArgument
            return
        }
    }
    $url = 'api/v1.0/columns/bulk-classification'

    $Columns = $Columns | Select-Object -Property "columnName", "tableName", "schemaName", "databaseName", "instanceId"

    $maxBatchSize = 20000
    Do {
        $batchSize = [Math]::Min($maxBatchSize, $Columns.Length)
        $batch = @($Columns | Select-Object -First $batchSize)

        $body = @{
            ColumnIdentifiers  = $batch
            TagIds             = $tagIds.ToArray()
            FreeTextAttributes = @{ }
        }
        $body = $body | ConvertTo-Json

        InvokeApiCall -Uri $url -Method PATCH -Body $body | Out-Null

        $Columns = $Columns | Select-Object -Skip $batchSize
    }
    While ($Columns.Length -ge $maxBatchSize)
}

<#
.SYNOPSIS
  Export classification to a file.
.DESCRIPTION
  Export classification to a file in a CSV format.
.PARAMETER InstanceName
  The fully-qualified name of the SQL Server instance. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER DatabaseName
  Optional parameter. Database name to fetch columns from. If not specified, all columns on the instance are exported.
.PARAMETER ExportFile
  Specifies the output file. Enter a path and file name. If the path is omitted, the default is the current location.
  If the file exists, it will be overwritten.
.PARAMETER Format
  Specifies the output format. Currently supported: csv, zip.
.EXAMPLE
  Export-Classification -instanceName "sqlserver\sql2016" -exportFile "sql2016.csv" -format 'csv'

  Exports file with classification for all columns from the given instance in the CSV format.
.EXAMPLE
  Export-Classification -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters" -exportFile "WideWorldImporters.zip" -format 'zip'

  Exports file with classification for all columns from the given database in the compressed CSV format.
#>
function Export-Classification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InstanceName,
        [string] $DatabaseName,
        [Parameter(Mandatory)] [string] $ExportFile,
        [Parameter(Mandatory)][ValidateSet("csv", "zip")] [string] $Format
    )
    $instanceId = GetInstanceIdByName $InstanceName
    if ($DatabaseName) {
        $url =
        "api/v1.0/instances/" + $instanceId +
        "/databases/" + [uri]::EscapeDataString($databaseName) +
        "/columns/export?format=$Format"
    }
    else {
        $url =
        "api/v1.0/instances/" + $instanceId +
        "/columns/export?format=$Format"
    }
    InvokeApiCall -Uri $url -Method Get -OutFile $ExportFile
}

function UpdateClassificationInternal {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] $cmd,
        [string] $name,
        [string] $value = $null
    )
    try {
        $cmd.Parameters["@name"].Value = $name
        if ([string]::IsNullOrEmpty($value)) {
            if ($cmd.Parameters.Contains("@value")) {
                $cmd.Parameters.RemoveAt("@value")
            }
            $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
            $cmd.CommandText = "sys.sp_dropextendedproperty"
        }
        else {
            $cmd.Parameters["@value"].Value = $value
            $cmd.CommandType = [System.Data.CommandType]::Text
            $cmd.CommandText = "IF EXISTS (SELECT 1
            FROM sys.columns c
            INNER JOIN sys.objects o ON c.object_id = o.object_id
            INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
            INNER JOIN sys.extended_properties xp ON xp.major_id = o.object_id AND xp.minor_id = c.column_id
            WHERE xp.name = @name AND c.name = @level2name AND o.name = @level1name AND s.name = @level0name)
              EXEC sp_updateextendedproperty @name = @name, @level0type = 'schema', @level0name = @level0name, @level1type = 'table',
                  @level1name = @level1name, @level2type = 'column', @level2name = @level2name, @value = @value
            ELSE
              EXEC sp_addextendedproperty @name = @name, @level0type = 'schema', @level0name = @level0name, @level1type = 'table',
                  @level1name = @level1name, @level2type = 'column', @level2name = @level2name, @value = @value"
        }
        $cmd.ExecuteNonQuery() | Out-Null
    }
    catch {
        Write-Output $_.Exception.Message
    }
}

<#
.SYNOPSIS
  Push sensitivity label and information type for columns to the live database.
.DESCRIPTION
  Push sensitivity label and information type for columns of a given database from SQL Data Catalog to the live database.
  It uses the ADD SENSITIVITY CLASSIFICATION syntax, on versions where that is supported.
  Otherwise it pushes to the database's extended properties.
.PARAMETER InstanceName
  Fully qualified domain name of the instance
.PARAMETER DatabaseName
  Name of the database
.PARAMETER UserName
  User name. Do not use this parameter for Windows Authentication
.PARAMETER Password
  Password. Do not use this parameter for Windows Authentication
.PARAMETER ForceUpdate
  Use this flag to overwrite any existing classification stored in extended properties by the classification from the SQL Data Catalog.
  Note that any unassigned classifications in Data Catalog will also remove the classifications in extended properties.
  This parameter has no effect when using the ADD SENSITIVITY CLASSIFICATION syntax.
.EXAMPLE
  Update-ClassificationInLiveDatabase -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters" -user "admin" -password "P@ssword123"

  Sets the classification in the provided database with the values stored in SQL Data Catalog, but only for columns that don't have it set.
.EXAMPLE
  Update-ClassificationInLiveDatabase -instanceName "sqlserver\sql2016" -databaseName "WideWorldImporters" -user "admin" -password "P@ssword123" -forceUpdate

  Overwrites the classification in the provided database with values stored in SQL Data Catalog.
#>
function Update-ClassificationInLiveDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $InstanceName,
        [Parameter(Mandatory)] [string] $DatabaseName,
        [string] $UserName = $null,
        [string] $Password = $null,
        [switch] $ForceUpdate
    )

    $credentials = ""
    if ([string]::IsNullOrEmpty($UserName)) {
        $credentials = "Integrated Security=True"
    }
    else {
        $credentials = "User ID=$UserName; Password=$Password"
    }

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Server=$InstanceName; Database=$DatabaseName; $credentials"
    try {
        $connection.Open()

        $cmd = New-Object System.Data.SqlClient.SqlCommand
        $cmd.Connection = $connection

        $cmd.CommandText = "SELECT SERVERPROPERTY('productVersion')"
        $version = $cmd.ExecuteScalar()
        $cmd.CommandText = "SELECT SERVERPROPERTY('edition')"
        $edition = $cmd.ExecuteScalar().ToLower()

        if (($version.StartsWith("15.")) -Or ($edition -like '*azure*')) {
            UpdateClassificationInLiveDatabaseSensitivityClassification -InstanceName $InstanceName -DatabaseName $DatabaseName -Cmd $cmd
        }
        else {
            UpdateClassificationInLiveDatabaseExtendedProperties -InstanceName $InstanceName -DatabaseName $DatabaseName -Cmd $cmd -ForceUpdate:$ForceUpdate
        }
    }
    finally {
        $connection.Close()
    }
}

$infoTypes = @{ }
$infoTypes.Add("Banking", "8A462631-4130-0A31-9A52-C6A9CA125F92")
$infoTypes.Add("Contact Info", "5C503E21-22C6-81FA-620B-F369B8EC38D1")
$infoTypes.Add("Credentials", "C64ABA7B-3A3E-95B6-535D-3BC535DA5A59")
$infoTypes.Add("Credit Card", "D22FA6E9-5EE4-3BDE-4C2B-A409604C4646")
$infoTypes.Add("Date Of Birth", "3DE7CC52-710D-4E96-7E20-4D5188D2590C")
$infoTypes.Add("Financial", "C44193E1-0E58-4B2A-9001-F7D6E7BC1373")
$infoTypes.Add("Health", "6E2C5B18-97CF-3073-27AB-F12F87493DA7")
$infoTypes.Add("Name", "57845286-7598-22F5-9659-15B24AEB125E")
$infoTypes.Add("National ID", "6F5A11A7-08B1-19C3-59E5-8C89CF4F8444")
$infoTypes.Add("Networking", "B40AD280-0F6A-6CA8-11BA-2F1A08651FCF")
$infoTypes.Add("SSN", "D936EC2C-04A4-9CF7-44C2-378A96456C61")
$infoTypes.Add("Other", "9C5B4809-0CCC-0637-6547-91A6F8BB609D")

$sensitivityLabels = @{ }
$sensitivityLabels.Add("Public", "1866CA45-1973-4C28-9D12-04D407F147AD")
$sensitivityLabels.Add("General", "684A0DB2-D514-49D8-8C0C-DF84A7B083EB")
$sensitivityLabels.Add("Confidential", "331F0B13-76B5-2F1B-A77B-DEF5A73C73C2")
$sensitivityLabels.Add("Confidential - GDPR", "989ADC05-3F3F-0588-A635-F475B994915B")
$sensitivityLabels.Add("Highly Confidential", "B82CE05B-60A9-4CF3-8A8A-D6A0BB76E903")
$sensitivityLabels.Add("Highly Confidential - GDPR", "3302AE7F-B8AC-46BC-97F8-378828781EFD")

function UpdateClassificationInLiveDatabaseExtendedProperties {
    param(
        [Parameter(Mandatory)] [string] $InstanceName,
        [Parameter(Mandatory)] [string] $DatabaseName,
        [Parameter(Mandatory)] [System.Data.SqlClient.SqlCommand] $Cmd,
        [switch] $ForceUpdate
    )
    $classifiedColumns = Get-ClassificationColumn -instanceName $InstanceName -databaseName $DatabaseName

    $cmd.CommandText = "SELECT 1 FROM sys.all_objects WHERE type = 'P' AND name = 'sp_addextendedproperty'"
    $exists = $cmd.ExecuteScalar()
    if ($null -eq $exists) {
        Write-Output "Database does not support extended properties"
        return
    }
    $null = . {
        $cmd.Parameters.AddWithValue("@level0type", 'Schema')
        $cmd.Parameters.AddWithValue("@level1type", 'Table')
        $cmd.Parameters.AddWithValue("@level2type", 'Column')
        $cmd.Parameters.AddWithValue("@value", $null)
        $cmd.Parameters.AddWithValue("@name", '')
        $cmd.Parameters.AddWithValue("@level0name", '')
        $cmd.Parameters.AddWithValue("@level1name", '')
        $cmd.Parameters.AddWithValue("@level2name", '')
    }
    foreach ($col in $classifiedColumns) {
        $cmd.Parameters["@level0name"].Value = $col.schemaName
        $cmd.Parameters["@level1name"].Value = $col.tableName
        $cmd.Parameters["@level2name"].Value = $col.columnName

        if ($ForceUpdate -eq $true) {
            UpdateClassificationInternal -cmd $cmd -name 'sys_information_type_name' -value $col.informationType
            if ([string]::IsNullOrEmpty($col.informationType)) {
                UpdateClassificationInternal -cmd $cmd -name 'sys_information_type_id'
            }
            else {
                UpdateClassificationInternal -cmd $cmd -name 'sys_information_type_id' -value $infoTypes[$col.informationType]
            }
            UpdateClassificationInternal -cmd $cmd -name 'sys_sensitivity_label_name' -value $col.sensitivityLabel
            if ([string]::IsNullOrEmpty($col.sensitivityLabel)) {
                UpdateClassificationInternal -cmd $cmd -name 'sys_sensitivity_label_id'
            }
            else {
                UpdateClassificationInternal -cmd $cmd -name 'sys_sensitivity_label_id' -value $sensitivityLabels[$col.sensitivityLabel]
            }
        }
        else {
            if (-Not [string]::IsNullOrEmpty($col.InformationType)) {
                try {
                    $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
                    $cmd.Parameters["@value"].Value = $infoTypes[$col.informationType]
                    $cmd.Parameters["@name"].Value = 'sys_information_type_id'
                    $cmd.CommandText = "sys.sp_addextendedproperty"
                    $cmd.ExecuteNonQuery()

                    $cmd.Parameters["@value"].Value = $col.informationType
                    $cmd.Parameters["@name"].Value = 'sys_information_type_name'
                    $cmd.CommandText = "sys.sp_addextendedproperty"
                    $cmd.ExecuteNonQuery()
                }
                catch {
                    Write-Output $_.Exception.Message
                }
            }

            if (-Not [string]::IsNullOrEmpty($col.SensitivityLabel)) {
                try {
                    $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
                    $cmd.Parameters["@value"].Value = $sensitivityLabels[$col.sensitivityLabel]
                    $cmd.Parameters["@name"].Value = 'sys_sensitivity_label_id'
                    $cmd.CommandText = "sys.sp_addextendedproperty"
                    $cmd.ExecuteNonQuery()

                    $cmd.Parameters["@value"].Value = $col.sensitivityLabel
                    $cmd.Parameters["@name"].Value = 'sys_sensitivity_label_name'
                    $cmd.CommandText = "sys.sp_addextendedproperty"
                    $cmd.ExecuteNonQuery()
                }
                catch {
                    Write-Output $_.Exception.Message
                }
            }
        }

        $percentComplete = [int]($i++ * 100 / $classifiedColumns.Length)
        Write-Progress -Activity "Updating classification in live database in progress" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
    }
}

function UpdateClassificationInLiveDatabaseSensitivityClassification {
    param(
        [Parameter(Mandatory)] [string] $InstanceName,
        [Parameter(Mandatory)] [string] $DatabaseName,
        [Parameter(Mandatory)] [System.Data.SqlClient.SqlCommand] $Cmd
    )
    $classifiedColumns = Get-ClassificationColumn -instanceName $InstanceName -databaseName $DatabaseName

    $cmd.CommandType = [System.Data.CommandType]::Text

    foreach ($col in $classifiedColumns) {
        $schemaName = EscapeSqlName -Name $col.schemaName
        $tableName = EscapeSqlName -Name $col.tableName
        $columnName = EscapeSqlName -Name $col.columnName

        $classificationFields = @()

        if (-Not [string]::IsNullOrEmpty($col.informationType)) {
            $informationTypeName = EscapeSqlString -String $col.informationType
            $classificationFields += , "INFORMATION_TYPE = '$informationTypeName'"
            $informationTypeId = $infoTypes[$col.informationType]
            if (-Not ($Null -eq $informationTypeId)) {
                $classificationFields += , "INFORMATION_TYPE_ID = '$informationTypeId'"
            }
        }

        if (-Not [string]::IsNullOrEmpty($col.sensitivityLabel)) {
            $labelName = EscapeSqlString -String $col.sensitivityLabel
            $classificationFields += , "LABEL = '$labelName'"
            $labelId = $sensitivityLabels[$col.sensitivityLabel]
            if (-Not ($Null -eq $labelId)) {
                $classificationFields += , "LABEL_ID = '$labelId'"
            }
        }

        if ($classificationFields.Count -eq 0) {
            $cmd.CommandText = "DROP SENSITIVITY CLASSIFICATION FROM $schemaName.$tableName.$columnName"
        }
        else {
            $cmd.CommandText = "ADD SENSITIVITY CLASSIFICATION TO $schemaName.$tableName.$columnName WITH ("
            $cmd.CommandText += $classificationFields -join ","
            $cmd.CommandText += ")"
        }

        $cmd.ExecuteNonQuery() | Out-Null

        $percentComplete = [int]($i++ * 100 / $classifiedColumns.Length)
        Write-Progress -Activity "Updating classification in live database in progress" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
    }
}

function EscapeSqlName {
    param(
        [Parameter(Mandatory)] [string] $Name
    )

    return "[" + $Name.replace(']', ']]') + "]"
}

function EscapeSqlString {
    param(
        [Parameter(Mandatory)] [string] $String
    )

    return $String.replace('''', '''''')
}

<#
.SYNOPSIS
  Enables authorization in SQL Data Catalog.
.DESCRIPTION
  Enables authorization in SQL Data Catalog based on Active Directory groups and users.
.PARAMETER FullAccessActiveDirectoryUserOrGroup
  Active Directory user or group that will be granted full access to the Data Catalog.
.EXAMPLE
  Enable-SqlDataCatalogAuthorization -fullAccessActiveDirectoryUserOrGroup "SqlDataCatalog-Admins"

  Enables authorization in SQL Data Catalog granting full access to the Active Directory "SqlDataCatalog-Admins" group.
#>
function Enable-SqlDataCatalogAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FullAccessActiveDirectoryUserOrGroup
    )

    $url = "api/v1.0/permissions"
    $body = @{
        ActiveDirectoryPrincipal = $FullAccessActiveDirectoryUserOrGroup
        Role                     = 'Admin'
    } | ConvertTo-Json
    InvokeApiCall -Uri $url -Method PUT -Body $body | Out-Null
}


<#
.SYNOPSIS
  Start scan of a registered instance.
.DESCRIPTION
  Scans the instance for new databases. Updates data stored in SQL Data Catalog based on metadata read from the live instance provided.
.PARAMETER FullyQualifiedInstanceName
  The fully-qualified name of the SQL Server instance to be registered. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.EXAMPLE
  Start-ClassificationInstanceScan -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename'

  Start a scan of a live instance "myinstancename" running on the "mysqlserver.mydomain.com" machine, which results in updating data about this instance stored in SQL Data Catalog.
#>

function Start-ClassificationInstanceScan {
    [CmdletBinding()]
    param (
        [Alias("InstanceName", "Name")]
        [Parameter(Mandatory, Position = 0, ValueFromPipeLine)]
        [string] $FullyQualifiedInstanceName
    )

    process {
        $instanceId = GetInstanceIdByName $FullyQualifiedInstanceName
        $url = "api/v1.0/instances/" + $instanceId + "/scan"

        $result = InvokeApiCall -Uri $url -Method Post -ForLocation
        return $result
    }
}

<#
.SYNOPSIS
  Start scan of a registered database.
.DESCRIPTION
  Scans the database for new tables and columns. Updates data stored in SQL Data Catalog based on metadata read from the live database provided.
.PARAMETER FullyQualifiedInstanceName
  The fully-qualified name of the SQL Server instance to be registered. For a named instance, this should take the form 'fully-qualified-host-name\instance-name' (e.g. "myserver.mydomain.com\myinstance"). For the default instance on a machine, just the fully-qualified name of the machine will suffice (e.g. "myserver.mydomain.com").
.PARAMETER DatabaseName
  The fully-qualified name of the database to be registered.
.EXAMPLE
  Start-ClassificationDatabaseScan -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename' -DatabaseName 'TestDB'

  Start a scan of a database "myinstancename\TestDB" running on the "mysqlserver.mydomain.com" machine, which results in updating data about this database stored in SQL Data Catalog.
#>

function Start-ClassificationDatabaseScan {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string] $FullyQualifiedInstanceName,
        [Parameter(Mandatory, Position = 1)]
        [string] $DatabaseName
    )

    process {
        $instanceId = GetInstanceIdByName $FullyQualifiedInstanceName
        $url = "api/v1.0/instances/" + $instanceId + "/databases/" + [uri]::EscapeDataString($DatabaseName) + "/scan"

        $result = InvokeApiCall -Uri $url -Method Post -ForLocation
        return $result
    }
}

<#
.SYNOPSIS
  Wait for an operation to complete
.DESCRIPTION
  Waits until the timeout number of seconds for the provided operation status url to change status to say that the operation is finished.
.PARAMETER Url
  The Url returned when an operation was accepted by Sql Data Catalog
.PARAMETER TimeoutInSeconds
  The maximum number of seconds to wait for the operation to be marked as finished.
.EXAMPLE
  Start-ClassificationInstanceScan -FullyQualifiedInstanceName 'mysqlserver.mydomain.com\myinstancename' | Wait-SqlDataCatalogOperation

  Start a scan and wait for it to finish.
#>
function Wait-SqlDataCatalogOperation {
  [CmdletBinding()]
  [OutputType([String])]
  param (
    [Parameter(Mandatory, Position = 0, ValueFromPipeLine)]
    [string] $Url,
    $TimeoutInSeconds
  )

  process {
    $TimeEnd = (Get-Date).AddSeconds($TimeoutInSeconds)
    Do {
      Start-Sleep -Seconds 1
      $result = InvokeApiCall -Uri $Url -Method Get
      if ($result.status -eq "Succeeded" -or $result.status -eq "Failed") {
        return $result.status
      }
    }
    Until ((Get-Date) -ge $TimeEnd)

    return "Timeout"
  }
}

function ArrayToNameBasedHashtable ($items) {
    $result = @{ }
    $items | ForEach-Object { $result[$_.Name] = $_ }
    return $result
}

Export-ModuleMember -Function Connect-SqlDataCatalog
Export-ModuleMember -Function Register-ClassificationInstance
Export-ModuleMember -Function Set-ClassificationInstanceCredential
Export-ModuleMember -Function Start-ClassificationInstanceScan
Export-ModuleMember -Function Start-ClassificationDatabaseScan
Export-ModuleMember -Function Get-ClassificationInstance
Export-ModuleMember -Function Get-ClassificationDatabase
Export-ModuleMember -Function Get-ClassificationColumn
Export-ModuleMember -Function Add-ClassificationColumnTag
Export-ModuleMember -Function Set-ClassificationColumnTag
Export-ModuleMember -Function Set-Classification
Export-ModuleMember -Function Copy-Classification
Export-ModuleMember -Function Export-Classification
Export-ModuleMember -Function Update-ClassificationInLiveDatabase
Export-ModuleMember -Function Enable-SqlDataCatalogAuthorization
Export-ModuleMember -Function Get-ClassificationTaxonomy
Export-ModuleMember -Function Wait-SqlDataCatalogOperation


# SIG # Begin signature block
# MIIe2AYJKoZIhvcNAQcCoIIeyTCCHsUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB7mRf8FBH8Gtko
# pwBGFH1GRd4Hx40QGxdVO1jLlxZH/aCCGb0wggSEMIIDbKADAgECAhBCGvKUCYQZ
# H1IKS8YkJqdLMA0GCSqGSIb3DQEBBQUAMG8xCzAJBgNVBAYTAlNFMRQwEgYDVQQK
# EwtBZGRUcnVzdCBBQjEmMCQGA1UECxMdQWRkVHJ1c3QgRXh0ZXJuYWwgVFRQIE5l
# dHdvcmsxIjAgBgNVBAMTGUFkZFRydXN0IEV4dGVybmFsIENBIFJvb3QwHhcNMDUw
# NjA3MDgwOTEwWhcNMjAwNTMwMTA0ODM4WjCBlTELMAkGA1UEBhMCVVMxCzAJBgNV
# BAgTAlVUMRcwFQYDVQQHEw5TYWx0IExha2UgQ2l0eTEeMBwGA1UEChMVVGhlIFVT
# RVJUUlVTVCBOZXR3b3JrMSEwHwYDVQQLExhodHRwOi8vd3d3LnVzZXJ0cnVzdC5j
# b20xHTAbBgNVBAMTFFVUTi1VU0VSRmlyc3QtT2JqZWN0MIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAzqqBP6OjYXiqMQBVlRGeJw8fHN86m4JoMMBKYR3x
# Lw76vnn3pSPvVVGWhM3b47luPjHYCiBnx/TZv5TrRwQ+As4qol2HBAn2MJ0Yipey
# qhz8QdKhNsv7PZG659lwNfrk55DDm6Ob0zz1Epl3sbcJ4GjmHLjzlGOIamr+C3bJ
# vvQi5Ge5qxped8GFB90NbL/uBsd3akGepw/X++6UF7f8hb6kq8QcMd3XttHk8O/f
# Fo+yUpPXodSJoQcuv+EBEkIeGuHYlTTbZHko/7ouEcLl6FuSSPtHC8Js2q0yg0Hz
# peVBcP1lkG36+lHE+b2WKxkELNNtp9zwf2+DZeJqq4eGdQIDAQABo4H0MIHxMB8G
# A1UdIwQYMBaAFK29mHo0tCb3+sQmVO8DveAky1QaMB0GA1UdDgQWBBTa7WR0FJwU
# PKvdmam9WyhNizzJ2DAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAR
# BgNVHSAECjAIMAYGBFUdIAAwRAYDVR0fBD0wOzA5oDegNYYzaHR0cDovL2NybC51
# c2VydHJ1c3QuY29tL0FkZFRydXN0RXh0ZXJuYWxDQVJvb3QuY3JsMDUGCCsGAQUF
# BwEBBCkwJzAlBggrBgEFBQcwAYYZaHR0cDovL29jc3AudXNlcnRydXN0LmNvbTAN
# BgkqhkiG9w0BAQUFAAOCAQEATUIvpsGK6weAkFhGjPgZOWYqPFosbc/U2YdVjXkL
# Eoh7QI/Vx/hLjVUWY623V9w7K73TwU8eA4dLRJvj4kBFJvMmSStqhPFUetRC2vzT
# artmfsqe6um73AfHw5JOgzyBSZ+S1TIJ6kkuoRFxmjbSxU5otssOGyUWr2zeXXbY
# H3KxkyaGF9sY3q9F6d/7mK8UGO2kXvaJlEXwVQRK3f8n3QZKQPa0vPHkD5kCu/1d
# Di4owb47Xxo/lxCEvBY+2KOcYx1my1xf2j7zDwoJNSLb28A/APnmDV1n0f2gHgMr
# 2UD3vsyHZlSApqO49Rli1dImsZgm7prLRKdFWoGVFRr1UTCCBOYwggPOoAMCAQIC
# EGJcTZCM1UL7qy6lcz/xVBkwDQYJKoZIhvcNAQEFBQAwgZUxCzAJBgNVBAYTAlVT
# MQswCQYDVQQIEwJVVDEXMBUGA1UEBxMOU2FsdCBMYWtlIENpdHkxHjAcBgNVBAoT
# FVRoZSBVU0VSVFJVU1QgTmV0d29yazEhMB8GA1UECxMYaHR0cDovL3d3dy51c2Vy
# dHJ1c3QuY29tMR0wGwYDVQQDExRVVE4tVVNFUkZpcnN0LU9iamVjdDAeFw0xMTA0
# MjcwMDAwMDBaFw0yMDA1MzAxMDQ4MzhaMHoxCzAJBgNVBAYTAkdCMRswGQYDVQQI
# ExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGjAYBgNVBAoT
# EUNPTU9ETyBDQSBMaW1pdGVkMSAwHgYDVQQDExdDT01PRE8gVGltZSBTdGFtcGlu
# ZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKqC8YSpW9hxtdJd
# K+30EyAM+Zvp0Y90Xm7u6ylI2Mi+LOsKYWDMvZKNfN10uwqeaE6qdSRzJ6438xqC
# pW24yAlGTH6hg+niA2CkIRAnQJpZ4W2vPoKvIWlZbWPMzrH2Fpp5g5c6HQyvyX3R
# TtjDRqGlmKpgzlXUEhHzOwtsxoi6lS7voEZFOXys6eOt6FeXX/77wgmN/o6apT9Z
# RvzHLV2Eh/BvWCbD8EL8Vd5lvmc4Y7MRsaEl7ambvkjfTHfAqhkLtv1Kjyx5VbH+
# WVpabVWLHEP2sVVyKYlNQD++f0kBXTybXAj7yuJ1FQWTnQhi/7oN26r4tb8QMspy
# 6ggmzRkCAwEAAaOCAUowggFGMB8GA1UdIwQYMBaAFNrtZHQUnBQ8q92Zqb1bKE2L
# PMnYMB0GA1UdDgQWBBRkIoa2SonJBA/QBFiSK7NuPR4nbDAOBgNVHQ8BAf8EBAMC
# AQYwEgYDVR0TAQH/BAgwBgEB/wIBADATBgNVHSUEDDAKBggrBgEFBQcDCDARBgNV
# HSAECjAIMAYGBFUdIAAwQgYDVR0fBDswOTA3oDWgM4YxaHR0cDovL2NybC51c2Vy
# dHJ1c3QuY29tL1VUTi1VU0VSRmlyc3QtT2JqZWN0LmNybDB0BggrBgEFBQcBAQRo
# MGYwPQYIKwYBBQUHMAKGMWh0dHA6Ly9jcnQudXNlcnRydXN0LmNvbS9VVE5BZGRU
# cnVzdE9iamVjdF9DQS5jcnQwJQYIKwYBBQUHMAGGGWh0dHA6Ly9vY3NwLnVzZXJ0
# cnVzdC5jb20wDQYJKoZIhvcNAQEFBQADggEBABHJPeEF6DtlrMl0MQO32oM4xpK6
# /c3422ObfR6QpJjI2VhoNLXwCyFTnllG/WOF3/5HqnDkP14IlShfFPH9Iq5w5Lfx
# sLZWn7FnuGiDXqhg25g59txJXhOnkGdL427n6/BDx9Avff+WWqcD1ptUoCPTpcKg
# jvlP0bIGIf4hXSeMoK/ZsFLu/Mjtt5zxySY41qUy7UiXlF494D01tLDJWK/HWP9i
# dBaSZEHayqjriwO9wU6uH5EyuOEkO3vtFGgJhpYoyTvJbCjCJWn1SmGt4Cf4U6d1
# FbBRMbDxQf8+WiYeYH7i42o5msTq7j/mshM/VQMETQuQctTr+7yHkFGyOBkwggT+
# MIID5qADAgECAhArc9t0YxFMWlsySvIwV3JJMA0GCSqGSIb3DQEBBQUAMHoxCzAJ
# BgNVBAYTAkdCMRswGQYDVQQIExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcT
# B1NhbGZvcmQxGjAYBgNVBAoTEUNPTU9ETyBDQSBMaW1pdGVkMSAwHgYDVQQDExdD
# T01PRE8gVGltZSBTdGFtcGluZyBDQTAeFw0xOTA1MDIwMDAwMDBaFw0yMDA1MzAx
# MDQ4MzhaMIGDMQswCQYDVQQGEwJHQjEbMBkGA1UECAwSR3JlYXRlciBNYW5jaGVz
# dGVyMRAwDgYDVQQHDAdTYWxmb3JkMRgwFgYDVQQKDA9TZWN0aWdvIExpbWl0ZWQx
# KzApBgNVBAMMIlNlY3RpZ28gU0hBLTEgVGltZSBTdGFtcGluZyBTaWduZXIwggEi
# MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC/UjaCOtx0Nw141X8WUBlm7boa
# mdFjOJoMZrJA26eAUL9pLjYvCmc/QKFKimM1m9AZzHSqFxmRK7VVIBn7wBo6bco5
# m4LyupWhGtg0x7iJe3CIcFFmaex3/saUcnrPJYHtNIKa3wgVNzG0ba4cvxjVDc/+
# teHE+7FHcen67mOR7PHszlkEEXyuC2BT6irzvi8CD9BMXTETLx5pD4WbRZbCjRKL
# Z64fr2mrBpaBAN+RfJUc5p4ZZN92yGBEL0njj39gakU5E0Qhpbr7kfpBQO1NArRL
# f9/i4D24qvMa2EGDj38z7UEG4n2eP1OEjSja3XbGvfeOHjjNwMtgJAPeekyrAgMB
# AAGjggF0MIIBcDAfBgNVHSMEGDAWgBRkIoa2SonJBA/QBFiSK7NuPR4nbDAdBgNV
# HQ4EFgQUru7ZYLpe9SwBEv2OjbJVcjVGb/EwDgYDVR0PAQH/BAQDAgbAMAwGA1Ud
# EwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwQAYDVR0gBDkwNzA1Bgwr
# BgEEAbIxAQIBAwgwJTAjBggrBgEFBQcCARYXaHR0cHM6Ly9zZWN0aWdvLmNvbS9D
# UFMwQgYDVR0fBDswOTA3oDWgM4YxaHR0cDovL2NybC5zZWN0aWdvLmNvbS9DT01P
# RE9UaW1lU3RhbXBpbmdDQV8yLmNybDByBggrBgEFBQcBAQRmMGQwPQYIKwYBBQUH
# MAKGMWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vQ09NT0RPVGltZVN0YW1waW5nQ0Ff
# Mi5jcnQwIwYIKwYBBQUHMAGGF2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqG
# SIb3DQEBBQUAA4IBAQB6f6lK0rCkHB0NnS1cxq5a3Y9FHfCeXJD2Xqxw/tPZzeQZ
# pApDdWBqg6TDmYQgMbrW/kzPE/gQ91QJfurc0i551wdMVLe1yZ2y8PIeJBTQnMfI
# Z6oLYre08Qbk5+QhSxkymTS5GWF3CjOQZ2zAiEqS9aFDAfOuom/Jlb2WOPeD9618
# KB/zON+OIchxaFMty66q4jAXgyIpGLXhjInrbvh+OLuQT7lfBzQSa5fV5juRvgAX
# IW7ibfxSee+BJbrPE9D73SvNgbZXiU7w3fMLSjTKhf8IuZZf6xET4OHFA61XHOFd
# kga+G8g8P6Ugn2nQacHFwsk+58Vy9+obluKUr4YuMIIFYTCCBEmgAwIBAgIRAJpg
# n5ipm8KZbIfo5gsrfJ4wDQYJKoZIhvcNAQELBQAwfTELMAkGA1UEBhMCR0IxGzAZ
# BgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMHU2FsZm9yZDEaMBgG
# A1UEChMRQ09NT0RPIENBIExpbWl0ZWQxIzAhBgNVBAMTGkNPTU9ETyBSU0EgQ29k
# ZSBTaWduaW5nIENBMB4XDTE4MTIwNjAwMDAwMFoXDTIzMTIwNjIzNTk1OVowgckx
# CzAJBgNVBAYTAkdCMRAwDgYDVQQRDAdDQjQgMFdaMRcwFQYDVQQIDA5DYW1icmlk
# Z2VzaGlyZTESMBAGA1UEBwwJQ2FtYnJpZGdlMSAwHgYDVQQJDBdDYW1icmlkZ2Ug
# QnVzaW5lc3MgUGFyazEZMBcGA1UECQwQTmV3bmhhbSBIb3VzZSAxMjEeMBwGA1UE
# CgwVUmVkIEdhdGUgU29mdHdhcmUgTHRkMR4wHAYDVQQDDBVSZWQgR2F0ZSBTb2Z0
# d2FyZSBMdGQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDh/hd0pOdC
# UsKEwSwrEPb9UiPTp4oY8NduanyhpJBtSbGS3rONtmiCmuQzIH88wfdiiSAeV0uI
# lfafT8dlaFIEfVfgRjVjVqIL2maAu/pwPdPNQnLVd3skVtapxTwlh7nAuuXHVXvW
# 5b5GZVWI0d4IOoc2PqLZLMqwoWM3KQxAeEexfa04shSWl1KeSQcaD2WwOtMkPIYo
# p+1z3+gB8STF5L6M8lsVKlhxQEtTiX7WKAnVMoq5/n3ahEU0mRIFG166wGf/Z0qN
# LgEO/LYCIsSD93JJJMHrwjgeJ2wZwZMo+x1USyXkawQuydJ8tngM8zUpGFknj1oN
# NmBhj4L0MSYpAgMBAAGjggGNMIIBiTAfBgNVHSMEGDAWgBQpkWD/ik366/mmarjP
# +eZLvUnOEjAdBgNVHQ4EFgQUcMNOWd43gPAUrYobG9FOLzUEmw4wDgYDVR0PAQH/
# BAQDAgeAMAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwMwEQYJYIZI
# AYb4QgEBBAQDAgQQMEYGA1UdIAQ/MD0wOwYMKwYBBAGyMQECAQMCMCswKQYIKwYB
# BQUHAgEWHWh0dHBzOi8vc2VjdXJlLmNvbW9kby5uZXQvQ1BTMEMGA1UdHwQ8MDow
# OKA2oDSGMmh0dHA6Ly9jcmwuY29tb2RvY2EuY29tL0NPTU9ET1JTQUNvZGVTaWdu
# aW5nQ0EuY3JsMHQGCCsGAQUFBwEBBGgwZjA+BggrBgEFBQcwAoYyaHR0cDovL2Ny
# dC5jb21vZG9jYS5jb20vQ09NT0RPUlNBQ29kZVNpZ25pbmdDQS5jcnQwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmNvbW9kb2NhLmNvbTANBgkqhkiG9w0BAQsFAAOC
# AQEAo6CgU7ULOpcpJ98jihCeKIB6Sw6Pvy6DPMeiySWtAmwDlE6HyNOeQfDwrkqu
# u1VRjtpkGsrEeSbrte7+JRBShd8ZqWtXREWIUXhQM4Rizp8YQOISEQASEKAeR4Wo
# vCPNbXHAqOxjDhijke7/f/Czr9GdEAgu1SpliRY5aF9yZ0butV8jwOIKdURBHyMJ
# DlpZRe4Wk1BTfS5jo6wk8ggTbwogRg7c0d7KNoSDtEFUQzfOOWRhR8Y2Gwtdr8xN
# YHRVsYd1qOnHZAVDWddNWg7rj0Gx76MqVQyNjDI+v8qe7A/qldxFt9BbJcL/WGGc
# 4IosPJ2DBqLpEWGmF8POMXJn4jCCBeAwggPIoAMCAQICEC58h8wOk0pS/pT9HLfN
# NK8wDQYJKoZIhvcNAQEMBQAwgYUxCzAJBgNVBAYTAkdCMRswGQYDVQQIExJHcmVh
# dGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQxGjAYBgNVBAoTEUNPTU9E
# TyBDQSBMaW1pdGVkMSswKQYDVQQDEyJDT01PRE8gUlNBIENlcnRpZmljYXRpb24g
# QXV0aG9yaXR5MB4XDTEzMDUwOTAwMDAwMFoXDTI4MDUwODIzNTk1OVowfTELMAkG
# A1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4GA1UEBxMH
# U2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQxIzAhBgNVBAMTGkNP
# TU9ETyBSU0EgQ29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
# MIIBCgKCAQEAppiQY3eRNH+K0d3pZzER68we/TEds7liVz+TvFvjnx4kMhEna7xR
# kafPnp4ls1+BqBgPHR4gMA77YXuGCbPj/aJonRwsnb9y4+R1oOU1I47Jiu4aDGTH
# 2EKhe7VSA0s6sI4jS0tj4CKUN3vVeZAKFBhRLOb+wRLwHD9hYQqMotz2wzCqzSgY
# dUjBeVoIzbuMVYz31HaQOjNGUHOYXPSFSmsPgN1e1r39qS/AJfX5eNeNXxDCRFU8
# kDwxRstwrgepCuOvwQFvkBoj4l8428YIXUezg0HwLgA3FLkSqnmSUs2HD3vYYimk
# fjC9G7WMcrRI8uPoIfleTGJ5iwIGn3/VCwIDAQABo4IBUTCCAU0wHwYDVR0jBBgw
# FoAUu69+Aj36pvE8hI6t7jiY7NkyMtQwHQYDVR0OBBYEFCmRYP+KTfrr+aZquM/5
# 5ku9Sc4SMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMDMBEGA1UdIAQKMAgwBgYEVR0gADBMBgNVHR8ERTBDMEGg
# P6A9hjtodHRwOi8vY3JsLmNvbW9kb2NhLmNvbS9DT01PRE9SU0FDZXJ0aWZpY2F0
# aW9uQXV0aG9yaXR5LmNybDBxBggrBgEFBQcBAQRlMGMwOwYIKwYBBQUHMAKGL2h0
# dHA6Ly9jcnQuY29tb2RvY2EuY29tL0NPTU9ET1JTQUFkZFRydXN0Q0EuY3J0MCQG
# CCsGAQUFBzABhhhodHRwOi8vb2NzcC5jb21vZG9jYS5jb20wDQYJKoZIhvcNAQEM
# BQADggIBAAI/AjnD7vjKO4neDG1NsfFOkk+vwjgsBMzFYxGrCWOvq6LXAj/MbxnD
# PdYaCJT/JdipiKcrEBrgm7EHIhpRHDrU4ekJv+YkdK8eexYxbiPvVFEtUgLidQgF
# TPG3UeFRAMaH9mzuEER2V2rx31hrIapJ1Hw3Tr3/tnVUQBg2V2cRzU8C5P7z2vx1
# F9vst/dlCSNJH0NXg+p+IHdhyE3yu2VNqPeFRQevemknZZApQIvfezpROYyoH3B5
# rW1CIKLPDGwDjEzNcweU51qOOgS6oqF8H8tjOhWn1BUbp1JHMqn0v2RH0aofU04y
# MHPCb7d4gp1c/0a7ayIdiAv4G6o0pvyM9d1/ZYyMMVcx0DbsR6HPy4uo7xwYWMUG
# d8pLm1GvTAhKeo/io1Lijo7MJuSy2OU4wqjtxoGcNWupWGFKCpe0S0K2VZ2+medw
# bVn4bSoMfxlgXwyaiGwwrFIJkBYb/yud29AgyonqKH4yjhnfe0gzHtdl+K7J+IMU
# k3Z9ZNCOzr41ff9yMU2fnr0ebC+ojwwGUPuMJ7N2yfTm18M04oyHIYZh/r9VdOEh
# dwMKaGy75Mmp5s9ZJet87EUOeWZo6CLNuO+YhU2WETwJitB/vCgoE/tqylSNklzN
# wmWYBp7OSFvUtTeTRkF8B93P+kPvumdh/31J4LswfVyA4+YWOUunMYIEcTCCBG0C
# AQEwgZIwfTELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3Rl
# cjEQMA4GA1UEBxMHU2FsZm9yZDEaMBgGA1UEChMRQ09NT0RPIENBIExpbWl0ZWQx
# IzAhBgNVBAMTGkNPTU9ETyBSU0EgQ29kZSBTaWduaW5nIENBAhEAmmCfmKmbwpls
# h+jmCyt8njANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgACh
# AoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAM
# BgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEiBCCry4i5ifwh9Zma+RZKW3rrhbhz
# 4OgQW9T7a3LPW8+pEzANBgkqhkiG9w0BAQEFAASCAQApjUyZnkK1RT8LP+YYZ/Pc
# EVGvkzHdZVNbA8a9W/kkW4/xHw1P6ZzMSY6+wXb89ebr7tjullUrs1kBXHC5orMw
# fAFgojPwt/7GobUrHCzNgpRfomq0mf88RUpX0KyHmC91H9jnIyVroz+gVO13QBV3
# eGcMG8ITtLTnd/DEijR1mgpscYIiNZ4XzJnDAvWvKyRkhxAhQi1iusjJ0dqsQP+2
# 8KHAaAVHvGFuiNKPokiFMWzpXpPh8/GJnNL1FkBp5JnDb9WN2S4MNm0+918Ic6UG
# WaztkNknLeOEPpKwszAL5eYHI/U+glZPKQoZegrRf3Ev5eODvPoONu1ZsNuCYgzC
# oYICKDCCAiQGCSqGSIb3DQEJBjGCAhUwggIRAgEBMIGOMHoxCzAJBgNVBAYTAkdC
# MRswGQYDVQQIExJHcmVhdGVyIE1hbmNoZXN0ZXIxEDAOBgNVBAcTB1NhbGZvcmQx
# GjAYBgNVBAoTEUNPTU9ETyBDQSBMaW1pdGVkMSAwHgYDVQQDExdDT01PRE8gVGlt
# ZSBTdGFtcGluZyBDQQIQK3PbdGMRTFpbMkryMFdySTAJBgUrDgMCGgUAoF0wGAYJ
# KoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMjAwNDEwMDIw
# NDAwWjAjBgkqhkiG9w0BCQQxFgQUEL5i7ZhQSpV5zZkHKdwl2HTHb8MwDQYJKoZI
# hvcNAQEBBQAEggEAWvXWVSBWdbLLTtWKD528JTVnoMNaADNkwY13vjT8opI61hOK
# p2cVRfauC7BBjry5mnWWIWV5mYSy2a+31Wk8JLzA4t+iO4QAwgn9PmLZBzJERmeK
# fWCAMctomnMjjJ9ilYXsK3DnrwJUhek0JI8Wd4sSjhVut9ELdjqeE2MBQ+a3HoB5
# HuZSy4Uop6uresVTS5oT1gjMwChPOGkmgHMn5WRED1GDdBg03BWijeqYDeC21QUI
# 0KYEMg5lHRcJnrLRfDS6YhiuTeJUW95pW/pcf7hCuJhUhkMUL7oX6MOoAZ/OL4qH
# IOLg8LMDspheFFAD4iQx77zV+j6X16w1KOvVrQ==
# SIG # End signature block
