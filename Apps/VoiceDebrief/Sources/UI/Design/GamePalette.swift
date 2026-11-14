import SwiftUI

/// The house colours named for the L03 game's board, offered to the game (Sources/Game belongs to the
/// game session). The values are the ones the board already draws with, so adopting these changes
/// nothing on screen; changing one here then changes it everywhere it is used.
enum GamePalette {
    /// The night sky behind the board, top to bottom.
    static let skyTop = Color(dsHex: 0x0B1B2B)
    static let skyBottom = Color(dsHex: 0x1B3A55)
    static let floor = Color(dsHex: 0xE8EEF2)
    static let wall = Color(dsHex: 0x12283C)
    static let wallSide = Color(dsHex: 0x5B4A3A)
    static let grass = Color(dsHex: 0x3E8E5E)
    /// Coins, stars and lamps: the house amber.
    static let gold = Color(dsHex: 0xF0B429)
    static let goldEdge = Color(dsHex: 0xB98500)
    static let wood = Color(dsHex: 0x8A5A2B)
    static let danger = DS.Palette.red
    static let dangerSide = Color(dsHex: 0xC9D2DA)
    static let lampOff = Color(dsHex: 0x6B7785)
    static let open = DS.Palette.green
    static let closed = Color(dsHex: 0x9AA6B2)
    static let player = DS.Palette.green
}

/// The player drawn as the owner's own avatar (their photo or generated character), for a game that
/// wants the person playing to be the one on the board.
struct GamePlayerSprite: View {
    var size: CGFloat = 32

    var body: some View {
        AvatarView(MyLook.shared.subject(id: "me"), size: size)
    }
}
