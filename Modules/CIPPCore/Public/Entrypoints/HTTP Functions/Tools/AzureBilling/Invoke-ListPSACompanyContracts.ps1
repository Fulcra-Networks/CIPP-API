using namespace System.Net

function Invoke-ListPSACompanyContracts {
    [CmdletBinding()]
    param($Request,$TriggerMetadata)

    if($Request.query.companyId){
        $contracts = Get-AutotaskCompanyContracts -CompanyId $Request.query.companyId
    }
    else {
        $contracts = @(@{id=-1;contractName='No company ID selected'})
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = @($contracts)
    })
}
