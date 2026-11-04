![GitHub release (latest by date)](https://img.shields.io/github/v/release/trailstack/syno.embyupdate)
![GitHub top language](https://img.shields.io/github/languages/top/trailstack/syno.embyupdate)
![GitHub](https://img.shields.io/github/license/trailstack/syno.embyupdate)

&nbsp;

![syno.embyupdate logo](./images/Emby.logo.svg)

### Automatically Update Emby Server on the Synology NAS platform

# Description

This script addresses common issues with automatically updating Emby Server on Synology NAS. It uses Synology's built-in tools to automatically detect the Emby installation location, manage updates, and notify the system of any issues.

The script downloads the official Emby Server SPK package from [Emby's GitHub Releases](https://github.com/MediaBrowser/Emby.Releases/releases) and installs it using Synology's package manager. It automatically detects your NAS hardware model and DSM version to select the correct SPK package for your system.

By default, the script only installs updates that are at least 7 days old, serving as a stability measure. Additionally, it retains previously downloaded and installed packages in an "Updates" archive for 60 days before automatic deletion to make rollbacks easier to find and perform.

# DSM Version Support

Emby Server publishes separate SPK packages for each DSM version line. The script automatically detects your DSM version and selects the correct package family:

| DSM Version | SPK Package Prefix |
|---|---|
| DSM 6.x | `emby-server-synology_` |
| DSM 7.0–7.1.x | `emby-server-synology7_` |
| DSM 7.2+ | `emby-server-synology72_` |

The script also detects your CPU architecture and selects the matching SPK build (x86_64, armv8, armada370, etc.).

# How-To Setup Example

### 1. Save the Script to Your NAS

Download the script and place it into a location of your choosing. As an example, if you are using the "`admin`" account for system administration tasks, you can place the script within that accounts home folder; such as in a nested directory location like this:

    /home/scripts/bash/emby/syno.embyupdate/syno.embyupdate.sh

-or-

    /homes/admin/scripts/bash/emby/syno.embyupdate/syno.embyupdate.sh

**Note:** Synology recommends that you disable the default "`admin`" account for security reasons. In these examples, the admin directory structure is just a script storage location. You can run the script from here even if you disable the "`admin`" account (which you really should).

### 2. Setup a Scheduled Task in the DSM

1. Open the [DSM](https://www.synology.com/en-global/knowledgebase/DSM/help) web interface
1. Open the [Control Panel](https://www.synology.com/en-global/knowledgebase/DSM/help/DSM/AdminCenter/ControlPanel_desc)
1. Open [Task Scheduler](https://www.synology.com/en-global/knowledgebase/DSM/help/DSM/AdminCenter/system_taskscheduler)
    1. Click Create -> Scheduled Task -> User-defined script
    1. Enter Task: name as '`Syno.Emby Update`', and leave User: set to '`root`'
    1. Click Schedule tab and configure per your requirements
    1. Click Task Settings tab
    1. Enter 'User-defined script' similar to:
    '`bash /volume1/homes/admin/scripts/bash/emby/syno.embyupdate/syno.embyupdate.sh`'
    ...if using the above script placement example. '`/volume1`' is the default storage volume on a Synology NAS. You can determine your script directory's full pathname by looking at the Location properties of the folder with the [File Station](https://www.synology.com/en-global/knowledgebase/DSM/help/FileStation/FileBrowser_desc) tool in the DSM:
        1. Right-click on the folder containing the script and choose Properties
        1. Copy the full directory path from the Location field
1. Click OK

# Script Logic Flow

1. Identify the "Emby Server" installation directory and other system-specific technical details
1. Detect DSM version to select the correct SPK package prefix (synology / synology7 / synology72)
1. Detect CPU architecture to select the correct SPK package suffix (x86_64, armv8, armada370, etc.)
1. Fetch the latest release from Emby's GitHub Releases API
1. Find the matching SPK asset using prefix + suffix matching
1. Compare currently running version against latest online version
1. If a new version exists and is older than the default 7-days - install the new version
1. Check if the upgrade was successful, and send appropriate notifications to the DSM and email (if configured)
    * Notifications are only sent when an upgrade installation takes place

# Script Directory Structure

The script will automatically create directories and files as needed in the following directory structure based off of the location of the script, as per this example:

    /volume1/homes/admin/scripts/bash/emby/syno.embyupdate
    |   config.ini
    |   README.md
    |   syno.embyupdate.sh
    |
    \---Archive
        +---Packages
        |       changelog.txt
        |       emby-server-synology7_4.9.5.0_x86_64.spk
        |       emby-server-synology7_4.10.0.40_x86_64.spk
        |       emby-server-synology72_4.10.1.0_x86_64.spk
        |       ...
        |
        \---Scripts
                 syno.embyupdate.v1.0.0.sh
                 syno.embyupdate.v1.0.1.sh
                 syno.embyupdate.v1.1.0.sh
                 ...

The Archive directory structure contains copies of update Packages as well as copies of the update Scripts that are running. The packages archive is intended for manual rollback purposes.

# Example Email Notification

    Dear user,

    Task Scheduler has completed a scheduled task.

    Task: Syno.Emby Update
    Start time: Tue, 03 Sep 2026 10:15:30 GMT
    Stop time: Tue, 03 Sep 2026 10:16:12 GMT
    Current status: 1 (Interrupted)
    Standard output/error:

    SYNO.EMBY UPDATE SCRIPT v1.0.0

            Script: syno.embyupdate.sh
        Script Dir: /volume1/homes/admin/scripts/bash/emby/syno.embyupdate
       Running Ver: 1.0.0
        Online Ver: 1.0.1 (45/50)
          Released: 2026-09-02 14:20:00-07:00 (1+ days old)
                      * Newer version found!

              Synology: DS923+ (aarch64), DSM 7.2.1-69057 Update 1
              Emby Dir: /var/packages/EmbyServer
           Running Ver: 4.10.0.40
            Online Ver: 4.10.1.0 (DSM 72 for aarch64)
              Released: 2026-09-03 08:05:34-07:00 (0+ days old)
                          * Newer version found!

          New Package: emby-server-synology72_4.10.1.0_armv8.spk
          Package Age: 0+ days old (0+ required for install)

      INSTALLING NEW PACKAGE:
      ----------------------------------------
      Downloading Emby Server package:

      Stopping EmbyServer service:
      {"action":"stop","beta":false,"error":{"code":0},"finished":true,"language":"enu","last_stage":"stopped","package":"EmbyServer","pid":12345,"scripts":[{"code":0,"message":"","type":"stop"}],"stage":"stopped","status":"stop","success":true,"username":"","version":"4.10.0.40-724080400"}

      Installing EmbyServer update:
      {"error":{"code":0},"results":[{"action":"upgrade","error":{"code":0},"finished":true,"installReboot":false,"installing":true,"language":"enu","last_stage":"postupgrade","package":"EmbyServer","packageName":"Emby Server","pid":12456,"scripts":[{"code":0,"message":"Installation Successful!","type":"postinst"}],"spk":"/volume1/homes/admin/scripts/bash/emby/syno.embyupdate/Archive/Packages/emby-server-synology72_4.10.1.0_armv8.spk","stage":"installed_and_stopped","status":"stop","success":true,"username":"","version":"4.10.0.40-724080400"}],"success":true}

      Starting EmbyServer service:
      {"action":"start","beta":false,"error":{"code":0},"finished":true,"language":"enu","last_stage":"started","package":"EmbyServer","pid":12567,"scripts":[{"code":0,"message":"","type":"start"}],"stage":"started","status":"running","success":true,"username":"","version":"4.10.1.0-724090100"}
      ----------------------------------------

          Update from: 4.10.0.40
                  to: 4.10.1.0 succeeded!

      From SYNOLOGY

# Default Settings (config.ini)

The script utilizes (4) default but user-configurable variables:

1. `MinimumAge=7`
    * A **7**-day age requirement for installing the latest version as a bug/issue deterrent
1. `OldUpdates=60`
    * A **60**-day age requirement for deleting old package installer files
1. `NetTimeout=900`
    * A **900**-second (15 minute) network timeout for hung network connections
1. `SelfUpdate=0`
    * A 0=off 1=on toggle to enable self-updating to the latest packaged release. Change this to **1** to enable self-updating that follows the same minimum age requirement as the Emby updates

# CLI Options

| Option | Description |
|---|---|
| `-a #` | Override the minimum age in days |
| `-h` | Display help message |

# Known Non-Issues

* If the script runs successfully, the DSM Task status will show "`Interrupted (1)`" and the notification email will state "`Current status: 1 (Interrupted)`". This exit/error status of (1) is intentionally caused by the script in order to force the DSM to perform an email notification of a successful update (in the form of an interruption/error). The DSM otherwise would only send notifications of failed task events, and notifications of successful Emby updates would not be possible.

# Common Mistakes

* Bash shell scripts running on Linux must be saved as LF (Line Feed) sequenced text. Alternatively, Windows typically uses CRLF (Carriage Return Line Feed). If you inadvertently save your script with CRLF instead of LF sequencing, it will error with verbiage such as:
    * `'\r': command not found`
    * `syntax error near unexpected`

    To resolve this issue you will need to [re]save your copy of the script with LF sequencing, or download a new copy directly from GitHub.
