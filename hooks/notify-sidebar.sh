#!/usr/bin/env bash
# Claude Code Notification hook → CLAS.app
#
# Reads the JSON event from stdin and forwards it to the local HTTP
# listener that CLAS.app exposes. Always exits 0 so that the Claude CLI
# never blocks on it: if the app is off, the worst case is a missed
# instant notification (the filesystem watcher will catch up within
# ~500ms anyway).
#
# Install: see README.md or paste into ~/.claude/settings.json under
# the `Notification` hook list (keeping any existing hooks).

set +e

PORT_FILE="$HOME/Library/Application Support/CLAS/port"
[[ -r "$PORT_FILE" ]] || exit 0

PORT="$(tr -d '[:space:]' < "$PORT_FILE")"
[[ -n "$PORT" ]] || exit 0

# 0.5s timeout, silent. Stream stdin straight into curl with
# --data-binary @- to avoid round-tripping the payload through a shell
# variable (which would break on payloads containing nulls or NL).
curl --silent --max-time 0.5 \
     --request POST \
     --header 'Content-Type: application/json' \
     --data-binary @- \
     "http://127.0.0.1:${PORT}/event" >/dev/null 2>&1

exit 0
