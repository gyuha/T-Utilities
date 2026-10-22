import CoreGraphics

/// Decides whether a mouse-down at `click` (screen coordinates) should dismiss the popover.
/// A nested `NSMenu.popUp` (e.g. the Stats rows) can leave `NSPopover.behavior = .transient` without its
/// outside-click monitor, so the shell checks this itself.
public enum PopoverDismissal {
    /// Clicks inside the popover keep it open; clicks on the status item are left to its toggle action.
    public static func shouldClose(click: CGPoint, popoverFrame: CGRect, statusButtonFrame: CGRect) -> Bool {
        !popoverFrame.contains(click) && !statusButtonFrame.contains(click)
    }
}
