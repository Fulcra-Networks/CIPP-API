using namespace System.Net

Function Invoke-ExecAssetManagement {
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    if ($Request.Query.TenantFilter -eq 'AllTenants') {
        write-host "$('~'*60)>"
        $body = 'All tenants not supported.'
    }
    elseif([String]::IsNullOrEmpty($TenantFilter)){
        $body = 'Empty tenant filter not supported.'
    }
    else {
        $TblTenant = Get-CIPPTable -TableName Tenants
        $Tenants = Get-CIPPAzDataTableEntity @TblTenant -Filter "PartitionKey eq 'Tenants'"

        $tenantId = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter } | Select-Object -ExpandProperty RowKey


        $Table = Get-CIPPTable -TableName PSAAssetManagement
        $rowData = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$tenantId'"

        $body = ($rowData.assetData|ConvertFrom-Json -Depth 10)
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
}
