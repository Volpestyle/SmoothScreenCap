import CoreGraphics
import Metal

enum CursorTextureFactory {
    static func makeCursorTexture(device: MTLDevice, size: Int = 64) throws -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw CursorTextureError.textureCreationFailed
        }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let center = CGFloat(size) / 2
        let radius = CGFloat(size) / 2 - 2

        for y in 0..<size {
            for x in 0..<size {
                let dx = CGFloat(x) - center
                let dy = CGFloat(y) - center
                let distance = sqrt(dx * dx + dy * dy)

                let index = (y * size + x) * 4
                if distance <= radius {
                    let edgeSoftness: CGFloat = 2
                    let alpha = min(1.0, (radius - distance) / edgeSoftness)
                    pixels[index + 0] = 255  // B
                    pixels[index + 1] = 255  // G
                    pixels[index + 2] = 255  // R
                    pixels[index + 3] = UInt8(alpha * 255)  // A
                } else {
                    pixels[index + 0] = 0
                    pixels[index + 1] = 0
                    pixels[index + 2] = 0
                    pixels[index + 3] = 0
                }
            }
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: size * 4
        )

        return texture
    }

    enum CursorTextureError: Error {
        case textureCreationFailed
    }
}
