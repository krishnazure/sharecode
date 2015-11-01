Switch-AzureMode -Name AzureServiceManagement

#################################################
# Modify the variables below
#################################################
$vmname = "BNG-MultiNIC"
$RootPassword = "!!Force2015!!"
$instanceSize = "Large"
$cloudService = "BNG-CS"
$Location = "East US"
$storageAccount ="barracudavm1343"
#Leave empty is no reserved IP is used 
$reservedIPname = ""
#Please create the VNET ,Subnet and update the values of the variable approprirately. 
$VNetName = "AzureVNET"
$Subnet1 = "Frontend"
$Subnet2 = "Backend" 
#Get the IP Address from the FrontEND and BackEND 
$NIC1IP = "10.0.0.5"
$NIC2IP = "10.0.0.21"
#Enter a VM Image name below to use a custom image. If left empty the latest image from the Azure Marketplace is used. 
$image = ""
$availabilitySetName ="BarracudaNGAVSet1" 
#Get your correct Azure Subscription Name - Get-AzureSubscription and look for SubscriptionName , to get the subscription Id.
$azureSubscriptionName = "Internal Consumption"
$Location = "East US"
[guid]::NewGuid()
$StorageAccountName = "bafw2015"
$ContainerName = $StorageAccountName + "con"
$disksize = 10
$disklabel="storedatadiskv343"
$nsgname="blacklabel"
$lun=1
[string]$hcaching = 'None'


function AskYesNo( $title, $question, $YesInfo, $NoInfo ) {
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", $YesInfo
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", $NoInfo
    
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $result = $host.ui.PromptForChoice($title, $question, $options, 0)
    return $result
}

Write-Host -NoNewLine "This script will create a "
Write-Host -NoNewLine -ForegroundColor yellow "dual-NIC Barracuda NG Firewall"
Write-Host " instance in Azure"
Write-Host ""
Write-Host -NoNewLine "Vnet name: "
Write-Host -ForegroundColor yellow $VNetName
Write-Host -NoNewLine "NIC 1: "
Write-Host -NoNewLine -ForegroundColor yellow "$NIC1IP in $Subnet1"
Write-Host " (management)"
Write-Host -NoNewLine "NIC 2: "
Write-Host -ForegroundColor yellow "$NIC2IP in $Subnet2"
Write-Host -NoNewLine "Azure DC: "
Write-Host -ForegroundColor yellow $Location

if ($reservedIPName -ne "")
{
    Write-Host "Using the Existing Reserved IP address: $reservedIPName" 
}

$yesorno = AskYesNo 'Do you want to continue?' $warn 'aborting script' 'using existing VNET' 
   
    switch ( $yesorno ) {
        0 { "OK! Creating a new Barracuda NG Firewall VM." }
        1 { 
            "Got it :( Please correct variable values in script and rerun."
            return
        }
    } 

# Create storage if it doesn't exist yet
if(!(Test-AzureName -Storage $storageAccount))
{
    Write-Host "Creating Storage Account $storageAccount in $Location"
    New-AzureStorageAccount -StorageAccountName $storageAccount -Location $Location
}

if ($reservedIPName -ne "") 
{
$reservedIP = Get-AzureReservedIP -ReservedIPName $reservedIPName
Write-Host "Using Existing Reserved IP!"
}

# Set storage account as default storage 
Set-AzureSubscription -SubscriptionName $azureSubscriptionName -CurrentStorageAccountName $storageAccount 

# If no explicit image is defined get the latest Barracuda NG Firewall Azure Image available in the Azure Marketplace
if ( $image -eq "")
{
    $image = Get-AzureVMImage | where { $_.ImageFamily -Match "Barracuda NG Firewall*"} | sort PublishedDate -Descending | select -ExpandProperty ImageName -First 1
    Write-Host "Using Image from Azure Marketplace..."
} 

# Create Azure VM 
$vm1 = New-AzureVMConfig -Name $vmname -InstanceSize $instanceSize -Image $image –AvailabilitySetName $availabilitySetName
Add-AzureProvisioningConfig -Linux -LinuxUser "azureuser" -Password $RootPassword -VM $vm1 -NoSSHEndpoint

# Add Endpoints for 1st NIC of the Barracuda NG Firewall 
Add-AzureEndpoint -Protocol tcp -LocalPort 22 -PublicPort 22 -Name "SSH" -VM $vm1
Add-AzureEndpoint -Protocol tcp -LocalPort 807 -PublicPort 807 -Name "MGMT" -VM $vm1
Add-AzureEndpoint -Protocol tcp -LocalPort 691 -PublicPort 691 -Name "TINATCP" -VM $vm1
Add-AzureEndpoint -Protocol udp -LocalPort 691 -PublicPort 691 -Name "TINAUDP" -VM $vm1
Write-Host "Added Endpoints..."

# Define Subnet and static IP Address for 1st NIC
Set-AzureSubnet -SubnetName $Subnet1 -VM $vm1 
Set-AzureStaticVNetIP -IPAddress $NIC1IP -VM $vm1 
Write-Host "Configured First NIC..."

# Add Additional NICS 
Add-AzureNetworkInterfaceConfig -Name "NIC2" -SubnetName $Subnet2 -StaticVNetIPAddress $NIC2IP -VM $vm1 
Write-Host "Added Second NIC..."

# Create Barracuda NG Firewall VM 
if ($reservedIPName -eq "") 
{
    New-AzureVM -ServiceName $cloudService -VM $vm1 -Location $Location -VNetName $VNetName 
    Write-Host "Creating VM without Reserved IP Address..."
}
else 
{
    New-AzureVM -ServiceName $cloudService -VM $vm1 -ReservedIPName $reservedIPName -Location $Location -VNetName $VNetName 
    Write-Host "Creating VM with Reserved IP Address $reservedIPName... "
}

Write-Host "Script is done. Creating the Virtual Machine.. Use Barracuda NG Admin to login to $cloudService.cloudapp.net: user: root, password: $RootPassword)"
Write-Host "Download Host from http://d.barracuda.com/ngfirewall/6.1.0/ngadmin_6-1-0-150.exe" 

Write-Host "Creating SQL Server to be past of thos Network"
$Location = "East US"
$family="SQL Server 2014 RTM DataWarehousing on Windows Server 2012 R2"
$image=Get-AzureVMImage | where { $_.ImageFamily -eq $family } | sort PublishedDate -Descending | select -ExpandProperty ImageName -First 1
#Makesure you change the -adminusername and password
$vm1 = New-AzureVMConfig -Name “SQLServer2014DW”  -ImageName $image  –InstanceSize “Small” | add-azureprovisioningconfig -windows -adminusername “xxx” -password “xxxx” |Set-AzureSubnet –SubnetNames “Backend“|New-AzureVM –ServiceName “SHIservice” –VNetname “AzureVNET” -Location $Location