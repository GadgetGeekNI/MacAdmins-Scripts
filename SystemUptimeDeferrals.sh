#!/bin/sh
#Uptime monitoring Using Jamf Helper. Written for Example by the local bash wizard. 
#This script will prompt the user to pick a reboot time if their uptime is over the threshold ($uptimeTolerance), they are able to defer this notification 5 times,
# Each time the deferral is triggered it will let the IT Team know with a Slack notification, this can be silenced easily if required. 
# When a reboot time is selected, it will give the user a closable countdown window.
# This is mainly for my own testing, as the script is scoped against a Jamf smart group to minimize network traffic, but it can be adjusted to whatever value to trigger the script off. 
uptimeTolerance=7

#set max amount of deferrals a user can make
maxDeferrals=5

# Send Slack Notification after set amount of deferrals
notifyDeferral=1

# Org Name for defaults
orgName=example

# Slack Webhook ID
slackHook=12345

# General Variables for the Notification Window
window="utility"
title="Information Systems Uptime Monitor"
heading="Please restart your computer"
timeout="7200"
# Default Reboot Icon
icon="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/Resources/Restart.png"
# Hard Nag Description
harddescription='You have now reached the maximum amount of deferrals available. 

You must now restart or pick a time period for your mac to restart today. 

Ensure that your work is saved before restarting.'

# Countdown Variables
countdownwindow="hud"
countdownheading="Thank you for choosing to reboot your Macbook!"
countdowndescription="Thank you for complying and selecting a time for your macbook to reboot. We recommend keeping this tab open to ensure that you do not forget the time you have committed to.
As this countdown timer nears its completion we recommend you save all work in preparation.
This is the only reminder of your accepted restart that you will receive."
# Countdown Icon
countdownicon="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/Resources/Message.png"

#Slack Variables for Cancellation or Deferral Monitoring
Hostname=$(hostname -f)
LoggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )

sendSlackNotificationDeferral () {
  curl -X POST --data-urlencode 'payload={"channel": "#is_jamfalerts", "text": "Hi there! '$LoggedInUser's machine, '$Hostname' has not been restarted in over '$uptime' days. This is a courtesy notification to tell you that they were asked to reboot and opted to defer the prompt. They have '$remainingDeferrals' deferrals left. Reach out to the user if required. "}' https://hooks.slack.com/services/"$slackHook"
}

sendSlackNotificationForceQuit () {
  curl -X POST --data-urlencode 'payload={"channel": "#is_jamfalerts", "text": "Hi there! '$LoggedInUser's machine, '$Hostname' has not been restarted in over '$uptime' days. This is a notification to tell you that they were force prompted to reboot but they force quit the promot via activity monitor. Please reach out to this user. "}' https://hooks.slack.com/services/"$slackHook"
}

## Path to Log file. Map your own Log Path.  Do not use /tmp as it is emptied on boot.
LogPath=/Library/Logs/"$orgName"

##Verify LogPath exists
if [ ! -d "$LogPath" ]; then
mkdir $LogPath
fi

## Set log file and console to recieve output of commands
Log_File="$LogPath/RebootDefer.log"
function sendToLog ()
{

echo "$(date +"%Y-%b-%d %T") : $1" | tee -a "$Log_File"

}

## begin log file
sendToLog "Script Started"

######### End Create settings for logging and create log file #########

######### Start the hard work ############

##Check to make sure general $icon path is real
if [ ! -e "$icon" ]; then
	icon="/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources/SoftwareUpdate.icns"
fi
##Check to make sure countdown $icon path is real
if [ ! -e "$countdownicon" ]; then
	icon="/System/Library/CoreServices/Install Command Line Developer Tools.app/Contents/Resources/SoftwareUpdate.icns"
fi
## Ensure that the end user does not alter the defaultDeferrals to circumvent this script and the deferral counter by writing its value every time before the rest of the script executes.
if [ -z "$4" ]; then
	deferral="NotSpecified"
	defaults write com."$orgName".UptimeMonitor.Deferral defaultDeferrals $maxDeferrals
	echo "Max Deferrals set to $maxDeferrals"
else
## This value can be set in Jamf if we want to override it. Otherwise it'll follow script logic to return default.
	deferral="$4"
	defaults write com."$orgName".UptimeMonitor.Deferral defaultDeferrals $4
	echo "Max Deferrals set to '$4"
fi
if [ $deferral = "NotSpecified" ];then
	##Calculate remaining deferrals
	##Check the Plist and find remaining deferrals from prior executions
    remainingDeferrals=$(defaults read com."$orgName".UptimeMonitor.Deferral remainingDeferrals)
	##Check that remainingDeferrals isn't empty (aka pulled back an empty value), if so set it to $maxDeferrals
	if [ -z $remainingDeferrals ]; then
        defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $maxDeferrals
		remainingDeferrals=$maxDeferrals
		echo "Deferral has not yet been set. Setting to Max Deferral count and pulling back remainingDeferral value."
    fi
	##Check if $remainingDeferrals returns a nonzero string. (Ensuring it is already set)
	if [ -n "$remainingDeferrals" ]; then
			echo "Remaining Deferral value of $remainingDeferrals is already set. Continuing"
	else
		if [[ $remainingDeferrals -le $maxDeferrals ]]; then
			deferral=$remainingDeferrals
			echo "Remaining Deferrals was less than Max. Continuing."
		else
			deferral=$maxDeferrals
			"Deferral logic flawed. Deferral set back to Max Deferrals."
		fi
	fi
fi

##Sanity Check that they didn't reboot today before this script popped up. If it is now below the threshold, Jamf recon will run and update the smart group before exiting the script and reset their Deferral count back to 0.
# Pull days active or 0 if days isn't a returned value.
uptime=$(uptime | awk '{if ($4 ~ /days/ || $4 ~ /day/) { print $3 } else { print 0 }}')
echo "This machine has been up for $uptime day/s"
sendToLog="System Uptime is 
	$uptime
"
if [[ $uptime -le $uptimeTolerance ]]; then
	echo "System Uptime is $uptime which is less than the tolerated threshold of $uptimeTolerance."
	sendToLog "Uptime is now less than the threshold.  Exiting"
	defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $maxDeferrals
	jamf recon
	exit 0
else
	echo "Uptime is greater than or equal to $uptimeTolerance days. Script will be run"
fi 

if [ $remainingDeferrals -le "0" ]; then
	##No deferrals left
	sendToLog "No deferrals left. Starting Hard Nag Prompt"

	##prompt the user
	hardnag=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType "$window" -title "$title" -heading "$heading" -description "$harddescription" -icon "$icon" -button2 "Restart" -showDelayOptions "0, 60, 300, 3600, 7200, 14400, 28800" -countdown -countdownPrompt "This will automatically timeout in " -timeout "$timeout")
	buttonClicked="${hardnag:$i-1}"
    timeChosen="${hardnag%?}"

    ## Convert seconds to minutes for restart command
    timeMinutes=$((timeChosen/60))

    ## Echoes for troubleshooting purposes
    echo "Button clicked was: $buttonClicked"
    echo "Time chosen was: $timeChosen"
    echo "Time in minutes: $timeMinutes"

	if [[ -z $hardnag ]];then
		#User force closed the prompt.
		remainingDeferrals=$(( $remainingDeferrals - 1 ))
		defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $remainingDeferrals
		echo "Hard Nag prompt was force exited."
		sendSlackNotificationForceQuit
		exit 0
	elif [[ "$buttonClicked" == "2" ]] && [[ ! -z "$timeChosen" ]]; then
		##User elected to restart or the timer ran out after 4 hours.  Kicking off Apple update script
		sendToLog "Starting Restart function"
		echo "Restart button was clicked. Initiating restart in $timeMinutes minutes"
        defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $maxDeferrals
        shutdown -r +${timeMinutes}
		# Friendly countdown that can be exited if desired by the end user to remind them of how long they have before a system shutdown.
		rebootcountdown=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType "$countdownwindow" -title "$title" -heading "$countdownheading" -description "$countdowndescription" -icon "$countdownicon" -countdown -countdownPrompt "Time until reboot " -timeout "$timeChosen")
		exit 0
    elif [[ "$buttonClicked" == "2" ]] && [[ -z "$timeChosen" ]]; then
    	##User elected to restart their mac immediately.
		sendToLog "Starting Restart function"
		echo "Restart button was clicked. Initiating immediate restart."
        defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $maxDeferrals
		shutdown -r now
		exit 0
	elif [[ $hardnag = 239 ]]; then
		#User either force closed the prompt.
		remainingDeferrals=$(( $remainingDeferrals - 1 ))
		defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $remainingDeferrals
		echo "Hard Nag prompt was force exited."
		sendSlackNotificationForceQuit
		exit 0
	else
		##Something unexpected happened.  I don't really know how the user got here, but for fear of breaking things or abruptly rebooting computers we will set a flag for the mac in Jamf saying something went wrong.
		echo "Something went wrong. Exiting with error."
		sendToLog "Something went wrong, the prompt equalled $hardnag"
		exit 1
	fi
else
	description="Your computer has not been restarted in at least $uptime days. A more frequent restart is recommended.

Doing so optimizes the performance of your computer as well as allows us to deploy security updates or new applications to you automatically.

You may defer this notification up to 5 times, repetitive deferrals are monitored by the IS team. You have $remainingDeferrals Deferrals left before you are unable to cancel this prompt.

Please select a time that is convenient for you to restart your machine."
	##User has a chance for deferral.
	sendToLog "Soft Nag starting. Remaining Deferral count is $remainingDeferrals"
	##prompt the user
	softnag=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType "$window" -title "$title" -heading "$heading" -description "$description" -icon "$icon" -button2 "Restart"  -showDelayOptions "0, 60, 300, 3600, 7200, 14400, 28800" -button1 "Defer Restart" -cancelButton 1 -countdown -countdownPrompt "This will automatically timeout in " -timeout "$timeout")
	
	##User has a chance for deferral.
	##Map time variables
    buttonClicked="${softnag:$i-1}"
    timeChosen="${softnag%?}"

    ## Convert seconds to minutes for restart command
    timeMinutes=$((timeChosen/60))

	if [[ -z $softnag ]];then
		#User force closed the prompt.
		remainingDeferrals=$(( $remainingDeferrals - 1 ))
		defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $remainingDeferrals
		sendSlackNotificationForceQuit
		exit 0
	elif [[ "$buttonClicked" == "2" ]] && [[ ! -z "$timeChosen" ]]; then
		##User elected to restart or the timer ran out after 4 hours.  Kicking off Apple update script
		sendToLog "Starting Restart function"
		echo "Restart button was clicked. Initiating restart in $timeMinutes minutes"
        defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $maxDeferrals
        shutdown -r +${timeMinutes}
		# Friendly countdown that can be exited if desired by the end user to remind them of how long they have before a system shutdown.
		rebootcountdown=$("/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType "$countdownwindow" -title "$title" -heading "$countdownheading" -description "$countdowndescription" -icon "$countdownicon" -countdown -countdownPrompt "Time until reboot " -timeout "$timeChosen")
		exit 0
    elif [[ "$buttonClicked" == "2" ]] && [[ -z "$timeChosen" ]]; then
    	##User elected to restart their mac immediately.
		sendToLog "Starting Restart function"
		echo "Restart button was clicked. Initiating immediate restart."
        defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $maxDeferrals
        shutdown -r now
		exit 0
	elif [[ "$buttonClicked" = "1" ]]; then
		#User either force closed the prompt, or choose the deferral option.
		sendToLog "Deferral was chosen."
		remainingDeferrals=$(( $remainingDeferrals - 1 ))
		defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $remainingDeferrals
		echo "Deferral option was chosen. Remaining Deferral count is now $remainingDeferrals"
		if [[ "$remainingDeferrals" -le "$notifyDeferral" ]]; then
		sendSlackNotificationDeferral
		fi
		exit 0
	elif [[ "$softnag" = 239 ]]; then
		#User either force closed the prompt.
		remainingDeferrals=$(( $remainingDeferrals - 1 ))
		defaults write com."$orgName".UptimeMonitor.Deferral remainingDeferrals $remainingDeferrals
		echo "Hard Nag prompt was force exited."
		sendSlackNotificationForceQuit
		exit 0
	else
		##Something unexpected happened.  I don't really know how the user got here, but for fear of breaking things or abruptly rebooting computers we will set a flag for the mac in Jamf saying something went wrong.
		sendToLog "Something went wrong, the prompt equalled $softnag"
		exit 1
	fi
fi

exit

# WIP Below
#time="0200"
#tomorrow=$(date -v+1d +%y%m%d)
#echo "Tomorrow's date is $tomorrow. Shutdown time is $time."
# Staging above for "Try for tomorrow button"
