var compactCases = 0
for width in [320.0, 375.0, 390.0, 430.0, 768.0, 1024.0] as [CGFloat] {
    for leftInset in [0.0, 44.0] as [CGFloat] {
        for rightInset in [0.0, 44.0] as [CGFloat] {
            for top in [0.0, 240.0, -20.0] as [CGFloat] {
                let layout = PeerInfoCompactHeaderLayout(width: width, leftInset: leftInset, rightInset: rightInset, top: top)
                for requestedBalanceWidth in [80.0, 125.0, 1000.0] as [CGFloat] {
                    let balanceWidth = min(requestedBalanceWidth, layout.maximumBalanceWidth(hasMusic: true))
                    let balanceSize = CGSize(width: balanceWidth, height: 20.0)
                    let musicSize = CGSize(width: layout.musicWidth(balanceWidth: balanceWidth), height: 20.0)
                    let balance = layout.balanceFrame(size: balanceSize, hasMusic: true)
                    let music = layout.musicFrame(size: musicSize, hasBalance: true)
                    precondition(abs(balance.minX - music.maxX - 6.0) < 0.001, "music and balance must not overlap")
                    precondition(music.minY == balance.minY && balance.minY == top, "both pills must share a baseline")
                    precondition(music.minX >= leftInset + 16.0 && balance.maxX <= width - rightInset - 16.0 + 0.001, "both pills must stay inside the profile band")
                    precondition(music.width > 0.0 && balance.width > 0.0, "each pill keeps a positive width")
                    compactCases += 1
                }
                let soloSize = CGSize(width: 100.0, height: 20.0)
                precondition(abs(layout.musicFrame(size: soloSize, hasBalance: false).midX - layout.row.midX) < 0.001, "a single song is centered")
                precondition(abs(layout.balanceFrame(size: soloSize, hasMusic: false).midX - layout.row.midX) < 0.001, "a single balance is centered")
                precondition(layout.maximumBalanceWidth(hasMusic: false) == layout.row.width, "a single balance can use the whole band")
            }
        }
    }
}
print("compact profile layout: \(compactCases) cases passed")
