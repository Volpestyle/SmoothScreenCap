import CoreMedia

struct SampleBufferRetimer {
  let offset: CMTime

  func retime(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
    var count: CMItemCount = 0
    let status = CMSampleBufferGetSampleTimingInfoArray(
      sampleBuffer,
      entryCount: 0,
      arrayToFill: nil,
      entriesNeededOut: &count
    )
    if status != noErr || count == 0 {
      return sampleBuffer
    }

    var timingInfo = [CMSampleTimingInfo](repeating: .invalid, count: count)
    let fillStatus = CMSampleBufferGetSampleTimingInfoArray(
      sampleBuffer,
      entryCount: count,
      arrayToFill: &timingInfo,
      entriesNeededOut: &count
    )
    if fillStatus != noErr {
      return sampleBuffer
    }

    for index in timingInfo.indices {
      if timingInfo[index].presentationTimeStamp.isValid {
        let shifted = timingInfo[index].presentationTimeStamp - offset
        timingInfo[index].presentationTimeStamp = CMTimeCompare(shifted, .zero) < 0 ? .zero : shifted
      }
      if timingInfo[index].decodeTimeStamp.isValid {
        let shifted = timingInfo[index].decodeTimeStamp - offset
        timingInfo[index].decodeTimeStamp = CMTimeCompare(shifted, .zero) < 0 ? .zero : shifted
      }
    }

    var outputBuffer: CMSampleBuffer?
    let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
      allocator: kCFAllocatorDefault,
      sampleBuffer: sampleBuffer,
      sampleTimingEntryCount: count,
      sampleTimingArray: &timingInfo,
      sampleBufferOut: &outputBuffer
    )
    if copyStatus != noErr {
      return sampleBuffer
    }
    return outputBuffer ?? sampleBuffer
  }
}
