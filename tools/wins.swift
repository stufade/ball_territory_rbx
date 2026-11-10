import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  if owner.lowercased().contains("roblox") {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print(w[kCGWindowNumber as String]!, owner, w[kCGWindowName as String] ?? "-", w[kCGWindowLayer as String]!, b["Width"]!, b["Height"]!, w[kCGWindowIsOnscreen as String] ?? false, b["X"]!, b["Y"]!)
  }
}
