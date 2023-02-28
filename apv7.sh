#!/bin/bash
# -------------------------------------------------------------------------
# Modified by Pete ...
# Version 01 24-Nov-2012 to read line-by-line from file check_macs.txt
# And then print a line telling me how long it's been since that MAC
# address has been seen and what it's common name is.
#
# Version 02 combines parts of the old clreadtemp6.sh and apread.sh into one super
# script. Purpose is to instead of targeting individual MACs we already have
# knowledge of, why not see who attaches to to the AP and begin tracking them?
# The advantage is less clerical work keeping track of MACs, among others.
#
# Newest and latest 25-Jan-2013 with robustness and other improvements, but
# probably needs a sandbox sub directory to help with marker file sprawl.
#
# No longer barfs when 00:0F:B5:39:F3:FF or any other MAC appears twice in
# the .csv
#
# Attempting re-writes to simplfify code, and calling this scanv2.sh 27-Jan-2013.
#
# 29-Jan-2013:
# added hook to detect and correct Roam-Away false positive alerts
# fixed +Back alerts displaying incorrect ELAPSEDMINS in e-mails
# added hook to detect first pass and initialize *_is_fresh.txt contents to 0
# killed off TEMPMINS variable - obsolete
# added hook to SENDEMAILALERT testing for 0 in PREVIOUSMINS
# fixed POWER populating PREVIOUSPOWER so that now it is correct
#
# 31-Jan-2013:
# Bugging me was the error encoutnered for not closing a curly brace, found and fixed.
# The _last_seen.txt marker now contains the full date, like 2013-01-02 01:02:34
# Seems like all new arrival mobiles hit the Roamed-Here section, not the Newly-Arrived ... fix?
# At least the Roamed-Here section now echos LEGACYDAYS, hours and minutes.
# Added LEGACYMINS, hours and days to help with Back comprehension.
# Re-worked the SENDEMAILALERT adding hooks galore. This will have to be tested to see if
# the message -m parm chokes on values that are zeros - even though I have taken countermeasures.
# Last power and last data officially deprecated now.
# 
# 3-Jan-2014:
# This script is known as non.sh because it's been written to track the non-associated
# MAC addresses in the radio environment and tell me how long since we have seen them.
#
# 17-Apr-2014:
# Changes include adding captures to newly-arrived section grabbing Crypto and Power.
# Also armed triggers when detecting Crypto has changed for an AP.
# 
# Moved output files into sandbox sub directoy to deal with file sprawl.
#
# 21-Apr-2015:
# Since when building the _attached.txt file you could find partial MAC addresses, such as :26:4B:32:70:A2 which will trip the HUNG code,
# stopping the script, new checks are placed by defining FILESIZE1= and MODFILESIZE1= variables which verify, at a primitive level, the
# contents of the _attached.txt file are sane.
#
# 10-Aug-2015:
# Minor enhancement to remove trailing space from the oui_custom.txt return.
# Like this:
# MACSTRING=$(egrep $SHORTMAC $HOMEP/oui_custom.txt | awk '{ print $2" "$3" "$4" "$5" "$6" "$7}' | sed -e 's/[[:space:]]*$//')
#
# 22-Aug-2015:
# Minor fix to improve readability of the HUNG message sent to master_log.txt
#
# 1-Sep-2015:
# Quashed a minor bug that was introducing extra <P> into the e-mail report stream, caused by poor Channel change detection reporting code.
#
# 6-Sep-2015:
# Added day indication to master_log.txt output
#
# 10-Sep-2015:
# Added code to capture historical data in the $SANDBOXAP/MAC_history.txt file.
#
# 18-Sep-2015:
# Idea is to send a text when the AP's ESSID (it's name as announced by the beacon packet) legitimately changes.
#
# 25-Sep-2015:
# Some false positives for Identity change fixed. Now we measure the length of the old and new ESSID to figure out if we should send a text message.
# 15-Oct-2015:
# Some false positives had been slipping through the flawed logic. Hopefully now fixed.
#
# 5-Oct-2015:
# Reached a point where ALL the APs airodump reports it has found are now being process by this script!
# Found a stackoverflow article "printing lines which have a field number greater than in awk" that shows how to do this.
# So yes, we can key on field 4 which for APs always has a number greater than zero, and for clients, is the power measurement, always less than zero.
#
# 20-Apr-2016:
# Since more and more vehicles have built in WiFi APs, yes access points, I'm scaling the gone window down to 60 minutes attempting to catch some of
# these hit-and-run APs that could be flying past my antennas. This is obviosly a huge assumption shift from original coding.
#
# 3-Jun-2016:
# Added a blacklist.txt hook in the Identity section that will inhibit reprting and texting if a change is discovered for a blacklisted AP.
#
# 11-Sep-2016:
# Minor cleanup of the format of text messages. Namely, I removed sendEmail -u option which just adds needless "Subject:" to a text message.
#
#  1-Oct-2016:
# Bye bye Sprint, we're on Cricket wireless. Changes needed for TXT alerts.
#
#  8-Jan-2017:
# Removed the if $CLIENTMARKER hook from Gone and Back detect section. In the case the script is not running and cannot detect and properly set the
# $CLIENTMARKER variable, later on when an AP returns, it cannot detect the Back condition. Likewise, it cannot properly detet and set Gone condition.
#
# 15-Oct-2017
# Added CHECKFORPAUSE and CHECKFORSTOP sub-routines.
#
# 19-Feb-2019:
# Minor formatting tweak for the weedout algorithm.
#
# 21-Nov-2019:
# Minor change to file checksum section, shortened interval to 3 total seconds(was 4).
#
# 07-Mar-2020:
# Copied from apv4.sh to apv6.sh with mods to the sendSMS and spped-up the sleep timers.
#

SENDEMAILALERT ()
{
   if [ "$EVENTTYPE" == "Back" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), last seen $LEGACYDAYS$DAY $LEGACYMODHOURS$HOUR $LEGACYMODMINS$MIN ago by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), last seen $LEGACYDAYS$DAY $LEGACYMODHOURS$HOUR $LEGACYMODMINS$MIN ago by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "Gone" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T) thrsh $QUIETTHRESH$MIN, elapsed $ELAPSEDMINS$MIN by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T) thrsh $QUIETTHRESH$MIN elapsed $ELAPSEDMINS$MIN by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "Newly-Arrived" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, BSSID '$CURRENTESSID', Ch '$CURRENTCHANNEL', Power '$CURRENTPOWER', Crypto $CURRENTCRYPTO, first seen $MONTH2/$DAY2/$YEAR2  $HOUR2:$MIN2:$SEC2, by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, Ch $CURRENTCHANNEL, Power '$CURRENTPOWER', Crypto $CURRENTCRYPTO, first detected $MONTH2/$DAY2/$YEAR2 $HOUR2:$MIN2:$SEC2, by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "Roamed-Here" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, Ch $CURRENTCHANNEL, Power '$CURRENTPOWER', Crypto $CURRENTCRYPTO, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, Ch $CURRENTCHANNEL, Power $CURRENTPOWER, Crypto $CURRENTCRYPTO, $(date +%D) $(date +%T), by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "Roamed-Away" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, from $SSID, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, from $SSID, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "undefined" ] ; then
      MESSAGE="$SCRIPTNAME Sad for you ... we got here somehow without defining the event ... Bye from $HOSTNAME"
      echo "$SCRIPTNAME Sad for you ... we got here somehow without defining the event ... Bye from $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "DEAD-MEAT" ] ; then
      MESSAGE="$SCRIPTNAME Sad for you ... we got here since insane data still rules the day ... Bye from $HOSTNAME"
      echo "$SCRIPTNAME Sad for you ... we got here since insane data still rules the day ... Bye from $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "HUNG" ] ; then
      MESSAGE="$SCRIPTNAME Sad for you ... we got here since insane data still rules the day ... Looping at $HOSTNAME"
      echo "$SCRIPTNAME Sad for you ... we got here since insane data still rules the day ... Looping at $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   if [ "$EVENTTYPE" == "BADD" ] ; then
      MESSAGE="$SCRIPTNAME Sad for you ... we got here since insane data namely elapsed days = $ELAPSEDDAYS still rules the day ... Looping at $HOSTNAME"
      echo "$SCRIPTNAME Sad for you ... we got here since insane data namely elapsed days = $ELAPSEDDAYS still rules the day ... Looping at $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
      echo $LASTSEENDATE > $SANDBOXAP/$F1"_last_seen.txt"
      echo "Just wrote $LASTSEENDATE to this APs _last_seen.txt file."
   fi
   # New code added 7-Jan-2014 for alerting of changes to the channel AP is broadcasting on...
   if [ "$EVENTTYPE" == "Channel" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, new $NEWCHANNEL1, old $CURRENTCHANNEL, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, new $NEWCHANNEL1, old $CURRENTCHANNEL, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      CHECKBLACKLIST
      if [ "$ISMACBLACKLISTED" == "NO" ] ; then
         echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
         # echo "\n\n" >> $HOMEP/"$HOSTNAME".txt
         echo "<P>" >> $HOMEP/"$HOSTNAME".txt
      fi
      # echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   # New code added 17-Apr-2014 for alerting of changes to the crypto AP is broadcasting ...
   if [ "$EVENTTYPE" == "Crypto" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME '$F2', OUI $MACSTRING, new $NEWCRYPTO1, old $CURRENTCRYPTO, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F2, OUI $MACSTRING, new $NEWCRYPTO1, old $CURRENTCRYPTO, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi
   # New code added 18-Apr-2014 for alerting of changes to the BSSID AP is broadcasting ...
   if [ "$EVENTTYPE" == "Identity" ] ; then
      MESSAGE="$EVENTTYPE $SCRIPTNAME $F1, OUI $MACSTRING, new '$NEWESSID1', old '$CURRENTESSID', $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo "$EVENTTYPE $SCRIPTNAME $F1, OUI $MACSTRING, new $NEWESSID1, old $CURRENTESSID, $((10#$(date +%m) + 0))/$((10#$(date +%d) + 0))/$(date +%Y) $(date +%T), by $HOSTNAME"
      echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
      CHECKBLACKLIST
      if [ "$ISMACBLACKLISTED" == "NO" ] ; then
         echo $MESSAGE >> $HOMEP/"$HOSTNAME".txt
         # echo "\n\n" >> $HOMEP/"$HOSTNAME".txt
         # echo "<P>" >> $HOMEP/"$HOSTNAME".txt
      fi
      echo "<P>" >> $HOMEP/"$HOSTNAME".txt
   fi

}

sendTEXTMESSAGE () {

   echo "Special event: so sending a text..."
   # Lesson learned: never place a variable that could be zero like ELAPSEDMINS in the -m field of sendEmail - it barfs.

}

date2stamp () {
    date --utc --date "$1" +%s
}

stamp2date (){
    date --utc --date "1970-01-01 $1 sec" "+%Y-%m-%d %T"
}

dateDiff (){
    case $1 in
        -s)   sec=1;      shift;;
        -m)   sec=60;     shift;;
        -h)   sec=3600;   shift;;
        -d)   sec=86400;  shift;;
        *)    sec=86400;;
    esac
    dte1=$(date2stamp $1)
    dte2=$(date2stamp $2)
    diffSec=$((dte2-dte1))
    if ((diffSec < 0)); then abs=-1; else abs=1; fi
    echo $((diffSec/sec*abs))
}
CHECKBLACKLIST (){
   cat $HOMEP/blacklist.txt | grep $F1
   RC=$?
   case $RC in
      0)   ISMACBLACKLISTED=YES; echo "This MAC $F1 <==> $F2 is blacklisted, event will not report in e-mail." ;;
      1)   ISMACBLACKLISTED=NO;;
   esac
}


#######################################################################################
weedOutLine()
{
   line="$@" # get all args
   # UNKNOWNMAC=0

   # F1 is simply the MAC address of the mobile
   # getCURRENTDATE
   APLASTSEENDATEFROMCSV=$(echo $line | awk -F" " '{ print $2, $3 }')
   APLASTSEENMINUTESAGOFROMCSV=$(dateDiff -m $CURRENTDATE $APLASTSEENDATEFROMCSV)
   F1=$(echo $line | awk -F" " '{print $1}')
   if [ ! -e $SANDBOXAP/$F1"_is_fresh.txt" ] ; then
      echo "1" > $SANDBOXAP/$F1"_is_fresh.txt"
      echo -n "B"
      # exit 0
   fi
   CLIENTMARKER=$(cat $SANDBOXAP/$F1"_is_fresh.txt")
   if ( [ $APLASTSEENMINUTESAGOFROMCSV -lt $WEEDOUTTHRESH ] || [ $CLIENTMARKER -eq 1 ] ) ; then
      # echo -n "$CLIENTMARKER"
      if [ "$CLIENTMARKER" == "" ] ; then
         CLIENTMARKER=1
      fi
      # if [ $CLIENTMARKER -eq 1 ] ; then
         echo $line >> $SANDBOXAP/"$NOTASSOC".txt
         echo -n "+"
         # echo -n " "
      # fi
   else
   echo -n "-"
   # echo -n " "
   fi
   if [ $FIRSTPASS -eq 0 ] ; then 
      # If this is the first pass, then go quickly, otherwise for all subsequent passes, go more slowly...
      sleep 0.110000
   fi   
}
#######################################################################################

getCURRENTDATE (){

   CURRENTDATE1="2014-10-18 22:16:30"
   CURRENTDATE2="2014-10-18 22:16:31"
   # LASTSEENDATE=$(awk '{ print $1 }' $SANDBOXAP/$MAC"_last_seen.txt")
   # LEGACYDATE=$(cat $SANDBOXAP/$MAC"_last_seen.txt")
   # LASTSEENDATE=$(cat $SANDBOXAP/$MAC"_last_seen.txt")
   # echo "Entering getCURRENTDATE until loop..."
   until [ "$CURRENTDATE1" == "$CURRENTDATE2" ] ; do
      CURRENTDATE1="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
      sleep 0.25000
      # echo "In the middle of getCURRENTDATE until loop..."
      CURRENTDATE2="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
   done
   # echo "Exiting getCURRENTDATE until loop..."
   CURRENTDATE=$CURRENTDATE1
}

#######################################################################################

CHECKFORPAUSE ()
{
while [ -e ./pause ] ; do
   echo "--$HOSTNAME box locally paused, delete to continue"
   isPauseDetected=YES
   sleep 5
done # Checking for pause
# if [ "$isPauseDetected" == "YES" ] ; then
#    echo "We want to slowly exit pause mode..."
#    sleep 15
#    isPauseDetected=NO
# fi

while [ -e $HOMEP/pause ] ; do
   echo "--$HOSTNAME box globaly paused, delete to continue"
   sleep 5
done # Checking for pause
# echo "--Pause no longer detected, sleeping 30 secs..."
# sleep 30
}

CHECKFORSTOP ()
{
if [ -e ./stop ] ; then
   echo "--$HOSTNAME box locally file stop1 detected, so stoppping ..."
   exit 0
fi

if [ -e $HOMEP/stop ] ; then
   echo "--$HOSTNAME box globaly file stop1 detected, so stoppping ..."
   exit 0
fi
}

processLine()
{
   # echo -n "."
    line="$@" # get all args

   # F1 is simply the MAC address of the mobile
   F1=$(echo $line | awk '{ print $1 }')

   # CURRENTCHANNEL is simply the channel the AP is broadcasting on right now...
   CURRENTCHANNEL=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $4 }')
   CURRENTCHANNEL=CURRENTCHANNEL+0
   # echo "$F1 found at $CURRENTCHANNEL, moving on..."

   # F2 is the common name we think the MAC really is, as recorded in file ./check_macs.txt
   F2=$(cat $HOMEP/check_macs.txt | grep -ai $F1 | awk '{ print $2 }' | sed -e 's/^ *//' -e 's/^ *$//')
   if ( [ "$F2" == "" ] && [ -e $SANDBOXAP/$F1"_current_essid.txt" ] ) ; then 
      # echo "Our MAC = $F1 does exist in the sandbox-ap file..."
      F2=$(cat $SANDBOXAP/$F1"_current_essid.txt")
   fi   
   if [ "$F2" == "" ] ; then
      # echo "Our MAC = $F1 was not found in our custom database of known MACs..."
      F2=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $14 }' | sed -e 's/^ *//' -e 's/^ *$//')
   fi
   if [ "$F2" == " " ] ; then
      # echo "Our MAC = $F1 was not found in our custom database of known MACs nor was it captured correctly in the csv file..."
      F2=$F1"_unkMAC"
   fi

   # Now dip into our custom OUI databse for another method to determine who the mobile is.
   SHORTMAC=${F1:0:8}
   MACSTRING=$(cat $HOMEP/oui_custom.txt | grep -i $SHORTMAC | awk '{ print $2" "$3" "$4" "$5" "$6" "$7}' | sed -e 's/[[:space:]]*$//')

   if [ "$MACSTRING" == "" ] ; then
      # echo "Our MAC = $F1 was not found in the custom OUI database..."
      # MACSTRING=$F1"_unkOUI"
      # Following line changed 5-Oct-2015 to shorten the unknown OUI reporting
      MACSTRING=$SHORTMAC"_unkOUI"
      # echo "So we will use $MACSTRING for the OUI descriptor."
      cat $UNKNOWNOUIFILE | grep $SHORTMAC
      RC=$?
      if [ $RC -eq 1 ] ; then 
         echo $SHORTMAC >> $HOMEP/unkOUI.txt
      fi   
   fi

   # First thing to do is estbalish persistnece for the client. We do this by setting
   # a marker file in the sandbox directory which will contain a 0 or 1. If the file
   # contains a 0 that means the leave threshold has been exceeded. If the the file
   # contains 1 that means the client has been seen within the threshold setting, and
   # he is considered nearby.
   touch $SANDBOXAP/$F1"_is_fresh.txt"
   # touch $SANDBOXAP/$F1"_last_seen.txt"

   # Next thing is to initialize the current channel and new channel markers.
   # Added this line 7-Jan-2014...
   touch $SANDBOXAP/$F1"_current_channel.txt"

   # This line inits the freshness to zero for all mobiles...
   # echo "0"  > $SANDBOXAP/$F1"_is_fresh.txt"
   # The wisdom of dipping into the _is_fresh variable so early is under review...
   CLIENTMARKER=$(cat $SANDBOXAP/$F1"_is_fresh.txt")
   # echo "      New freshness ClientMarker variable found to be: $CLIENTMARKER"

   # The following lines grab the Last seen minute and last seen hour from the .csv file for the mobile...
   # Sadly the data can be erratic, insane, so we first use SHORTMIN and SHORTHOUR and truncate any garbage.

   # SHORTMIN=$(awk -F, '{print $0}' $1 | grep -ai $F1 | awk -F"[ ]" '{print $5}' | awk -F: '{print $2}')
   # MINUTE1=${SHORTMIN:0:2} # Truncate away any garbage that might be appended
   # echo "Prior to entering the do-until loop, MINUTE1 is $MINUTE1."

   # SHORTHOUR=$(awk -F, '{print $0}' $1 | grep -ai $F1 | awk -F"[ ]" '{ print $5}' | awk -F: '{print $1}')
   # HOUR1=${SHORTHOUR:0:2} # Truncate away any garbage that might be appended
   # echo "Prior to entering the do-until loop, HOUR1   is $HOUR1."

   # The following lines grab last seen power and last seen data from the .csv file for the mobile...
   # Sadly erratic, we have to test for newline characters in our data...

   # echo "Grab Power..."
   # echo $POWER > $SANDBOXAP/$F1"_last_powr.txt"
   # POWER=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk '{ print $6 }' | awk -F, '{ print $1}')                        
   # echo "Got Power?"
   # for a in "$POWER"; do
   #    while [[ "$a" != '\012' ]] ; do
   #    POWER=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk '{ print $6 }' | awk -F, '{ print $1}')
   #    echo "Just grabbed new POWER = $POWER, so how does it look?"
   #    sleep 1
   #    done
   # done

   # echo $DATA > $SANDBOXAP/$F1"_last_data.txt"
   # DATA=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk '{ print $7 }' | awk -F, '{ print $1}')
   # for a in "$DATA"; do
   #    while [[ "$a" != '\012' ]] ; do
   #    DATA=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk '{ print $7 }' | awk -F, '{ print $1}')
   #    echo "Just grabbed new DATA = $DATA, so how does it look?"
   #    sleep 1
   #    done
   # done

   # SHORTSECOND2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $5}' | awk -F: '{print $3}' | awk -F, '{ print $1 }')
   # SECOND2=${SHORTSECOND2:0:2}

   # SHORTHOUR2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $5}' | awk -F: '{print $1}')
   # HOUR2=${SHORTHOUR2:0:2}


# The following until-do-done loop is a safeguard against the crazy nonesense data sometimes
# retrieved when dealing with airodump-ng's .csv files. It has become necessary since some
# out of range numbers are being returned on a regular basis. Of course the assumption is that
# consecutive sampled minutes won't both be equally insane. If so, I have yet another problem...

# Init the variables...
LEGACYDAYS=0 ; LEGACYMODHOURS=0 ; LEGACYMODMINS=0
SECOND1=0  ; MINUTE1=0  ; HOUR1=0  ; DAY1=0  ; MONTH1=0  ; YEAR1=0
SECOND2=1  ; MINUTE2=1  ; HOUR2=1  ; DAY2=1  ; MONTH2=1  ; YEAR2=1
LOOPPASS=0
# NILCHAR=""

# The following line works for the most part, yet unequal values slip through.... ???? Why ????
# while (( $SECOND1 != $SECOND2 )) && \
#       (( $MINUTE1 != $MINUTE2 )) && \
#       (( $HOUR1 != $HOUR2 )) && \
#       (( $DAY1 != $DAY2 )) && \
#       (( $MONTH1 != $MONTH2 )) && \
#       (( $YEAR1 != $YEAR2 )) ; do

# while [[ $SECOND1 != $SECOND2 ]] && \
#       [[ $MINUTE1 != $MINUTE2 ]] && \
#       [[ $HOUR1 != $HOUR2 ]] && \
#       [[ $DAY1 != $DAY2 ]] && \
#       [[ $MONTH1 != $MONTH2 ]] && \
#       [[ $YEAR1 != $YEAR2 ]] ; do

# until [ $SECOND1 -eq $SECOND2 ] && \
#       [ $MINUTE1 -eq $MINUTE2 ] && \
#       [ $HOUR1 -eq $HOUR2 ] && \
#       [ $DAY1 -eq $DAY2 ] && \
#       [ $MONTH1 -eq $MONTH2 ] && \
#       [ $YEAR1 -eq $YEAR2 ] ; do

until [ $SECOND1 -eq $SECOND2 ] && \
      [ $MINUTE1 -eq $MINUTE2 ] && \
      [ $HOUR1 -eq $HOUR2 ] && \
      [ $DAY1 -eq $DAY2 ] && \
      [ $MONTH1 -eq $MONTH2 ] && \
      [ $YEAR1 -eq $YEAR2 ] && \
      [ $YEAR2LENGTH -eq 4 ] ; do

   echo -n "."

   CSVSTRING=$(egrep -a -m1 $F1 $FILE1 | awk -F, '{ print $1 $2 $3 }' | grep -ai $F1)
   # echo "Found CSVSTRING=$CSVSTRING,so moving on..."
   CSVSTRINGLENGTH=${#CSVSTRING}

   ### Following line detects when the client MAC appears not even once in the csv file. The returned string is always exactly 0 chars long.
   if [ $CSVSTRINGLENGTH -eq 0 ] ; then
      # echo "Appears not at all..."
      LASTSEENDATE=$(awk '{ print $1 }' $SANDBOXAP/$F1"_last_seen.txt")
      MACAPPEARSTIMES=0
   fi

   ### Following line detects when the client MAC appears just once in the csv file. The returned string is always exactly 57 chars long.
   if [ $CSVSTRINGLENGTH -eq 57 ] ; then

      MACAPPEARSTIMES=1

      SEC1=${CSVSTRING:55:2}
      SECOND1="$(echo $SEC1 | awk '{print $1 + 0}')"
      # echo "Found SECOND1=$SECOND1,so moving on..."

      MIN1=${CSVSTRING:52:2}
      MINUTE1="$(echo $MIN1 | awk '{print $1 + 0}')"
      # echo "Found MINUTE1=$MINUTE1,so moving on..."

      HR1=${CSVSTRING:49:2}
      HOUR1="$(echo $HR1 | awk '{print $1 + 0}')"
      # echo "Found HOUR1=$HOUR1,so moving on..."

      DY1=${CSVSTRING:46:2}
      DAY1="$(echo $DY1 | awk '{print $1 + 0}')"
      # echo "Found DAY1=$DAY1,so moving on..."

      MON1=${CSVSTRING:43:2}
      MONTH1="$(echo $MON1 | awk '{print $1 + 0}')"
      # echo "Found MONTH1=$MONTH1,so moving on..."

      YR1=${CSVSTRING:38:4}
      YEAR1="$(echo $YR1 | awk '{print $1 + 0}')"
      # echo "Found YEAR1=$YEAR1,so moving on..."

   fi

   # Following line detects when the client MAC appears TWICE     in the csv file. The returned string is always exactly 115 chars long.
   if [ $CSVSTRINGLENGTH -eq 115 ] ; then

      echo "Appears more than once -- MAC = $F1, <==> $F2,  so grabbing the correct last seen times."
      MACAPPEARSTIMES=2

      SEC1=${CSVSTRING:55:2}
      SECOND1="$(echo $SEC1 | awk '{print $1 + 0}')"
      # echo "Found SECOND1=$SECOND1,so moving on..."

      MIN1=${CSVSTRING:52:2}
      MINUTE1="$(echo $MIN1 | awk '{print $1 + 0}')"
      # echo "Found MINUTE1=$MINUTE1,so moving on..."

      HR1=${CSVSTRING:49:2}
      HOUR1="$(echo $HR1 | awk '{print $1 + 0}')"
      # echo "Found HOUR1=$HOUR1,so moving on..."

      DY1=${CSVSTRING:46:2}
      DAY1="$(echo $DY1 | awk '{print $1 + 0}')"
      # echo "Found DAY1=$DAY1,so moving on..."

      MON1=${CSVSTRING:43:2}
      MONTH1="$(echo $MON1 | awk '{print $1 + 0}')"
      # echo "Found MONTH1=$MONTH1,so moving on..."

      YR1=${CSVSTRING:38:4}
      YEAR1="$(echo $YR1 | awk '{print $1 + 0}')"
      # echo "Found YEAR1=$YEAR1,so moving on..."

   fi

   LASTSEENDATE="$YR1-$MON1-$DY1 $HR1:$MIN1:$SEC1"
   DATE1LENGTH=${#LASTSEENDATE}

   # echo "Found DATE1LENGTH= $DATE1LENGTH, so moving on..."
   #########################################################################################
   sleep .250
   #########################################################################################

   CSVSTRING=$(egrep -a -m1 $F1 $FILE1 | awk -F, '{ print $1 $2 $3 }' | grep -ai $F1)
   # echo "Found CSVSTRING=$CSVSTRING,so moving on..."

   CSVSTRINGLENGTH=${#CSVSTRING}

   if [ $CSVSTRINGLENGTH -eq 0 ] ; then
      # echo "Appears not at all..."
      MACAPPEARSTIMES=0
      LASTSEENDATE=$(awk '{ print $1 }' $SANDBOXAP/$F1"_last_seen.txt")
   fi


   ### Following line detects when the client MAC appears just once in the csv file. The returned string is always exactly 57 chars long.
   if [ $CSVSTRINGLENGTH -eq 57 ] ; then

      MACAPPEARSTIMES=1

      SEC2=${CSVSTRING:55:2}
      SECOND2="$(echo $SEC2 | awk '{print $1 + 0}')"
      # echo "Found SECOND2=$SECOND2,so moving on..."

      MIN2=${CSVSTRING:52:2}
      MINUTE2="$(echo $MIN2 | awk '{print $1 + 0}')"
      # echo "Found MINUTE2=$MINUTE2,so moving on..."

      HR2=${CSVSTRING:49:2}
      HOUR2="$(echo $HR2 | awk '{print $1 + 0}')"
      # echo "Found HOUR2=$HOUR2,so moving on..."

      DY2=${CSVSTRING:46:2}
      DAY2="$(echo $DY2 | awk '{print $1 + 0}')"
      # echo "Found DAY2=$DAY2,so moving on..."

      MON2=${CSVSTRING:43:2}
      MONTH2="$(echo $MON2 | awk '{print $1 + 0}')"
      # echo "Found MONTH2=$MONTH2,so moving on..."

      YR2=${CSVSTRING:38:4}
      YEAR2="$(echo $YR2 | awk '{print $1 + 0}')"
      # echo "Found YEAR2=$YEAR2,so moving on..."
   fi

   ### Following line detects when the client MAC appears TWICE     in the csv file. The returned string is always exactly 115 chars long.
   if [ $CSVSTRINGLENGTH -eq 115 ] ; then

      MACAPPEARSTIMES=2

      SEC2=${CSVSTRING:55:2}
      SECOND2="$(echo $SEC2 | awk '{print $1 + 0}')"
      # echo "Found SECOND2=$SECOND2,so moving on..."

      MIN2=${CSVSTRING:52:2}
      MINUTE2="$(echo $MIN2 | awk '{print $1 + 0}')"
      # echo "Found MINUTE2=$MINUTE2,so moving on..."

      HR2=${CSVSTRING:49:2}
      HOUR2="$(echo $HR2 | awk '{print $1 + 0}')"
      # echo "Found HOUR2=$HOUR2,so moving on..."

      DY2=${CSVSTRING:46:2}
      DAY2="$(echo $DY2 | awk '{print $1 + 0}')"
      # echo "Found DAY2=$DAY2,so moving on..."

      MON2=${CSVSTRING:43:2}
      MONTH2="$(echo $MON2 | awk '{print $1 + 0}')"
      # echo "Found MONTH2=$MONTH2,so moving on..."

      YR2=${CSVSTRING:38:4}
      YEAR2="$(echo $YR2 | awk '{print $1 + 0}')"
      # echo "Found YEAR2=$YEAR2,so moving on..."

    fi

   YEAR2LENGTH=${#YR2}

   # echo "      Only exit if match: $SECOND1 s1 and $MINUTE1 min1 and $HOUR1 hr1 $DAY1 d1 $MONTH1 m1 $YEAR1 y1."
   # echo "      Only exit if match: $SECOND2 s2 and $MINUTE2 min2 and $HOUR2 hr2 $DAY2 d2 $MONTH2 m2 $YEAR2 y2."
   # echo "incremented LOOPPASS..."
   if [ $LOOPPASS -gt 4 ] ; then
      sleep 60
      echo -n "slowing down..."
   fi
  
   if [ $LOOPPASS -gt 15 ] ; then
      echo "      Hanging, looping since cannot grab sane data"
      echo "_HUNG $(date +%a) $(date +%D) $(date +%T) H $SCRIPTNAME $LOOPPASS $F2 $F1, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $HOMEP/master_log.txt
      echo "_HUNG $(date +%a) $(date +%D) $(date +%T) H $SCRIPTNAME $LOOPPASS $F2 $F1, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $SANDBOXAP/$F1"_history.txt"
      echo "_HUNG $(date +%a) $(date +%D) $(date +%T) H $SCRIPTNAME $LOOPPASS $F2 $F1, OUI $MACSTRING, using $FILE1, by $HOSTNAME"
      # echo "_HUNG $(date +%D) $(date +%T) $LOOPPASS $F2 at $SSID, $F1, OUI $MACSTRING, using $FILE1, by $HOSTNAME"
      EVENTTYPE="HUNG"
      SENDEMAILALERT
      LOOPPASS=0
      echo "+----------------------------------Debug Info----------------------------------------------------------------------------+"
      echo "SECOND1=$SECOND1, SECOND2=$SECOND2, MINUTE1=$MINUTE1, MINUTE2=$MINUTE2, HOUR1=$HOUR1, HOUR2=$HOUR2, DAY1=$DAY1, DAY2=$DAY2, MONTH1=$MONTH1, MONTH2=$MONTH2"
      echo "YEAR1=$YEAR1, YEAR2=$YEAR2, ASSOCSSID1LENGTH=$ASSOCSSID1LENGTH, ASSOCSSID2LENGTH=$ASSOCSSID2LENGTH, ASSOCSSID1=$ASSOCSSID1, ASSOCSSID2=$ASSOCSSID2"
      echo "DATE1LENGTH=$DATE1LENGTH, DATE2LENGTH=$DATE2LENGTH"
      echo "CSVSTRINGLENGTH=$CSVSTRINGLENGTH"
      echo "CSVSTRING=$CSVSTRING"
      echo "+------------------------------------------------------------------------------------------------------------------------+"
      MESSAGE="$SCRIPTNAME Sad for you ... $EVENTTYPE insane data still rules the day ... Looping at $HOSTNAME"
      sendTEXTMESSAGE
      exit 0
   fi

   LASTSEENDATE="$YR2-$MON2-$DY2 $HR2:$MIN2:$SEC2"
   DATE2LENGTH=${#LASTSEENDATE}
   # echo "Found DATE2LENGTH= $DATE2LENGTH, so moving on..."

   # New code 10-Feb-2013 since correctly assigning CURRENTDATE seems to be wonky...
   # echo "About to grab current date......... moving on..."
   getCURRENTDATE
   # CURRENTDATE=-1
   # CURRENTDATE1=0
   # until [ "$CURRENTDATE" == "$CURRENTDATE1" ] ; do
   #    CURRENTDATE="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
   #    sleep 0.250000
   #    CURRENTDATE1="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
   # done

   if [ $MACAPPEARSTIMES -gt 0 ] ; then
      ELAPSEDDAYS=$(dateDiff -d $LASTSEENDATE $CURRENTDATE)
      # echo "Elapsed days is $ELAPSEDDAYS, so moving on..."
   fi

   let "LOOPPASS += 1"
done

# echo "      Exited these match: $SECOND1 s1 and $MINUTE1 min1 and $HOUR1 hr1 $DAY1 d1 $MONTH1 m1 $YEAR1 y1."
# echo "      Exited these match: $SECOND2 s2 and $MINUTE2 min2 and $HOUR2 hr2 $DAY2 d2 $MONTH2 m2 $YEAR2 y2."

LASTSEENDATE="$YR2-$MON2-$DY2 $HR2:$MIN2:$SEC2"
# echo "For this AP, last seen date is: $LASTSEENDATE."

# New code 10-Feb-2013 since correctly assigning CURRENTDATE seems to be wonky...
CURRENTDATE=-1
CURRENTDATE1=0
until [ "$CURRENTDATE" == "$CURRENTDATE1" ] ; do
   CURRENTDATE="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
   # echo "Still sleepy?"
   # echo "Newly constructed current   date  is $CURRENTDATE"
   # echo "Newly constructed current   date1 is $CURRENTDATE1"
   # usleep 500000
   sleep 0.25000
   CURRENTDATE1="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
done

# echo "Not sleepy"
# echo "Newly constructed last seen date is $LASTSEENDATE"
# echo "Newly constructed current   date is $CURRENTDATE"

if [ $LOOPPASS -gt 8 ] ; then
   echo "=Loop $(date +%a) $(date +%D) $(date +%T) $LOOPPASS $SCRIPTNAME $F2, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $HOMEP/master_log.txt
   echo "=Loop $(date +%a) $(date +%D) $(date +%T) $LOOPPASS $SCRIPTNAME $F2, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $SANDBOXAP/$F1"_history.txt"
   echo "=Loop $(date +%a) $(date +%D) $(date +%T) $LOOPPASS $SCRIPTNAME $F2, OUI $MACSTRING, using $FILE1, by $HOSTNAME"
fi
# echo -n "$LOOPPASS loops"

# First read the Legacy Date in case we need it...
LEGACYDATE=$(cat $SANDBOXAP/$F1"_last_seen.txt")
LASTSEENEXISTS=$(echo $?)
# Now save off the last seen date in our new sandbox...
echo $LASTSEENDATE > $SANDBOXAP/$F1"_last_seen.txt"

ELAPSEDMINS=$(dateDiff -m $LASTSEENDATE $CURRENTDATE)
ELAPSEDHOURS=$(dateDiff -h $LASTSEENDATE $CURRENTDATE)
ELAPSEDDAYS=$(dateDiff -d $LASTSEENDATE $CURRENTDATE)

MODMINUTE=$(($ELAPSEDMINS % 60))
MODHOURS=$(($ELAPSEDHOURS % 24))

NUMATTACHEDCLIENTS=$(cat $FILE1 | grep -ai $F1 | wc -l)
let "NUMATTACHEDCLIENTS -= 1"

echo "$SCRIPTNAME .. $ELAPSEDDAYS d, $MODHOURS h, $MODMINUTE m, ($ELAPSEDMINS m) since $F1 <=> $MACSTRING <=> $F2, clients $NUMATTACHEDCLIENTS, Fresh = $CLIENTMARKER"
echo "$SCRIPTNAME .. $ELAPSEDDAYS d, $MODHOURS h, $MODMINUTE m, ($ELAPSEDMINS m) since $F1 <=> $MACSTRING <=> $F2, clients $NUMATTACHEDCLIENTS, Fresh = $CLIENTMARKER" >> log.txt
# echo "At $SCRIPTNAME .. $ELAPSEDDAYS d, $MODHOURS h, $MODMINUTE m, $ELAPSEDMINS elapsed, $POWER pow, $DATA data, since $F1 <=> $MACSTRING <=> $F2"
# echo "At $SCRIPTNAME .. $ELAPSEDDAYS d, $MODHOURS h, $MODMINUTE m, $ELAPSEDMINS elapsed, $POWER pow, $DATA data, since $F1 <=> $MACSTRING <=> $F2" >> log.txt

# Added 6-Feb-2013 to stop collecting, reporting bad data
   if [ $ELAPSEDDAYS -gt 499 ] ; then
      echo "      Insane Data detected, so bye bye"
      echo "_BADD $(date +%a) $(date +%D) $(date +%T) _ ap.sh $F2 at $SSID, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $HOMEP/master_log.txt
      echo "_BADD $(date +%a) $(date +%D) $(date +%T) _ ap.sh $F2 at $SSID, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $SANDBOXAP/$F1"_history.txt"
      echo "_BADD $(date +%a) $(date +%D) $(date +%T) _  $F2 at $SSID, OUI $MACSTRING, using $FILE1, by $HOSTNAME"
      EVENTTYPE="BADD"
      SENDEMAILALERT
      LOOPPASS=0
      # exit 0
   fi

############## New Arrvial Code Section #############################################
# Below are the sections written to trigger leave and arrival alerts of our MAC client
#####################################################################################
# First, test if the client is brand new to the AP, if so, send e-mail...
#------------------------------------------------------------------------------------
# if [ "$CLIENTMARKER" == "" ] ; then
if [ $LASTSEENEXISTS -eq 1 ] ; then # Remember, this variable $LASTSEENEXISTS was set by a return code check. If there's no _last_seen.txt file, this will be 1.
   echo "...$F2 Newly arrived."

   # New arrivals also need their current broadcasting channels saved...
   CURRENTCHANNEL=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $4 }' | awk '{ print $1 }')
   let "CURRENTCHANNEL += 0"
   echo $CURRENTCHANNEL > $SANDBOXAP/$F1"_current_channel.txt"

   CURRENTCRYPTO=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $6 }' | awk '{ print $1 }' | sed -e 's/^ *//' -e 's/^ *$//') ### That last sed ...removes any LEADING and TRAILING whitespace padding
   echo $CURRENTCRYPTO > $SANDBOXAP/$F1"_current_crypto.txt"

   CURRENTPOWER=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $9 }' | awk '{ print $1 }')
   let "CURRENTPOWER += 0"
   echo $CURRENTPOWER > $SANDBOXAP/$F1"_current_power.txt"

   # CURRENTESSID=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $14 }' | awk '{ print $1 }')  ### That last awk print $1 removes any whitespace padding
   CURRENTESSID=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $14 }' | sed -e 's/^ *//' -e 's/^ *$//')  ### That last sed ...removes any LEADING and TRAILING whitespace padding
   echo $CURRENTESSID > $SANDBOXAP/$F1"_current_essid.txt"


   SHORTSEC2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $3}' | awk -F: '{print $3}' | awk -F, '{ print $1 }')
   SEC2=${SHORTSEC2:0:2}
   SECOND2="$(echo $SEC2 | awk '{print $1 + 0}')"

   SHORTMIN2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $3}' | awk -F: '{print $2}')
   MIN2=${SHORTMIN2:0:2}
   MINUTE2="$(echo $MIN2 | awk '{print $1 + 0}')"

   SHORTHOUR2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $3}' | awk -F: '{print $1}')
   HR2=${SHORTHOUR2:0:2}
   HOUR2="$(echo $HR2 | awk '{print $1 + 0}')"

   SHORTDAY2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $2}' | awk -F- '{ print $3}')
   DY2=${SHORTDAY2:0:2}
   DAY2="$(echo $DY2 | awk '{print $1 + 0}')"

   SHORTMONTH2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $2}' | awk -F- '{ print $2}')
   MON2=${SHORTMONTH2:0:2}
   MONTH2="$(echo $MON2 | awk '{print $1 + 0}')"

   SHORTYEAR2=$(awk -F, '{print $0}' $FILE1 | grep -ai $F1 | awk -F"[ ]" '{ print $2}' | awk -F- '{ print $1}')
   YR2=${SHORTYEAR2:0:4}
   YEAR2="$(echo $YR2 | awk '{print $1 + 0}')"


   # Ok, so brand new mobile just arrived at the AP, so...
   EVENTTYPE="Newly-Arrived"
   echo "1" > $SANDBOXAP/$F1"_is_fresh.txt"

   echo "++New $(date +%a) $(date +%D) $(date +%T) + $SCRIPTNAME $F2, OUI $MACSTRING, ESSID $CURRENTESSID, crypto $CURRENTCRYPTO, power $CURRENTPOWER, chan $CURRENTCHANNEL first seen $MONTH2/$DAY2/$YEAR2 $HOUR2:$MIN2:$SEC2, by $HOSTNAME" >> $HOMEP/master_log.txt
   echo "++New $(date +%a) $(date +%D) $(date +%T) + $SCRIPTNAME $F2, OUI $MACSTRING, ESSID $CURRENTESSID, crypto $CURRENTCRYPTO, power $CURRENTPOWER, chan $CURRENTCHANNEL first seen $MONTH2/$DAY2/$YEAR2 $HOUR2:$MIN2:$SEC2, by $HOSTNAME" >> $SANDBOXAP/$F1"_history.txt"
   echo "++New $(date +%a) $(date +%D) $(date +%T) + $SCRIPTNAME $F2, OUI $MACSTRING, ESSID $CURRENTESSID, crypto $CURRENTCRYPTO, power $CURRENTPOWER, chan $CURRENTCHANNEL first seen $MONTH2/$DAY2/$YEAR2 $HOUR2:$MIN2:$SEC2, by $HOSTNAME"

   SENDEMAILALERT
fi

############## Detect Gone condition, set is_fresh.txt ##############################
#####################################################################################
#------------------------------------------------------------------------------------
LEGACYMINS=$(dateDiff -m $LEGACYDATE $CURRENTDATE)
if [ $FIRSTPASS -eq 0 ] ; then
   if [ $ELAPSEDMINS -gt $QUIETTHRESH ] ; then
      # if [ $CLIENTMARKER -eq 0 ] ; then
      # Above if clause removed since $CLIENTMARKER is set by this script, but what if this script is stopped before it can properly detect a Back condition and correctly set _is_fresh to 1?
      # Removing the above if clause ensures that apv4.sh is not at the mercy of bad database data that will prevent reporting of a Gone condition when it legitimately happens.
      if [ $LEGACYMINS -gt $QUIETTHRESH ] ; then
         echo "ZERO out all the _is_fresh.txt files, then proceed..."
         echo "0" > $SANDBOXAP/$F1"_is_fresh.txt"
         # CLIENTMARKER=0
         EVENTTYPE="Gone"
         echo "$EVENTTYPE $F2 from $SCRIPTNAME OUI $MACSTRING $(date +%D) $(date +%T) thrsh $QUIETTHRESH m, elapsed $ELAPSEDMINS m, by $HOSTNAME"
         echo "-Gone $(date +%a) $(date +%D) $(date +%T) - $SCRIPTNAME $F2, thrsh $QUIETTHRESH m, elapsed $ELAPSEDMINS m, OUI $MACSTRING, using $FILE1, by $HOSTNAME"
         echo "-Gone $(date +%a) $(date +%D) $(date +%T) - $SCRIPTNAME $F2, thrsh $QUIETTHRESH m, elapsed $ELAPSEDMINS m, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $HOMEP/master_log.txt
         echo "-Gone $(date +%a) $(date +%D) $(date +%T) - $SCRIPTNAME $F2, thrsh $QUIETTHRESH m, elapsed $ELAPSEDMINS m, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $SANDBOXAP/$F1"_history.txt"
         SENDEMAILALERT
      fi
   fi

############## Detect Back condition, set is_fresh.txt ##############################
#####################################################################################
#------------------------------------------------------------------------------------
   if [ $ELAPSEDMINS -lt $QUIETTHRESH ] ; then
      # if [ $CLIENTMARKER -eq 0 ] ; then
      # Above if clause removed since $CLIENTMARKER is set by this script, but what if this script is stopped before it can properly detect a Gone condition and correctly set _is_fresh to 0?
      # Removing the above if clause ensures that apv4.sh is not at the mercy of bad database data that will prevent reporting of a Back condition when it legitimately happens.
      # echo -n "test1 $ELAPSEDMINS less than $QUIETTHRESH."
      if [ $CLIENTMARKER -eq 0 ] ; then
         echo "1" > $SANDBOXAP/$F1"_is_fresh.txt"
      fi
      if [ $LEGACYMINS -gt $QUIETTHRESH ] ; then
         # Added 6-Feb-2013 to stop collecting, reporting bad data
         # echo -n "test2 $LEGACYMINS greater $QUIETTHRESH."
         if [ $ELAPSEDDAYS -lt 3000 ] ; then
            echo "test3 One out all the _is_fresh.txt files, then proceed..."
            echo "1" > $SANDBOXAP/$F1"_is_fresh.txt"
            # CLIENTMARKER=1
            EVENTTYPE="Back"

            # LEGACYMINS=$(dateDiff -m $LEGACYDATE $CURRENTDATE)
            LEGACYHOURS=$(dateDiff -h $LEGACYDATE $CURRENTDATE)
            LEGACYDAYS=$(dateDiff -d $LEGACYDATE $CURRENTDATE)

            LEGACYMODMINS=$(($LEGACYMINS % 60))
            LEGACYMODHOURS=$(($LEGACYHOURS % 24))
      
            echo "+Back $(date +%a) $(date +%D) $(date +%T) + $SCRIPTNAME $F2, thrsh $QUIETTHRESH m, last seen $LEGACYDAYS d, $LEGACYMODHOURS h, $LEGACYMODMINS m ago, OUI $MACSTRING, using $FILE1, by $HOSTNAME"
            echo "+Back $(date +%a) $(date +%D) $(date +%T) + $SCRIPTNAME $F2, thrsh $QUIETTHRESH m, last seen $LEGACYDAYS d, $LEGACYMODHOURS h, $LEGACYMODMINS m ago, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $HOMEP/master_log.txt
            echo "+Back $(date +%a) $(date +%D) $(date +%T) + $SCRIPTNAME $F2, thrsh $QUIETTHRESH m, last seen $LEGACYDAYS d, $LEGACYMODHOURS h, $LEGACYMODMINS m ago, OUI $MACSTRING, using $FILE1, by $HOSTNAME" >> $SANDBOXAP/$F1"_history.txt"
            SENDEMAILALERT
         fi
      fi
   fi
fi

############## Detect NEWCHANNEL and compare to CURRENTCHANNEL section ##############
#####################################################################################
#------------------------------------------------------------------------------------
if [ $FIRSTPASS -eq 1 ] ; then
   echo $CURRENTCHANNEL > $SANDBOXAP/$F1"_current_channel.txt"
fi

if [ $FIRSTPASS -eq 0 ] ; then
   # echo $CURRENTCHANNEL > $SANDBOXAP/$F1"_current_channel.txt"
   CURRENTCHANNEL=$(cat $SANDBOXAP/$F1"_current_channel.txt")
   NEWCHANNEL1=1
   NEWCHANNEL2=2
   until [ $NEWCHANNEL1 -eq $NEWCHANNEL2 ] ; do
      NEWCHANNEL1=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $4 }' | sed -e 's/^ *//' -e 's/^ *$//') ### That last sed removes any whitespace padding
      sleep .250
      NEWCHANNEL2=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $4 }' | sed -e 's/^ *//' -e 's/^ *$//') ### That last sed removes any whitespace padding
   done
      NEWCHANNEL1=NEWCHANNEL1+0
   # echo "$F1 found at $CURRENTCHANNEL, moving on..."  
   if [ $NEWCHANNEL1 -gt 0 ] ; then
      if [ $NEWCHANNEL1 -ne $CURRENTCHANNEL ] ; then
         # echo "$F2 has changed broadcast channel from $CURRENTCHANNEL to $NEWCHANNEL"
         echo "+Chan $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F2 has changed broadcast channel from $CURRENTCHANNEL to $NEWCHANNEL1"
         echo "+Chan $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F2 has changed broadcast channel from $CURRENTCHANNEL to $NEWCHANNEL1" >> $HOMEP/master_log.txt
         echo "+Chan $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F2 has changed broadcast channel from $CURRENTCHANNEL to $NEWCHANNEL1" >> $SANDBOXAP/$F1"_history.txt"
         echo $NEWCHANNEL1 > $SANDBOXAP/$F1"_current_channel.txt"
         EVENTTYPE="Channel"
         SENDEMAILALERT
      fi
   fi
fi


############## Detect NEWCRYPTO and compare to CURRENTCRYPTO section ##############
#####################################################################################
#------------------------------------------------------------------------------------
# if [ $FIRSTPASS -eq 1 ] ; then
#    echo $CURRENTCRYPTO > $SANDBOXAP/$F1"_current_crypto.txt"
# fi

if [ $FIRSTPASS -eq 0 ] ; then
   CURRENTCRYPTO=$(cat $SANDBOXAP/$F1"_current_crypto.txt")
   NEWCRYPTO1=aaa
   NEWCRYPTO2=bbb
   until [ "$NEWCRYPTO1" == "$NEWCRYPTO2" ] ; do
      NEWCRYPTO1=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $6 }' | sed 's/^[ \t]*//;s/[ \t]*$//') ### That last sed removes any whitespace padding
      # NEWCRYPTO1=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $6 }' | sed -e 's/^ *//' -e 's/^ *$//') ### That last sed removes any whitespace padding
      sleep .250
      NEWCRYPTO2=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $6 }' | sed 's/^[ \t]*//;s/[ \t]*$//') ### That last sed removes any whitespace padding
      # NEWCRYPTO2=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $6 }' | sed -e 's/^ *//' -e 's/^ *$//') ### That last sed removes any whitespace padding
   done
      # NEWCRYPTO1=NEWRYPTO1+0
   # echo "$F1 found at $CURRENTCRYPTO, moving on..."  
   # if [ $NEWCRYPTO1 -gt 0 ] ; then
      if [ "$NEWCRYPTO1" != "$CURRENTCRYPTO" ] ; then
         # echo "$F2 has changed crypto from $CURRENTCRYPTO to $NEWRYPTO"
         echo "+Cryp $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F2 has changed crypto from $CURRENTCRYPTO to $NEWCRYPTO1"
         echo "+Cryp $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F2 has changed crypto from $CURRENTCRYPTO to $NEWCRYPTO1" >> $HOMEP/master_log.txt
         echo "+Cryp $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F2 has changed crypto from $CURRENTCRYPTO to $NEWCRYPTO1" >> $SANDBOXAP/$F1"_history.txt"
         echo $NEWCRYPTO1 > $SANDBOXAP/$F1"_current_crypto.txt"
         EVENTTYPE="Crypto"
         SENDEMAILALERT
      fi
   # fi
fi

############## Detect Identity (ESSID) and compare to Current Identity section ######
#####################################################################################
#------------------------------------------------------------------------------------
# if [ $FIRSTPASS -eq 1 ] ; then
#    echo $CURRENTESSID > $SANDBOXAP/$F1"_current_essid.txt"
# fi

if [ $FIRSTPASS -eq 0 ] ; then
   CURRENTESSID=$(cat $SANDBOXAP/$F1"_current_essid.txt")
   CURRENTESSIDLENGTH=${#CURRENTESSID}
   NEWESSID1=aaa
   NEWESSID2=bbb
   NEWESSID1LENGTH=1
   NEWESSID2LENGTH=2
   until [ "$NEWESSID1" == "$NEWESSID2" ] ; do
      NEWESSID1=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $14 }'| sed -e 's/^ *//' -e 's/^ *$//') ### That last sed removes any whitespace padding
      sleep .250
      NEWESSID2=$(cat $FILE1 | grep -m 1 -ai $F1 | awk -F, '{ print $14 }'| sed -e 's/^ *//' -e 's/^ *$//') ### That last sed removes any whitespace padding
   done
   NEWESSID1LENGTH=${#NEWESSID1}
   NEWESSID2LENGTH=${#NEWESSID2}
   # echo "$F1 found at $CURRENTCRYPTO, moving on..."  
   if ( [ "$NEWESSID1" != "$CURRENTESSID" ] && [ "$NEWESSID1" != "" ] ) ; then
      CHECKBLACKLIST
      if [ "$ISMACBLACKLISTED" == "NO" ] ; then
         # echo "$F2 has changed crypto from $CURRENTESSID to $NEWESSID"
         echo "+SSID $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F1 has changed ESSID from $CURRENTESSID to $NEWESSID1"
         echo "+SSID $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F1 has changed ESSID from $CURRENTESSID to $NEWESSID1" >> $HOMEP/master_log.txt
         echo "+SSID $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F1 has changed ESSID from $CURRENTESSID to $NEWESSID1" >> $SANDBOXAP/$F1"_history.txt"
         echo $NEWESSID1 > $SANDBOXAP/$F1"_current_essid.txt"
         EVENTTYPE="Identity"
         SENDEMAILALERT
         # if ( [ "$NEWESSID1" != "" ] && [ "$NEWESSID2" != "" ] ) ; then
         # if ( [ "$NEWESSID1" != "" ] && [ "$NEWESSID2" != "" ] && [ "$NEWESSID1" != " " ] && [ "$NEWESSID2" != " " ] ) ; then
         # if ( [ "$NEWESSID1LENGTH" != "$ZERO" ] && [ "$NEWESSID2LENGTH" != "$ZERO" ] ) ; then
         if ( [ "$NEWESSID1LENGTH" != 0 ] && [ "$CURRENTESSIDLENGTH" != 0 ] ) ; then
            echo "Detected legitimate ESSID change, so text out word..."
            sendTEXTMESSAGE
            echo "+TXT+ $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F1 has changed ESSID from $CURRENTESSID to $NEWESSID1"
            echo "+TXT+ $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F1 has changed ESSID from $CURRENTESSID to $NEWESSID1" >> $HOMEP/master_log.txt
            echo "+TXT+ $(date +%a) $(date +%D) $(date +%T) d $SCRIPTNAME $F1 has changed ESSID from $CURRENTESSID to $NEWESSID1" >> $SANDBOXAP/$F1"_history.txt"
         fi
      fi
   fi
fi

}
##############################
### Main script stars here ###
##############################

declare -i LEGACYDAYS
declare -i LEGACYMODHOURS
declare -i LEGACYMODMINS
declare -i SECOND1
declare -i MINUTE1
declare -i HOUR1
declare -i DAY1
declare -i MONTH1
declare -i YEAR1
declare -i SECOND2
declare -i MINUTE2
declare -i HOUR2
declare -i DAY2
declare -i MONTH2
declare -i YEAR2
# Two new variables to track the channel an AP broadcasts on...
declare -i NEWCHANNEL
declare -i CURRENTCHANNEL
declare -i NEWCHANNEL1
declare -i NEWCHANNEL2
declare -i LASTSEENEXISTS

# declare -i INTERDELAY
# declare -i INTRADELAY

FIRSTPASS=1
DAY=d
HOUR=h
MIN=m

ZERO=0
ONE=1
CURRENTESSIDLENGTH=3

HOMEP=.
UNKNOWNOUIFILE=$HOMEP/unkOUI.txt

while [ -e ./go ] ; do
   if [ $FIRSTPASS -eq 0 ] ; then
      INTERDELAY=$(cat $HOMEP/interdelay.txt)
      INTRADELAY=$(cat $HOMEP/intradelay.txt)
   else
      INTERDELAY=1
      INTRADELAY=1
   fi

   LOOPPASS=0
   ZERO=0
   FILE1=$1
   SANDBOXAP=$HOMEP/sandbox-ap
   MINUTE1=-1 ; HOUR1=-1 ; DAY1=-1 ; MONTH1=-1 ; YEAR1=-1
   MINUTE2=1  ; HOUR2=1  ; DAY2=1  ; MONTH2=1  ; YEAR2=1
   MINUTETHRESH15=0
   PREVIOUSMINS=1
   TEMPMINS=-1
   MODMINUTE=0
   MODHOUR=0
   THRESH=-1
   ELAPSEDMINS=-1
   THRESHEXCEEDALERTED=-1
   # QUIETTHRESH=10080     ### 1440 seconds in one day, so use nice round multiples of 1440 here.
   # QUIETTHRESH=4320     ### 4320 seconds is three days, so use nice round multiples of 1440 here.
   QUIETTHRESH=59     ### Trying to ID fly-by APs mounted in cars with this change.
   WEEDOUTTHRESH=80
   MESSAGE="undefined"
   EVENTTYPE="undefined"
   NOTASSOC="AP_list"
   # SSID="(apv2.sh)"
   SSID=${0##*/}
   SCRIPTNAME=${0##*/}
   NEWCHANNEL=0
   CURRENTCHANNEL=0
   CKSUM1=1
   CKSUM2=2
   NUMATTACHEDCLIENTS=0
   FILESIZE1=-1
   FILESIZE2=-2
   MODFILESIZE1=-1
   MODFILESIZE2=-2
   LINEVAR="ap_line.txt"
   declare -i CLIENTMARKER
   CLIENTMARKER=-1

   CHECKFORPAUSE
   CHECKFORSTOP

   echo "Time to build up list of broadcasting APs..."
   if [ -e $SANDBOXAP/"$NOTASSOC".txt ] ; then
      rm $SANDBOXAP/"$NOTASSOC".txt
   fi
   # until [[ CKSUM1 -eq CKSUM2 ]] ; do
   until ( [[ CKSUM1 -eq CKSUM2 ]] && [[ MODFILESIZE1 -eq ZERO ]] && [[ MODFILESIZE2 -eq ZERO ]] ); do
      echo -n "*"
      # cat $FILE1 | grep -ae WPA -ae WEP -ae OPN | awk -F, 'length($1)==17 { print $1 }' > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # Following line added 8-Feb-2015 since scanv18.sh is coded in a similar way
      # egrep -ae WPA -ae WEP -ae OPN $FILE1 | awk -F, 'length($1)==17 { print $1 }' > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # egrep -ae WPA -ae WEP -ae OPN $FILE1 | awk -F, '{ print $1 $3 }' | sort > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # Following line pulled from a stackoverflow.com answer, retrieved 5-Oct-2015:
      # Below line modified 23May2021 after we could never break out of the until loop. It disallows anything past that isn't at least 36 char. long.
      awk -v threshold=0 -F, '$4 > threshold' $FILE1 | awk -F, '{ print $1 $3 }' | grep '^.\{36\}' | sort > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # awk -v threshold=0 -F, '$4 > threshold' $FILE1 | awk -F, '{ print $1 $3 }' | awk 'length($1==17 { print $1 $2 }' | sort > $SANDBOXAP/"$NOTASSOC"_attached.txt
      CKSUM1=$(cksum $SANDBOXAP/"$NOTASSOC"_attached.txt | awk '{ print $1 }')
      # echo "Cksum-1 is $CKSUM1, so onward..."
      FILESIZE1=$(stat --printf="%s" $SANDBOXAP/"$NOTASSOC"_attached.txt)
      MODFILESIZE1=$((FILESIZE1 % 38))
      echo "Cksum-1 is $CKSUM1, and Modfilesize1 is $MODFILESIZE1 so onward..."

      sleep .50

      # cat $FILE1 | grep -ae WPA -ae WEP -ae OPN | awk -F, 'length($1)==17 { print $1 }' > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # Following line added 8-Feb-2015 since scanv18.sh is coded in a similar way
      # egrep -ae WPA -ae WEP -ae OPN $FILE1 | awk -F, 'length($1)==17 { print $1 }' > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # egrep -ae WPA -ae WEP -ae OPN $FILE1 | awk -F, '{ print $1 $3 }' | sort > $SANDBOXAP/"$NOTASSOC"_attached.txt
      # Following line pulled from a stackoverflow.com answer, retrieved 5-Oct-2015:
      awk -v threshold=0 -F, '$4 > threshold' $FILE1 | awk -F, '{ print $1 $3 }' | grep '^.\{36\}' | sort > $SANDBOXAP/"$NOTASSOC"_attached.txt
      CKSUM2=$(cksum $SANDBOXAP/"$NOTASSOC"_attached.txt | awk '{ print $1 }')
      # echo "Cksum-2 is $CKSUM2, so onward..."
      FILESIZE2=$(stat --printf="%s" $SANDBOXAP/"$NOTASSOC"_attached.txt)
      MODFILESIZE2=$((FILESIZE1 % 38))
      echo "Cksum-2 is $CKSUM2, and Modfilesize2 is $MODFILESIZE2 so onward..."
      echo " "

      sleep .50

   done
#### The new loop below attempts to filter out non clients older than, say, 3 hours...
   echo "About to perform the weedout process, hang on..."
   # Set loop separator to end of line
   getCURRENTDATE
   RAWNONFILE=$SANDBOXAP/"$NOTASSOC"_attached.txt
   BAKIFS=$IFS
   IFS=$(echo -en "\n\b")
   exec 3<&0
   exec 0<"$RAWNONFILE"
   while read -r line
   do
      # echo -n "*** Current LINE: $line"
      # use $line variable to process line in processLine() function
      weedOutLine $line
      # sleep $INTRADELAY
      # echo -n "-"
   done
   exec 0<&3
   # restore $IFS which was used to determine what the field separators are
   IFS=$BAKIFS

   sleep 1

   echo ""
   echo "Ok, just completed weedout process. Just found $(cat $SANDBOXAP/"$NOTASSOC".txt | wc -l) fresh APs, threshold is $WEEDOUTTHRESH$MIN, out of $(cat $SANDBOXAP/"$NOTASSOC"_attached.txt | wc -l) total."



   # cat $SANDBOXAP/"$NOTASSOC"_attached.txt >> $SANDBOXAP/"$NOTASSOC".txt
   # cat $SANDBOXAP/"$NOTASSOC".txt | sort -uo $SANDBOXAP/"$NOTASSOC".txt

   # cat $SANDBOXAP/"$NOTASSOC"_attached.txt | sort -uo $SANDBOXAP/"$NOTASSOC"_attached.txt

   echo -n " " >> $SANDBOXAP/$LINEVAR
   echo -n "(" >> $SANDBOXAP/$LINEVAR
   echo -n $(cat $SANDBOXAP/"$NOTASSOC".txt | wc -l) >> $SANDBOXAP/$LINEVAR
   echo -n "," >> $SANDBOXAP/$LINEVAR
   echo -n $(cat $SANDBOXAP/"$NOTASSOC"_attached.txt | wc -l) >> $SANDBOXAP/$LINEVAR
   echo -n ")" >> $SANDBOXAP/$LINEVAR

   echo ""

   # cat $SANDBOXAP/"$NOTASSOC"_attached.txt >> $SANDBOXAP/"$NOTASSOC".txt
   # cat $SANDBOXAP/"$NOTASSOC".txt | sort -uo $SANDBOXAP/"$NOTASSOC".txt

   # cat $SANDBOXAP/"$NOTASSOC"_attached.txt | sort -uo $SANDBOXAP/"$NOTASSOC"_attached.txt

   # echo -n $(cat $SANDBOXAP/"$NOTASSOC"_attached.txt | wc -l) >> $SANDBOXAP/$LINEVAR
   # echo -n "," >> $SANDBOXAP/$LINEVAR

   # echo ""
   echo "Just wrote you a nice _attached.txt file, so go check it Mkay?"
   echo "-------------------------------------------------------------------------------------------"
   ls -alrt $SANDBOXAP/$NOTASSOC*.txt
   echo "--- Check-Sum of the _attached file is: $CKSUM1, so moving on..."
   echo "****** $NOTASSOC ** $SCRIPTNAME ** Inter delay=$INTERDELAY, intra delay=$INTRADELAY **"
   echo "$(cat $SANDBOXAP/"$NOTASSOC".txt | wc -l) / $(cat $SANDBOXAP/"$NOTASSOC"_attached.txt | wc -l) APs broadcasting in this run, weed out threshold is $WEEDOUTTHRESH$MIN."
   echo "-------------------------------------------------------------------------------------------"


   FILE=$SANDBOXAP/"$NOTASSOC".txt
   if [ -e $HOMEP/full ] ; then
      FILE=$SANDBOXAP/"$NOTASSOC"_attached.txt
      echo "******************************************* Despite Weedout algorithm, detected ./full so we will check all MACs *******************************************"
   fi

   # read $FILE using the file descriptors
   # FILE is defined by the newest freshest MACs found in the .csv file.

   # Set loop separator to end of line
   BAKIFS=$IFS
   IFS=$(echo -en "\n\b")
   exec 3<&0
   exec 0<"$FILE"
   while read -r line
   do
      # echo -n "*** Current LINE: $line"
      # sleep 5
      # use $line variable to process line in processLine() function
      processLine $line
      sleep $INTRADELAY
      echo " "
   done
   exec 0<&3
   # restore $IFS which was used to determine what the field separators are
   IFS=$BAKIFS

   echo "****** $CURRENTDATE *****************************************************"
   ls -alrt $SANDBOXAP/$NOTASSOC*.txt
   echo "****** $NOTASSOC ** $SCRIPTNAME ** Inter delay=$INTERDELAY, intra delay=$INTRADELAY **"
   # echo "****** $CURRENTDATE *****************************************************" >> log.txt
   echo ''
   echo "NOTE: If you wish that this script bypasses the weed-out file, and want the full monty, simply: touch full"
   echo ''
   echo ''
   # echo "Current date is ... $(date '+%Y') $(date '+%m') $(date '+%d') $(date '+%H') $(date '+%M') $(date '+%S')" >> log.txt
   FIRSTPASS=0
   sleep $INTERDELAY
   INTERDELAY=$(cat $HOMEP/interdelay.txt)
   INTRADELAY=$(cat $HOMEP/intradelay.txt)
   CHECKFORPAUSE
   CHECKFORSTOP
done
exit 0
