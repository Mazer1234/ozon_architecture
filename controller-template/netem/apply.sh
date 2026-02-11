#!/bin/sh
set -eu

apk add --no-cache iproute2 >/dev/null 2>&1 || true

DELAY="${NETEM_DELAY_MS:-0}"
JITTER="${NETEM_JITTER_MS:-0}"
LOSS="${NETEM_LOSS_PCT:-0}"
IFACE="eth0"

tc qdisc del dev "$IFACE" root 2>/dev/null || true

if [ "$DELAY" = "0" ] && [ "$LOSS" = "0" ]; then
    echo "[netem] no shaping applied"
else
    if [ "$JITTER" = "0" ]; then
        echo "[netem] applying delay=${DELAY}ms loss=${LOSS}%"
        tc qdisc add dev "$IFACE" root netem delay "${DELAY}ms" loss "${LOSS}%"
    else
        echo "[netem] applying delay=${DELAY}ms jitter=${JITTER}ms loss=${LOSS}%"
        tc qdisc add dev "$IFACE" root netem delay "${DELAY}ms" "${JITTER}ms" loss "${LOSS}%"
    fi
fi