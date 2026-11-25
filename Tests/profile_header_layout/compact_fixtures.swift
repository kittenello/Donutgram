var compactCases = 0
for width in [320.0, 375.0, 390.0, 430.0, 768.0, 1024.0] as [CGFloat] {
    for leftInset in [0.0, 44.0] as [CGFloat] {
        for rightInset in [0.0, 44.0] as [CGFloat] {
            for top in [0.0, 240.0, -20.0] as [CGFloat] {
                let layout = PeerInfoCompactHeaderLayout(width: width, leftInset: leftInset, rightInset: rightInset, top: top)
                for requestedBalanceWidth in [80.0, 125.0, 1000.0] as [CGFloat] {
                    let balanceWidth = min(requestedBalanceWidth, layout.maximumBalanceWidth(hasMusic: true))
                    let balanceSize = CGSize(width: balanceWidth, height: 20.0)
                    let maximumMusicWidth = layout.musicWidth(balanceWidth: balanceWidth)
                    for musicWidth in [min(72.0, maximumMusicWidth), maximumMusicWidth] {
                        let musicSize = CGSize(width: musicWidth, height: 20.0)
                        let frames = layout.frames(musicSize: musicSize, balanceSize: balanceSize)
                        let music = frames.music!
                        let balance = frames.balance!
                        precondition(abs(balance.minX - music.maxX - layout.spacing) < 0.001, "the pills must stay next to each other")
                        precondition(abs((music.minX + balance.maxX) * 0.5 - layout.row.midX) < 0.001, "the pair must be centered")
                        precondition(music.minY == balance.minY && balance.minY == top, "both pills must share a baseline")
                        precondition(music.minX >= leftInset + 16.0 - 0.001 && balance.maxX <= width - rightInset - 16.0 + 0.001, "both pills must stay inside the profile band")
                        precondition(music.size == musicSize && balance.size == balanceSize, "the pills keep their measured sizes")
                        compactCases += 1
                    }
                }
                let soloSize = CGSize(width: 100.0, height: 20.0)
                let musicOnly = layout.frames(musicSize: soloSize, balanceSize: nil)
                precondition(musicOnly.balance == nil && abs(musicOnly.music!.midX - layout.row.midX) < 0.001, "a single song is centered")
                let balanceOnly = layout.frames(musicSize: nil, balanceSize: soloSize)
                precondition(balanceOnly.music == nil && abs(balanceOnly.balance!.midX - layout.row.midX) < 0.001, "a single balance is centered")
                let empty = layout.frames(musicSize: nil, balanceSize: nil)
                precondition(empty.music == nil && empty.balance == nil, "an empty row has no frames")
                precondition(layout.maximumBalanceWidth(hasMusic: false) == layout.row.width, "a single balance can use the whole band")
            }
        }
    }
}
print("compact profile layout: \(compactCases) cases passed")
