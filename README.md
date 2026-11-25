# Vẽ Tranh — app vẽ cho iPad

Phát triển từ [Sketchbook Studio](https://github.com/alfredang/sketchbookapp) (giấy phép MIT,
© Tertiary Infotech Academy Pte Ltd). Bản này do thangvt.txdn@gmail.com bổ sung:

- **Giao diện tiếng Việt**, tên app "Vẽ Tranh", Bundle ID `vn.ctxdn.vetranh`.
- **Vẽ kỹ thuật**: mẫu giấy *Lưới mm* và *Khung bản vẽ* (viền + khung tên), khổ **A3**,
  hình **Ghi kích thước** (2 mũi tên + số mm, hiện số đo khi kéo). Khổ A4/A3 vẽ ở 200 dpi:
  1 mm = 7,876 px, tỉ lệ 1:1 khi in.
- **Xuất & chia sẻ**: PDF cả sổ (đúng khổ giấy), PNG trang này hoặc tất cả trang (••• → Xuất & chia sẻ).
- **Ghi chú lên PDF / ảnh**: Thư viện → + → *Ghi chú lên PDF* (tối đa 30 trang) hoặc *Ghi chú lên ảnh*.
  Mỗi trang có lớp nền khoá và lớp "Ghi chú"; xuất PDF ra bản đã chú thích.
- **Tô màu cho bé**: 6 tranh nét (tàu hoả, ngôi nhà, bông hoa, con cá, trời nắng, con bướm);
  chọn công cụ Đổ màu rồi chạm vào từng vùng.

## Build không cần Mac

Mỗi lần đẩy code, GitHub Actions (`.github/workflows/build.yml`) build trên macOS và đính kèm
file **VeTranh-unsigned.ipa** ở mục *Actions → lần chạy → Artifacts*.

Cài lên iPad từ Windows: tải Sideloadly → cắm iPad → kéo file .ipa vào → đăng nhập Apple ID → Start.
Với Apple ID miễn phí, app hết hạn sau 7 ngày (cài lại để gia hạn) và iCloud không hoạt động
(app tự lưu trên máy). Muốn phát hành TestFlight/App Store cần tài khoản Apple Developer
(99 USD/năm) và điền `DEVELOPMENT_TEAM` trong `project.yml`.

> Ghi chú: UI test gốc (`SketchbookUITests`) tìm nút theo nhãn tiếng Anh nên cần cập nhật
> trước khi chạy lại; CI hiện chỉ kiểm tra biên dịch.

---

# Sketchbook

A natural drawing studio for **iPad & iPhone** — sketch with pressure-sensitive brushes and Apple Pencil (or finger), work in **multi-page** sketchbooks and layers, trace reference photos, use symmetry and rulers, fill with color, apply filter effects, and bring your art into the real world with **AR**. Everything syncs to your personal **iCloud**.

![Sketchbook — editor with the iPad side panel](screenshot.png)

[![Platform](https://img.shields.io/badge/platform-iPadOS%20%7C%20iOS%2017%2B-blue.svg)](https://www.apple.com/ipados/)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI-brightgreen.svg)](https://developer.apple.com/xcode/swiftui/)
[![Drawing](https://img.shields.io/badge/engine-PencilKit-purple.svg)](https://developer.apple.com/documentation/pencilkit)
[![AR](https://img.shields.io/badge/AR-RealityKit-red.svg)](https://developer.apple.com/augmented-reality/realitykit/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](#license)

## Features

| Feature | How it works |
|---------|--------------|
| ✏️ **Brush library** | 20 Procreate-style brushes grouped into **Inking · Sketching · Painting** (incl. the ✨ **Stardust** particle brush), each with live stroke previews |
| ✒️ **Pencil grades** | Graphite 2H · H · HB · 2B · 4B · 6B (darkness + width) |
| 📄 **Multi-page sketchbooks** | Many pages per sketchbook — pull firmly past the top/bottom edge to flip (past the last page creates a new one), add before/after, clear or delete |
| 🗒️ **Pages sidebar** | iPad: every page as a live thumbnail — tap to jump, drag to reorder, trash to delete |
| 🔷 **Vector shapes** | Rectangle, circle, triangle, line, diamond, star, pentagon, hexagon, arrow & heart — drag out, rotate/resize/flip with handles, optional solid fill |
| 📐 **Canvas presets** | Square, Standard, Wide, A4 & Letter sizes with portrait/landscape and selectable paper colors |
| 🔍 **Pinch to zoom** | Two-finger pinch (1×–5×) — **all layers zoom & pan together**; double-tap to reset |
| 🤌 **Quick gestures** | Two-finger tap = undo, three-finger tap = redo (Procreate-style) |
| 📱 **iPad side panel** | Collapsible, tabbed inspector (Brushes / Shapes / Adjustments / Color / Layers) — pickers open here, never over the canvas |
| 📏 **Adjustable size** | Brush & eraser size sliders; full-spectrum color picker with opacity + quick palette |
| 🪣 **Color fill** | Tap-again colour dialog on the fill tool; vector-fills placed shapes, scanline flood-fill everywhere else (template lines never fence fills) |
| 🧽 **Eraser** | Bitmap eraser with adjustable size + live preview |
| 🪢 **Lasso** | Select, move, cut & duplicate strokes |
| ↩️ **Undo / Redo** | Unified document timeline — strokes, fills, shapes, adjustments, page & layer edits |
| 🎚️ **Adjustments** | Live-preview HSB, Colour Balance, Gradient Map, Gaussian/Motion Blur, Noise, Sharpen, Bloom, Halftone, Chromatic Aberration |
| 🎨 **Filter effects** | Mono, Sepia, Vibrant, Invert, Comic, Soft Blur |
| 🖌️ **Painting styles** | Oil, Watercolor, Pointillism, Mosaic (Core Image) |
| 🗂️ **Layers** | Live thumbnails, add / duplicate / reorder / lock / hide / rename, per-layer opacity, **groups** |
| 🖼️ **Insert images** | Add photos or files as artwork layers (Procreate-style Add) |
| 📐 **Drawing guides** | Ruler, 1/2/3-point **perspective**, isometric & grid overlays |
| 🔁 **Symmetry guides** | Vertical, Horizontal & 4-way (kaleidoscope) live mirroring |
| ✍️ **Pencil or finger** | iPad defaults to Apple Pencil drawing (fingers pan/zoom/undo) with a one-tap finger-drawing toggle; iPhone draws with fingers; palm rejection while stroking |
| 💾 **Autosave** | Saves seconds after every change and when the app backgrounds |
| 🔒 **Orientation lock** | Pin the current orientation so the canvas won't rotate while you draw |
| 📄 **Templates** | Blank, **Ring File**, Ruled, Grid, Dot Grid, Isometric, Storyboard, Music Staff |
| 🖼️ **Learn by tracing** | Import a photo as an adjustable-opacity reference overlay |
| ⭐ **Favorites** | Star sketches; favorites sort to the top |
| ⚙️ **Settings** | Light / Dark / System theme, tool & new-sketch defaults |
| ☁️ **iCloud storage** | Sketches saved to your personal iCloud Documents container (local fallback) |
| 🪄 **Sketch → AR** | Place your flattened artwork onto a real surface with RealityKit |

## Tech Stack

- **SwiftUI** — app shell, gallery, editor UI, panels
- **PencilKit** — drawing canvas, ink/brush tools, eraser, ruler, palm rejection
- **Core Image** — filter effects
- **Core Graphics** — flood fill, page-template rendering, layer compositing
- **RealityKit + ARKit** — sketch-to-AR placement
- **iCloud Documents (FileManager ubiquity container)** — cross-device sync
- **PhotosUI** — reference-image import
- **XcodeGen** — project generation from `project.yml`

## Architecture

```
Sketchbook/
├── App/            SketchbookApp (entry), Info.plist, entitlements
├── Theme/          Brand tokens (Theme.swift), color-hex helpers
├── Models/         SketchDocument (multi-page), Page, Layer, BrushType, Template
├── Store/          DocumentStore — iCloud + local persistence
├── Drawing/        CanvasView (PencilKit), SymmetryEngine, FloodFill,
│                   FilterEngine, TemplateRenderer, LayerCompositor
├── AR/             ARSketchView / ARSketchScreen (RealityKit)
└── Features/
    ├── Gallery/    Browse, new-sketch sheet, duplicate, delete
    ├── Editor/     EditorView, EditorViewModel, toolbar panels
    └── About/      About + Feedback tabs (Tertiary Infotech house style)
```

Each sketch is a JSON `.sketch` document — a sketchbook of one or more **pages**, each with its own
layer stack (layers store serialized `PKDrawing` data + optional raster images). The editor keeps
**one persistent `PKCanvasView`** for the active layer; inactive layers are composited to images and
stacked in z-order, mirroring the canvas's live zoom/offset so every layer stays in register at any
zoom. All `PKDrawing` rasterisation runs under light traits (Dark Mode inverts PencilKit ink).
Symmetry mirrors freshly drawn strokes on commit. Color fill vector-fills placed shapes or
flood-fills a rasterised artwork snapshot. Documents written before multi-page support migrate
automatically.

## Getting Started

Requirements: **Xcode 16+** (iOS 26 SDK), an iPad or iPad Simulator (iPadOS 17+), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/alfredang/sketchbookapp.git
cd sketchbookapp
xcodegen generate            # produces Sketchbook.xcodeproj from project.yml
open Sketchbook.xcodeproj     # then Run on an iPad / simulator
```

Or build from the command line:

```bash
xcodebuild -project Sketchbook.xcodeproj -scheme Sketchbook \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  build
```

> iCloud and AR require running on a real device with a signing team. In the Simulator the app
> automatically falls back to local on-device storage, and AR shows a camera-preview placement.

## Roadmap

- Animated/looping AR placement and export to USDZ
- Brush studio (custom textures, stabilization, taper)
- Per-page export (PDF)
- Shared iCloud sketchbooks

## License

MIT © Tertiary Infotech Academy Pte Ltd
