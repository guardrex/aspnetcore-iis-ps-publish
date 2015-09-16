# net5-iis-ps-publish
Experimental script for publishing .NET 5 projects to one or more Azure IIS VM's
# Requirements
- Powershell 5 http://www.microsoft.com/en-us/download/details.aspx?id=48729
- Powershell Community Extensions (PSCX) https://pscx.codeplex.com/

# WARNING!
This script is highly EXPERIMENTAL! Do not use with any application publishing in a production environment. Use at your own risk.

# Notes
The chunking algorithm for sending large files in a PSSession is from "Send-File" from the Windows PowerShell Cookbook ISBN: 1449320686 (O'Reilly) by Lee Holmes (http://www.leeholmes.com/guide) http://poshcode.org/2216

Make sure the Azure Cloud Services certificate is installed locally. See: http://techthoughts.info/remote-powershell-to-azure-vm-automating-certificate-configuration/

The script only works with .NET 5 projects that have a single runtime and a single package version of each package.