// swift-tools-version:5.9
// RarX — trình nén & giải nén cho macOS.
// Mở thư mục này bằng Xcode (nhấp đúp Package.swift) để chỉnh sửa và chạy thử,
// hoặc chạy ./build.sh để tạo RarX.app hoàn chỉnh.

import PackageDescription

// Nhúng Info.plist tối giản vào tệp chạy, để bản chạy thử từ Xcode cũng có mã định danh ứng dụng.
let devInfoPlist = Context.packageDirectory + "/Resources/Info-dev.plist"

let package = Package(
    name: "RarX",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RarX",
            path: "Sources/RarX",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", devInfoPlist])
            ]
        )
    ]
)
