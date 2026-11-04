#!/bin/bash
# shellcheck disable=SC2154,SC2181
# shellcheck source=/dev/null
#
# A script to automagically update Emby Server on Synology NAS
# This must be run as root to natively control running services
#
# Author: https://github.com/trailstack/syno.embyupdate
#
# Original update concept based on: https://github.com/michealespinola/syno.plexupdate
#
# Example Synology DSM Scheduled Task type 'user-defined script':
# bash /volume1/homes/admin/scripts/bash/emby/syno.embyupdate.sh

# SCRAPE SCRIPT PATH INFO
SrceFllPth=$(readlink -f "${BASH_SOURCE[0]}")
SrceFolder=$(dirname "$SrceFllPth")
SrceFileNm=${SrceFllPth##*/}

# REDIRECT STDOUT TO TEE IN ORDER TO DUPLICATE THE OUTPUT TO THE TERMINAL AS WELL AS A .LOG FILE
exec > >(tee "$SrceFllPth.log") 2>"$SrceFllPth.debug"

# ENABLE XTRACE OUTPUT FOR DEBUG FILE
set -x

# SCRIPT VERSION
SeuscrpVer=1.0.0
MinDSMVers=6.0
# PRINT OUR GLORIOUS HEADER BECAUSE WE ARE FULL OF OURSELVES
printf "\n"
printf "%s\n" "SYNO.EMBY UPDATE SCRIPT v$SeuscrpVer"
printf "\n"

# CHECK IF ROOT
if [ "$EUID" -ne "0" ]; then
  printf ' %s\n\n' "* This script MUST be run as root - exiting.."
  /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Emby Server\n\nSyno.Emby Update task failed. Script was not run as root."}'
  printf "\n"
  exit 1
fi

# CHECK IF DEFAULT CONFIG FILE EXISTS, IF NOT CREATE IT
create_or_update_config() {
  local ConfigFile="$1"
  if [ ! -f "$ConfigFile" ]; then
    printf ' %s\n\n' "* CONFIGURATION FILE (config.ini) IS MISSING, CREATING DEFAULT SETUP.."
    touch "$ConfigFile"
    ExitStatus=1
  fi
  # Function to add key-value pairs along with comments if not present
  add_config_with_comment() {
    local key="$1"
    local value="$2"
    local comment="$3"
    if ! grep -q "^$key=" "$ConfigFile"; then
      printf '%s\n' "$comment" >> "$ConfigFile"
      printf '%s\n' "$key=$value" >> "$ConfigFile"
    fi
  }
  # Default configurations
  add_config_with_comment "MinimumAge" "7"   "# A NEW UPDATE MUST BE THIS MANY DAYS OLD"
  add_config_with_comment "OldUpdates" "60"  "# PREVIOUSLY DOWNLOADED PACKAGES DELETED IF OLDER THAN THIS MANY DAYS"
  add_config_with_comment "NetTimeout" "900" "# NETWORK TIMEOUT IN SECONDS (900s = 15m)"
  add_config_with_comment "SelfUpdate" "0"   "# SCRIPT WILL SELF-UPDATE IF SET TO 1"
}
create_or_update_config "$SrceFolder/config.ini"

# LOAD CONFIG FILE IF IT EXISTS
if [ -f "$SrceFolder/config.ini" ]; then
  source "$SrceFolder/config.ini"
fi

# PRINT SCRIPT STATUS/DEBUG INFO
printf '%16s %s\n'                   "Script:" "$SrceFileNm"
printf '%16s %s\n'               "Script Dir:" "$(fold -w 72 -s     < <(printf '%s' "$SrceFolder") | sed '2,$s/^/                 /')"

# CHECK FOR BASIC INTERNET CONNECTIVITY
if nslookup one.one.one.one >/dev/null 2>&1; then
  :
elif ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  printf '\n %s\n\n' "* DNS resolution appears to be failing - exiting.."
  exit 1
else
  printf '\n %s\n\n' "* Internet appears to be down - exiting.."
  exit 1
fi

# OVERRIDE SETTINGS WITH CLI OPTIONS
while getopts ":a:h" opt; do
  case ${opt} in
    a) # OVERRIDE MINIMUM AGE
      if [[ $OPTARG =~ ^[0-9]+$ ]]; then
        MinimumAge=$OPTARG
        printf '%16s %s\n'         "Override:" "-a, Minimum Age set to $MinimumAge days"
      else
        printf '\n%16s %s\n\n'   "Bad Option:" "-a, requires a number value for minimum age in days"
        exit 1
      fi
      ;;
    h) # HELP OPTION
      printf '\n%s\n\n'  "Usage: $SrceFileNm [-a #] [-h]"
      printf ' %s\n'   "-a: Override the minimum age in days"
      printf ' %s\n\n' "-h: Display this help message"
      exit 0
      ;;
    \?) # INVALID OPTION
      printf '\n%16s %s\n\n'     "Bad Option:" "-$OPTARG, Invalid (-h for help)"
      exit 1
      ;;
    :) # MISSING ARGUMENT
      printf '\n%16s %s\n\n'     "Bad Option:" "-$OPTARG, Requires an argument (-h for help)"
      exit 1
      ;;
  esac
done

# CHECK IF SCRIPT IS ARCHIVED
if [ ! -d "$SrceFolder/Archive/Scripts" ]; then
  mkdir -p "$SrceFolder/Archive/Scripts"
fi
if [ ! -f "$SrceFolder/Archive/Scripts/syno.embyupdate.v$SeuscrpVer.sh" ]; then
  cp "$SrceFllPth" "$SrceFolder/Archive/Scripts/syno.embyupdate.v$SeuscrpVer.sh"
else
  cmp -s "$SrceFllPth" "$SrceFolder/Archive/Scripts/syno.embyupdate.v$SeuscrpVer.sh"
  if [ "$?" -ne "0" ]; then
    cp "$SrceFllPth" "$SrceFolder/Archive/Scripts/syno.embyupdate.v$SeuscrpVer.sh"
  fi
fi

# GET EPOCH TIMESTAMP FOR AGE CHECKS
TodaysDate=$(date +%s)

# SCRAPE GITHUB FOR LATEST SCRIPT INFO
GitHubRepo=trailstack/syno.embyupdate
GitHubRawJson=$(curl -s -w '\n%{http_code}' -m "$NetTimeout" \
  "https://api.github.com/repos/$GitHubRepo/releases/latest")
GitHubHttpCode=$(echo "$GitHubRawJson" | tail -1)
GitHubJson=$(echo "$GitHubRawJson" | sed '$d')
if [ "$GitHubHttpCode" = "200" ]; then
  GitHubHeaders=$(curl -s -I -m "$NetTimeout" "https://api.github.com/repos/$GitHubRepo/releases/latest")
  SeusApiRlm=$(echo "$GitHubHeaders" | grep -i '^x-ratelimit-limit:' | awk '{print $2}' | tr -d '[:space:]')
  SeusApiRlr=$(echo "$GitHubHeaders" | grep -i '^x-ratelimit-remaining:' | awk '{print $2}' | tr -d '[:space:]')
  SeusApiMsg=$(printf '%s' "$GitHubJson" | jq -r '.message // "none"')
  SeusNewVer=$(printf '%s' "$GitHubJson" | jq -r '.tag_name' | sed 's/^v//')
  SeusRlDate=$(printf '%s' "$GitHubJson" | jq -r '.published_at')
  SeusRlDate=$(date --date "$SeusRlDate" +'%s')
  SeusRelAge=$(((TodaysDate-SeusRlDate)/86400))
  SeusDwnUrl=https://raw.githubusercontent.com/$GitHubRepo/v$SeusNewVer/syno.embyupdate.sh
  SeusRelDes=$(printf '%s' "$GitHubJson" | jq -r '.body // ""')
  SeusHlpUrl=https://github.com/$GitHubRepo/issues
else
  printf ' %s\n\n' "* UNABLE TO CHECK FOR LATEST VERSION OF SCRIPT.."
  ExitStatus=1
fi

# PRINT SCRIPT STATUS/DEBUG INFO
printf '%16s %s\n'      "Running Ver:" "$SeuscrpVer"

if [ "$SeusNewVer" = "null" ]; then
  printf "%16s %s\n" "GitHub API Msg:" "$(fold -w 72 -s     < <(printf '%s' "$SeusApiMsg") | sed '2,$s/^/                 /')"
  printf "%16s %s\n" "GitHub API Lmt:" "$SeusApiRlm connections per hour per IP"
  ExitStatus=1
elif [ "$SeusNewVer" != "" ]; then
  printf '%16s %s\n'     "Online Ver:" "$SeusNewVer (attempts left $SeusApiRlr/$SeusApiRlm)"
  printf '%16s %s\n'       "Released:" "$(date --rfc-3339 seconds --date @"$SeusRlDate") ($SeusRelAge+ days old)"
fi

# COMPARE SCRIPT VERSIONS
if [[ "$SeusNewVer" != "null" ]]; then
  if /usr/bin/dpkg --compare-versions "$SeusNewVer" gt "$SeuscrpVer"; then
    printf '%17s%s\n' '' "* Newer version found!"
    if [ "$SelfUpdate" -eq "1" ]; then
      if [ "$SeusRelAge" -ge "$MinimumAge" ]; then
        printf "\n"
        printf "%s\n" "INSTALLING NEW SCRIPT:"
        printf "%s\n" "----------------------------------------"
        /bin/wget -nv -O "$SrceFolder/Archive/Scripts/$SrceFileNm" "$SeusDwnUrl" 2>&1
        if [ "$?" -eq "0" ]; then
          cp -f -v "$SrceFolder/Archive/Scripts/$SrceFileNm" "$SrceFolder/Archive/Scripts/$SrceFileNm.cmp" 2>&1
          mv -f -v "$SrceFolder/Archive/Scripts/$SrceFileNm" "$SrceFolder/$SrceFileNm" 2>&1
          printf "%s\n" "----------------------------------------"
          cmp -s "$SrceFolder/Archive/Scripts/$SrceFileNm.cmp" "$SrceFolder/$SrceFileNm"
          if [ "$?" -eq "0" ]; then
            printf '%17s%s\n' '' "* Script update succeeded!"
            /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Syno.Emby Update\n\nSelf-Update completed successfully"}'
            ExitStatus=1
            if [ -n "$SeusRelDes" ]; then
              printf "\n"
              printf "%s\n" "RELEASE NOTES:"
              printf "%s\n" "----------------------------------------"
              printf "%s\n" "$SeusRelDes"
              printf "%s\n" "----------------------------------------"
              printf "%s\n" "Report issues to: $SeusHlpUrl"
            fi
          else
            printf '%17s%s\n' '' "* Script update failed to overwrite."
            /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Syno.Emby Update\n\nSelf-Update failed."}'
            ExitStatus=1
          fi
        else
          printf '%17s%s\n' '' "* Script update failed to download."
          /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Syno.Emby Update\n\nSelf-Update failed to download."}'
          ExitStatus=1
        fi
      else
        printf ' \n%s\n' "Update newer than $MinimumAge days - skipping.."
      fi
      find "$SrceFolder/Archive/Scripts" -type f -name "$SrceFileNm.cmp" -delete
    fi
  else
    printf '%17s%s\n' '' "* No new version found."
  fi
fi
printf "\n"

# SCRAPE SYNOLOGY HARDWARE MODEL
SynoHModel=$(< /proc/sys/kernel/syno_hw_version)
# SCRAPE SYNOLOGY CPU ARCHITECTURE
ArchFamily=$(uname -m)

# FIXES FOR INCONSISTENT ARCHITECTURE MATCHES
[ "$ArchFamily" = "i686" ]   && ArchFamily=x86
[ "$ArchFamily" = "armv7l" ] && ArchFamily=armv7

# SCRAPE DSM VERSION AND CHECK COMPATIBILITY
DSMVersion=$(grep -i "productversion=" "/etc.defaults/VERSION" | cut -d"\"" -f 2)
if /usr/bin/dpkg   --compare-versions "$DSMVersion" "ge" "6.0"    && /usr/bin/dpkg --compare-versions "$DSMVersion" "lt" "7"; then
  DSMmajor="6"
  DSMEmbyPrefix="emby-server-synology_"
elif /usr/bin/dpkg --compare-versions "$DSMVersion" "ge" "7"      && /usr/bin/dpkg --compare-versions "$DSMVersion" "lt" "7.2"; then
  DSMmajor="7"
  DSMEmbyPrefix="emby-server-synology7_"
elif /usr/bin/dpkg --compare-versions "$DSMVersion" "ge" "7.2"    && /usr/bin/dpkg --compare-versions "$DSMVersion" "lt" "8"; then
  DSMmajor="72"
  DSMEmbyPrefix="emby-server-synology72_"
else
  printf ' %s\n' "* Unsupported DSM version: $DSMVersion - exiting.."
  /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Emby Server\n\nSyno.Emby Update task failed. No coinciding Emby version identified for this version of Synology DSM."}'
  printf "\n"
  exit 1
fi

# CHECK IF DSM IS SUFFICIENT
if /usr/bin/dpkg --compare-versions "$MinDSMVers" gt "$DSMVersion"; then
  printf ' %s\n' "* Syno.Emby Update requires DSM $MinDSMVers minimum to install - exiting.."
  /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Emby Server\n\nSyno.Emby Update task failed. DSM not sufficient version."}'
  printf "\n"
  exit 1
fi
DSMVersion=$(grep -i "buildnumber="    "/etc.defaults/VERSION" | cut -d'"' -f 2 | { read -r build; printf '%s-%s' "$DSMVersion" "$build"; })
DSMUpdateV=$(grep -i "smallfixnumber=" "/etc.defaults/VERSION" | cut -d'"' -f 2)
if [ -n "$DSMUpdateV" ]; then
  DSMVersion="$DSMVersion Update $DSMUpdateV"
fi

# SCRAPE CURRENTLY RUNNING EMBY VERSION
RunVersion=$(/usr/syno/bin/synopkg version "EmbyServer")
RunVersion=$(echo "$RunVersion" | sed 's/-.*//')

# MAP CPU ARCHITECTURE TO EMBY SPK SUFFIX
# Emby publishes SPK packages with architecture-specific suffixes
case "$ArchFamily" in
  x86_64)             EmbyArchSuffix="_x86_64.spk" ;;
  aarch64)            EmbyArchSuffix="_armv8.spk" ;;
  armv7)              EmbyArchSuffix="_armv7_standalone.spk" ;;
  armada370)          EmbyArchSuffix="_armada370.spk" ;;
  armada375)          EmbyArchSuffix="_armada375.spk" ;;
  armadaxp)           EmbyArchSuffix="_armadaxp.spk" ;;
  armv5)              EmbyArchSuffix="_armv5.spk" ;;
  armv7_legacy)       EmbyArchSuffix="_armv7_legacy.spk" ;;
  hi3535)             EmbyArchSuffix="_hi3535.spk" ;;
  ppc)                EmbyArchSuffix="_ppc.spk" ;;
  comcerto2k)         EmbyArchSuffix="_comcerto2k.spk" ;;
  monaco)             EmbyArchSuffix="_monaco.spk" ;;
  i686)               EmbyArchSuffix="_x86.spk" ;;
  *)                  EmbyArchSuffix="_${ArchFamily}.spk" ;;
esac

# SCRAPE EMBY FOLDER LOCATION AND CREATE ARCHIVED PACKAGES DIR W/OLD FILE CLEANUP
EmbyFolder=$(readlink /var/packages/EmbyServer/shares/EmbyServer 2>/dev/null || echo "/var/packages/EmbyServer")

if [ -d "$EmbyFolder/Updates" ]; then
  mv -f "$EmbyFolder/Updates/"* "$SrceFolder/Archive/Packages/" 2>/dev/null
  if [ -n "$(find "$EmbyFolder/Updates/" -prune -empty 2>/dev/null)" ]; then
    rmdir "$EmbyFolder/Updates/"
  fi
fi
if [ -d "$SrceFolder/Archive/Packages" ]; then
  find "$SrceFolder/Archive/Packages" -type f -name "emby-server-synology*.spk" -mtime +"$OldUpdates" -delete
else
  mkdir -p "$SrceFolder/Archive/Packages"
fi

# SCRAPE EMBY RELEASES FROM GITHUB (latest STABLE release only, no betas)
EmbyRepo=MediaBrowser/Emby.Releases
# per_page=100 is plenty, then jq filters out prereleases and picks the newest stable
EmbyRawJson=$(curl -s -w '\n%{http_code}' -m "$NetTimeout" \
  "https://api.github.com/repos/$EmbyRepo/releases?per_page=100")
EmbyHttpCode=$(echo "$EmbyRawJson" | tail -1)
EmbyJson=$(echo "$EmbyRawJson" | sed '$d')

if [ "$EmbyHttpCode" = "200" ]; then
  # FILTER OUT PRERELEASES, PICK MOST RECENT STABLE
  EmbyJson=$(printf '%s' "$EmbyJson" | jq '[.[] | select(.prerelease == false)] | sort_by(.published_at) | last')
  # RATE LIMIT was already included in the HTTP response headers via curl -w
  # Fetch rate limit from same endpoint (HEAD only, no body)
  EmbyApiRlm=$(curl -s -I -m "$NetTimeout" "https://api.github.com/repos/$EmbyRepo/releases" \
    | grep -i '^x-ratelimit-limit:' | awk '{print $2}' | tr -d '[:space:]')
  EmbyApiRlr=$(curl -s -I -m "$NetTimeout" "https://api.github.com/repos/$EmbyRepo/releases" \
    | grep -i '^x-ratelimit-remaining:' | awk '{print $2}' | tr -d '[:space:]')

  # SCRAPE API ERRORS
  EmbyApiMsg=$(printf '%s' "$EmbyJson" | jq -r '.message // "none"')

  # SCRAPE VERSION AND RELEASE DATE
  EmbyNewVer=$(printf '%s' "$EmbyJson" | jq -r '.tag_name' | sed 's/^v//')
  EmbyRlDate=$(printf '%s' "$EmbyJson" | jq -r '.published_at')
  EmbyRlDate=$(date --date "$EmbyRlDate" +'%s' 2>/dev/null || echo "0")
  EmbyRelAge=$(((TodaysDate-EmbyRlDate)/86400))

  # FIND THE MATCHING SPK PACKAGE USING PREFIX + SUFFIX
  EmbyDwnUrl=$(printf '%s' "$EmbyJson" | jq -r --arg prefix "$DSMEmbyPrefix" --arg suffix "$EmbyArchSuffix" \
    '.assets[] | select(.name | startswith($prefix) and endswith($suffix)) | .browser_download_url')

  EmbyPackage="${EmbyDwnUrl##*/}"

  # CALCULATE PACKAGE AGE FROM RELEASE DATE
  PackageAge=$(((TodaysDate-EmbyRlDate)/86400))
else
  printf ' %s\n' "* UNABLE TO CHECK FOR LATEST VERSION OF EMBY SERVER.."
  printf "\n"
  ExitStatus=1
fi

# PRINT EMBY STATUS/DEBUG INFO
printf '%16s %s\n'         "Synology:" "$SynoHModel ($ArchFamily), DSM $DSMVersion"
printf '%16s %s\n'         "Emby Dir:" "$(fold -w 72 -s     < <(printf '%s' "$EmbyFolder") | sed '2,$s/^/                 /')"
printf '%16s %s\n'      "Running Ver:" "$RunVersion"
if [ "$EmbyNewVer" != "" ]; then
  printf '%16s %s\n'     "Online Ver:" "$EmbyNewVer (DSM $DSMmajor for $ArchFamily)"
  printf '%16s %s\n'       "Released:" "$(date --rfc-3339 seconds --date @"$EmbyRlDate") ($PackageAge+ days old)"
else
  printf '%16s %s\n'     "Online Ver:" "Nonexistent (DSM $DSMmajor for $ArchFamily)"
  printf '%16s %s\n'     "Package Match:" "Prefix: $DSMEmbyPrefix | Suffix: $EmbyArchSuffix"
  ExitStatus=1
fi

# COMPARE EMBY VERSIONS
if [ -n "$EmbyNewVer" ] && /usr/bin/dpkg --compare-versions "$EmbyNewVer" gt "$RunVersion"; then
  printf '%17s%s\n' '' "* Newer version found!"
  printf "\n"
  printf '%16s %s\n'    "New Package:" "$EmbyPackage"
  printf '%16s %s\n'    "Package Age:" "$PackageAge+ days old ($MinimumAge+ required for install)"
  printf "\n"

  # DOWNLOAD AND INSTALL THE EMBY UPDATE
  if [ "$PackageAge" -ge "$MinimumAge" ]; then
    printf "%s\n" "INSTALLING NEW PACKAGE:"
    printf "%s\n" "----------------------------------------"
    printf "%s\n" "Downloading Emby Server package:"
    if [ -f "$SrceFolder/Archive/Packages/$EmbyPackage" ]; then
      printf "%s\n" "* Package already exists in local Archive"
    fi
    /bin/wget -nv -c -nc -P "$SrceFolder/Archive/Packages/" "$EmbyDwnUrl" 2>&1
    if [ "$?" -eq "0" ]; then
      printf "\n%s\n"   "Stopping EmbyServer service (JSON):"
      /usr/syno/bin/synopkg stop    "EmbyServer"
      printf "\n%s\n" "Installing EmbyServer update (JSON):"
      /usr/syno/bin/synopkg install "$SrceFolder/Archive/Packages/$EmbyPackage" | \
        jq -c '.results[] |= (
          if (.scripts // empty) | type == "array" then
            .scripts |= map(
              if .message then
                .message |= (
                  gsub("<[^>]*>"; "")     # Strip HTML
                  | split("\n")[0]        # Keep only the first real line
                )
              else . end
            )
          else .
          end
        )'
      printf "\n%s\n" "Starting EmbyServer service (JSON):"
      /usr/syno/bin/synopkg start   "EmbyServer"
    else
      printf '\n %s\n' "* Package download failed, skipping install.."
    fi
    printf "%s\n" "----------------------------------------"
    printf "\n"
    NowVersion=$(/usr/syno/bin/synopkg version "EmbyServer")
    printf '%16s %s\n'  "Update from:" "$RunVersion"
    printf '%16s %s'             "to:" "$EmbyNewVer"

    # REPORT EMBY UPDATE STATUS
    if /usr/bin/dpkg --compare-versions "$NowVersion" gt "$RunVersion"; then
      printf ' %s\n' "succeeded!"
      printf "\n"
      /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Emby Server\n\nSyno.Emby Update task completed successfully"}'
      ExitStatus=1
    else
      printf ' %s\n' "failed!"
      /usr/syno/bin/synonotify PKGHasUpgrade '{"%PKG_HAS_UPDATE%": "Emby Server\n\nSyno.Emby Update task failed. Installation not newer version."}'
      ExitStatus=1
    fi
  else
    printf ' %s\n' "Update newer than $MinimumAge days - skipping.."
  fi
else
  if [ -n "$EmbyNewVer" ]; then
    printf '%17s%s\n' '' "* No new version found."
  fi
fi

printf "\n"

# CLOSE AND NORMALIZE THE LOGGING REDIRECTIONS
exec >&- 2>&- 1>&2

# EXIT NORMALLY BUT POSSIBLY WITH FORCED EXIT STATUS FOR SCRIPT NOTIFICATIONS
if [ -n "$ExitStatus" ]; then
  exit "$ExitStatus"
fi
