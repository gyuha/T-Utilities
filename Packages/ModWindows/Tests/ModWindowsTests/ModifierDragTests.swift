import CoreGraphics
import Testing
@testable import ModWindows

struct ModifierDragTests {
    let frame = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func defaultModifierIsOption() {
        #expect(DragModifiers.default == [.option])
        #expect(DragModifiers.stored(DragModifiers.default.rawValue) == [.option])
    }

    @Test func storedValueRoundTripsAndFallsBackWhenEmpty() {
        let both: DragModifiers = [.control, .command]
        #expect(DragModifiers.stored(both.rawValue) == both)
        #expect(DragModifiers.stored(0) == .default)
        #expect(DragModifiers.stored(1 << 9) == .default)
    }

    @Test func matchesOnlyTheExactModifierSet() {
        let option: DragModifiers = [.option]
        #expect(option.matches(.maskAlternate))
        #expect(!option.matches([]))
        #expect(!option.matches([.maskAlternate, .maskCommand]))
        #expect(!option.matches(.maskCommand))
    }

    @Test func ignoresNonModifierFlagsLikeCapsLock() {
        #expect(DragModifiers.option.matches([.maskAlternate, .maskAlphaShift]))
    }

    @Test func multipleModifiersAllRequired() {
        let combo: DragModifiers = [.control, .command]
        #expect(combo.matches([.maskControl, .maskCommand]))
        #expect(!combo.matches(.maskControl))
    }

    @Test func moveShiftsOriginAndKeepsSize() {
        let result = ModifierDragLogic.moved(frame, by: CGPoint(x: 30, y: -20))
        #expect(result == CGRect(x: 130, y: 80, width: 400, height: 300))
    }

    @Test func regionIsTheQuadrantUnderTheCursor() {
        #expect(ModifierDragLogic.region(of: CGPoint(x: 120, y: 120), in: frame) == .init(horizontal: .left, vertical: .top))
        #expect(ModifierDragLogic.region(of: CGPoint(x: 480, y: 380), in: frame) == .init(horizontal: .right, vertical: .bottom))
        #expect(ModifierDragLogic.region(of: CGPoint(x: 480, y: 120), in: frame) == .init(horizontal: .right, vertical: .top))
    }

    @Test func bottomRightResizeAnchorsTopLeft() {
        let result = ModifierDragLogic.resized(frame, region: .init(horizontal: .right, vertical: .bottom), by: CGPoint(x: 50, y: 40))
        #expect(result == CGRect(x: 100, y: 100, width: 450, height: 340))
    }

    @Test func topLeftResizeAnchorsBottomRight() {
        let result = ModifierDragLogic.resized(frame, region: .init(horizontal: .left, vertical: .top), by: CGPoint(x: 50, y: 40))
        #expect(result == CGRect(x: 150, y: 140, width: 350, height: 260))
        #expect(result.maxX == frame.maxX && result.maxY == frame.maxY)
    }

    @Test func resizeStopsAtMinimumSizeWithoutMovingAnchor() {
        let result = ModifierDragLogic.resized(frame, region: .init(horizontal: .left, vertical: .top), by: CGPoint(x: 900, y: 900))
        #expect(result.size == ModifierDragLogic.minimumSize)
        #expect(result.maxX == frame.maxX && result.maxY == frame.maxY)
    }
}
