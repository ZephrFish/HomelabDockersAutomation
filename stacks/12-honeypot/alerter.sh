#!/bin/sh
# Wait for log file to appear
echo "[alerter] Waiting for OpenCanary log..."
while [ ! -f /var/tmp/opencanary.log ]; do sleep 3; done
echo "[alerter] Tailing log, sending alerts to ntfy + email..."

tail -F /var/tmp/opencanary.log | while IFS= read -r line; do
    # Parse JSON fields
    SRC=$(echo "$line" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('src_host', '?'))
except: print('?')
" 2>/dev/null)

    DST_PORT=$(echo "$line" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(str(d.get('dst_port', '?')))
except: print('?')
" 2>/dev/null)

    LOG_TYPE=$(echo "$line" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    t = str(d.get('logtype', '?'))
    types = {
        '1000': 'PORT-SCAN', '2000': 'FTP', '3000': 'HTTP',
        '4000': 'SSH', '5000': 'Telnet', '6000': 'HTTPPROXY',
        '7000': 'MySQL', '8000': 'MSSQL', '9000': 'NTP',
        '11000': 'SNMP', '12000': 'RDP', '13000': 'SIP',
        '14000': 'VNC', '15000': 'TFTP', '99000': 'USER'
    }
    print(types.get(t, 'UNKNOWN(' + t + ')'))
except: print('?')
" 2>/dev/null)

    # Skip startup/system events with no source
    [ "$SRC" = "?" ] || [ -z "$SRC" ] && continue

    MSG="Honeypot hit: $LOG_TYPE on port $DST_PORT from $SRC"

    # Send to ntfy
    curl -s -X POST "http://10.10.76.127:8085/homelab-security" \
        -H "Title: OpenCanary Alert" \
        -H "Priority: high" \
        -H "Tags: rotating_light,honeypot" \
        -d "$MSG" > /dev/null 2>&1 || true

    # Send email via local Postfix
    python3 -c "
import smtplib
from email.mime.text import MIMEText
msg = MIMEText('''$MSG

Raw log: $line
''')
msg['Subject'] = '[OpenCanary] $LOG_TYPE from $SRC'
msg['From'] = 'opencanary@ultra-lab.chaos.local'
msg['To'] = 'canarylocal@zsec.uk'
try:
    s = smtplib.SMTP('opencanary-smtp', 587, timeout=10)
    s.sendmail(msg['From'], [msg['To']], msg.as_string())
    s.quit()
except Exception as e:
    print('[alerter] email error:', e)
" 2>&1

    echo "[alerter] $MSG"
done
