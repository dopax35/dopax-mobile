import SwiftUI

/// A card in the "ARTICLES FOR YOU" carousel.
///
/// Content is bundled rather than fetched (decision D8): there is no CMS, and a
/// study build must not depend on a network call to render its home screen.
struct TodayArticle: Identifiable, Equatable {
    let id: String
    let source: String
    let title: String
    let iconName: String

    static let bundled: [TodayArticle] = [
        TodayArticle(id: "walking",
                     source: "PARKINSON RESEARCH NEWS",
                     title: "New study links daily walking to slower symptom progression",
                     iconName: "figure.walk"),
        TodayArticle(id: "on-off",
                     source: "DOPA-X GUIDES",
                     title: "Understanding ON and OFF periods: a practical guide",
                     iconName: "clock.arrow.circlepath"),
        TodayArticle(id: "consistency",
                     source: "DOPA-X GUIDES",
                     title: "Why testing at the same time each day matters",
                     iconName: "calendar.badge.clock"),
    ]
}

struct TodayArticlesCarousel: View {
    let articles: [TodayArticle]
    @State private var visibleIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                        card(article)
                            .onAppear { visibleIndex = index }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }

            pageControl
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func card(_ article: TodayArticle) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.todaySurfaceBrandStrong)
                Image(systemName: article.iconName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.onboardingAccent)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 8) {
                Text(article.source)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.8)
                    .foregroundColor(.onboardingAccent)
                Text(article.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.dopaxBlack90)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 168, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
    }

    private var pageControl: some View {
        HStack(spacing: 6) {
            ForEach(articles.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.onboardingAccentSoft)
                    .opacity(index == visibleIndex ? 1 : 0.3)
                    .frame(width: index == visibleIndex ? 20 : 7, height: 7)
            }
        }
    }
}
