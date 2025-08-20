//
//  CoreDataExtensions.swift
//  Aidoku
//
//  Created by AI Analysis Feature - Core Data Extensions
//

import Foundation
import AidokuRunner

// MARK: - MangaObject Extensions

extension MangaObject {
    func toAidokuManga() -> AidokuRunner.Manga {
        return AidokuRunner.Manga(
            sourceKey: self.sourceId ?? "",
            key: self.id ?? "",
            title: self.title ?? "",
            cover: self.cover,
            artists: self.artist?.components(separatedBy: ", "),
            authors: self.author?.components(separatedBy: ", "),
            description: self.desc,
            url: URL(string: self.url ?? ""),
            tags: self.tags as? [String],
            status: PublishingStatus(rawValue: Int(self.status)) ?? .unknown,
            contentRating: MangaContentRating(rawValue: Int(self.nsfw)) ?? .safe,
            viewer: MangaViewer(rawValue: Int(self.viewer)) ?? .defaultViewer,
            updateStrategy: .always, // Default update strategy
            nextUpdateTime: self.nextUpdateTime.flatMap { Int($0.timeIntervalSince1970) },
            chapters: nil // Will be loaded separately if needed
        )
    }
}

// MARK: - ChapterObject Extensions

extension ChapterObject {
    func toAidokuChapter() -> AidokuRunner.Chapter {
        return AidokuRunner.Chapter(
            sourceKey: self.sourceId ?? "",
            key: self.id ?? "",
            title: self.title,
            scanlator: self.scanlator,
            url: URL(string: self.url ?? ""),
            language: self.lang ?? "en",
            chapterNum: self.chapter >= 0 ? self.chapter : nil,
            volumeNum: self.volume >= 0 ? self.volume : nil,
            dateUploaded: self.dateUploaded.flatMap { Int($0.timeIntervalSince1970) }
        )
    }
}

// MARK: - PublishingStatus Extension

extension PublishingStatus {
    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .unknown
        case 1: self = .ongoing
        case 2: self = .completed
        case 3: self = .cancelled
        case 4: self = .hiatus
        default: self = .unknown
        }
    }
}

// MARK: - MangaContentRating Extension

extension MangaContentRating {
    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .safe
        case 1: self = .suggestive
        case 2: self = .nsfw
        default: self = .safe
        }
    }
}

// MARK: - MangaViewer Extension

extension MangaViewer {
    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .defaultViewer
        case 1: self = .rtl
        case 2: self = .ltr
        case 3: self = .vertical
        case 4: self = .webtoon
        default: self = .defaultViewer
        }
    }
}