#!/bin/bash
# Nhấp đúp tệp này trong Finder để biên dịch và cài RarX vào thư mục Ứng dụng.
cd "$(dirname "$0")" || exit 1
clear
echo "=============================================="
echo "   Đang biên dịch và cài đặt RarX…"
echo "=============================================="
./build.sh --install 2>&1 | tee build.log
status=${PIPESTATUS[0]}
echo
if [ "$status" -eq 0 ]; then
    echo "✅ Đã cài xong RarX. Bạn có thể đóng cửa sổ này."
else
    echo "❌ Có lỗi (xem build.log trong thư mục RarX)."
fi
