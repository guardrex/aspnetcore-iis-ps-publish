<#
#
# net5-iis-ps-publish
#
# Experimental prototype for using Powershell to publish an ASP.NET 5 project to IIS
#
# Requirements:
#
#   Powershell 5
#   http://www.microsoft.com/en-us/download/details.aspx?id=48729
#
#   Powershell Community Extensions (PSCX)
#   https://pscx.codeplex.com/
#
#   ! WARNING !
#   This script is highly EXPERIMENTAL! Do not use with any application publishing
#   in a production environment. Use at your own risk.
#
# The chunking algorithm for sending large files in a PSSession is from "Send-File"
# from the Windows PowerShell Cookbook ISBN: 1449320686 (O'Reilly) by Lee Holmes 
# (http://www.leeholmes.com/guide) http://poshcode.org/2216
#
# Make sure the Azure Cloud Services certificate is installed locally.
# See: http://techthoughts.info/remote-powershell-to-azure-vm-automating-certificate-configuration/
#>

# Provide the path to your local project output folder. This is the folder that contains the approot and wwwroot
$sourcePathToOutput = 'C:\...<path to output folder of project>...\output'

# Provide servers: The Cloud Service endpoint, the server's port at that endpoint, the admin username, 
# the IIS website name on that server, the path to the website (the folder on the server that will contain 
# the approot and wwwroot folders)
$servers = @(
    ('myeastusservice.cloudapp.net',50000,'adminuser','corporate_public','F:\corporate_public'),
    ('myeastusservice.cloudapp.net',50001,'adminuser','corporate_public','F:\corporate_public'),
    ('mywestusservice.cloudapp.net',50000,'adminuser','corporate_public','F:\corporate_public'),
    ('mywestusservice.cloudapp.net',50001,'adminuser','corporate_public','F:\corporate_public')
)

Import-Module Pscx
Cls

function CompressSendFolder {
    param (
        [Parameter(Mandatory = $true)]
        $Source,
        [Parameter(Mandatory = $true)]
        $SourcePathToOutputSubfolder,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )
    # Process folders first
    Get-ChildItem -Path $Source -Recurse | ForEach-Object -Process {
        if ($_.Attributes -eq "Directory") {
            $path = $_.FullName.SubString($SourcePathToOutputSubfolder.Length)
            Write-Host Creating folder $path
            Invoke-Command -Session $Session -ScriptBlock {
                param($path)
                New-Item $env:USERPROFILE\AppData\Local\Temp\deployment$path -type directory -Force | Out-Null
            } -ArgumentList $path
        }
    }
    # Files next
    Get-ChildItem -Path $Source -Recurse | ForEach-Object -Process {
        if ($_.Attributes -eq "Directory") {
            $path = $_.FullName.SubString($SourcePathToOutputSubfolder.Length)
            Write-Host Creating folder $path
            Invoke-Command -Session $Session -ScriptBlock {
                param($path)
                New-Item $env:USERPROFILE\AppData\Local\Temp\deployment$path -type directory -Force | Out-Null
            } -ArgumentList $path
        } else {
            $path = $_.FullName.SubString($SourcePathToOutputSubfolder.Length)
            Compress-Archive -Path $_.FullName -DestinationPath $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip -Force | Out-Null
            Write-Host Compressing, chunking, and moving file $path
            $src = $env:USERPROFILE + "\AppData\Local\Temp\deployment\compressed_temp.zip"
            $sourcePath = (Resolve-Path $src).Path
            $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
            $streamChunks = @()
            Write-Progress -Activity "Sending $src" -Status "Preparing file"
            $streamSize = 1MB
            for($position = 0; $position -lt $sourceBytes.Length; $position += $streamSize) {
                $remaining = $sourceBytes.Length - $position
                $remaining = [Math]::Min($remaining, $streamSize)
                $nextChunk = New-Object byte[] $remaining
                [Array]::Copy($sourcebytes, $position, $nextChunk, 0, $remaining)
                $streamChunks += ,$nextChunk
            }
            $remoteScript = {
                param($length)
                $dest = $env:USERPROFILE + "\AppData\Local\Temp\deployment\compressed_temp.zip"
                $Destination = $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dest)
                $destBytes = New-Object byte[] $length
                $position = 0
                foreach ($chunk in $input) {
                    Write-Progress -Activity "Writing $dest" -Status "Sending file" -PercentComplete ($position / $length * 100)
                    [GC]::Collect()
                    [Array]::Copy($chunk, 0, $destBytes, $position, $chunk.Length)
                    $position += $chunk.Length
                }
                [IO.File]::WriteAllBytes($dest, $destBytes)
                [GC]::Collect()
            }
            $streamChunks | Invoke-Command -Session $session $remoteScript -ArgumentList $sourceBytes.Length
            Invoke-Command -Session $Session -ScriptBlock {
                param($path,$baseName,$ext)
                Expand-Archive -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip -DestinationPath $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp -Force | Out-Null
                Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp\$baseName$ext -Destination $env:USERPROFILE\AppData\Local\Temp\deployment$path | Out-Null
                Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp -Force -Recurse
                Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip
            } -ArgumentList $path,$_.BaseName,$_.Extension
            Remove-Item $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip -Force
        }
    }
}

function CompressSendFile {
    param (
        [Parameter(Mandatory = $true)]
        $Source,
        [Parameter(Mandatory = $true)]
        $BaseName,
        [Parameter(Mandatory = $true)]
        $Extension,
        [Parameter(Mandatory = $true)]
        $SourcePathToOutputSubfolder,
        [Parameter(Mandatory = $true)]
        $DeploymentFolder,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )
    # File only
    $path = $Source.SubString($SourcePathToOutputSubfolder.Length)
    Compress-Archive -Path $Source -DestinationPath $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip -Force | Out-Null
    Write-Host Compressing chunking and moving file $path
    $src = $env:USERPROFILE + "\AppData\Local\Temp\deployment\compressed_temp.zip"
    $sourcePath = (Resolve-Path $src).Path
    $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
    $streamChunks = @()
    Write-Progress -Activity "Sending $src" -Status "Preparing file"
    $streamSize = 1MB
    for($position = 0; $position -lt $sourceBytes.Length; $position += $streamSize) {
        $remaining = $sourceBytes.Length - $position
        $remaining = [Math]::Min($remaining, $streamSize)
        $nextChunk = New-Object byte[] $remaining
        [Array]::Copy($sourcebytes, $position, $nextChunk, 0, $remaining)
        $streamChunks += ,$nextChunk
    }
    $remoteScript = {
        param($length)
        $dest = $env:USERPROFILE + "\AppData\Local\Temp\deployment\compressed_temp.zip"
        $Destination = $executionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dest)
        $destBytes = New-Object byte[] $length
        $position = 0
        foreach ($chunk in $input) {
            Write-Progress -Activity "Writing $dest" -Status "Sending file" -PercentComplete ($position / $length * 100)
            [GC]::Collect()
            [Array]::Copy($chunk, 0, $destBytes, $position, $chunk.Length)
            $position += $chunk.Length
        }
        [IO.File]::WriteAllBytes($dest, $destBytes)
        [GC]::Collect()
    }
    $streamChunks | Invoke-Command -Session $session $remoteScript -ArgumentList $sourceBytes.Length
    Invoke-Command -Session $Session -ScriptBlock {
        param($path,$baseName,$ext,$DeploymentFolder)
        Expand-Archive -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip -DestinationPath $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp -Force | Out-Null
        Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp\$baseName$ext -Destination $env:USERPROFILE\AppData\Local\Temp\deployment$DeploymentFolder$path | Out-Null
        Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp -Force -Recurse
        Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip
    } -ArgumentList $path,$BaseName,$Extension,$DeploymentFolder
    Remove-Item $env:USERPROFILE\AppData\Local\Temp\deployment\compressed_temp.zip -Force
}

$sourcePathToOutputWwwroot = $sourcePathToOutput + '\wwwroot'
$sourcePathToOutputApproot = $sourcePathToOutput + '\approot'
$sourcePathToOutputPackages = $sourcePathToOutput + '\approot\packages'
# Create local folders
Write-Host
Write-Host Creating local folders
if (Test-Path $env:USERPROFILE\AppData\Local\Temp\deployment) {
    Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment -Force -Recurse | Out-Null
}
New-Item $env:USERPROFILE\AppData\Local\Temp\deployment -type directory -Force | Out-Null
Write-Host OK
###################################
#                                 #
# Create XML manifest of wwwroot  #
#                                 #
###################################
Write-Host 
Write-Host Creating local manifest of wwwroot
$doc_wwwroot = New-Object -TypeName XML
$doc_wwwroot.CreateXmlDeclaration("1.0", $null, $null) | Out-Null
$rootNode = $doc_wwwroot.CreateElement("manifest");
Get-ChildItem -Path $sourcePathToOutputWwwroot -Recurse | ForEach-Object -Process {
    $itemNode = $doc_wwwroot.CreateElement("data");
    $itemNode.SetAttribute("path", $_.FullName)
    $itemNode.SetAttribute("baseName", $_.BaseName)
    $itemNode.SetAttribute("ext", $_.Extension)
    $itemNode.SetAttribute("isDirectory", ($_.Attributes -eq "Directory"))
    if ($_.Attributes -ne "Directory") {
        $itemNode.SetAttribute("hash", (Get-FileHash $_.FullName -Algorithm MD5).hash)
    } else {
        $itemNode.SetAttribute("hash", "")
    }
    $rootNode.AppendChild($itemNode) | Out-Null;
}
$doc_wwwroot.AppendChild($rootNode) | Out-Null;
Write-Host OK
###################################
#                                 #
# Create XML manifest of packages #
#                                 #
###################################
Write-Host 
Write-Host Creating local manifest of approot/packages
$doc_approot_packages = New-Object -TypeName XML
$doc_approot_packages.CreateXmlDeclaration("1.0", $null, $null) | Out-Null
$rootNode = $doc_approot_packages.CreateElement("manifest");
Get-ChildItem -Path $sourcePathToOutputPackages | ForEach-Object -Process {
    Try
    {
        $itemNode = $doc_approot_packages.CreateElement("data");
        $itemNode.SetAttribute("path", $_.FullName)
        $itemNode.SetAttribute("baseName", $_.BaseName)
        $version = (Get-ChildItem -Path $_.FullName)[0]
        $itemNode.SetAttribute("version", $version.BaseName)
        $itemNode.SetAttribute("isDirectory", ($_.Attributes -eq "Directory"))
        $rootNode.AppendChild($itemNode) | Out-Null;
    }
    Catch [system.exception]
    {
        Write-host Failure to find version: $_.FullName $_.BaseName $_.Attributes
    }
}
$doc_approot_packages.AppendChild($rootNode) | Out-Null;
Write-Host OK
###################################
#                                 #
# Run the server array            #
#                                 #
###################################
foreach($server in $servers) {
    # Load vars for this server
    $cloudService = $server[0]
    $port = $server[1]
    $serverUsername = $server[2]
    $websiteName = $server[3]
    $destinationPathToOutput = $server[4]
    Write-Host
    Write-Host Generating session for $server[0] : $server[1]
    $pw = Read-Host -Prompt "Input the password for user '$serverUsername' on server at ${cloudService}:${port}"
    $secpasswd = ConvertTo-SecureString $pw -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($serverUsername, $secpasswd)
    $Session = New-PSSession -ComputerName $cloudService -Port $port -Credential $mycreds -UseSSL -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)
    $variable = Get-Variable -Name Session -Scope Global -ErrorAction SilentlyContinue
    if ($variable -eq $null) {
        Write-Host FAIL!
    } else {
        Write-Host OK
        Write-Host
        Write-Host Checking runtime and moving if needed
        $runtime = (Get-ChildItem -Path $sourcePathToOutputApproot\runtimes)[0]
        $replaceRuntime = Invoke-Command -Session $Session -ScriptBlock {
            param($runtime,$destinationPathToOutput)
            # Create folders
            if (Test-Path $env:USERPROFILE\AppData\Local\Temp\deployment) {
                Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment -Force -Recurse | Out-Null
            }
            New-Item $env:USERPROFILE\AppData\Local\Temp\deployment -type directory -Force | Out-Null
            New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\runtimes -type directory -Force | Out-Null
            New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\packages -type directory -Force | Out-Null
            New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\wwwroot_source -type directory -Force | Out-Null
            # Check the runtime
            if (!(Test-Path $destinationPathToOutput\approot\runtimes\$runtime)) {
                New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\runtimes\$runtime -type directory -Force | Out-Null
                Return $true
            } else {
                Return $false
            }
        } -ArgumentList $runtime,$destinationPathToOutput
        if ($replaceRuntime) {
            CompressSendFolder -Source $sourcePathToOutputApproot\runtimes\$runtime -Session $Session -SourcePathToOutputSubfolder $sourcePathToOutputApproot
        }
        Write-Host OK
        ###################################
        #                                 #
        # Deal with wwwroot items         #
        #                                 #
        ###################################
        Write-Host
        Write-Host Creating server folders and determing wwwroot files needed
        [string]$doc_wwwroot_Str = Invoke-Command -Session $Session -ScriptBlock {
            param($doc_wwwroot,$sourcePathToOutputWwwroot,$destinationPathToOutput)
            Foreach ($item in (Select-XML -Xml $doc_wwwroot -XPath '//data')) {
                $path = $item.Node.path.SubString($sourcePathToOutputWwwroot.Length)
                if ($item.Node.isDirectory -eq "True") {
                    Write-Host Adding folder $path
                    New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\wwwroot_source$path -type directory -Force | Out-Null
                    $item.Node.ParentNode.RemoveChild($item.Node)
                } else {
                    if (Test-Path $destinationPathToOutput\wwwroot$path) {
                        if ($item.Node.hash -eq (Get-FileHash $destinationPathToOutput\wwwroot$path -Algorithm MD5).hash) {
                            # Write-Host File exists on server and hash matches source: Removing this node from the wwwroot manifest
                            $item.Node.ParentNode.RemoveChild($item.Node)
                        } else {
                            # Write-Host File exists on server but does not match source: Leaving node for $path
                        } 
                    } else {
                        # Write-Host File does not exist: Leaving node for $path
                    }
                }
            }
            Return $doc_wwwroot.OuterXml
        } -ArgumentList $doc_wwwroot,$sourcePathToOutputWwwroot,$destinationPathToOutput
        $doc_wwwroot2 = New-Object -TypeName XML
        $doc_wwwroot2.LoadXml('<?xml version="1.0"?>' + $doc_wwwroot_Str.Substring($doc_wwwroot_Str.IndexOf('<')))
        Write-Host OK
        Write-Host
        Write-Host Using wwwroot manifest copying files for archive
        $counter = 0
        Foreach ($item in (Select-XML -Xml $doc_wwwroot2 -XPath '//data')) {
            $path = $item.Node.path.SubString($sourcePathToOutputWwwroot.Length)
            if ($item.Node.isDirectory -ne "True") {
                CompressSendFile -Source $sourcePathToOutputWwwroot$path -BaseName $item.Node.baseName -Extension $item.Node.ext -DeploymentFolder \wwwroot_source -Session $Session -SourcePathToOutputSubfolder $sourcePathToOutputWwwroot
                $counter += 1
            }
        }
        if ($counter -gt 0) {
            $updateWwwrootItems = $true
        } else {
            $updateWwwrootItems = $false
        }
        Write-Host OK
        ###################################
        #                                 #
        # Deal with packages              #
        #                                 #
        ###################################
        Write-Host
        Write-Host Creating server folders and determing packages needed
        [string]$doc_approot_packages_Str = Invoke-Command -Session $Session -ScriptBlock {
            param($doc_approot_packages,$sourcePathToOutputPackages,$destinationPathToOutput)
            Foreach ($item in (Select-XML -Xml $doc_approot_packages -XPath '//data')) {
                $path = $item.Node.path.SubString($sourcePathToOutputPackages.Length)
                if (!(Test-Path $destinationPathToOutput\approot\packages$path)) {
                    New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\packages$path -type directory -Force | Out-Null
                } else {
                    # We only remove here if the version inside is different
                    $version = (Get-ChildItem -Path $destinationPathToOutput\approot\packages$path)[0].ToString()
                    if ($version -eq $item.Node.version) {
                        $item.Node.ParentNode.RemoveChild($item.Node)
                    }
                }
            }
            Return $doc_approot_packages.OuterXml
        } -ArgumentList $doc_approot_packages,$sourcePathToOutputPackages,$destinationPathToOutput
        $doc_approot_packages2 = New-Object -TypeName XML
        $doc_approot_packages2.LoadXml('<?xml version="1.0"?>' + $doc_approot_packages_Str.Substring($doc_approot_packages_Str.IndexOf('<')))
        Write-Host OK
        Write-Host
        Write-Host Using package manifest copying packages
        $counter = 0
        Foreach ($item in (Select-XML -Xml $doc_approot_packages2 -XPath '//data')) {
            CompressSendFolder -Source $item.Node.path -Session $Session -SourcePathToOutputSubfolder $sourcePathToOutputApproot
            $counter += 1
        }
        if ($counter -gt 0) {
            $updatepackages = $true
        } else {
            $updatepackages = $false
        }
        Write-Host OK
        Write-Host
        ###################################
        #                                 #
        # Deal with global.json           #
        #                                 #
        ###################################
        $moveGlobalJsonFile = $false
        if (Test-Path $sourcePathToOutputApproot\global.json) {
            CompressSendFile -Source $sourcePathToOutputApproot\global.json -BaseName "global" -Extension ".json" -DeploymentFolder \ -Session $Session -SourcePathToOutputSubfolder $sourcePathToOutputApproot
            $moveGlobalJsonFile = $true
            Write-Host OK
        }
        Write-Host
        ###################################
        #                                 #
        # Deploy the payload              #
        #                                 #
        ###################################
        Write-Host Deploy the new payload
        Invoke-Command -Session $Session -ScriptBlock {
            param($doc_wwwroot2,$sourcePathToOutputWwwroot,$websiteName,$destinationPathToOutput,$replaceRuntime,$moveGlobalJsonFile,$updateWwwrootItems,$updatepackages,$doc_approot_packages2,$sourcePathToOutputApproot)
            # Stop the AppPool
            if((Get-WebAppPoolState $websiteName).Value -ne 'Stopped') {
                Stop-WebAppPool -Name $websiteName
                while((Get-WebAppPoolState $websiteName).Value -ne 'Stopped') {
                    Start-Sleep -s 1
                }
                Write-Host `-AppPool Stopped
            }
            # Handle wwwroot items
            if ($updateWwwrootItems) {
                Foreach ($item in (Select-XML -Xml $doc_wwwroot2 -XPath '//data')) {
                    $path = $item.Node.path.SubString($sourcePathToOutputWwwroot.Length)
                    if ($item.Node.isDirectory -eq "True" -and (!(Test-Path $destinationPathToOutput\wwwroot$path))) {
                        New-Item $destinationPathToOutput\wwwroot$path -type directory -Force | Out-Null
                        Write-Host `-Added folder $path into wwwroot
                    } elseif ($item.Node.isDirectory -eq "False") {
                        Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\wwwroot_source$path -Destination $destinationPathToOutput\wwwroot$path
                        Write-Host `-Copied file $path into wwwroot
                    }
                }
            }
            # Runtime replacement
            if ($replaceRuntime) {
                Remove-Item $destinationPathToOutput\approot\runtimes -recurse -Force
                Write-Host `-Cleared runtimes folder on the server
                New-Item $destinationPathToOutput\approot\runtimes -type directory -Force | Out-Null
                Write-Host `-Created runtimes folder
                Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\runtimes\$runtime -Destination $destinationPathToOutput\approot\runtimes -Force -Recurse
                Write-Host `-Copied $runtime into approot/runtimes
            }
            # global.json
            if ($moveGlobalJsonFile) {
                Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\global.json -Destination $destinationPathToOutput\approot -Force
                Write-Host `-Copied global.json into approot
            }
            # Packages
            if ($updatepackages) {
                if (!(Test-Path $destinationPathToOutput\approot\packages)) {
                    New-Item $destinationPathToOutput\approot\packages -type directory -Force | Out-Null
                }
                Foreach ($item in (Select-XML -Xml $doc_approot_packages2 -XPath '//data')) {
                    $path = $item.Node.path.SubString($sourcePathToOutputApproot.Length)
                    if ((Test-Path $destinationPathToOutput\approot$path)) {
                        Remove-Item $destinationPathToOutput\approot$path -Force -Recurse | Out-Null
                    }
                    Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment$path -Destination $destinationPathToOutput\approot$path -Recurse
                    Remove-Item $env:USERPROFILE\AppData\Local\Temp\deployment$path -Force -Recurse | Out-Null
                }
                Write-Host `-Set packages into approot/packages
            }
            # Restart the AppPool
            if((Get-WebAppPoolState $websiteName).Value -ne 'Started') {
                Start-WebAppPool -Name $websiteName
                while((Get-WebAppPoolState $websiteName).Value -ne 'Started') {
                    Start-Sleep -s 1
                }
                Write-Host `-AppPool Started
            }
        } -ArgumentList $doc_wwwroot2,$sourcePathToOutputWwwroot,$websiteName,$destinationPathToOutput,$replaceRuntime,$moveGlobalJsonFile,$updateWwwrootItems,$updatepackages,$doc_approot_packages2,$sourcePathToOutputApproot
        Write-Host OK
        Write-Host
        Write-Host Disconnecting and removing session
        Disconnect-PSSession -Session $Session | Out-Null
        Remove-PSSession -Session $Session | Out-Null
        Write-Host OK
    }
    $Session = $null
    Write-Host
    Write-Host 'Done!'
}
