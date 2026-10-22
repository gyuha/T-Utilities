import CoreGraphics
import Testing
@testable import TUCore

struct PopoverDismissalTests {
    let popover = CGRect(x: 100, y: 500, width: 400, height: 300)
    let button = CGRect(x: 300, y: 820, width: 40, height: 24)

    @Test func clickOutsideBothClosesPopover() {
        #expect(PopoverDismissal.shouldClose(click: CGPoint(x: 50, y: 50), popoverFrame: popover, statusButtonFrame: button))
    }

    @Test func clickInsidePopoverKeepsItOpen() {
        #expect(!PopoverDismissal.shouldClose(click: CGPoint(x: 200, y: 600), popoverFrame: popover, statusButtonFrame: button))
    }

    @Test func clickOnStatusButtonIsLeftToItsToggle() {
        #expect(!PopoverDismissal.shouldClose(click: CGPoint(x: 310, y: 830), popoverFrame: popover, statusButtonFrame: button))
    }
}
