# net5-iis-ps-publish
Experimental script for publishing .NET 5 projects to one or more Azure IIS VM's
## WARNING!
This script is highly **EXPERIMENTAL!** Do not use with any application publishing in a production environment. Use at your own risk.
### Requirements
- Powershell 5 http://www.microsoft.com/en-us/download/details.aspx?id=48729
- Powershell Community Extensions (PSCX) https://pscx.codeplex.com/
### Notes
The chunking algorithm for sending large files in a PSSession is from "Send-File" from the Windows PowerShell Cookbook ISBN: 1449320686 (O'Reilly) by Lee Holmes (http://www.leeholmes.com/guide) http://poshcode.org/2216

Make sure the Azure Cloud Services certificate is installed locally. See: http://techthoughts.info/remote-powershell-to-azure-vm-automating-certificate-configuration/

The script only works with .NET 5 projects that have a single runtime and a single package version of each package.

Because the script goes by version numbers when deciding if a package should be replaced on the server, make sure you change your application version if you want the scrpt to upload your application changes.
### Configuration
Provide the path to the output folder of your project (i.e., the path to the folder where you published your project, which is the folder that contains your approot and wwwroot folders).
```
$sourcePathToOutput = '<PATH_TO_LOCAL_PUBLISH_FOLDER>'
```
Provide server data in the array.
```
$servers = @(
    ('<CLOUD_SERVICE>.cloudapp.net',55000,'<ADMIN_USERNAME>','<IIS_WEBSITE_NAME>','<PATH_TO_WEBSITE_FOLDER>'),
    ('<CLOUD_SERVICE>.cloudapp.net',55001,'<ADMIN_USERNAME>','<IIS_WEBSITE_NAME>','<PATH_TO_WEBSITE_FOLDER>'),
    ('<CLOUD_SERVICE>.cloudapp.net',55002,'<ADMIN_USERNAME>','<IIS_WEBSITE_NAME>','<PATH_TO_WEBSITE_FOLDER>')
)
```
### Processing
1. Create a manifest of the project's wwwroot folder
2. Create a manifest of the project's packages
3. Update the application on each Azure VM
  1. Take credentials for the server and establish a PowerShell session
  2. Establish a deployment folder for the deployment on the server and determine if the runtime is correct
  3. Check wwwroot items on the server by hash comparison and send up any wwwroot items from the local project to the deployment folder
  4. Check packages on the server by package version and send up any packages from the local project to the deployment folder
  5. Move the global.json from the local project to the server (if it exists)
  6. Deploy the payload on the server from the deployment folder to the application folder
    1. Stop the AppPool (to prevent file locks)
    2. Copy wwwroot items (if needed)
    3. Replace the runtime (if needed)
    4. Move the global.json file (if needed)
    5. Update packages (if needed)
    6. Restart the AppPool
  7. Disconnect and remove the PowerShell session to the server