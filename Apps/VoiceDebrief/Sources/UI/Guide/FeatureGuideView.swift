import SwiftUI
import UIKit

/// One feature guide: each step a picture of the screen with numbered arrows, then what each number is.
struct FeatureGuideView: View {
    let guide: FeatureGuide
    let ideas: IdeaBook?
    let pictures: String

    var body: some View {
        List {
            Section {
                Text(guide.intro)
            }
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                Section {
                    GuidePicture(name: step.image, caption: step.caption)
                    ForEach(step.callouts, id: \.n) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(c.n)")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(GuideStyle.callout, in: Circle())
                                .accessibilityLabel("Number \(c.n)")
                            Text(c.text)
                        }
                    }
                } header: {
                    Text("\(index + 1). \(step.caption)")
                }
            }
            if let ideas {
                let related = guide.ideas.compactMap { id in ideas.ideas.first { $0.id == id } }
                if !related.isEmpty {
                    Section("Where this stands") {
                        ForEach(related) { idea in
                            NavigationLink {
                                IdeaDetailView(idea: idea, book: ideas)
                            } label: {
                                IdeaRow(idea: idea, status: ideas.status(idea.status) ?? IdeaStatus(id: idea.status, label: idea.status, meaning: ""))
                            }
                        }
                    }
                }
            }
            Section {
                Text("Pictures: \(pictures)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .readableWidth()
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How the guides look, in one place for the design session.
enum GuideStyle {
    static let callout = Color(red: 0.9, green: 0.12, blue: 0.31)    // the arrows' colour in the pictures
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
