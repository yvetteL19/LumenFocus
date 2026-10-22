import Foundation

/// Optional off-screen prompts. These describe actions, not medical outcomes.
enum Tips {
    static func random(for date: Date = Date()) -> String {
        let prompts = [
            "把目光移到屏幕之外。",
            "找一个远处的物体，轻松眨眼。",
            "如果方便，起身走动一下。",
            "放下手边的事，给自己片刻空隙。",
            "看看窗外，或房间较远的地方。"
        ]
        return L(prompts.randomElement() ?? prompts[0])
    }
}
