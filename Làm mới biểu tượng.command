#!/bin/bash
# RarX — làm mới biểu tượng ứng dụng và biểu tượng tệp nén (.rar, .7z, .zip…) trong Finder/Dock.
clear
echo "=============================================="
echo "   RarX — làm mới biểu tượng"
echo "=============================================="

LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
APP=/Applications/RarX.app
[ -d "$APP" ] || APP="$HOME/Applications/RarX.app"
if [ ! -d "$APP" ]; then
    echo "❌ Không thấy RarX.app trong thư mục Ứng dụng."
    echo "   Hãy cài RarX trước (nhấp đúp “Cài đặt RarX.command”, hoặc kéo RarX từ tệp .dmg vào Ứng dụng)."
    exit 1
fi

VER="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
echo "RarX đang cài: $VER  ($APP)"
case "$VER" in
    1.0*|0.*)
        echo
        echo "⚠️  Đây là bản cũ (biểu tượng cũ). Hãy cài bản 1.1.0 trở lên trước:"
        echo "    • nhấp đúp “Cài đặt RarX.command” trong thư mục RarX mới, hoặc"
        echo "    • tải RarX .dmg ở https://github.com/xuanthanhtnt/RarX/releases rồi kéo vào Ứng dụng."
        echo "   Sau đó chạy lại tệp này."
        exit 1 ;;
esac
echo

# 1. Bỏ đăng ký mọi bản RarX khác (Thùng rác, thư mục build, Xcode…) để macOS không lấy biểu tượng từ bản cũ.
echo "Bỏ đăng ký các bản RarX cũ…"
for app in "$HOME"/.Trash/*.app; do
    [ -d "$app" ] && "$LS" -u "$app" 2>/dev/null
done
mdfind "kMDItemCFBundleIdentifier == 'com.rarx.app'" 2>/dev/null | while IFS= read -r other; do
    [ "$other" != "$APP" ] && [ -d "$other" ] && "$LS" -u "$other" 2>/dev/null && echo "  - $other"
done
find "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop" -maxdepth 4 -name "RarX.app" -not -path "$APP" 2>/dev/null | while IFS= read -r other; do
    "$LS" -u "$other" 2>/dev/null && echo "  - $other"
done

# 2. Đăng ký lại bản đang cài.
"$LS" -f -R -trusted "$APP"
echo "Đã đăng ký lại $APP"

# 3. Xoá bộ nhớ đệm biểu tượng (cần mật khẩu Mac; khi gõ sẽ không hiện ký tự).
echo
echo "Xoá bộ nhớ đệm biểu tượng của macOS (tự tạo lại). Nhập mật khẩu đăng nhập Mac khi được hỏi:"
sudo -v || { echo "Không có mật khẩu — dừng lại."; exit 1; }
sudo rm -rf /Library/Caches/com.apple.iconservices.store
sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -o -name com.apple.iconservices -o -name com.apple.iconservicesagent \) -exec rm -rf {} + 2>/dev/null
rm -rf "$HOME"/Library/Caches/com.apple.iconservices* 2>/dev/null
qlmanage -r cache >/dev/null 2>&1
sudo killall iconservicesd 2>/dev/null
killall iconservicesagent 2>/dev/null

# 4. Mở RarX một lần để nó nhận làm ứng dụng mặc định cho .rar/.7z…, rồi khởi động lại Dock và Finder.
open -g "$APP"
sleep 3
killall Dock 2>/dev/null
killall Finder 2>/dev/null

echo
echo "✅ Xong. Dock và Finder đang khởi động lại — đợi vài giây rồi mở thư mục chứa tệp .rar/.7z."
echo "   • Biểu tượng RarX chỉ hiện cho tệp mà RarX là ứng dụng mặc định."
echo "     .zip mặc định do “Archive Utility” của macOS quản lý nên giữ biểu tượng zip của Apple;"
echo "     muốn đổi: RarX ▸ Cài đặt ▸ Chung ▸ Ứng dụng mặc định ▸ “Cả tệp ZIP”."
echo "   • Nếu vẫn chưa thấy biểu tượng mới: khởi động lại máy Mac một lần."
