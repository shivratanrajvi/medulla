
# The VM created will have the following characteristics
# •	Up-to-date Debian 12 OS;
# •	8GB of RAM;
# •	2 CPUs.
#
# Software requirements:
# •	Powershell Core version 6 or higher
# •	VirtualBox version 7 or higher
# If these requirements are not met, they will be installed. 
# NB: To install Powershell Core version 6 or higher, run the following:
#       powershell.exe -File .\create_vbox_vm.ps1
#     then follow the instructions given
#
# To create a VM and install Medulla in it, the following command must be run:
#   pwsh.exe -File .\create_vbox_vm.ps1


$NB_CPU = 2
$RAM_SIZE = 8192
$HDD_SIZE = 20480

if ($IsLinux) {
    $DEBIAN_ISO_BASEURL = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/'
    $VBOXMANAGE = 'vboxmanage'
}
elseif ($IsMacOS) {
    $DEBIAN_ISO_BASEURL = 'https://cdimage.debian.org/debian-cd/current/arm64/iso-cd/'
    $VBOXMANAGE = 'vboxmanage'
}
elseif ($IsWindows) {
    $DEBIAN_ISO_BASEURL = 'https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/'
    $VBOXMANAGE = 'C:\Progra~1\Oracle\VirtualBox\VBoxManage.exe'
}

# Initialize script variables used in the script
$DEST_PATH = $null
$ISOFILE_DEST = $null

function Invoke-InPowerShellVersion {
    $currentVersion = $PSVersionTable.PSVersion

    # Check if the major version is 6 or higher
    if ($currentVersion.Major -lt 6) {
        Write-Host "You are running PowerShell Version $currentVersion"

        # Check if pwsh exists before upgrading
        try {
            Write-Host "Checking if a newer version of PowerShell is found..."
            Start-Process -FilePath "pwsh" -ArgumentList "-V" -NoNewWindow -Wait
        }
        catch {
            Write-Host "PowerShell will be tentatively upgraded..."
            Install-LatestPowerShell
            if (-not $?) {
                Show-ErrorMessage "Error upgrading PowerShell. Please upgrade PowerShell manually."
                Exit
            }
            else {
                Write-Host "Powershell updated successfully"
                Exit
            }
        }
        finally {
            Write-Host "Restart the install by running the script using pwsh instead of powershell"
            Exit
        }
    }
}

function Install-LatestPowerShell {
    try {
        Start-Process -Wait -FilePath "apt" -ArgumentList "-y install pwsh"
    }
    catch {
        try {
            Start-Process -Wait -FilePath "yum" -ArgumentList "-y install pwsh"
        }
        catch {
            # Both commands failed. We are probably not running Linux
        }
        finally {
            # Extract the download URL for the MSI installer from Github API
            $repoUrl = "https://api.github.com/repos/PowerShell/PowerShell"
            $latestRelease = Invoke-RestMethod -Uri "$repoUrl/releases/latest"
            $downloadUrl = $latestRelease.assets | Where-Object { $_.name -like "*win-x64.msi" } | Select-Object -ExpandProperty browser_download_url

            # Download the MSI installer
            Invoke-WebRequest -Uri $downloadUrl -OutFile "PowerShellInstaller.msi"

            # Install PowerShell using the downloaded installer
            Start-Process -Wait -FilePath "msiexec.exe" -ArgumentList "/i PowerShellInstaller.msi /quiet"

            # Clean up the temporary installer file
            Remove-Item -Path "PowerShellInstaller.msi" -Force
        }
    }
}

function Invoke-VboxManage {
    try {
        if (Start-Process -Wait -FilePath "$VBOXMANAGE" -ArgumentList "-V") {
            Write-Host "VirtualBox is already installed..."
        }
    }
    # If vboxmanage does not exist, try to install VirtualBox
    catch {
        Write-Host "VirtualBox will be tentatively installed..."
        Install-LatestVirtualBox
    }
}

function Install-LatestVirtualBox {
    # Get the latest release information
    $repoUrl = 'https://download.virtualbox.org/virtualbox'
    $LatestVersion = (Invoke-WebRequest -Uri "$repoUrl/LATEST.TXT").Content.Trim()

    # Get the full version including the 6-digit number
    $DownloadPageContent = (Invoke-WebRequest -Uri "https://download.virtualbox.org/virtualbox/$LatestVersion").Content
    $FullVersion = $LatestVersion + '-' + [regex]::Matches($DownloadPageContent, '[0-9]{6,}').Groups[1].Value

    # Build the download URL for the extension pack
    $downloadExtPackUrl = $repoUrl + '/' + $LatestVersion + '/Oracle_VM_VirtualBox_Extension_Pack-' + $LatestVersion + '.vbox-extpack'

    # Download the installer and extension pack
    if ($IsMacOS){
        $FileName = 'VirtualBox-' + $FullVersion + '-OSX.dmg'
        $downloadUrl = $repoUrl + '/' + $LatestVersion + '/' + $FileName
        Invoke-WebRequest -Uri $downloadUrl -OutFile "$FileName"
    }
    Invoke-WebRequest -Uri $downloadExtPackUrl -OutFile "VirtualBox_Extension_Pack.vbox-extpack"

    # Install VirtualBox
    if ($IsWindows) {
        Start-Process -Wait -FilePath "winget" -ArgumentList "install Oracle.Virtualbox --accept-source-agreements"
    }
    elseif ($IsLinux) {
    }
    elseif ($IsMacOS){
        Start-Process -Wait -FilePath "hdiutil" -ArgumentList "attach $FileName"
        Start-Process -Wait -FilePath "sudo" -ArgumentList "installer -pkg /Volumes/VirtualBox/VirtualBox.pkg -target /Volumes/Macintosh\ HD"
        Start-Process -Wait -FilePath "hdiutil" -ArgumentList "detach /Volumes/VirtualBox"
        Remove-Item -Path "$FileName" -Force
    }
    
    # Install the extension pack
    Start-Process -Wait -FilePath "$VBOXMANAGE" -ArgumentList "extpack install VirtualBox_Extension_Pack.vbox-extpack"
    Remove-Item -Path "VirtualBox_Extension_Pack.vbox-extpack" -Force
}

function Show-ErrorMessage {
    param (
        [parameter(mandatory=$true)] $MESSAGE,
        $CMD
    )
    Write-Host "### $MESSAGE. Exiting" -ForegroundColor red
    if (-not ([string]::IsNullOrEmpty($CMD))) {
        Write-Host "Failed command: $CMD" -ForegroundColor red
    }
}

function Get-SSHPubKey {
    if ((Test-Path "$HOME/.ssh/id_rsa_medulla", "$HOME/.ssh/id_rsa_medulla.pub") -contains $false) {
        $CMD = "ssh-keygen -f $HOME/.ssh/id_rsa_medulla -N '' -b 2048 -t rsa -q"
        try {
            Invoke-Expression $CMD
        }
        catch {
            Show-ErrorMessage "Error generating the SSH keys" "$CMD"
            Exit
        }
        Write-Host "# SSH key pair created"
    }
    $id_rsa_pub = Get-Content -Path $HOME/.ssh/id_rsa_medulla.pub -TotalCount 1
    return $id_rsa_pub
}

function New-TempFolder {
    if ($IsMacOS){
        $script:DEST_PATH = Join-Path $Env:TMPDIR $(New-Guid)
    }
    elseif ($IsLinux) {
        $script:DEST_PATH = Join-Path $Env:XDG_RUNTIME_DIR $(New-Guid)
    }
    elseif ($IsWindows) {
        $script:DEST_PATH = Join-Path $Env:TEMP $(New-Guid)
    }
    $CMD = 'New-Item -Type Directory -Path $DEST_PATH | Out-Null'
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "The temporary folder $DEST_PATH could not be created" "$CMD"
        Exit
    }
    Write-Host "# Temporary folder $DEST_PATH created"
}

function Get-OSIso {
    param (
        [parameter(mandatory=$true)] $URL,
        [parameter(mandatory=$true)] $DEST
    )
    # Download SHA512SUMS file
    if (-not $url.EndsWith('/')) {
        $URL = $URL + "/"
    }
    $SUMFILE_URL = $URL + "SHA512SUMS"
    $SUMFILE_DEST = Join-Path $DEST "SHA512SUMS"
    $CMD = 'Invoke-WebRequest -Uri $SUMFILE_URL -OutFile $SUMFILE_DEST'
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "The checksum file $SUMFILE_URL could not be downloaded to $SUMFILE_DEST" "$CMD"
        Exit
    }
    $HASH, $ISOFILE = Get-Content $SUMFILE_DEST | Select-Object -First 1 | ForEach-Object { $_.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries) }
    $ISOFILE_URL = $URL + $ISOFILE
    $script:ISOFILE_DEST = Join-Path $DEST $ISOFILE
    $CMD = 'Invoke-WebRequest -Uri $ISOFILE_URL -OutFile $ISOFILE_DEST'
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "The ISO file $ISOFILE_URL could not be downloaded to $ISOFILE_DEST" "$CMD"
        Exit
    }
    $DLFILE_HASH = (Get-FileHash $ISOFILE_DEST -Algorithm SHA512).Hash
    if (-not $DLFILE_HASH -ieq $HASH) {
        Show-ErrorMessage "The calculated hash $DLFILE_HASH is different from the hash $HASH in $SUMFILE_DEST"
        Exit
    }
}

function Get-RandomPassword {
    param (
        [int] $length = 4
    )
    $RandomString = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count $length | ForEach-Object {[char]$_})
    return $RandomString
}

function Edit-PreseedFile {
    param (
        [parameter(mandatory=$true)] $DEST,
        [parameter(mandatory=$true)] $UUID
    )
    if ($IsWindows) {
        $script:PreseedFile = 'C:\Progra~1\Oracle\VirtualBox\UnattendedTemplates\debian_preseed.cfg'
    }
    elseif ($IsLinux) {
        # TBD $script:PreseedFile = 'C:\Progra~1\Oracle\VirtualBox\UnattendedTemplates\debian_preseed.cfg'
    }
    elseif ($IsLinux) {
        # TBD $script:PreseedFile = 'C:\Progra~1\Oracle\VirtualBox\UnattendedTemplates\debian_preseed.cfg'
    }
    $PUBKEY = Get-SSHPubKey
    #$PreseedFile = $DEST + '/Medulla/Unattended-' + $UUID + '-preseed.cfg'
    Copy-Item "$PreseedFile" -Destination "$PreseedFile + '.bak'"
    $TEXT_ADDED = "\
    in-target mkdir -p /root/.ssh; \
    in-target /bin/sh -c `"echo '$PUBKEY' >> /root/.ssh/authorized_keys`"; \
    in-target chown -R root:root /root/.ssh/; \
    in-target chmod 600 /root/.ssh/authorized_keys; \
    in-target chmod 700 /root/.ssh/; \
    "
    (Get-Content $PreseedFile) -replace 'd-i preseed/late_command string', "d-i preseed/late_command string $TEXT_ADDED" | Set-Content $PreseedFile
}

function New-VBOXVM {
    param (
        [parameter(mandatory=$true)] $ISO_PATH,
        [parameter(mandatory=$true)] $DEST
    )
    $VM_UUID = $(New-Guid)
    if ($IsMacOS){
        $INTERFACE = 'en0: Wi-Fi'
        $TYPE = 'Debian'
    }
    elseif ($IsLinux) {
        $INTERFACE = 'eth0'
        $TYPE = 'Debian_64'
    }
    elseif ($IsWindows) {
        $INTERFACE = 'Red Hat VirtIO Ethernet Adapter'
        $TYPE = 'Debian_64'
    }
    $script:ROOT_PASSWORD = Get-RandomPassword 4
    $CMD = "$VBOXMANAGE createvm --basefolder=$DEST --name Medulla --uuid $VM_UUID --ostype $TYPE --register"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error creating the VM" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE modifyvm Medulla --cpus $NB_CPU --memory $RAM_SIZE --vram 12 --graphicscontroller VBoxSVGA"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error setting the VM resources" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE modifyvm Medulla --nic1 bridged --bridge-adapter1 '$INTERFACE'"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error creating the VM network settings" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE createmedium disk --filename $DEST/Medulla/Medulla.vdi --size $HDD_SIZE --variant Standard"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error creating the VM storage file $DEST/Medulla/Medulla.vdi" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE storagectl Medulla --name 'SATA Controller' --add sata --bootable on"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error adding the VM storage controller" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE storageattach Medulla --storagectl 'SATA Controller' --port 0 --device 0 --type hdd --medium $DEST/Medulla/Medulla.vdi"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error attaching the VM storage file $DEST/Medulla/Medulla.vdi to the SATA controller" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE storagectl Medulla --name 'IDE Controller' --add ide"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error adding the VM disk controller" "$CMD"
        Exit
    }
    $CMD = "$VBOXMANAGE storageattach Medulla --storagectl 'IDE Controller' --port 0 --device 0 --type dvddrive --medium $ISO_PATH"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error attaching the OS ISO image $ISO_PATH to the IDE controller" "$CMD"
        Exit
    }
    Edit-PreseedFile -DEST $DEST_PATH -UUID $VM_UUID
    $CMD = "$VBOXMANAGE unattended install Medulla --iso=$ISO_PATH --user=medulla --password=$ROOT_PASSWORD --country=FR --hostname=medulla.local --package-selection-adjustment=minimal --install-additions --language=en-US --start-vm=gui"
    #$CMD = "$VBOXMANAGE unattended install Medulla --iso=$ISO_PATH --user=medulla --password=$ROOT_PASSWORD --country=FR --hostname=medulla.local --package-selection-adjustment=minimal --install-additions --language=en-US --start-vm=headless"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error starting the unattended installation of the OS" "$CMD"
        Exit
    }
    Write-Host "Root password is $ROOT_PASSWORD"
}

function Test-VMUp {
    param (
        [int]$MaxAttempts = 10,
        [int]$RetryIntervalSeconds = 120
    )

    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        try {
            $CMD = "$VBOXMANAGE guestproperty get Medulla '/VirtualBox/GuestInfo/Net/0/V4/IP'"
            $VM_IP = $(Invoke-Expression $CMD).Split(':')[1].Trim()
            if ([bool]($VM_IP -as [ipaddress])) {
                Set-VMNetwork
                if ($?) {
                    Restart-VMNetwork $VM_IP
                    Write-Host "VM IP is $VM_IP"
                    break
                }
            }
        }
        catch {
            Write-Host "Connection to VM failed. Retrying in 2 minutes..."
        }

        Start-Sleep -Seconds $RetryIntervalSeconds
        $attempt++
    }

    if ($attempt -ge $MaxAttempts) {
        Write-Host "Max retry attempts reached. Connection to VM failed."
    }
}


function Set-VMNetwork {
    # Get VM details
    $CMD = "$VBOXMANAGE guestproperty get Medulla '/VirtualBox/GuestInfo/Net/0/V4/IP'"
    $VM_IP = $(Invoke-Expression $CMD).Split(':')[1].Trim()
    $CMD = "$VBOXMANAGE guestproperty get Medulla '/VirtualBox/GuestInfo/Net/0/V4/Netmask'"
    $VM_NETMASK = $(Invoke-Expression $CMD).Split(':')[1].Trim()
    $CMD = "ssh -i $HOME/.ssh/id_rsa_medulla -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@$VM_IP cat /var/lib/dhcp/dhclient*.leases"
    $LEASES_CONTENT = Invoke-Expression $CMD
    $VM_GATEWAY = $LEASES_CONTENT | Where-Object { $_ -match 'routers' } | ForEach-Object { $_.Split(" ")[4].Trim(";") }
    $VM_INTERFACE = $LEASES_CONTENT | Where-Object { $_ -match 'interface' } | ForEach-Object { $_.Split(" ")[3].Trim(";").Trim("`"") }
    $VM_DNS = $LEASES_CONTENT | Where-Object { $_ -match 'domain-name-servers' } | ForEach-Object { $_.Split(" ")[4].Trim(";") }
    # Reconfigure the network
    $CMD = "ssh -i $HOME/.ssh/id_rsa_medulla -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@$VM_IP ""sed -i `'s/iface $VM_INTERFACE inet .*`$/iface $VM_INTERFACE inet static\naddress $VM_IP\nnetmask $VM_NETMASK\ngateway $VM_GATEWAY\ndns-nameservers $VM_DNS/`' /etc/network/interfaces"""
    $CMD
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error reconfiguring the network" "$CMD"
        Exit
    }
}

function Restart-VMNetwork{
    param (
        [parameter(mandatory=$true)] $VM_IP
    )
    # Restart network
    $CMD = "ssh -f -i $HOME/.ssh/id_rsa_medulla -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@$VM_IP ""nohup systemctl restart systemd-networkd &"""
    $CMD
    try {
        Invoke-Expression $CMD
    }
    finally {
        # Wait for interface to restart
        Start-Sleep -Seconds 5
    }
}

function Install-Medulla {
    $CMD = "$VBOXMANAGE guestproperty get Medulla '/VirtualBox/GuestInfo/Net/0/V4/IP'"
    $VM_IP = $(Invoke-Expression $CMD).Split(':')[1].Trim()
    # Install wget
    $CMD = "ssh -i $HOME/.ssh/id_rsa_medulla -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@$VM_IP apt -y install wget"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error installing wget" "$CMD"
    }
    # Copy install script
    $CMD = "scp -i $HOME/.ssh/id_rsa_medulla -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null install_from_ansible.sh root@${VM_IP}:install_from_ansible.sh"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error transferring install_from_ansible.sh file" "$CMD"
    }
    # Run install script
    $CMD = "ssh -i $HOME/.ssh/id_rsa_medulla -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -t root@$VM_IP source install_from_ansible.sh"
    try {
        Invoke-Expression $CMD
    }
    catch {
        Show-ErrorMessage "Error installing Medulla" "$CMD"
    }
}

function Show-CleanUpMessage {
    # First restore preseed file
    Move-Item -Path "$PreseedFile + '.bak'" -Destination "$PreseedFile" -Force

    # Show what needs to be done for removing all the temporary files
    Write-Host "Run the following commands to delete the VM and temporary files created:"
    Write-Host "Start-Process -Wait -FilePath `"$VBOXMANAGE`" -ArgumentList `"controlvm Medulla poweroff`""
    Write-Host "Start-Process -Wait -FilePath `"$VBOXMANAGE`" -ArgumentList `"unregistervm Medulla --delete`""
    Write-Host "Remove-Item -LiteralPath `"$DEST_PATH`" -Force -Recurse"
}



Invoke-InPowerShellVersion
Invoke-VboxManage
New-TempFolder
Get-OSIso -URL $DEBIAN_ISO_BASEURL -DEST $DEST_PATH
New-VBOXVM -ISO_PATH $ISOFILE_DEST -DEST $DEST_PATH
Test-VMUp
Install-Medulla
Show-CleanUpMessage
