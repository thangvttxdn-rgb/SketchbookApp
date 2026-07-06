import UIKit
import PencilKit

/// Flattens layers into a single image — used for the gallery thumbnail, PNG
/// export, the flood-fill snapshot and the AR texture.
enum LayerCompositor {
    /// Render one layer (its image then its strokes) at the given size, at
    /// FULL alpha: every caller applies `layer.opacity` exactly once itself
    /// (the editor via `.opacity()`, adjustments/filters by keeping the layer's
    /// opacity property). Baking it in here as well applied it twice.
    static func renderLayer(_ layer: Layer, size: CGSize, scale: CGFloat = 1) -> UIImage {
        // Light traits: in Dark Mode `PKDrawing.image` INVERTS ink colours
        // (black → white). Without this pin, applying any adjustment/filter in
        // the dark theme baked white ink into the layer — artwork "vanished"
        // on the white paper.
        renderInLightMode {
            let renderer = UIGraphicsImageRenderer(size: size, format: format(scale: scale))
            return renderer.image { _ in
                let rect = CGRect(origin: .zero, size: size)
                layer.image?.draw(in: rect, blendMode: .normal, alpha: 1)
                let strokeImage = layer.drawing.image(from: rect, scale: scale)
                strokeImage.draw(in: rect, blendMode: .normal, alpha: 1)
            }
        }
    }

    /// Composite the full document. `includeReference` keeps tracing-reference
    /// layers (off for export so trace photos never leak into the artwork).
    static func composite(_ document: SketchDocument,
                          includeReference: Bool = false,
                          includeBackground: Bool = true,
                          scale: CGFloat = 1) -> UIImage {
        renderInLightMode {
            let size = document.canvasSize
            let renderer = UIGraphicsImageRenderer(size: size, format: format(scale: scale))
            return renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                if includeBackground {
                    UIColor(hex: document.backgroundHex).setFill()
                    ctx.cgContext.fill(rect)
                    TemplateRenderer.render(document.template, size: size,
                                            backgroundColor: .clear).draw(in: rect)
                }
                for layer in document.layers where layer.isVisible {
                    if layer.isReference && !includeReference { continue }
                    layer.image?.draw(in: rect, blendMode: .normal, alpha: layer.opacity)
                    layer.drawing.image(from: rect, scale: scale)
                        .draw(in: rect, blendMode: .normal, alpha: layer.opacity)
                }
            }
        }
    }

    /// Run a render block under LIGHT traits so PencilKit never hands back
    /// dark-mode-inverted ink. ALL PKDrawing rasterisation must go through
    /// this (see the renderLayer note).
    private static func renderInLightMode(_ body: () -> UIImage) -> UIImage {
        var result = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            result = body()
        }
        return result
    }

    /// Small composite of ONE page (for the pages sidebar thumbnails).
    static func renderPage(_ page: Page, canvasSize: CGSize, backgroundHex: String,
                           maxDimension: CGFloat = 140) -> UIImage {
        let ratio = min(maxDimension / canvasSize.width, maxDimension / canvasSize.height, 1)
        let target = CGSize(width: max(canvasSize.width * ratio, 1),
                            height: max(canvasSize.height * ratio, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2   // crisp on retina at thumbnail size
        // Render under LIGHT traits: in Dark Mode PencilKit inverts ink colours
        // (black → white), which blanks the thumbnails on their white paper.
        var result = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            result = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                let rect = CGRect(origin: .zero, size: target)
                UIColor(hex: backgroundHex).setFill()
                ctx.cgContext.fill(rect)
                for layer in page.layers where layer.isVisible && !layer.isReference {
                    layer.image?.draw(in: rect, blendMode: .normal, alpha: layer.opacity)
                    layer.drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: ratio)
                        .draw(in: rect, blendMode: .normal, alpha: layer.opacity)
                }
            }
        }
        return result
    }

    /// Small preview of ONE layer (for the layers panel). Transparent areas
    /// show the paper colour so ink reads naturally at thumbnail size.
    static func renderLayerThumb(_ layer: Layer, canvasSize: CGSize, backgroundHex: String,
                                 maxDimension: CGFloat = 96) -> UIImage {
        let ratio = min(maxDimension / canvasSize.width, maxDimension / canvasSize.height, 1)
        let target = CGSize(width: max(canvasSize.width * ratio, 1),
                            height: max(canvasSize.height * ratio, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2   // crisp on retina at thumbnail size
        var result = UIImage()
        // Light traits: in Dark Mode PencilKit inverts ink colours (black →
        // white), which blanks the thumbnail on its light paper.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            result = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                let rect = CGRect(origin: .zero, size: target)
                UIColor(hex: backgroundHex).setFill()
                ctx.cgContext.fill(rect)
                layer.image?.draw(in: rect, blendMode: .normal, alpha: layer.opacity)
                layer.drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: ratio)
                    .draw(in: rect, blendMode: .normal, alpha: layer.opacity)
            }
        }
        return result
    }

    static func thumbnail(_ document: SketchDocument, maxDimension: CGFloat = 600) -> UIImage {
        let full = composite(document, includeReference: false, scale: 1)
        let size = document.canvasSize
        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1)
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in full.draw(in: CGRect(origin: .zero, size: target)) }
    }

    private static func format(scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat.default()
        f.scale = scale
        f.opaque = false
        return f
    }
}
