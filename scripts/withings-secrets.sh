#!/bin/sh
# Writes Config/Secrets.xcconfig (gitignored) from data/withings.env (gitignored), so the Withings client
# credentials reach the app's Info.plist at build time without ever being committed. Run after changing them.
set -e
cd "$(dirname "$0")/.."
. ./data/withings.env
umask 077
printf 'WITHINGS_CLIENT_ID = %s\nWITHINGS_CLIENT_SECRET = %s\n' "$WITHINGS_CLIENT_ID" "$WITHINGS_CLIENT_SECRET" > Config/Secrets.xcconfig
echo "Wrote Config/Secrets.xcconfig"
