# dcsplus-utils
This repository will contain various helpful scripts and tools for using with Swisscom's [DCS+](https://www.swisscom.com/dcs) product. Among other things, this will include utilities to prepare parts of your infrastructure for migrating towards DCS+ or helps your to configure some hidden settings in vCloudDirector through its API.

## Disclaimer
These scripts are under continous development and provided "as is". Therefore no support can be given. Use the scripts on your own risk after reading the full source code - no liability is taken for the case that any script will break parts of your infrastructure.

## Sub-projects

### vcd-metricsgetter
- Technology: PowerShell (with PowerCLI libraries)
- Runs on: DCS+, DCS, any other provider running vCloudDirector
- Howto: Edit the variables at the beginning of [the script](vcd-metricsgetter/vcd-getmetrics.ps1) and afterwards run it on any PowerShell terminal. The VMware libraries must be installed first, please refer to the [DCS+ Guide](https://dcsplusguide.scapp.io/ug/vcloud-director-api.html) for further information about this.

### vcd-egw-syslogsetter
- Technology: bash Shell & curl
- Runs on: DCS+, DCS, any other provider running vCloudDirector 8.20
- Howto: Edit the variables at the beginning of [the script](vcd-egw-syslogsetter/setsyslogserver.sh) and afterwards run it on any bash-Terminal with curl installed. At the end, the output of the configuration task submission to the API is being dumped. Unfortunately, it is still not possible to retrieve through the API that the setting was properly applied. Please go to the vCloudDirector Web UI, then to the properties of the affected EdgeGateway and look at the tab "Syslog Server Settings". Please also note, that the "Synchronize Syslog Server Settings" function will rollback your configuration (e.g no syslog server set at all!)
