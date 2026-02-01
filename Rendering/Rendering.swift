import Foundation

public enum RenderingError: Error {
  case deviceUnavailable
  case shaderLibraryNotFound
  case pipelineCreationFailed(String)
  case textureCreationFailed
  case pixelBufferPoolCreationFailed
  case invalidOutputSize
}
