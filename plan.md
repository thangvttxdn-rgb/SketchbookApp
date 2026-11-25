# Kế hoạch: Vẽ Tranh cho iPad (dựa trên Sketchbook Studio, MIT)

Nguồn gốc: github.com/alfredang/sketchbookapp, giấy phép MIT, giữ nguyên ghi chú bản quyền gốc.

## Phạm vi (hướng C)

1. **Thương hiệu + Việt hoá**: tên app "Vẽ Tranh", Bundle ID `vn.thangvt.vetranh`, giao diện tiếng Việt,
   About ghi người bổ sung thangvt.txdn@gmail.com, ghi công tác giả gốc.
2. **Vẽ kỹ thuật**: mẫu giấy "Lưới mm" và "Khung bản vẽ" (viền + khung tên), khổ A3,
   hình "Ghi kích thước" (đường có 2 mũi tên + nhãn số mm, hiện số đo trực tiếp khi kéo).
   Quy ước tỉ lệ: khổ A4/A3 vẽ ở 200 dpi, 1 mm = 7,876 px (tỉ lệ 1:1 so với giấy in).
3. **Xuất PDF nhiều trang**: cả sổ thành 1 file PDF đúng khổ giấy; xuất PNG trang hiện tại hoặc tất cả trang.
4. **Ghi chú lên ảnh/PDF**: từ Thư viện, mở PDF (tối đa 30 trang) hoặc ảnh, mỗi trang có lớp nền khoá
   và lớp "Ghi chú" để vẽ lên; xuất lại PDF đã chú thích.
5. **Tô màu cho bé**: 6 tranh nét vẽ bằng code (tàu hoả, ngôi nhà, bông hoa, con cá, mặt trời, con bướm),
   lớp nét vẽ khoá ở trên, lớp màu ở dưới để đổ màu không đè nét.
6. **Build không cần Mac**: GitHub Actions (macOS) build bản Simulator + file .ipa chưa ký
   để cài bằng Sideloadly/AltStore từ Windows.

## Kiểm tra

- Không có trình biên dịch Swift trên Linux → kiểm tra bằng GitHub Actions sau khi đẩy code; sửa đến khi build xanh.
- UI test gốc dùng nhãn tiếng Anh nên không chạy trong CI (ghi chú trong README).
