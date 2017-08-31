#Log Everything
Start-Transcript
#Log in the Azure account
Login-AzureRmAccount
$vNetSubNetName=""
#User may have several subscriptions, so select one to use for this script
Get-AzureRMSubscription | Sort Name | Select Name |FT
$subscr=Read-Host "Enter selected subscription name from list above"
$subscription = Get-AzureRmSubscription -SubscriptionName $subscr

while (!$subscription) {
    Get-AzureRMSubscription | Sort Name | Select Name |FT
    Write-Host "Invalid subscription name chosen, please enter subscription name from list above" -ForegroundColor red -BackgroundColor Black
    $subscr = Read-Host 
    $subscription = Get-AzureRmSubscription -SubscriptionName $subscr
}

Get-AzureRMSubscription -SubscriptionName $subscr | Select-AzureRmSubscription
Write-Host "Setting Azure subscription to: " $subscr -ForegroundColor green -BackgroundColor black

#VMs should be part of a resource group, either an existing one or a new one
Get-AzureRMResourceGroup | Sort ResourceGroupName | Select ResourceGroupName |FT
$rgName=Read-Host "Enter existing or new resource group name"

$rg = Get-AzureRmResourceGroup -Name $rgName

if (!$rg) {
    Write-Host "New Resource Group Name, additional settings required" -ForegroundColor magenta -BackgroundColor Black
    
    #Resource groups need to be part of a location
    Get-AzureRmLocation | Sort Location | Select Location |FT
    $locName=Read-Host "Enter location name such as WestUS"

    $loc = Get-AzureRmLocation | where Location -eq $locName
    while (!$loc) {
        Get-AzureRmLocation | Sort Location | Select Location |FT
        $locName=Read-Host "Invalid location name entered, pleae enter location name such as WestUS"
        $loc = Get-AzureRmLocation | where Location -eq $locName
    }


    #Create the resource group
    $rg = New-AzureRMResourceGroup -Name $rgName -Location $locName
} else {
    $loc = $rg | Select Location
    $locName = $loc.Location
}
Write-Host "Resource Group configuration completed. Using Resource Group" $rgName "in" $locName -ForegroundColor green -BackgroundColor Black

#VMs need a storage account to store the virtual disk, either an existing one or a new one 
Get-AzureRMStorageAccount | Sort StorageAccountName |Select StorageAccountName | FT
$saName=Read-Host "Enter existing or new Storage Account Name"
$sa = Get-AzureRMStorageAccount | where StorageAccountName -eq $saName
if (!$sa)
{
    Write-Host "1. Standard_LRS. Locally-redundant storage"
    Write-Host "2. Standard_ZRS. Zone-redundant storage"
    Write-Host "3. Standard_GRS, Geo-redundant storage"
    Write-Host "4. Standard_RAGRS, Read access geo-redundant storage"
    Write-Host "5. Premium_LRS, Premium locally-redundant storage"
    $storageAccountSkuSelection = Read-Host "Enter number of storage SKU to use, default is [1] Standard_LRS"
    switch ($storageAccountSkuSelection) {
        1 { $storageAccSku = "Standard_LRS" }
        2 { $storageAccSku = "Standard_ZRS" }
        3 { $storageAccSku = "Standard_GRS" }
        4 { $storageAccSku = "Standard_RAGRS" }
        5 { $storageAccSku = "Premium_LRS" }
        Default { $storageAccSku = "Standard_LRS"}
    }

    Write-Host "New Storage Account, Creating" $saName "..." -ForegroundColor green -BackgroundColor Black
    $storageAccS = "Standard_LRS"
    New-AzureRMStorageAccount -Name $saName -ResourceGroupName $rgName -Type $storageAccSku -Location $locName
} else {
    Write-Host "Existing storage account selected" $saName -ForegroundColor green -BackgroundColor Black
}

Get-AzureRmVirtualNetwork | Select Name, ResourceGroupName, Location | Format-Table
$vnetName = Read-Host "Enter Virtual Network existing name, or new name to create a new Virtual Network"

$vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $rgName -Name $vnetName

if (!$vNet) {
    Write-Host "New virtual network name entered, configuration will begin..." -ForegroundColor magenta -BackgroundColor Black
    
    $vNetAddressPrefix = Read-Host "Enter address prefix for virtual network, press [Enter] to use default of 10.0.0.0/16"
    if (!$vNetAddressPrefix)
    {
        $vNetAddressPrefix = "10.0.0.0/16"
    }

    $dnsIP = Read-Host "Enter private IP of DNS Server, or press [Enter] to use default of 10.0.0.4"
    if (!$dnsIP)
    {
        $dnsIP = "10.0.0.4"
    }
    New-AzureRMVirtualNetwork -Name $vNetName -ResourceGroupName $rgName -Location $locName -AddressPrefix $vNetAddressPrefix -DnsServer $dnsIP

} else {
    #Fix this later, not sure yet if more than one address prefix can be on a Vnet
    #Write-Host "Address Prefixes available"
    #$vNet.AddressSpace.AddressPrefixes
    #$vNetAddressPrefix = ReadHost "Enter address prefix to use"

    $vNetAddressPrefix = $vNet.AddressSpace.AddressPrefixes[0]
    $dnsIP = $vNet.DhcpOptions.DnsServers[0]
}
$vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $rgName -Name $vnetName
Write-Host "Using Virtual Network" $vnet.Name "with address prefix" $vNet.AddressSpace.AddressPrefixes " and DNS Server" $vNet.DhcpOptions.DnsServers -ForegroundColor green -BackgroundColor Black

#Setup the subnet environment

while (!$vNetSubNetName) {
    Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vNet | Select Name, AddressPrefix |Format-Table
    $vNetSubNetName = Read-Host "Enter name of existing subnet or new subnet name"
    $vNetSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $vNetSubNetName -VirtualNetwork $vNet
    while (!$vNetSubnet) 
    {
        Write-Host "New subnet name, additional settings required" -ForegroundColor magenta -BackgroundColor Black
        $vNetSubNetAddressPrefix = Read-Host "Enter address prefix for subnet, press [Enter] to use default of 10.0.0.0/24"
        if (!$vNetSubNetAddressPrefix)
            {
                $vNetSubNetAddressPrefix = "10.0.0.0/24"
            }
        Add-AzureRMVirtualNetworkSubnetConfig -Name $vNetSubNetName -AddressPrefix $vNetSubNetAddressPrefix -VirtualNetwork $vNet
        Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
        $vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $rgName -Name $vnetName
        $vNetSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $vNetSubNetName -VirtualNetwork $vNet
        Write-Host "Created subnet" $vNetSubnet.Name "with address prefix" $vNetSubnet.AddressPrefix -ForegroundColor green -BackgroundColor Black
        

        #Setup security group and initial rules for the virtual network to allow RDP traffic to all VMs in the subnet   
        $nsgName = Read-Host "Enter subnet Network Security Group name"
        $rules = @()
        $rulePriority=100
        $webIP = Read-Host "Enter destination address prefix of server to allow traffic, e.g. 10.0.0.6/32, enter * for all IPs, or enter blank value and press [Enter] when complete"
        while ($webIP)
        {
            $webRuleName = Read-Host "Enter name for this rule (no spaces)"
            $webRuleDescription = Read-Host "Enter description of this rule"
            $webPort = Read-Host "Enter port to allow traffic on e.g. 80 for web traffic, 3389 for RDP, 1433 for SQL"
    
            $webAccessType = Read-Host "Enter Access type: Allow or Deny (default Allow)"
            if (!$webAccessType) {
                $webAccessType = "Allow"
            }

            $webProtocol = Read-Host "Enter protocol, (default Tcp)"
            if (!$webProtocol)
            {
                $webProtocol = "Tcp"
            }

            $webDirection = Read-Host "Enter traffic direction, (default Inbound)"
            if (!$webDirection) {
                $webDirection = "Inbound"
            }

            $sourceAddressPrefix = Read-Host "Enter source address prefix, (default Internet)"
            if (!$sourceAddressPrefix)
            {
                $sourceAddressPrefix = "Internet"
            }

            $sourcePortRange = Read-Host "Enter source port range, default *"
            if (!$sourcePortRange) {
                $sourcePortRange="*"
            }
    
            $webRule = New-AzureRMNetworkSecurityRuleConfig -Name $webRuleName -Description $webRuleDescription -Access $webAccessType -Protocol $webProtocol -Direction $webDirection -Priority $rulePriority -SourceAddressPrefix $sourceAddressPrefix -SourcePortRange $sourcePortRange -DestinationAddressPrefix $webIP -DestinationPortRange $webPort
    
            $rules = $rules + $webRule
            Write-Host ".............." -ForegroundColor green -BackgroundColor Black
            Write-Host "Rule Added" -ForegroundColor green -BackgroundColor Black
            Write-Host ".............." -ForegroundColor green -BackgroundColor Black
            $rulePriority = $rulePriority+1
            $webIP = Read-Host "Enter destination address prefix of server to allow traffic, e.g. 10.0.0.6/32, enter * for all IPs, or enter blank value and press [Enter] when complete"
        }
        $nsg = New-AzureRMNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $locName -SecurityRules $rules
        #Add the security group to the subnet
        Set-AzureRMVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $vNetSubNetName -AddressPrefix $vNetSubNetAddressPrefix -NetworkSecurityGroup $nsg
        $vnetSubnetName = ""    
    }
}

Write-Host "Using subnet" $vNetSubnet.Name "with address prefix" $vNetSubnet.AddressPrefix -ForegroundColor green -BackgroundColor Black

Write-Host "Begin configuration of environment VMs" -ForegroundColor magenta -BackgroundColor Black

        #Set private IP address for this VM
        while (!$privateIPAddress){
            $privateIPAddress = Read-Host("Enter Private IP address, e.g. 10.0.0.4")
        
        }
        while (!$vmName) {
            $vmName = Read-Host "Enter VM Name (no spaces, 8 characters or less)"
        }

        #Select VM Sizing
        while (!$vmSize) {
            $vmSizeMaxCores = Read-Host "Enter maximum number of cores for VM, e.g. 4"
            $vmSizeMaxRam = Read-Host "Enter maximum RAM for VM in MB, e.g. 4096" 
            $vmSizeMaxDataDiskCount = Read-Host "Enter maximum data disks to be attached, e.g. 2"
            Get-AzureRmVMSize -Location $locName | Where NumberOfCores -le $vmSizeMaxCores | Where MemoryInMB -le $vmSizeMaxRam| Where MaxDataDiskCount -le $vmSizeMaxDataDiskCount | Select Name, NumberOfCores, MemoryInMB, MaxDataDiskCount | Format-Table
            $vmSize = Read-Host "Enter Name of VM Size for VM" $privateIPAddress "or press [Enter] to search sizes again"
        }
        
        # Create an availability set for domain controller virtual machines
        $avSetName = Read-Host "Enter availability set name, or press [Enter] for none"
        if ($avSetName) {
            $avSet = New-AzureRMAvailabilitySet -Name $avSetName -ResourceGroupName $rgName -Location $locName
        }
        $nicName=$vmName+"-NIC"
        $pipName=$vmName+"-PublicIP"

        while (!$nicName) {
            $nicName = Read-Host "Enter NIC name, e.g. 'adVM-NIC'"
        }
        $allocationMethod = Read-Host "Enter allocation method, press [Enter] for default value 'Dynamic'"
        if (!$allocationMethod)
        {
            $allocationMethod = "Dynamic"
        }
        
        $dnsName = Read-Host "Enter Unique, public domain name label for this server or press [Enter] for none"

        if (!$dnsName) {
            $pip = New-AzureRmPublicIpAddress -Name $pipName -ResourceGroupName $rgName -Location $locName -AllocationMethod $allocationMethod
        } else {
            $pip = New-AzureRmPublicIpAddress -Name $pipName -DomainNameLabel $dnsName -ResourceGroupName $rgName -Location $locName -AllocationMethod $allocationMethod
        }
        
        $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $locName -SubnetId $vNetSubnet.Id -PublicIpAddressId $pip.Id -PrivateIpAddress $privateIPAddress
        if (!$avSet) {
            $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
        } else {
            $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $avSet.Id
        }

        $storageAcc=Get-AzureRMStorageAccount -ResourceGroupName $rgName -Name $saName
        $numOfDisks = Read-Host ("How many additional disks should be added? (Default 1)")
        if (!$numOfDisks)
        {
            $numOfDisks = 1
        }
        
        for ($i=0; $i -lt $numOfDisks; $i++){
            $vmDiskLabel=Read-Host "Enter disk label (no spaces) e.g. ADDS-Data, SQLData, SPLog etc"
            $vmDiskSize=Read-Host "Enter disk size in GB, e.g. 20"
            $vhdURI = $storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/" + $vmName +"-"+$vnetName+"-"+$vmDiskLabel + ".vhd"
            #for now only allow creation of empty disks, later version might have coding for image files
            Add-AzureRmVMDataDisk -VM $vm -Name $vmDiskLabel -DiskSizeInGB $vmDiskSize -VhdUri $vhdURI -CreateOption Empty
            $vmDiskLabel=""
            $vmDiskSize=""
            $vhdURI = ""
        }

        $cred=Get-Credential -Message "Type the name and password of the local administrator account for the VM"
        #Will only do Windows machines, later version may include option for Linux configuration
        $vm=Set-AzureRMVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        
        $publishers = @()
        $offers = @()
        $skus = @()
        $publisherSearchName = Read-Host ("Enter part or full name of publisher for server to be searched for or press [Enter] to search for Microsoft")
        if (!$publisherSearchName){
            $publisherSearchName="Microsoft"
        }
        $searchTerm = "*"+$publisherSearchName+"*"
        Write-Host "Searching for " $searchTerm -ForegroundColor magenta -BackgroundColor Black
        $publishers = Get-AzureRmVMImagePublisher -Location $locName | Where PublisherName -Like $searchTerm | Select PublisherName
        $publishers |FT -AutoSize
        $publisherName = Read-Host "Enter publisher name from list above"
        #$publisher = Get-AzureRmVMImagePublisher -Location $locName | Where PublisherName -Like $searchTerm | Select PublisherName

        #This takes awhile so will do this once and keep the results for later
        $offers = Get-AzureRmVMImageOffer -Location $locName -PublisherName $publisherName | Select Offer, PublisherName
        $skus = $offers | foreach {Get-AzureRmVMImageSku -Location $locName -PublisherName $_.PublisherName -Offer $_.Offer} | Select PublisherName, Offer, Skus
        
        $skus |Format-Table -AutoSize
        $skuName = Read-Host "Enter SKU Name to be selected"
        $skuList = $skus | Where Skus -eq $skuName | Select PublisherName, Offer, Skus
        
            $skuList
            $offerName = Read-Host ("Enter Offer to use")
            $publisherName = Read-Host ("Enter PublisherName to use")

        $version = Read-Host "Enter version of deployment, press [Enter] to use default of 'latest'"

        if (!$version){
            $version="latest"
        }
        $vm=Set-AzureRMVMSourceImage -VM $vm -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $version
        $vm=Add-AzureRMVMNetworkInterface -VM $vm -Id $nic.Id
        $osDiskUri=$storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/"+$vmName+"_"+$vnetName+"_OSDisk.vhd"
        $vm=Set-AzureRMVMOSDisk -VM $vm -Name ($vmName+"OSDisk") -VhdUri $osDiskUri -CreateOption fromImage
        New-AzureRMVM -ResourceGroupName $rgName -Location $locName -VM $vm

Write-Host "For a SharePoint Farm configuration follow steps for individual VM configurations athttps://technet.microsoft.com/library/mt723354.aspx"



#End logging
Stop-Transcript