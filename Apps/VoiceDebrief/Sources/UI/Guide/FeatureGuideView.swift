import SwiftUI
import UIKit

/// One feature guide: each step a picture of the screen with numbered arrows, and what each number is.
/// On a wide screen the picture and its numbers sit side by side; an Open button goes to the section.
struct FeatureGuideView: View {
    let guide: FeatureGuide
    let ideas: IdeaBook?
    let pictures: String
    var go: (RootTab) -> Void = { _ in }
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text(guide.intro).font(.title3).foregroundStyle(.secondary)
                if let raw = guide.open, let tab = RootTab(rawValue: raw) {
                    Button { go(tab) } label: { Label("Open \(tab.title)", systemImage: tab.symbol) }
                        .buttonStyle(.borderedProminent)
                        .tint(tab.tint)
                }
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("\(index + 1). \(step.caption)").font(DS.TypeScale.heading)
                        if sizeClass == .regular {
                            HStack(alignment: .top, spacing: DS.Space.l) {
                                GuidePicture(name: step.image, caption: step.caption).frame(width: 320)
                                Callouts(callouts: step.callouts)
                            }
                        } else {
                            GuidePicture(name: step.image, caption: step.caption)
                            Callouts(callouts: step.callouts)
                        }
                    }
                    .padding(DS.Space.m)
                    .dsSurface()
                }
                if let ideas {
                    let related = guide.ideas.compactMap { id in ideas.ideas.first { $0.id == id } }
                    if !related.isEmpty {
                        DSSectionHeader(title: "Where this stands", symbol: "lightbulb")
                        VStack(spacing: 0) {
                            ForEach(related) { idea in
                                NavigationLink {
                                    IdeaDetailView(idea: idea, book: ideas)
                                } label: {
                                    HStack {
                                        IdeaRow(idea: idea, status: ideas.status(idea.status) ?? IdeaStatus(id: idea.status, label: idea.status, meaning: ""))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                                    }
                                    .padding(DS.Space.s)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .dsSurface()
                    }
                }
                Text("Pictures: \(pictures)").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Palette.ground)
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The numbered notes beside or under a picture.
struct Callouts: View {
    let callouts: [FeatureGuide.Callout]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(callouts, id: \.n) { c in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(c.n)")
                        .font(.callout.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(GuideStyle.callout, in: Circle())
                        .accessibilityLabel("Number \(c.n)")
                    Text(c.text).font(.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A guide's picture, at most the width of a phone, tap to see it full screen.
struct GuidePicture: View {
    let name: String
    let caption: String
    @State private var zoomed = false

    var body: some View {
        if let url = GuideBook.pictureURL(name), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable().scaledToFit()
                .frame(maxWidth: 360)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("\(caption) Numbered arrows mark the parts described below.")
                .onTapGesture { zoomed = true }
                .fullScreenCover(isPresented: $zoomed) {
                    NavigationStack {
                        ScrollView { Image(uiImage: image).resizable().scaledToFit().padding() }
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { zoomed = false } } }
                    }
                }
        } else {
            Label("The picture is not in this build.", systemImage: "photo").foregroundStyle(.secondary)
        }
    }
}
