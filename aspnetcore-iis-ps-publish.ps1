<#
#
# aspnetcore-iis-ps-publish
#
# Experimental prototype for using Powershell to publish an ASP.NET Core project to an IIS web server
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
#   This script is highly EXPERIMENTAL! Do not use with application publishing
#   in a production environment without serious testing. Use at your own risk.
#
# The chunking algorithm for sending large files in a PSSession is from "Send-File"
# from the Windows PowerShell Cookbook ISBN: 1449320686 (O'Reilly) by Lee Holmes 
# (http://www.leeholmes.com/guide) http://poshcode.org/2216
#
# Make sure the Azure Cloud Services certificate is installed locally.
# See: http://techthoughts.info/remote-powershell-to-azure-vm-automating-certificate-configuration/
#>

# Provide the path to your local project output folder. This is the folder that contains the payload to move
# e.g., C:\My_Cool_Project\My_Project_Assets_Folder\bin\Release\dnxcore50\win7-x64
$sourcePathToOutput = '<path to output folder of project to the platform and runtime>'

# Provide servers: The Cloud Service endpoint, the server's port at that endpoint, the admin username, 
# the IIS website AppPool name on that server, the path to the website (the folder on the server that will contain 
# the payload of the application)
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

# Create local folders
Write-Host
Write-Host Creating local folders
if (Test-Path $env:USERPROFILE\AppData\Local\Temp\deployment) {
    Remove-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment -Force -Recurse | Out-Null
}
New-Item $env:USERPROFILE\AppData\Local\Temp\deployment -type directory -Force | Out-Null
Write-Host OK

##############################################
#                                            #
# Create XML manifest of the payload folder  #
#                                            #
##############################################
Write-Host 
Write-Host Creating local manifest of payload
$doc_payload = New-Object -TypeName XML
$doc_payload.CreateXmlDeclaration("1.0", $null, $null) | Out-Null
$rootNode = $doc_payload.CreateElement("manifest");
Get-ChildItem -Path $sourcePathToOutput -Recurse | ForEach-Object -Process {
    $itemNode = $doc_payload.CreateElement("data");
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
$doc_payload.AppendChild($rootNode) | Out-Null;
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
    $webAppPoolName = $server[3]
    $destinationPathToOutput = $server[4]
    $pw = Read-Host -Prompt "Input the password for user '$serverUsername' on server at ${cloudService}:${port}"
    Write-Host
    Write-Host Generating session for $server[0] : $server[1]
    $secpasswd = ConvertTo-SecureString $pw -AsPlainText -Force
    $mycreds = New-Object System.Management.Automation.PSCredential ($serverUsername, $secpasswd)
    $Session = New-PSSession -ComputerName $cloudService -Port $port -Credential $mycreds -UseSSL -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)
    $variable = Get-Variable -Name Session -Scope Global -ErrorAction SilentlyContinue
    if ($variable -eq $null) {
        Write-Host FAIL!
    } else {
        Write-Host OK
        Write-Host

        ###################################
        #                                 #
        # Deal with payload items         #
        #                                 #
        ###################################
        Write-Host Creating server folders and determing payload files needed
        [string]$doc_payload_Str = Invoke-Command -Session $Session -ScriptBlock {
            param($doc_payload,$sourcePathToOutput,$destinationPathToOutput)
            Foreach ($item in (Select-XML -Xml $doc_payload -XPath '//data')) {
                $path = $item.Node.path.SubString($sourcePathToOutput.Length)
                if ($item.Node.isDirectory -eq "True") {
                    Write-Host Adding folder $path
                    New-Item $env:USERPROFILE\AppData\Local\Temp\deployment\payload_source$path -type directory -Force | Out-Null
                } else {
                    if (Test-Path $destinationPathToOutput$path) {
                        if ($item.Node.hash -eq (Get-FileHash $destinationPathToOutput$path -Algorithm MD5).hash) {
                            # Write-Host File exists on server and hash matches source: Removing this node from the payload manifest
                            $item.Node.ParentNode.RemoveChild($item.Node)
                        } else {
                            # Write-Host File exists on server but does not match source: Leaving node for $path
                        } 
                    } else {
                        # Write-Host File does not exist: Leaving node for $path
                    }
                }
            }
            Return $doc_payload.OuterXml
        } -ArgumentList $doc_payload,$sourcePathToOutput,$destinationPathToOutput
        $doc_payload2 = New-Object -TypeName XML
        $doc_payload2.LoadXml('<?xml version="1.0"?>' + $doc_payload_Str.Substring($doc_payload_Str.IndexOf('<')))
        Write-Host OK
        Write-Host
        Write-Host Using payload manifest copying files for archive
        $counter = 0
        Foreach ($item in (Select-XML -Xml $doc_payload2 -XPath '//data')) {
            $path = $item.Node.path.SubString($sourcePathToOutput.Length)
            if ($item.Node.isDirectory -ne "True") {
                CompressSendFile -Source $sourcePathToOutput$path -BaseName $item.Node.baseName -Extension $item.Node.ext -DeploymentFolder \payload_source -Session $Session -SourcePathToOutputSubfolder $sourcePathToOutput
                $counter += 1
            }
        }
        if ($counter -gt 0) {
            $updatePayloadItems = $true
        } else {
            $updatePayloadItems = $false
        }
        Write-Host OK

        ###################################
        #                                 #
        # Deploy the payload              #
        #                                 #
        ###################################
        if ($updatePayloadItems) {
            Write-Host Deploy the new payload
            Invoke-Command -Session $Session -ScriptBlock {
                param($doc_payload2,$sourcePathToOutput,$webAppPoolName,$destinationPathToOutput)
                # Stop the AppPool
                if((Get-WebAppPoolState $webAppPoolName).Value -ne 'Stopped') {
                    Stop-WebAppPool -Name $webAppPoolName
                    while((Get-WebAppPoolState $webAppPoolName).Value -ne 'Stopped') {
                        Start-Sleep -s 1
                    }
                    Write-Host `-AppPool Stopped
                }
                # Handle wwwroot items
                if (!(Test-Path $destinationPathToOutput)) {
                    New-Item $destinationPathToOutput -type directory -Force | Out-Null
                }
                Foreach ($item in (Select-XML -Xml $doc_payload2 -XPath '//data')) {
                    $path = $item.Node.path.SubString($sourcePathToOutput.Length)
                    if ($item.Node.isDirectory -eq "True" -and (!(Test-Path $destinationPathToOutput$path))) {
                        New-Item $destinationPathToOutput$path -type directory -Force | Out-Null
                        Write-Host `-Added folder $path
                    } elseif ($item.Node.isDirectory -eq "False") {
                        Copy-Item -Path $env:USERPROFILE\AppData\Local\Temp\deployment\payload_source$path -Destination $destinationPathToOutput$path
                        Write-Host `-Copied file $path
                    }
                }
                # Restart the AppPool
                if((Get-WebAppPoolState $webAppPoolName).Value -ne 'Started') {
                    Start-WebAppPool -Name $webAppPoolName
                    while((Get-WebAppPoolState $webAppPoolName).Value -ne 'Started') {
                        Start-Sleep -s 1
                    }
                    Write-Host `-AppPool Started
                }
            } -ArgumentList $doc_payload2,$sourcePathToOutput,$webAppPoolName,$destinationPathToOutput
            Write-Host OK
        } else {
            Write-Host No payload changes were detected. The server payload is current. No deployment has been processed.
        }
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
