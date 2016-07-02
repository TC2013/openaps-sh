#!/bin/bash

# This script sets up an openaps environment to work with loop.sh,
# by defining the required devices, reports, and aliases.
#
# Released under MIT license. See the accompanying LICENSE.txt file for
# full terms and conditions
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

die() {
  echo "$@"
  exit 1
}

if [[ $# -lt 2 ]]; then
    #openaps device show pump 2>/dev/null >/dev/null || die "Usage: setup.sh <directory> <pump serial #> [max_iob] [Share serial #]
    openaps device show pump 2>/dev/null >/dev/null || die "Usage: setup.sh <directory> <pump serial #> [max_iob] [/dev/ttySOMETHING] [Share serial #]"
fi
directory=`mkdir -p $1; cd $1; pwd`
serial=$2

if [[ $# -lt 3 ]]; then
    max_iob=0
else
    max_iob=$3
fi
if [[ $# -gt 3 ]]; then
    share_serial=$5
fi
if [[ $# -gt 3 ]]; then
    ttyport=$4
fi
echo -n Setting up oref0 in $directory for pump $serial with max_iob $max_iob and TTY $ttyport
echo

read -p "Continue? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then

( ( cd $directory 2>/dev/null && git status ) || ( openaps init $directory ) ) || die "Can't init $directory"
cd $directory || die "Can't cd $directory"

( ! grep -q max_iob preferences.json 2>/dev/null || [[ $max_iob != "0" ]] ) && echo "{ \"max_iob\": $max_iob }" > preferences.json
cat preferences.json
git add preferences.json

sudo cp ~/src/oref0/logrotate.openaps /etc/logrotate.d/openaps
sudo cp ~/src/oref0/logrotate.rsyslog /etc/logrotate.d/rsyslog

test -d /var/log/openaps || sudo mkdir /var/log/openaps && sudo chown $USER /var/log/openaps

openaps vendor add openapscontrib.timezones
openaps vendor add openxshareble
openaps vendor add mmeowlink.vendors.mmeowlink

# don't re-create devices if they already exist
openaps device show 2>/dev/null > /tmp/openaps-devices

# add devices
grep -q pump.ini .gitignore 2>/dev/null || echo pump.ini >> .gitignore
git add .gitignore
#grep pump /tmp/openaps-devices || openaps device add pump medtronic $serial || die "Can't add pump"
grep pump /tmp/openaps-devices || openaps device add pump mmeowlink subg_rfspy $ttyport $serial || die "Can't add pump"
#grep cgm /tmp/openaps-devices || openaps device add cgm dexcom || die "Can't add CGM"
#git add cgm.ini
grep cgm /tmp/openaps-devices || openaps device add cgm openxshareble || die "Can't add Share"
openaps use cgm configure --serial $share_serial
git add cgm.ini
#openaps device remove ns-glucose
grep ns-glucose /tmp/openaps-devices || openaps device add ns-glucose process 'bash -c "curl -m 30 -s $NIGHTSCOUT_HOST/api/v1/entries/sgv.json?count=288 | json -e \"this.glucose = this.sgv\""' || die "Can't add ns-glucose"
git add ns-glucose.ini
grep oref0 /tmp/openaps-devices || openaps device add oref0 process oref0 || die "Can't add oref0"
git add oref0.ini
grep iob /tmp/openaps-devices || openaps device add iob process --require "pumphistory profile clock" oref0 calculate-iob || die "Can't add iob"
git add iob.ini
grep meal /tmp/openaps-devices || openaps device add meal process --require "pumphistory profile clock carbs glucose basal" oref0 meal || die "Can't add meal"
git add meal.ini
grep get-profile /tmp/openaps-devices || openaps device add get-profile process --require "settings bg_targets isf basal_profile preferences carb_ratios" oref0 get-profile || die "Can't add get-profile"
git add get-profile.ini
grep detect-sensitivity /tmp/openaps-devices || openaps device add detect-sensitivity process --require "glucose pumphistory isf basal_profile profile" oref0 detect-sensitivity || die "Can't add detect-sensitivity"
git add detect-sensitivity.ini
#openaps device remove determine-basal
grep determine-basal /tmp/openaps-devices || openaps device add determine-basal process --require "iob temp_basal glucose profile autosens meal" oref0 determine-basal || die "Can't add determine-basal"
git add determine-basal.ini
grep pebble /tmp/openaps-devices || openaps device add pebble process --require "glucose iob basal_profile temp_basal suggested enacted meal" oref0 pebble || die "Can't add pebble"
git add pebble.ini
grep tz /tmp/openaps-devices || openaps device add tz timezones || die "Can't add tz"
git add tz.ini

# don't re-create reports if they already exist
openaps report show 2>/dev/null > /tmp/openaps-reports

# add reports for frequently-refreshed monitoring data
ls monitor 2>/dev/null >/dev/null || mkdir monitor || die "Can't mkdir monitor"
grep monitor/cgm-glucose.json /tmp/openaps-reports || openaps report add monitor/cgm-glucose.json JSON cgm iter_glucose_hours 25 || die "Can't add cgm-glucose.json"
mkdir raw-cgm
grep raw-cgm/raw-entries.json /tmp/openaps-reports || openaps report add raw-cgm/raw-entries.json JSON cgm oref0_glucose --hours 24
mkdir cgm
grep cgm/cgm-glucose.json /tmp/openaps-reports || openaps report add cgm/cgm-glucose.json JSON tz rezone --date display_time --date dateString raw-cgm/raw-entries.json
grep cgm/ns-glucose.json /tmp/openaps-reports || openaps report add cgm/ns-glucose.json text ns-glucose shell || die "Can't add ns-glucose.json"
grep monitor/mmtune.json /tmp/openaps-reports || openaps report add monitor/mmtune.json JSON pump mmtune || die "Can't add mmtune"
grep settings/model.json /tmp/openaps-reports || openaps report add settings/model.json JSON pump model || die "Can't add model"
grep monitor/clock.json /tmp/openaps-reports || openaps report add monitor/clock.json JSON pump read_clock || die "Can't add clock.json"
grep monitor/clock-zoned.json /tmp/openaps-reports || openaps report add monitor/clock-zoned.json JSON tz clock monitor/clock.json || die "Can't add clock-zoned.json"
grep monitor/temp_basal.json /tmp/openaps-reports || openaps report add monitor/temp_basal.json JSON pump read_temp_basal || die "Can't add temp_basal.json"
grep monitor/reservoir.json /tmp/openaps-reports || openaps report add monitor/reservoir.json JSON pump reservoir || die "Can't add reservoir.json"
grep monitor/battery.json /tmp/openaps-reports || openaps report add monitor/battery.json JSON pump read_battery_status || die "Can't add battery.json"
grep monitor/status.json /tmp/openaps-reports || openaps report add monitor/status.json JSON pump status || die "Can't add status.json"
grep monitor/pumphistory.json /tmp/openaps-reports || openaps report add monitor/pumphistory.json JSON pump iter_pump_hours 5 || die "Can't add pumphistory.json"
grep settings/pumphistory-24h.json /tmp/openaps-reports || openaps report add settings/pumphistory-24h.json JSON pump iter_pump_hours 27 || die "Can't add pumphistory-24h.json"
grep monitor/pumphistory-zoned.json /tmp/openaps-reports || openaps report add monitor/pumphistory-zoned.json JSON tz rezone monitor/pumphistory.json || die "Can't add pumphistory-zoned.json"
grep settings/pumphistory-24h-zoned.json /tmp/openaps-reports || openaps report add settings/pumphistory-24h-zoned.json JSON tz rezone settings/pumphistory-24h.json || die "Can't add pumphistory-24h-zoned.json"
grep monitor/iob.json /tmp/openaps-reports || openaps report add monitor/iob.json text iob shell monitor/pumphistory-zoned.json settings/profile.json monitor/clock-zoned.json || die "Can't add iob.json"
grep monitor/meal.json /tmp/openaps-reports || openaps report add monitor/meal.json text meal shell monitor/pumphistory-zoned.json settings/profile.json monitor/clock-zoned.json monitor/glucose.json settings/basal_profile.json monitor/carbhistory.json || die "Can't add meal.json"
#openaps report remove settings/autosens.json
grep settings/autosens.json /tmp/openaps-reports || openaps report add settings/autosens.json text detect-sensitivity shell monitor/glucose.json settings/pumphistory-24h-zoned.json settings/insulin_sensitivities.json settings/basal_profile.json settings/profile.json || die "Can't add autosens.json"

# add reports for infrequently-refreshed settings data
ls settings 2>/dev/null >/dev/null || mkdir settings || die "Can't mkdir settings"
grep settings/bg_targets.json /tmp/openaps-reports || openaps report add settings/bg_targets.json JSON pump read_bg_targets || die "Can't add bg_targets.json"
grep settings/insulin_sensitivities.json /tmp/openaps-reports || openaps report add settings/insulin_sensitivities.json JSON pump read_insulin_sensitivities || die "Can't add insulin_sensitivities.json"
grep settings/carb_ratios.json /tmp/openaps-reports || openaps report add settings/carb_ratios.json JSON pump read_carb_ratios || die "Can't add carb_ratios.json"
grep settings/basal_profile.json /tmp/openaps-reports || openaps report add settings/basal_profile.json JSON pump read_selected_basal_profile || die "Can't add basal_profile.json"
grep settings/settings.json /tmp/openaps-reports || openaps report add settings/settings.json JSON pump read_settings || die "Can't add settings.json"
grep settings/profile.json /tmp/openaps-reports || openaps report add settings/profile.json text get-profile shell settings/settings.json settings/bg_targets.json settings/insulin_sensitivities.json settings/basal_profile.json preferences.json settings/carb_ratios.json settings/temptargets.json || die "Can't add profile.json"

# add suggest and enact reports
ls enact 2>/dev/null >/dev/null || mkdir enact || die "Can't mkdir enact"
#openaps report remove enact/suggested.json
grep enact/suggested.json /tmp/openaps-reports || openaps report add enact/suggested.json text determine-basal shell monitor/iob.json monitor/temp_basal.json monitor/glucose.json settings/profile.json settings/autosens.json monitor/meal.json || die "Can't add suggested.json"
grep enact/enacted.json /tmp/openaps-reports || openaps report add enact/enacted.json JSON pump set_temp_basal enact/suggested.json || die "Can't add enacted.json"

# upload results
ls upload 2>/dev/null >/dev/null || mkdir upload || die "Can't mkdir upload"
grep upload/pebble.json /tmp/openaps-reports || openaps report add upload/pebble.json text pebble shell monitor/glucose.json monitor/iob.json settings/basal_profile.json monitor/temp_basal.json enact/suggested.json enact/enacted.json monitor/meal.json || die "Can't add pebble.json"

# don't re-create aliases if they already exist
openaps alias show 2>/dev/null > /tmp/openaps-aliases

# add aliases to get data
openaps alias add invoke "report invoke" || die "Can't add invoke"
openaps alias add mmtune '! bash -c "echo -n \"mmtune: \" && openaps report invoke monitor/mmtune.json 2>/dev/null >/dev/null; grep -v setFreq monitor/mmtune.json | grep -A2 `json -a setFreq -f monitor/mmtune.json` | while read line; do echo -n \"$line \"; done"'
openaps alias add wait-for-silence '! bash -c "echo -n \"Listening: \"; for i in `seq 1 100`; do echo -n .; ~/src/mmeowlink/bin/mmeowlink-any-pump-comms.py --port '$ttyport' --wait-for 20 2>/dev/null | egrep -v subg | egrep No && break; done"'
openaps alias add wait-for-long-silence '! bash -c "echo -n \"Listening: \"; for i in `seq 1 100`; do echo -n .; ~/src/mmeowlink/bin/mmeowlink-any-pump-comms.py --port '$ttyport' --wait-for 35 2>/dev/null | egrep -v subg | egrep No && break; done"'
openaps alias add monitor-cgm "report invoke raw-cgm/raw-entries.json cgm/cgm-glucose.json" || die "Can't add monitor-cgm"
#openaps alias add monitor-share "report invoke monitor/share-glucose.json" || die "Can't add monitor-share"
openaps alias add get-ns-glucose "report invoke cgm/ns-glucose.json" || die "Can't add get-ns-glucose"
openaps alias add monitor-pump "report invoke monitor/clock.json monitor/temp_basal.json monitor/pumphistory.json monitor/pumphistory-zoned.json monitor/clock-zoned.json monitor/iob.json monitor/meal.json monitor/reservoir.json monitor/battery.json monitor/status.json" || die "Can't add monitor-pump"
openaps alias add ns-temptargets '! bash -c "curl -m 30 -s \"$NIGHTSCOUT_HOST/api/v1/treatments.json?find\[created_at\]\[\$gte\]=`date -d \"6 hours ago\" -Iminutes`&find\[eventType\]\[\$regex\]=Target\" > settings/temptargets.json; openaps report invoke settings/profile.json 2>/dev/null >/dev/null; exit 0 "' || die "Can't add ns-temptargets"
openaps alias add ns-meal-carbs '! bash -c "curl -m 30 -s \"$NIGHTSCOUT_HOST/api/v1/treatments.json?find\[carbs\]\[\$exists\]=true\" > monitor/carbhistory.json; oref0-meal monitor/pumphistory-zoned.json settings/profile.json monitor/clock-zoned.json monitor/carbhistory.json monitor/glucose.json settings/basal_profile.json > monitor/meal.json.new; grep -q COB monitor/meal.json.new && mv monitor/meal.json.new monitor/meal.json; exit 0"' || die "Can't add ns-meal-carbs"
openaps alias add get-settings "report invoke settings/model.json settings/bg_targets.json settings/insulin_sensitivities.json settings/basal_profile.json settings/settings.json settings/carb_ratios.json settings/profile.json" || die "Can't add get-settings"
openaps alias add bg-fresh-check '! bash -c "cat cgm/glucose.json | json -c \"minAgo=(new Date()-new Date(this.dateString))/60/1000; return minAgo < 5 && minAgo > 0 && this.glucose > 30\" | grep -q glucose"'
openaps alias add get-bg '! bash -c "while (openaps bg-fresh-check); do echo -n .; sleep 5; done; openaps monitor-cgm 2>/dev/null | tail -1 && grep -q glucose cgm/cgm-glucose.json && rsync -rtu cgm/cgm-glucose.json cgm/glucose.json; rsync -rtu cgm/glucose.json monitor/glucose.json"' || die "Can't add get-bg"
openaps alias add get-ns-bg '! bash -c "openaps bg-fresh-check || ( openaps get-ns-glucose && cat cgm/ns-glucose.json | json -c \"minAgo=(new Date()-new Date(this.dateString))/60/1000; return minAgo < 10 && minAgo > -5 && this.glucose > 30\" | grep -q glucose && rsync -rtu cgm/ns-glucose.json cgm/glucose.json; rsync -rtu cgm/glucose.json monitor/glucose.json )"' || die "Can't add get-ns-bg"
openaps alias add gather '! bash -c "openaps report invoke monitor/status.json 2>/dev/null >/dev/null && echo -n Ref && test $(cat monitor/status.json | json bolusing) == false && echo -n resh && openaps monitor-pump 2>/dev/null >/dev/null && echo ed pumphistory || (echo; exit 1) 2>/dev/null"' || die "Can't add gather"
# if autosens.json is not newer than pumphistory-24h-zoned.json, or autosens.json is less than 5 bytes, refresh
openaps alias add autosens '! bash -c "(find settings/ -newer settings/autosens.json | grep -q pumphistory-24h-zoned.json || find settings/ -size -5c | grep -q autosens.json) && openaps invoke settings/autosens.json"'
openaps alias add refresh-old-pumphistory '! bash -c "find monitor/ -mmin -30 -size +100c | grep -q pumphistory-zoned || openaps gather "'
openaps alias add refresh-old-pumphistory-24h '! bash -c "find settings/ -mmin -30 -size +100c | grep -q pumphistory-24h-zoned || (openaps report invoke settings/pumphistory-24h.json settings/pumphistory-24h-zoned.json 2>/dev/null >/dev/null && echo Refreshed old pumphistory-24h)"'
openaps alias add refresh-temp-and-enact '! bash -c "find monitor/ -mmin -2 -size +5c | grep -q temp_basal || (openaps report invoke monitor/temp_basal.json 2>/dev/null >/dev/null && echo Refreshed temp && openaps enact)"'
openaps alias add refresh-pumphistory-and-enact '! bash -c "find monitor/ -mmin -3 | grep -q pumphistory-zoned || (openaps gather && openaps enact)"'
openaps alias add refresh-old-profile '! bash -c "find settings/ -mmin -30 -size +5c | grep -q profile || (openaps get-settings 2>/dev/null >/dev/null && echo Refreshed settings)"'
openaps alias add refresh-profile '! bash -c "find settings/ -mmin -15 -size +5c | grep -q settings.json || (openaps get-settings 2>/dev/null >/dev/null && echo Refreshed settings)"'
openaps alias add refresh-pumphistory-24h '! bash -c "find settings/ -mmin -15 -size +100c | grep -q pumphistory-24h-zoned || (openaps report invoke settings/pumphistory-24h.json settings/pumphistory-24h-zoned.json 2>/dev/null >/dev/null && echo Refreshed pumphistory-24h)"'

# add aliases to enact and loop
openaps alias add enact '! bash -c "rm enact/suggested.json; openaps invoke enact/suggested.json && if (cat enact/suggested.json && grep -q duration enact/suggested.json); then ( rm enact/enacted.json; openaps invoke enact/enacted.json ; grep -q duration enact/enacted.json || openaps invoke enact/enacted.json ) 2>&1 | egrep -v \"^  |subg_rfspy|handler\" && cat enact/enacted.json | json -0 | tee enact/enacted.json; grep incorrectly enact/suggested.json && ~/src/oref0/bin/clockset.sh 2>/dev/null; fi"' || die "Can't add enact"
openaps alias add ns-loop '! bash -c "echo Starting ns-loop at `date`: && openaps get-ns-bg; openaps ns-temptargets && echo -n Refreshed temptargets && openaps ns-meal-carbs && echo \" and meal-carbs\" && openaps upload && openaps autosens"' || die "Can't add ns-loop"
openaps alias add pump-loop '! bash -c "until(echo Starting pump-loop at `date`: && openaps wait-for-silence && openaps refresh-old-pumphistory && openaps refresh-old-pumphistory-24h && openaps refresh-old-profile && openaps refresh-temp-and-enact && openaps refresh-pumphistory-and-enact && openaps refresh-profile && openaps refresh-pumphistory-24h && echo Completed pump-loop at `date`); do openaps wait-for-long-silence && openaps mmtune; done"' || die "Can't add pump-loop"

# add aliases to upload results
openaps alias add pebble '! bash -c "grep -q iob monitor/iob.json && grep -q absolute enact/suggested.json && openaps report invoke upload/pebble.json"' || die "Can't add pebble"
openaps alias add prep-pumphistory-entries '! bash -c "cat monitor/pumphistory-zoned.json | json -e \"this.dateString = this.timestamp\" | json -e \"this.medtronic = this._type\" | json -e \"this.type = \\\"medtronic\\\"\" | json -e \"this.date = new Date(Date.parse(this.timestamp)).getTime( )\" > upload/pumphistory-entries.json"' || die "Can't add prep-pumphistory-entries"
openaps alias add upload-pumphistory-entries '! bash -c "openaps prep-pumphistory-entries && ns-upload-entries upload/pumphistory-entries.json"' || die "Can't add upload-pumphistory-entries"
openaps alias add latest-ns-treatment-time '! bash -c "nightscout latest-openaps-treatment $NIGHTSCOUT_HOST | json created_at"' || die "Can't add latest-ns-treatment-time"
openaps alias add format-latest-nightscout-treatments '! bash -c "nightscout cull-latest-openaps-treatments monitor/pumphistory-zoned.json settings/model.json $(openaps latest-ns-treatment-time) > upload/latest-treatments.json"' || die "Can't add format-latest-nightscout-treatments"
openaps alias add upload-recent-treatments '! bash -c "openaps format-latest-nightscout-treatments && test $(json -f upload/latest-treatments.json -a created_at eventType | wc -l ) -gt 0 && (ns-upload $NIGHTSCOUT_HOST $API_SECRET treatments.json upload/latest-treatments.json ) || echo \"No recent treatments to upload\""' || die "Can't add upload-recent-treatments"
openaps alias add format-ns-status '! bash -c "ns-status monitor/clock-zoned.json monitor/iob.json enact/suggested.json enact/enacted.json monitor/battery.json monitor/reservoir.json monitor/status.json > upload/ns-status.json"' || die "Can't add format-ns-status"
openaps alias add upload-ns-status '! bash -c "grep -q iob monitor/iob.json && grep -q absolute enact/suggested.json && openaps format-ns-status && grep -q iob upload/ns-status.json && ns-upload $NIGHTSCOUT_HOST $API_SECRET devicestatus.json upload/ns-status.json"' || die "Can't add upload-ns-status"
openaps alias add upload '! bash -c "echo -n Upload && ( openaps upload-ns-status; openaps report invoke enact/suggested.json 2>/dev/null; openaps pebble; openaps upload-pumphistory-entries; openaps upload-recent-treatments ) 2>/dev/null >/dev/null && echo ed"' || die "Can't add upload"

read -p "Schedule openaps in cron? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
# add crontab entries
(crontab -l; crontab -l | grep -q PATH || echo 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin') | crontab -
(crontab -l; crontab -l | grep -q killall || echo '* * * * * killall -g --older-than 10m openaps') | crontab -
(crontab -l; crontab -l | grep -q "reset-git" || echo "* * * * * cd $directory && oref0-reset-git") | crontab -
(crontab -l; crontab -l | grep -q get-bg || echo "* * * * * cd $directory && ps aux | grep -v grep | grep -q 'openaps get-bg' || ( date; openaps get-bg ; cat cgm/glucose.json | json -a sgv dateString | head -1 ) | tee -a /var/log/openaps/cgm-loop.log") | crontab -
(crontab -l; crontab -l | grep -q ns-loop || echo "* * * * * cd $directory && ps aux | grep -v grep | grep -q 'openaps ns-loop' || openaps ns-loop | tee -a /var/log/openaps/ns-loop.log") | crontab -
(crontab -l; crontab -l | grep -q pump-loop || echo "* * * * * cd $directory && ( ps aux | grep -v grep | grep -q 'openaps pump-loop' || openaps pump-loop ) 2>&1 | tee -a /var/log/openaps/pump-loop.log") | crontab -
crontab -l
fi

fi
