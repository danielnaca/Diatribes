import Foundation
import SwiftData

// MARK: - SwiftData models

@Model
final class SavedArticle {
    var id: UUID
    var title: String
    var url: String
    var excerpt: String
    var paragraphs: [String]
    var language: String
    var savedAt: Date

    init(title: String, url: String, excerpt: String, paragraphs: [String], language: String) {
        self.id         = UUID()
        self.title      = title
        self.url        = url
        self.excerpt    = excerpt
        self.paragraphs = paragraphs
        self.language   = language
        self.savedAt    = Date()
    }
}

@Model
final class FeedSubscription {
    var id: UUID
    var title: String
    var feedUrl: String
    var siteUrl: String
    var favicon: String   // URL string for favicon image
    var addedAt: Date

    init(title: String, feedUrl: String, siteUrl: String, favicon: String) {
        self.id      = UUID()
        self.title   = title
        self.feedUrl = feedUrl
        self.siteUrl = siteUrl
        self.favicon = favicon
        self.addedAt = Date()
    }
}

// MARK: - API response types

struct FetchedArticle: Codable {
    let title: String
    let url: String
    let excerpt: String
    let paragraphs: [String]
}

struct FetchedFeed: Codable {
    let title: String
    let site_url: String
    let favicon: String
    let items: [FeedItem]
}

struct FeedItem: Codable, Identifiable {
    let title: String
    let url: String
    let excerpt: String
    let date: String
    let guid: String

    var id: String { guid }
}

// Navigation value for pushing ArticleReaderView
struct ArticleReaderData: Identifiable, Hashable {
    let id         = UUID()
    let title:      String
    let source:     String
    let paragraphs: [String]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ArticleReaderData, rhs: ArticleReaderData) -> Bool { lhs.id == rhs.id }
}
