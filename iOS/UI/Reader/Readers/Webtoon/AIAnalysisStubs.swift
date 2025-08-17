//  AIAnalysisStubs.swift
//  Tanoshi (iOS)
//
//  Lightweight fallbacks compiled when the real AIAnalysis sources are not
//  part of the target. These provide no-op implementations just to satisfy
//  references in reader files.

import Foundation
import UIKit

// MARK: - Minimal Models

struct DialogueLine {
	let pageIndex: Int
	let textId: Int
	let speaker: String
	let text: String
	let timestamp: TimeInterval?
}

struct AudioSegment {
	let dialogueId: String
	let audioData: Data
	let duration: TimeInterval
	let speaker: String
	let text: String
}

struct PageAnalysis {
	let pageIndex: Int
}

struct AnalysisResult {
	let mangaId: String
	let chapterId: String
	let pages: [PageAnalysis]
	let transcript: [DialogueLine]
	let audioSegments: [AudioSegment]?
}

// MARK: - Config Manager (no-op)

actor AIAnalysisConfigManager {
	static let shared = AIAnalysisConfigManager()
	var isAutoAnalysisEnabled: Bool { false }
	var voiceSettings: Void { () }
	func validateConfiguration() async throws {}
}

// MARK: - Analysis Manager (no-op)

actor AIAnalysisManager {
	static let shared = AIAnalysisManager()

	func analyzeChapterAutomatically(mangaId: String, chapterId: String) async throws -> AnalysisResult {
		AnalysisResult(
			mangaId: mangaId,
			chapterId: chapterId,
			pages: [],
			transcript: [],
			audioSegments: nil
		)
	}

	func analyzePageAutomatically(mangaId: String, chapterId: String, pageIndex: Int) async throws -> PageAnalysis? {
		return nil
	}

	func generatePageAudio(mangaId: String, chapterId: String, pageIndex: Int, pageAnalysis: PageAnalysis) async throws -> [AudioSegment] {
		return []
	}

	func getAnalysisResult(mangaId: String, chapterId: String) async -> AnalysisResult? {
		return nil
	}

	func prepareFirstPages(
		mangaId: String,
		chapterId: String,
		minimumPages: Int,
		generateAudio: Bool,
		progress: ((Int, Int) -> Void)? = nil
	) async {
		progress?(0, max(0, minimumPages))
	}
}

// MARK: - Audio Playback Manager (no-op)

@MainActor
class AudioPlaybackManager: NSObject {
	static let shared = AudioPlaybackManager()
	func playPageAudio(_ segments: [AudioSegment], transcript: [DialogueLine], pageIndex: Int) async {}
}
