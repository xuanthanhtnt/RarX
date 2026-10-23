#!/bin/bash
# RarX — làm mới biểu tượng tệp nén khi Finder hiện tệp .rar/.7z trống.
clear
echo "=============================================="
echo "   RarX — làm mới biểu tượng tệp"
echo "=============================================="
echo "Bước này xoá bộ nhớ đệm biểu tượng của macOS (sẽ tự tạo lại)."
echo "Hãy nhập mật khẩu đăng nhập Mac khi được hỏi (khi gõ sẽ không hiện ký tự)."
echo
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in "$HOME"/.Trash/*.app; do
    [ -d "$app" ] && "$LS" -u "$app" && echo "Bỏ đăng ký: $(basename "$app")"
done
"$LS" -f /Applications/RarX.app
sudo -v || { echo "Không có mật khẩu — dừng lại."; exit 1; }
sudo rm -rf /Library/Caches/com.apple.iconservices.store
sudo find /private/var/folders/ \( -name com.apple.dock.iconcache -o -name com.apple.iconservices \) -exec rm -rf {} + 2>/dev/null
qlmanage -r cache >/dev/null 2>&1
sudo killall iconservicesd 2>/dev/null
killall iconservicesagent 2>/dev/null
killall Dock 2>/dev/null
killall Finder 2>/dev/null
echo
echo "✅ Xong. Nếu biểu tượng vẫn chưa hiện, hãy khởi động lại máy Mac một lần."
