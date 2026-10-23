#!/bin/bash
# =============================================================================
#  build.sh — đóng gói RarX.app cho macOS
#
#  Cách dùng:
#    ./build.sh               Tạo build/RarX.app
#    ./build.sh --install     Tạo rồi cài vào /Applications (hoặc ~/Applications)
#    ./build.sh --dmg         Tạo thêm build/RarX.dmg để chia sẻ
#    ./build.sh --zip         Tạo thêm build/RarX.zip (gói mà chức năng Cập nhật trong ứng dụng tải về)
#    ./build.sh --universal   Chạy được trên cả Apple Silicon lẫn Intel (cần Xcode đầy đủ)
#
#  Biến môi trường: VERSION (mặc định 1.1.0), BUILD_NUMBER, BUNDLE_ID.
#  Yêu cầu: macOS 13 trở lên và Xcode (miễn phí trên App Store).
#  Lần chạy đầu sẽ tự tải 7-Zip (7zz) chính chủ từ GitHub/7-zip.org để đóng gói kèm.
#  Công cụ RAR không đóng gói sẵn: RarX tự tải bản chính thức từ rarlab.com ở lần mở đầu tiên.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"

APP_NAME="RarX"
BUNDLE_ID="${BUNDLE_ID:-com.rarx.app}"
VERSION="${VERSION:-1.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SEVENZIP_VERSION="${SEVENZIP_VERSION:-26.04}"

INSTALL=0
MAKE_DMG=0
MAKE_ZIP=0
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --dmg) MAKE_DMG=1 ;;
        --zip) MAKE_ZIP=1 ;;
        --universal) UNIVERSAL=1 ;;
        -h|--help)
            sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "Tham số không hợp lệ: $arg (xem ./build.sh --help)"; exit 1 ;;
    esac
done

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
step() { printf "\n\033[1;36m▸ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m⚠︎ %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✗ %s\033[0m\n" "$*"; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "build.sh chỉ chạy trên macOS."

# Ưu tiên bộ công cụ của Xcode: Command Line Tools trên một số phiên bản macOS thiếu
# plugin macro của SwiftUI (lỗi "SwiftUIMacros.StateMacro could not be found").
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    XCODE_APP=""
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        [[ -d "$candidate/Contents/Developer" ]] && { XCODE_APP="$candidate"; break; }
    done
    if [[ -z "$XCODE_APP" ]]; then
        XCODE_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | grep -v '/.Trash/' | head -1 || true)"
    fi
    if [[ -n "$XCODE_APP" && -d "$XCODE_APP/Contents/Developer" ]]; then
        export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        echo "Dùng bộ công cụ của $XCODE_APP"
    else
        warn "Không thấy Xcode — dùng Command Line Tools. Nếu biên dịch lỗi, hãy cài Xcode từ App Store."
    fi
fi
command -v swift >/dev/null 2>&1 || fail "Chưa có Swift. Cài Xcode từ App Store (khuyên dùng) hoặc chạy: xcode-select --install"

# -----------------------------------------------------------------------------
step "1/5  Chuẩn bị lõi 7-Zip"
mkdir -p "$ROOT/Vendor"
if [[ -x "$ROOT/Vendor/7zz" ]]; then
    echo "Đã có Vendor/7zz — bỏ qua bước tải."
else
    VER_NODOT="${SEVENZIP_VERSION//./}"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    URLS=(
        "https://github.com/ip7z/7zip/releases/download/${SEVENZIP_VERSION}/7z${VER_NODOT}-mac.tar.xz"
        "https://www.7-zip.org/a/7z${VER_NODOT}-mac.tar.xz"
    )
    OK=0
    for url in "${URLS[@]}"; do
        echo "Đang tải $url"
        if curl -fL --retry 2 --connect-timeout 15 -o "$TMP/7z.tar.xz" "$url"; then OK=1; break; fi
    done
    if [[ $OK -eq 0 ]]; then
        # Thử tìm bản mới nhất trên trang tải của 7-Zip.
        PAGE_URL="$(curl -fsL https://www.7-zip.org/download.html | grep -oE '[^"]*7z[0-9]+-mac\.tar\.xz' | head -1 || true)"
        if [[ -n "$PAGE_URL" ]]; then
            [[ "$PAGE_URL" == http* ]] || PAGE_URL="https://www.7-zip.org/$PAGE_URL"
            echo "Đang tải $PAGE_URL"
            curl -fL --retry 2 -o "$TMP/7z.tar.xz" "$PAGE_URL" && OK=1
        fi
    fi
    if [[ $OK -eq 1 ]]; then
        tar -xJf "$TMP/7z.tar.xz" -C "$TMP"
        [[ -f "$TMP/7zz" ]] || fail "Gói 7-Zip tải về không có 7zz."
        cp "$TMP/7zz" "$ROOT/Vendor/7zz"
        chmod +x "$ROOT/Vendor/7zz"
        [[ -f "$TMP/License.txt" ]] && cp "$TMP/License.txt" "$ROOT/Vendor/7-Zip-License.txt"
        xattr -dr com.apple.quarantine "$ROOT/Vendor/7zz" 2>/dev/null || true
        echo "Đã tải 7-Zip $SEVENZIP_VERSION."
    elif command -v 7zz >/dev/null 2>&1; then
        warn "Không tải được 7-Zip — dùng bản Homebrew: $(command -v 7zz)"
        cp "$(command -v 7zz)" "$ROOT/Vendor/7zz"
    else
        warn "Không tải được 7-Zip. RarX vẫn được tạo nhưng cần cài thêm: brew install sevenzip"
    fi
fi
if [[ -x "$ROOT/Vendor/7zz" ]]; then
    SEVEN_INFO="$("$ROOT/Vendor/7zz" </dev/null 2>/dev/null || true)"
    printf '%s\n' "$SEVEN_INFO" | sed -n '2p'
fi

# -----------------------------------------------------------------------------
step "2/5  Biên dịch mã nguồn Swift (bản phát hành)"
# Thư mục biên dịch tạm đặt ngoài iCloud/Tài liệu để nhanh hơn và không bị đồng bộ.
SCRATCH="${SCRATCH:-$HOME/Library/Caches/RarX-build}"
SWIFT_FLAGS=(-c release --scratch-path "$SCRATCH")
if [[ $UNIVERSAL -eq 1 ]]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi
swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
[[ -x "$BIN_DIR/$APP_NAME" ]] || fail "Không thấy tệp chạy $BIN_DIR/$APP_NAME"

# -----------------------------------------------------------------------------
step "3/5  Đóng gói $APP_NAME.app"
# Đóng gói và ký trong thư mục tạm (ngoài iCloud), vì iCloud tự gắn thuộc tính mở rộng
# khiến codesign báo "resource fork, Finder information, or similar detritus not allowed".
APP="$SCRATCH/package/$APP_NAME.app"
OUT_APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
if [[ -x "$ROOT/Vendor/7zz" ]]; then
    cp "$ROOT/Vendor/7zz" "$APP/Contents/MacOS/7zz"
fi
[[ -f "$ROOT/Vendor/7-Zip-License.txt" ]] && cp "$ROOT/Vendor/7-Zip-License.txt" "$APP/Contents/Resources/"
if [[ -x "$ROOT/Vendor/rar" ]]; then
    # Tuỳ chọn: tự đặt công cụ rar (đã có bản quyền) vào Vendor/ để đóng gói kèm.
    cp "$ROOT/Vendor/rar" "$APP/Contents/MacOS/rar"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Biểu tượng tệp nén (RAR, 7Z, ZIP…) mà Finder hiển thị cho các tệp RarX mở.
cp "$ROOT"/Resources/DocIcons/*.icns "$APP/Contents/Resources/"
cp "$ROOT/Resources/HuongDan.html" "$APP/Contents/Resources/HuongDan.html"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
    -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# -----------------------------------------------------------------------------
step "4/5  Ký ứng dụng (ad-hoc, chạy được trên máy này)"
# Bỏ thuộc tính mở rộng (Finder/iCloud) mà codesign không chấp nhận.
xattr -cr "$APP" 2>/dev/null || true
for helper in "$APP/Contents/MacOS/7zz" "$APP/Contents/MacOS/rar"; do
    [[ -f "$helper" ]] && codesign --force --sign - --timestamp=none "$helper"
done
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP" >/dev/null 2>&1 && echo "Chữ ký hợp lệ."

# -----------------------------------------------------------------------------
step "5/5  Hoàn tất"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -d "$OUT_APP" && -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$OUT_APP" >/dev/null 2>&1 || true
fi
rm -rf "$OUT_APP"
if [[ $INSTALL -eq 0 ]]; then
    # Khi cài thẳng vào Ứng dụng thì không để lại bản sao thứ hai (tránh macOS nhầm giữa hai bản RarX).
    mkdir -p "$ROOT/build"
    ditto "$APP" "$OUT_APP"
fi
if [[ $MAKE_DMG -eq 1 ]]; then
    mkdir -p "$ROOT/build"
    DMG="$ROOT/build/$APP_NAME.dmg"
    STAGE="$(mktemp -d)"
    ditto "$APP" "$STAGE/$APP_NAME.app"
    ln -s /Applications "$STAGE/Applications"
    rm -f "$DMG"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Đã tạo $DMG"
fi

if [[ $MAKE_ZIP -eq 1 ]]; then
    mkdir -p "$ROOT/build"
    ZIP="$ROOT/build/$APP_NAME.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Đã tạo $ZIP"
fi

if [[ $INSTALL -eq 1 ]]; then
    DEST="/Applications"
    if [[ ! -w "$DEST" ]]; then
        DEST="$HOME/Applications"
        mkdir -p "$DEST"
    fi
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$DEST/$APP_NAME.app"
    ditto "$APP" "$DEST/$APP_NAME.app"
    if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
        "$LSREGISTER" -f "$DEST/$APP_NAME.app" >/dev/null 2>&1 || true
    fi
    /System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
    bold "Đã cài: $DEST/$APP_NAME.app"
    open "$DEST/$APP_NAME.app"
    # Finder giữ biểu tượng tệp cũ trong bộ nhớ — khởi động lại Finder để hiện biểu tượng RAR/7Z mới.
    sleep 3
    echo "Làm mới biểu tượng tệp (Finder sẽ tự mở lại)…"
    killall Finder >/dev/null 2>&1 || true
else
    bold "Xong: $OUT_APP"
    echo "Mở thử:  open \"$OUT_APP\""
    echo "Cài đặt: ./build.sh --install"
fi
