#!/bin/sh
set -eu
umask 077
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Manual use only after approval to pair this host with WhatsApp.
cd "$ROOT/whatsapp-bridge"
mkdir -p store
chmod 700 store
exec "$ROOT/bin/whatsapp-bridge"
