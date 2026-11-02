#!/bin/sh
# Builds Frameworks/Libv2ray.xcframework: the Xray-core wrapper used by v2rayNG
# (2dust/AndroidLibXrayLite, pinned to a release commit), compiled for iOS with gomobile.
# Needs Go (any recent version; GOTOOLCHAIN=auto fetches the one go.mod asks for) and Xcode.
set -eu
VERSION=v26.10.10
COMMIT=0a02333081243df017453ccb432ad3cafcfd69e3      # what $VERSION points at; refuse anything else
MOBILE=v0.0.0-20260908204917-8b95e45f8d3e            # golang.org/x/mobile from that release's go.mod

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Frameworks/Libv2ray.xcframework"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 --branch "$VERSION" https://github.com/2dust/AndroidLibXrayLite.git "$WORK/src"
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "AndroidLibXrayLite $VERSION is not $COMMIT, refusing" >&2; exit 1; }

# iOS kills a Network Extension that grows past ~50 MB; keep Go's heap well under that.
cat > "$WORK/src/libv2ray_ios.go" <<'GO'
//go:build ios

package libv2ray

import "runtime/debug"

func init() {
	debug.SetMemoryLimit(32 << 20)
	debug.SetGCPercent(10)
}
GO

export GOTOOLCHAIN=auto GOBIN="$WORK/bin" PATH="$WORK/bin:$PATH"
cd "$WORK/src"
go install "golang.org/x/mobile/cmd/gomobile@$MOBILE" "golang.org/x/mobile/cmd/gobind@$MOBILE"
go get "golang.org/x/mobile@$MOBILE"
gomobile init
gomobile bind -target=ios,iossimulator -iosversion=16.0 -trimpath -ldflags="-s -w -buildid=" -o "$WORK/Libv2ray.xcframework" .

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$WORK/Libv2ray.xcframework" "$OUT"
echo "Built $OUT"
