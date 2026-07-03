import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Procreate-style adjustments applied to the active layer with live-tunable
/// parameters (unlike `SketchFilter`, which is one-shot). Each adjustment
/// declares its slider metadata; `AdjustmentEngine.apply` runs the Core Image
/// pipeline with the chosen values.
enum SketchAdjustment: String, CaseIterable, Identifiable {
    // Color
    case hsb
    case colorBalance
    case gradientMapWarm
    // Blur
    case gaussianBlur
    case motionBlur
    // Stylize
    case noise
    case sharpen
    case bloom
    case halftone
    case chromaticAberration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hsb: return "Hue, Saturation, Brightness"
        case .colorBalance: return "Colour Balance"
        case .gradientMapWarm: return "Gradient Map"
        case .gaussianBlur: return "Gaussian Blur"
        case .motionBlur: return "Motion Blur"
        case .noise: return "Noise"
        case .sharpen: return "Sharpen"
        case .bloom: return "Bloom"
        case .halftone: return "Halftone"
        case .chromaticAberration: return "Chromatic Aberration"
        }
    }

    var systemImage: String {
        switch self {
        case .hsb: return "slider.horizontal.3"
        case .colorBalance: return "circle.lefthalf.filled"
        case .gradientMapWarm: return "circle.and.line.horizontal"
        case .gaussianBlur: return "drop.halffull"
        case .motionBlur: return "wind"
        case .noise: return "circle.dotted"
        case .sharpen: return "triangle"
        case .bloom: return "sun.max"
        case .halftone: return "circle.grid.3x3"
        case .chromaticAberration: return "rainbow"
        }
    }

    /// Menu grouping, mirroring Procreate's Adjustments panel sections.
    static var color: [SketchAdjustment] { [.hsb, .colorBalance, .gradientMapWarm] }
    static var blur: [SketchAdjustment] { [.gaussianBlur, .motionBlur] }
    static var stylize: [SketchAdjustment] { [.noise, .sharpen, .bloom, .halftone, .chromaticAberration] }

    /// Slider metadata for this adjustment.
    var parameters: [AdjustmentParam] {
        switch self {
        case .hsb:
            return [AdjustmentParam(key: "hue", label: "Hue", range: -180...180, initial: 0, unit: "°"),
                    AdjustmentParam(key: "saturation", label: "Saturation", range: 0...2, initial: 1),
                    AdjustmentParam(key: "brightness", label: "Brightness", range: -0.5...0.5, initial: 0)]
        case .colorBalance:
            return [AdjustmentParam(key: "temperature", label: "Warmth", range: 3000...10000, initial: 6500, unit: "K"),
                    AdjustmentParam(key: "tint", label: "Tint", range: -100...100, initial: 0)]
        case .gradientMapWarm:
            return [AdjustmentParam(key: "intensity", label: "Intensity", range: 0...1, initial: 0.8)]
        case .gaussianBlur:
            return [AdjustmentParam(key: "radius", label: "Radius", range: 0...40, initial: 8, unit: "px")]
        case .motionBlur:
            return [AdjustmentParam(key: "radius", label: "Distance", range: 0...40, initial: 20, unit: "px"),
                    AdjustmentParam(key: "angle", label: "Angle", range: -180...180, initial: 0, unit: "°")]
        case .noise:
            return [AdjustmentParam(key: "amount", label: "Amount", range: 0...1, initial: 0.25)]
        case .sharpen:
            return [AdjustmentParam(key: "sharpness", label: "Amount", range: 0...2, initial: 0.7)]
        case .bloom:
            return [AdjustmentParam(key: "intensity", label: "Intensity", range: 0...1.5, initial: 0.6),
                    AdjustmentParam(key: "radius", label: "Radius", range: 1...30, initial: 10, unit: "px")]
        case .halftone:
            return [AdjustmentParam(key: "width", label: "Dot Size", range: 4...30, initial: 10, unit: "px")]
        case .chromaticAberration:
            return [AdjustmentParam(key: "offset", label: "Offset", range: 0...24, initial: 6, unit: "px")]
        }
    }

    var defaultParams: [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, $0.initial) })
    }
}

struct AdjustmentParam: Identifiable {
    let key: String
    let label: String
    let range: ClosedRange<Double>
    let initial: Double
    var unit: String = ""
    var id: String { key }
}

enum AdjustmentEngine {
    private static let context = CIContext()

    /// Apply `adjustment` to `image` with the given parameter values (keys as
    /// declared in `SketchAdjustment.parameters`; missing keys use defaults).
    static func apply(_ adjustment: SketchAdjustment, to image: UIImage,
                      params: [String: Double]) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let merged = adjustment.defaultParams.merging(params) { _, new in new }
        func value(_ key: String) -> Double { merged[key] ?? 0 }
        var output: CIImage?

        switch adjustment {
        case .hsb:
            let hue = CIFilter.hueAdjust()
            hue.inputImage = input
            hue.angle = Float(value("hue") * .pi / 180)
            let cc = CIFilter.colorControls()
            cc.inputImage = hue.outputImage
            cc.saturation = Float(value("saturation"))
            cc.brightness = Float(value("brightness"))
            output = cc.outputImage
        case .colorBalance:
            let f = CIFilter.temperatureAndTint()
            f.inputImage = input
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: value("temperature"), y: value("tint"))
            output = f.outputImage
        case .gradientMapWarm:
            // Luminance → warm sunset ramp, blended back by intensity.
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = input
            let map = CIFilter.falseColor()
            map.inputImage = mono.outputImage
            map.color0 = CIColor(red: 0.16, green: 0.05, blue: 0.35)
            map.color1 = CIColor(red: 1.0, green: 0.78, blue: 0.36)
            let mapped = map.outputImage
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = input
            blend.targetImage = mapped
            blend.time = Float(value("intensity"))
            output = blend.outputImage
        case .gaussianBlur:
            let f = CIFilter.gaussianBlur()
            f.inputImage = input.clampedToExtent()
            f.radius = Float(value("radius"))
            output = f.outputImage
        case .motionBlur:
            let f = CIFilter.motionBlur()
            f.inputImage = input.clampedToExtent()
            f.radius = Float(value("radius"))
            f.angle = Float(value("angle") * .pi / 180)
            output = f.outputImage
        case .noise:
            // Monochrome grain dissolved over the artwork.
            let rnd = CIFilter.randomGenerator()
            let grain = rnd.outputImage?
                .cropped(to: input.extent)
            let mono = CIFilter.colorControls()
            mono.inputImage = grain
            mono.saturation = 0
            let blend = CIFilter.dissolveTransition()
            blend.inputImage = input
            blend.targetImage = mono.outputImage
            blend.time = Float(value("amount") * 0.5)
            output = blend.outputImage
        case .sharpen:
            let f = CIFilter.sharpenLuminance()
            f.inputImage = input
            f.sharpness = Float(value("sharpness"))
            output = f.outputImage
        case .bloom:
            let f = CIFilter.bloom()
            f.inputImage = input
            f.intensity = Float(value("intensity"))
            f.radius = Float(value("radius"))
            output = f.outputImage
        case .halftone:
            let f = CIFilter.dotScreen()
            f.inputImage = input
            f.width = Float(value("width"))
            f.angle = 0
            f.sharpness = 0.7
            f.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
            output = f.outputImage
        case .chromaticAberration:
            output = chromaticAberration(input, offset: CGFloat(value("offset")))
        }

        // Layers are transparent PNGs: re-mask with the ORIGINAL alpha for the
        // effects that would otherwise paint the empty area (halftone renders
        // white dots everywhere, noise/gradient dissolve onto transparency).
        if adjustment == .halftone || adjustment == .noise || adjustment == .gradientMapWarm,
           let effected = output {
            let masked = CIFilter.blendWithAlphaMask()
            masked.inputImage = effected
            masked.backgroundImage = CIImage(color: .clear).cropped(to: input.extent)
            masked.maskImage = input
            output = masked.outputImage
        }

        guard let result = output?.cropped(to: input.extent),
              let cg = context.createCGImage(result, from: input.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Shift the red channel one way and blue the other, then re-composite.
    private static func chromaticAberration(_ input: CIImage, offset: CGFloat) -> CIImage? {
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, dx: CGFloat) -> CIImage? {
            let m = CIFilter.colorMatrix()
            m.inputImage = input
            m.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
            m.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
            m.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
            m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return m.outputImage?.transformed(by: CGAffineTransform(translationX: dx, y: 0))
        }
        guard let red = channel(1, 0, 0, dx: offset),
              let green = channel(0, 1, 0, dx: 0),
              let blue = channel(0, 0, 1, dx: -offset) else { return nil }
        let add1 = CIFilter.additionCompositing()
        add1.inputImage = red
        add1.backgroundImage = green
        let add2 = CIFilter.additionCompositing()
        add2.inputImage = blue
        add2.backgroundImage = add1.outputImage
        return add2.outputImage
    }
}
