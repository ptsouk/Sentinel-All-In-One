# parameters
$adoArmConnectionSPNDisplayName = "ado-arm-connection"
$location = "westeurope"
$storageAccountSubscriptionId = "6568220f-c927-40c3-9ab9-e681106aec28"
$storageAccountResourceGroup = "deploy-sentinelComponents-rg"
$storageAccountName = "hxfua5r7jmc4nsq8d6vkgty3"
$storageAccountContainerName = "sentinel-all-in-one-v2"
$startTime     = Get-Date
$expiryTime    = $startTime.AddHours(3)
$permissions   = "r"
$protocol      = "HttpsOnly"

try {

    # Connect to Azure
    
    # https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-template
    $principalId = (Get-AzADServicePrincipal -DisplayName $adoArmConnectionSPNDisplayName).id
    
    Write-Output "ADO SPN: $principalId"

    # Create storage account
    Set-AzContext -SubscriptionId $storageAccountSubscriptionId 
    New-AzDeployment -Location $location -Name "deploy-sentinelComponents-storage" `
        -TemplateFile .\deploy.storage.json `
        -resourceGroupName $storageAccountResourceGroup `
        -resourceGroupLocation $location `
        -storageAccountName $storageAccountName `
        -containerName $storageAccountContainerName `
        -principalId $principalId `
        -DeploymentDebugLogLevel All `
        -Verbose
    
    # Upload components to storage account
    Set-AzContext -SubscriptionId $storageAccountSubscriptionId 
    $context = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
    Get-ChildItem -Path .\components -Recurse | ForEach-Object {
        Set-AzStorageBlobContent -Container $storageAccountContainerName -File $_.FullName -Blob "$($_.Name)" -Force -Context $context
    }

    # Generate SAS token for components container
    $context = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
    $sas = New-AzStorageContainerSASToken `
    -Context $context `
    -Name $storageAccountContainerName `
    -StartTime $startTime `
    -ExpiryTime $expiryTime `
    -Permission $permissions `
    -Protocol $protocol

    $targetSubscriptions = Import-Csv .\targetSubscriptions_lab.csv -Delimiter ";"

    foreach ($targetSubscription in $targetSubscriptions) {
        # Deploy the template
        Write-Output "Deploying to subscription $($targetSubscription.SubscriptionName)"
        Set-AzContext -SubscriptionId $targetSubscription.SubscriptionId
        New-AzDeployment -Location $location -Name "deploySentinel-$($targetSubscription.SubscriptionName)" `
            -TemplateFile .\template.json `
            -TemplateParameterFile .\parameters.json `
            -resourceGroupName "$($targetSubscription.SubscriptionName)-Sentinel-RG" `
            -workspaceName "$($targetSubscription.SubscriptionName)-Sentinel-LAW-01" `
            -componentStorageAccountName $storageAccountName `
            -componentsStorageContainerName $storageAccountContainerName `
            -sasToken $sas `
            -DeploymentDebugLogLevel All `
            -Verbose
        Write-Output "Finished Deploying to subscription $($targetSubscription.SubscriptionName)"
    }
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}