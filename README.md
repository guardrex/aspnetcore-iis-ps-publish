# net5-iis-ps-publish
Experimental script for publishing .NET 5 projects to one or more IIS servers.
## WARNING!
This script is highly **EXPERIMENTAL!** Do not use with any application publishing in a production environment. Use at your own risk.
### Requirements
- PowerShell 5 http://www.microsoft.com/en-us/download/details.aspx?id=48729
- PowerShell Community Extensions (PSCX) https://pscx.codeplex.com/

### Notes
The chunking algorithm for sending large files in a PSSession is adapted from "Send-File" from the Windows PowerShell Cookbook ISBN: 1449320686 (O'Reilly) by Lee Holmes (http://www.leeholmes.com/guide) Code: http://poshcode.org/2216

For Azure Cloud Services, make sure the certificate for your cloud service is installed locally. For tips on doing this for Azure Cloud Services (Azure VM's), see the [TechThoughts blog post](http://techthoughts.info/remote-powershell-to-azure-vm-automating-certificate-configuration/).

The script only works with .NET 5 projects that have a single runtime and a single package version of each package.

Because the script goes by version numbers when deciding if a package should be replaced on the server, make sure you change your application version if you want the scrpt to upload your application changes.
### Configuration
Provide the path to the output folder of your project. This is the path to the folder where you published your project, which is the folder that contains your `approot` and `wwwroot` folders.
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
The sample (and the script itself) demonstrates using Azure Cloud Services and Azure VM's, but the script should work just as well on-prem. Change the address of the server to the server's IP address. Indicate the server's port where PowerShell is listening. If you don't port map it away, it's typically 5986 for SSL.

In the Azure scenario, note that these ports have been mapped in the Azure portal for these VM's: e.g., 55000 -> 5986, 55001 -> 5986, 55002 -> 5986. Each server under a Cloud Service endpoint (mycloudservice.cloudapp.net) must have a single, dedicated endpoint setup this way in the Azure portal.

Make sure that the path to the website folder in the script array is to the folder that holds the `approot` and `wwwroot` folders on the server. Recall that binding a website to a .NET 5 app's phycial folder in IIS is different: In IIS, you bind the website directly to the `wwwroot` folder. The folder that the script needs is the folder **above** the `wwwroot` folder.

##### Example
Say we have two Azure Cloud Services (myeastusservice.cloudapp.net and mywestusservice.cloudapp.net), each with two VM's. Each of the two VM's have had a dedicated port mapped to 5986 for SSL PowerShell. The web application has the same name on each VM, and the physical path is pointed to a data drive (F:) in the same location. This is how the array should be setup for this example:
```
$servers = @(
    ('myeastusservice.cloudapp.net',50000,'adminuser','corporate_public','F:\corporate_public'),
    ('myeastusservice.cloudapp.net',50001,'adminuser','corporate_public','F:\corporate_public'),
    ('mywestusservice.cloudapp.net',50000,'adminuser','corporate_public','F:\corporate_public'),
    ('mywestusservice.cloudapp.net',50001,'adminuser','corporate_public','F:\corporate_public')
)
```
### Processing
1. Create a manifest of the project's `wwwroot` folder
2. Create a manifest of the project's packages
3. Update the application on each Azure VM
  1. Take credentials for the server and establish a PowerShell session
  2. Establish a deployment folder for the deployment on the server and determine if the runtime is correct
  3. Check `wwwroot` items on the server by hash comparison and send up any `wwwroot` items from the local project to the deployment folder
  4. Check packages on the server by package version and send up any packages from the local project to the deployment folder
  5. Move the `global.json` from the local project to the server (if it exists)
  6. Deploy the payload on the server from the deployment folder to the application folder
    1. Stop the AppPool (to prevent file locks)
    2. Copy `wwwroot` items (if needed)
    3. Replace the runtime (if needed)
    4. Move the `global.json` file (if needed)
    5. Update packages (if needed)
    6. Restart the AppPool
  7. Disconnect and remove the PowerShell session to the server