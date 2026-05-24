//
//  FeedPerformanceMonitor.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

import Foundation
import OSLog
import os.signpost
import Darwin
import CoreGraphics
import QuartzCore

@MainActor
enum FeedPerformanceMonitor {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ClipStack"
    private static let logger = Logger(subsystem: subsystem, category: "FeedPerformance")
    private static let signpostLog = OSLog(subsystem: subsystem, category: .pointsOfInterest)

    private static var settledPageCount = 0
    private static var firstFrameStartTimes: [Int: CFTimeInterval] = [:]
    private static var firstFrameSignposts: [Int: OSSignpostID] = [:]

    static func pageSettled(index: Int, total: Int) {
        settledPageCount += 1
        let memoryMB = residentMemoryMB() ?? -1

        logger.info(
            "page_settled index=\(index, privacy: .public) total=\(total, privacy: .public) settled_count=\(settledPageCount, privacy: .public) rss_mb=\(memoryMB, format: .fixed(precision: 1), privacy: .public)"
        )

        os_signpost(
            .event,
            log: signpostLog,
            name: "Page Settled",
            "index=%{public}d total=%{public}d settled_count=%{public}d rss_mb=%{public}.1f",
            index,
            total,
            settledPageCount,
            memoryMB
        )
    }

    static func scrollPhaseChanged(_ phase: String, velocityY: CGFloat) {
        logger.debug(
            "scroll_phase phase=\(phase, privacy: .public) velocity_y=\(Double(velocityY), format: .fixed(precision: 1), privacy: .public)"
        )
    }

    static func firstFrameRequested(index: Int, videoID: Int) {
        guard firstFrameStartTimes[index] == nil else { return }

        let signpostID = OSSignpostID(log: signpostLog)
        firstFrameStartTimes[index] = CACurrentMediaTime()
        firstFrameSignposts[index] = signpostID

        os_signpost(
            .begin,
            log: signpostLog,
            name: "First Frame",
            signpostID: signpostID,
            "index=%{public}d video_id=%{public}d",
            index,
            videoID
        )
    }

    static func firstFrameReady(index: Int, videoID: Int) {
        guard let start = firstFrameStartTimes.removeValue(forKey: index) else {
            return
        }

        let latencyMS = (CACurrentMediaTime() - start) * 1_000
        let signpostID = firstFrameSignposts.removeValue(forKey: index) ?? OSSignpostID(log: signpostLog)

        logger.info(
            "first_frame_ready index=\(index, privacy: .public) video_id=\(videoID, privacy: .public) latency_ms=\(latencyMS, format: .fixed(precision: 1), privacy: .public)"
        )

        os_signpost(
            .end,
            log: signpostLog,
            name: "First Frame",
            signpostID: signpostID,
            "index=%{public}d video_id=%{public}d latency_ms=%{public}.1f",
            index,
            videoID,
            latencyMS
        )
    }

    static func firstFrameFailed(index: Int, videoID: Int, message: String) {
        let signpostID = firstFrameSignposts.removeValue(forKey: index) ?? OSSignpostID(log: signpostLog)
        firstFrameStartTimes.removeValue(forKey: index)

        logger.error(
            "first_frame_failed index=\(index, privacy: .public) video_id=\(videoID, privacy: .public) message=\(message, privacy: .public)"
        )

        os_signpost(
            .end,
            log: signpostLog,
            name: "First Frame",
            signpostID: signpostID,
            "index=%{public}d video_id=%{public}d failed=1",
            index,
            videoID
        )
    }

    private static func residentMemoryMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return Double(info.resident_size) / 1_048_576
    }
}
