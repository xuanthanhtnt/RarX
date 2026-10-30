# RarX — trình nén & giải nén cho macOS

RarX là ứng dụng nén/giải nén gốc cho macOS (SwiftUI + AppKit), dùng **7-Zip** chính chủ làm lõi
và **RAR của RARLAB** (tuỳ chọn) để tạo/sửa tệp `.rar`.

## Tính năng

| Nhóm | Chi tiết |
|---|---|
| Mở & duyệt | Xem nội dung tệp nén như Finder: cây thư mục bên trái, bảng tệp (tên, kích thước, sau nén, tỉ lệ, loại, ngày sửa, CRC32), sắp xếp theo cột, tìm kiếm toàn bộ tệp nén, thanh đường dẫn |
| Giải nén | Toàn bộ hoặc chỉ mục đã chọn; tự tạo thư mục khi cần; xử lý trùng tên (hỏi / ghi đè / bỏ qua / giữ cả hai); mật khẩu; mở thư mục khi xong; chuyển tệp nén vào Thùng rác |
| Nén | 7Z, ZIP, TAR, TAR.GZ, TAR.XZ, TAR.BZ2, RAR*; 6 mức nén; mật khẩu AES-256 (ẩn cả tên tệp với 7Z/RAR); ZipCrypto tương thích Finder; chia nhiều phần (100 MB, 700 MB, 4 GB FAT32, DVD, tuỳ chỉnh); solid; bản ghi khôi phục & khoá tệp (RAR); ghi chú (RAR); bỏ tệp rác macOS; kiểm tra sau khi nén; nén mỗi mục thành tệp riêng |
| Sửa tệp nén | Thêm tệp (kéo thả hoặc nút Thêm) vào đúng thư mục đang xem, xoá, đổi tên, tạo thư mục mới — với 7Z, ZIP, TAR (RAR cần công cụ RAR) |
| Tiện ích | Kiểm tra tính toàn vẹn, sửa tệp hỏng (RAR/ZIP), chuyển đổi định dạng (vd. RAR → ZIP), xem nhanh (Quick Look), mở tệp trong tệp nén, kéo tệp ra Finder, đo hiệu năng, tính mã kiểm tra (CRC32/SHA-1/SHA-256/SHA-512/MD5…) |
| Tích hợp macOS | Mở bằng nhấp đúp, thả lên Dock, Finder ▸ Thao tác nhanh/Dịch vụ (Nén…, Nén nhanh ZIP, Giải nén tại đây, Giải nén vào thư mục riêng, Giải nén…, Mã kiểm tra), menu Dock, Mở gần đây, chế độ tối |
| Định dạng đọc | 7Z, ZIP, RAR/RAR5, TAR, GZ, BZ2, XZ, ZST, ISO, DMG, CAB, WIM, ARJ, LZH, CPIO, RPM, DEB, tệp chia phần `.001` / `.partN.rar` |

\* Tạo `.rar` cần công cụ dòng lệnh `rar` (RAR for macOS) của RARLAB — RarX **tự tải bản chính thức từ rarlab.com** ở lần mở đầu tiên và cập nhật bằng một nút bấm (xem bên dưới).

## Cài đặt nhanh

Yêu cầu: macOS 13 Ventura trở lên và **Xcode** (miễn phí trên App Store).

Cách dễ nhất: **nhấp đúp `Cài đặt RarX.command`** trong Finder. Terminal sẽ mở ra, tự tải 7-Zip,
biên dịch, cài RarX vào thư mục Ứng dụng rồi mở ứng dụng (lần đầu mất khoảng 1–2 phút).
Nếu macOS chặn, chuột phải vào tệp ▸ Mở.

Hoặc trong Terminal:

```bash
cd RarX
./build.sh --install      # biên dịch, đóng gói 7-Zip, cài vào /Applications và mở RarX
```

Các tuỳ chọn khác:

```bash
./build.sh                # chỉ tạo build/RarX.app
./build.sh --dmg          # tạo thêm build/RarX.dmg để gửi cho người khác
./build.sh --universal    # chạy trên cả Apple Silicon và Intel (cần Xcode đầy đủ)
```

Lần đầu `build.sh` tự tải `7zz` (7-Zip cho macOS) từ GitHub/7-zip.org vào thư mục `Vendor/`.
Không có mạng thì cài bằng Homebrew trước: `brew install sevenzip`.

### Lần mở đầu tiên

Ứng dụng được ký "ad-hoc" trên chính máy bạn nên mở bình thường. Nếu bạn gửi `RarX.dmg` sang máy khác,
máy đó cần chuột phải vào RarX ▸ **Mở** ở lần đầu (vì chưa được Apple công chứng).

### Bật trong menu chuột phải của Finder

Sau khi cài, chuột phải vào tệp ▸ **Thao tác nhanh** hoặc **Dịch vụ** sẽ có các mục “RarX: …”.
Nếu chưa thấy: Cài đặt hệ thống ▸ Bàn phím ▸ Phím tắt bàn phím ▸ Dịch vụ ▸ bật các mục RarX.

### Biểu tượng

Biểu tượng ứng dụng lấy từ `Resources/Artwork/app-icon-source.png` (nền tối, ánh sáng cyan) và biểu tượng tệp nén
(RAR, 7Z, ZIP, TAR, GZ, XZ, ZST, CAB, WIM, tệp chia phần…) lấy từ `Resources/Artwork/file-icon-source.png`
(tím – cam, kèm nhãn phần mở rộng nhỏ ở dưới). Muốn thay hình: chép ảnh mới đè lên hai tệp đó rồi chạy

```bash
python3 scripts/make_icons.py            # tạo lại Resources/AppIcon.icns và Resources/DocIcons/*.icns
python3 scripts/make_icons.py xem.png    # kèm ảnh xem trước;  thêm --no-badge để bỏ nhãn phần mở rộng
```

Khi cài, RarX tự nhận mở các định dạng macOS không hỗ trợ (RAR, 7Z…) để Finder dùng biểu tượng này. Nếu tệp .rar/.7z
vẫn hiện trang trống (thường do ứng dụng nén cũ để lại bộ nhớ đệm biểu tượng), nhấp đúp
**`Làm mới biểu tượng.command`** và nhập mật khẩu Mac — Dock và Finder sẽ khởi động lại với biểu tượng mới.

### Đặt RarX làm ứng dụng mặc định

RarX ▸ Cài đặt ▸ Chung ▸ *Ứng dụng mặc định*, hoặc trong Finder: chọn một tệp `.rar` ▸ ⌘I ▸ Mở bằng ▸ RarX ▸ Thay đổi tất cả.

### Công cụ RAR (tự cài, cập nhật bằng một nút)

RarX không đóng gói sẵn `rar` (bản quyền thuộc RARLAB). Thay vào đó:

1. **Lần mở đầu tiên** (cần mạng), RarX tự tải gói “RAR for macOS” chính thức từ rarlab.com — đúng kiến trúc Apple Silicon/Intel —
   và cất trong `~/Library/Application Support/RarX/Tools/rar`. Không cần quyền quản trị, không mất khi cập nhật RarX.
2. Khi RARLAB phát hành bản mới, **RarX ▸ Cài đặt ▸ Công cụ** hiện nút **Cập nhật lên RAR x.xx** — bấm một lần là xong
   (RarX cũng tự kiểm tra mỗi ngày khi mở ứng dụng; tắt được trong cùng mục).
3. Có khoá bản quyền? Bấm **Nhập khoá bản quyền…** và chọn tệp `rarreg.key`; khoá được giữ lại qua các lần cập nhật.
4. Đã có sẵn `rar` ở nơi khác (Homebrew…)? Mở *Nâng cao* trong cùng mục để chỉ đường dẫn.

Giải nén `.rar` **không** cần công cụ này — 7-Zip đã đọc được. Gói của RARLAB là bản dùng thử; nếu dùng lâu dài hãy mua giấy phép tại rarlab.com.

### Cập nhật RarX

**RarX ▸ Kiểm tra cập nhật…** (hoặc cửa sổ **Giới thiệu RarX**, nơi cũng có thông tin nhà phát triển) hỏi GitHub bản phát hành
mới nhất của kho [`xuanthanhtnt/RarX`](https://github.com/xuanthanhtnt/RarX). Nếu mới hơn bản đang chạy, bấm **Cập nhật ngay**:
RarX tải `RarX-<phiên bản>.zip`, kiểm tra đúng ứng dụng, tự thoát, thay bản cũ rồi mở lại. Mặc định RarX tự kiểm tra mỗi 12 giờ.
Đổi kho GitHub hoặc thông tin nhà phát triển ở `Sources/RarX/Updates/AppInfo.swift`.

## Phát triển bằng Xcode

Nhấp đúp `Package.swift` để mở bằng Xcode, chọn scheme **RarX** ▸ ⌘R. Khi chạy từ Xcode, RarX tìm `7zz` trong
`Vendor/` (chạy `./build.sh` một lần để tải) hoặc trong Homebrew. Tích hợp Finder và loại tệp mặc định chỉ hoạt động
với bản `.app` do `build.sh` tạo.

> Lưu ý: hãy dùng bộ công cụ của Xcode. Command Line Tools trên một số phiên bản macOS thiếu plugin macro của SwiftUI
> (lỗi `SwiftUIMacros.StateMacro could not be found`); `build.sh` tự chọn Xcode nếu có.

## Build và phát hành trên GitHub

Workflow `.github/workflows/build.yml` chạy trên máy chủ macOS của GitHub:

- Mỗi lần đẩy lên `main` (hoặc mở Pull Request): biên dịch bản Universal (Apple Silicon + Intel), kiểm tra gói và lưu
  `RarX-<phiên bản>.zip` / `.dmg` trong mục **Actions ▸ Artifacts**.
- **Phát hành bản mới** (cách dễ nhất, không cần dòng lệnh): trên GitHub mở **Actions ▸ Build RarX ▸ Run workflow** và bấm
  nút xanh. Mặc định workflow phát hành đúng số `VERSION=` trong `build.sh` (hiện là 1.1.2); có thể điền số khác ở ô
  *release_version*, hoặc bỏ tích *publish* nếu chỉ muốn build thử. Kết quả: một Release `v1.1.2` kèm `RarX-1.1.2.zip`,
  `RarX-1.1.2.dmg` và `SHA256SUMS.txt`.
- Hoặc tạo Release thủ công trên GitHub (**Releases ▸ Draft a new release**) với **tag dạng `v1.2.0`** (chữ `v` + số, không phải
  `V12`) rồi **Publish release** — workflow tự build và đính kèm các tệp vào Release đó.
- Trước khi phát hành, tăng `VERSION=` trong `build.sh` cho khớp số phiên bản mới.

Người đang dùng RarX chỉ cần bấm **Cập nhật ngay** là nhận bản này.

## Cấu trúc mã nguồn

```
Sources/RarX/
├── App/        Khởi động, AppDelegate, menu, quản lý cửa sổ, Dịch vụ Finder
├── Engine/     Gọi 7-Zip/RAR: liệt kê, giải nén, nén, sửa, chuyển đổi; phân tích đầu ra; định dạng
├── Updates/    Thông tin ứng dụng, cập nhật RarX từ GitHub Releases, tự cài/cập nhật công cụ RAR
├── Model/      Tài liệu tệp nén (cây thư mục, lựa chọn), tác vụ nền, cài đặt, luồng công việc chung
└── UI/         Giao diện SwiftUI: màn hình chào, cửa sổ duyệt, bảng nén/giải nén, cài đặt, công cụ
Resources/      Info.plist (loại tệp, Dịch vụ), biểu tượng, ảnh gốc biểu tượng (Artwork/), trang hướng dẫn
scripts/        make_icons.py — tạo biểu tượng ứng dụng và biểu tượng tệp từ ảnh gốc
.github/        Workflow build và phát hành
```

## Giấy phép thành phần

- **7-Zip** © Igor Pavlov — GNU LGPL, kèm giới hạn unRAR (không dùng mã giải nén RAR để tái tạo thuật toán nén RAR).
  Tệp giấy phép được đóng gói vào `RarX.app/Contents/Resources/7-Zip-License.txt`.
- **RAR** © Alexander Roshal / RARLAB — RarX không đóng gói sẵn mà tải công cụ `rar` chính thức từ rarlab.com về máy người dùng.
  RarX là ứng dụng độc lập, không liên kết với RARLAB hay WinRAR.
