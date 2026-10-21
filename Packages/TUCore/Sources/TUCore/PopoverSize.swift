import CoreGraphics

/// User-resizable popover geometry, persisted via `@AppStorage` under these keys.
public enum PopoverSize {
    public static let widthKey = "popover.width"
    public static let listHeightKey = "popover.listHeight"

    public static let defaultWidth: CGFloat = 420
    public static let defaultListHeight: CGFloat = 560

    public static let widthRange: ClosedRange<CGFloat> = 360...900
    public static let listHeightRange: ClosedRange<CGFloat> = 240...1400
}
