# dcs-migration
- Technology: PowerShell
- Runs on: DCS+, DCS and any other provider running vCloudDirector
- Howto: 1. Open a PowerShell console and change the directory to the folder where the scripts are stored. 
2. Run the following Command if you downloaded the scripts via Browser: Unblock-File -Path .\* otherwise Powershell will prevent you running the scripts and modules.
3. Copy the folder vCloudDirectorRest in the folder Modules to one of the ModulePaths of PowerShell (in your PS console enter $env:PSModulePath to display all ModulePaths).
4. Run the scripts by providing all required parameters.

