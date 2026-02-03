import AppKit
import CoreGraphics
import EventLog
import Metal

enum CursorTextureFactory {
    private static var textureCache: [CursorType: MTLTexture] = [:]
    private static var hotspotCache: [CursorType: CGPoint] = [:]

    static func cursorTexture(for type: CursorType, device: MTLDevice) -> MTLTexture? {
        if let cached = textureCache[type] {
            return cached
        }
        guard let nsCursor = nsCursor(for: type),
              let texture = makeTexture(from: nsCursor, device: device) else {
            return nil
        }
        textureCache[type] = texture
        hotspotCache[type] = nsCursor.hotSpot
        return texture
    }

    static func hotspot(for type: CursorType) -> CGPoint {
        if let cached = hotspotCache[type] {
            return cached
        }
        guard let nsCursor = nsCursor(for: type) else {
            return CGPoint(x: 0, y: 0)
        }
        let hotspot = nsCursor.hotSpot
        hotspotCache[type] = hotspot
        return hotspot
    }

    static func loadAllCursorTextures(device: MTLDevice) -> [CursorType: MTLTexture] {
        var textures: [CursorType: MTLTexture] = [:]
        for type in CursorType.allCases {
            if let texture = cursorTexture(for: type, device: device) {
                textures[type] = texture
            }
        }
        return textures
    }

    static func clearCache() {
        textureCache.removeAll()
        hotspotCache.removeAll()
    }

    private static func nsCursor(for type: CursorType) -> NSCursor? {
        switch type {
        case .arrow: return NSCursor.arrow
        case .iBeam: return NSCursor.iBeam
        case .pointingHand: return NSCursor.pointingHand
        case .crosshair: return NSCursor.crosshair
        case .closedHand: return NSCursor.closedHand
        case .openHand: return NSCursor.openHand
        case .resizeLeft: return NSCursor.resizeLeft
        case .resizeRight: return NSCursor.resizeRight
        case .resizeLeftRight: return NSCursor.resizeLeftRight
        case .resizeUp: return NSCursor.resizeUp
        case .resizeDown: return NSCursor.resizeDown
        case .resizeUpDown: return NSCursor.resizeUpDown
        case .disappearingItem: return NSCursor.disappearingItem
        case .operationNotAllowed: return NSCursor.operationNotAllowed
        case .dragLink: return NSCursor.dragLink
        case .dragCopy: return NSCursor.dragCopy
        case .contextualMenu: return NSCursor.contextualMenu
        }
    }

    private static func makeTexture(from cursor: NSCursor, device: MTLDevice) -> MTLTexture? {
        let image = cursor.image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        return texture
    }
}
