import Foundation
import SGitVault

/// "Add a gallery page to this vault": an `index.html` and an `app.json` at the top of the vault, and a
/// `gallery.json` listing the pictures, so the vault opens as a photo gallery in the web Vault too. Follows
/// the web Vault's app contract (library/guides/vault-html/AUTHORING.md in SG/Send): everything inline, data
/// read with `sg.vfs.readText`, pictures set from JavaScript (a vault path given to `img.src` from script is
/// read from the vault), no network.
enum GalleryPage {
    static let indexPath = "index.html"
    static let appPath = "app.json"
    static let listPath = "gallery.json"

    struct Item: Codable, Equatable, Sendable {
        let path: String
        let name: String
        let kind: String
        /// The small picture kept in `.sgit/thumbs/`, when the file has one.
        let thumb: String?
    }

    static func list(_ files: [VaultFile]) throws -> Data {
        let all = Set(files.map(\.path))
        let items = PhotoGalleryView.pictures(in: files).map { file -> Item in
            let thumb = file.contentHash.map(FileFacts.thumbPath).flatMap { all.contains($0) ? $0 : nil }
            return Item(path: file.path, name: VaultListing.name(of: file.path), kind: "\(VaultListing.kind(of: file.path))", thumb: thumb)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(GalleryList(items: items))
    }

    struct GalleryList: Codable, Equatable, Sendable {
        var format = "sgit.ai/gallery/v1"
        var items: [Item]
    }

    static func app(title: String) throws -> Data {
        let object: [String: Any] = ["entry": indexPath, "present": true, "title": title, "hud": ["mode": "minimal"]]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func html(title: String) -> Data {
        let safe = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        return Data("""
        <!doctype html>
        <html lang="en-GB">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(safe)</title>
        <style>
          :root { color-scheme: dark; }
          body { margin: 0; background: #0b0c10; color: #e8e8ea; font: 15px/1.4 -apple-system, system-ui, sans-serif; }
          header { padding: 20px 16px 8px; }
          h1 { margin: 0; font-size: 22px; }
          p.count { margin: 4px 0 0; color: #9a9aa2; font-size: 13px; }
          .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 3px; padding: 3px; }
          .cell { position: relative; aspect-ratio: 1; background: #1a1b22; overflow: hidden; cursor: pointer; }
          .cell img { width: 100%; height: 100%; object-fit: cover; display: block; }
          .cell .play { position: absolute; right: 6px; bottom: 4px; font-size: 13px; color: #fff; text-shadow: 0 0 3px #000; }
          .viewer { position: fixed; inset: 0; background: #000; display: none; align-items: center; justify-content: center; }
          .viewer.open { display: flex; }
          .viewer img, .viewer video { max-width: 100%; max-height: 100%; }
          .viewer .bar { position: fixed; top: 0; left: 0; right: 0; display: flex; justify-content: space-between; padding: 12px; }
          .viewer button { background: rgba(255,255,255,.15); color: #fff; border: 0; border-radius: 18px; padding: 8px 14px; font-size: 15px; }
          .viewer .name { position: fixed; bottom: 16px; width: 100%; text-align: center; color: #bbb; font-size: 12px; }
        </style>
        </head>
        <body>
        <header><h1>\(safe)</h1><p class="count" id="count">Opening…</p></header>
        <div class="grid" id="grid"></div>
        <div class="viewer" id="viewer">
          <div class="bar"><button id="close">Close</button><span><button id="prev">‹</button> <button id="next">›</button></span></div>
          <div id="stage"></div>
          <div class="name" id="name"></div>
        </div>
        <script>
        (function () {
          var items = [], at = 0;
          var grid = document.getElementById('grid'), viewer = document.getElementById('viewer'), stage = document.getElementById('stage');
          function types(p) { var e = p.split('.').pop().toLowerCase(); return { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', heic: 'image/heic', gif: 'image/gif', mov: 'video/quicktime', mp4: 'video/mp4', m4v: 'video/mp4' }[e] || 'application/octet-stream'; }
          function show(i) {
            at = (i + items.length) % items.length;
            var item = items[at];
            stage.textContent = '';
            document.getElementById('name').textContent = item.name + ' · ' + (at + 1) + ' of ' + items.length;
            sg.vfs.read(item.path).then(function (buf) {
              var url = URL.createObjectURL(new Blob([buf], { type: types(item.path) }));
              var el = document.createElement(item.kind === 'video' ? 'video' : 'img');
              if (item.kind === 'video') { el.controls = true; el.playsInline = true; }
              el.src = url;
              stage.appendChild(el);
            });
            viewer.classList.add('open');
          }
          document.getElementById('close').onclick = function () { viewer.classList.remove('open'); stage.textContent = ''; };
          document.getElementById('prev').onclick = function () { show(at - 1); };
          document.getElementById('next').onclick = function () { show(at + 1); };
          sg.vfs.readText('\(listPath)').then(JSON.parse).then(function (data) {
            items = data.items || [];
            document.getElementById('count').textContent = items.length + (items.length === 1 ? ' picture' : ' pictures') + ', kept encrypted in this vault';
            items.forEach(function (item, i) {
              var cell = document.createElement('div');
              cell.className = 'cell';
              var img = document.createElement('img');
              img.alt = item.name;
              img.src = item.thumb || item.path;
              cell.appendChild(img);
              if (item.kind === 'video') { var p = document.createElement('span'); p.className = 'play'; p.textContent = '▶'; cell.appendChild(p); }
              cell.onclick = function () { show(i); };
              grid.appendChild(cell);
            });
          }).catch(function (e) { document.getElementById('count').textContent = 'The list of pictures could not be read: ' + e; })
            .then(function () { try { window.parent.postMessage({ type: 'sg-app-ready' }, '*'); } catch (e) {} });
        })();
        </script>
        </body>
        </html>
        """.utf8)
    }
}

extension VaultShelf {
    /// Writes the gallery page, its app.json and the list of pictures as one signed commit.
    func addGalleryPage(to vault: SavedVault) async throws {
        let files = contents[vault.id]?.files ?? []
        let title = vault.name
        try await putFiles([(GalleryPage.listPath, try GalleryPage.list(files)),
                            (GalleryPage.appPath, try GalleryPage.app(title: title)),
                            (GalleryPage.indexPath, GalleryPage.html(title: title))],
                           in: vault, message: VaultNaming.fit("Add a gallery page for \(files.count) files"))
        UsageLog.shared.action("vault.add-gallery-page")
    }
}
