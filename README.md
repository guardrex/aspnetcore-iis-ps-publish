# netcore-iis-ps-publish
Experimental script for publishing ASP.NET Core projects to one or more IIS servers.

### Updated for `dotnet cli`!!!
Yes! `dotnet cli` publishing, based on a flat output structure, is radically different from what we had with DNX. This script has been updated to work with `dotnet cli` projects.

## WARNING!
This script is highly **EXPERIMENTAL!** Do not use with any application publishing in a production environment without serious testing. Use at your own risk.
### Requirements
- PowerShell 5 http://www.microsoft.com/en-us/download/details.aspx?id=48729
- PowerShell Community Extensions (PSCX) https://pscx.codeplex.com/

The installer for WS2012R2 is Win8.1AndW2K12R2-KB3066437-x64.msu.

### Notes
The chunking algorithm for sending large files in a PSSession is adapted from "Send-File" from the Windows PowerShell Cookbook ISBN: 1449320686 (O'Reilly) by Lee Holmes (http://www.leeholmes.com/guide) Code: http://poshcode.org/2216

For Azure Cloud Services, make sure the certificate for your cloud service is installed locally. For tips on doing this for Azure Cloud Services (Azure VM's), see the [TechThoughts blog post](http://techthoughts.info/remote-powershell-to-azure-vm-automating-certificate-configuration/).
### Configuration
Provide the path to the output folder of your project, which is the folder that contains your `wwwroot`, `refs`, and any contents folders that you specified in `project.json`. You'll also see a number of DLL's and your application's executable (.exe), program database (.pdb), dependency (.dep), and DLL (.dll) files. For example, the path for a `dnxcore50 win7-x64` target platform, runtime, and payload would be in this format: `C:\My_Cool_Project\My_Project_Assets_Folder\bin\Release\dnxcore50\win7-x64`.
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

Make sure that the path to the website folder in the script array is to the folder that holds the `wwwroot` folder on the server. Recall that binding a website to a ASP.NET Core app's phycial folder in IIS is different: In IIS, you bind the website directly to the `wwwroot` folder. The folder that the script needs is the folder **above** the `wwwroot` folder.

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
1. Create a manifest of the project's payload folder
2. Update the application on each Azure VM
  1. Take credentials for the server and establish a PowerShell session
  2. Establish a deployment folder for the deployment on the server
  3. Check payload items on the server by hash comparison and send up any payload items from the local project to the deployment folder
  4. Deploy the payload on the server from the deployment folder to the application folder
    1. Stop the AppPool (to prevent file locks)
    2. Copy payload items (if needed)
    3. Restart the AppPool
  5. Disconnect and remove the PowerShell session to the server