import XCTest
import SwiftUI
@testable import BCarousel

final class BCarouselTests: XCTestCase {
    
    /// 可写的外部 index 容器（模拟父视图的 @State）
    private final class Box {
        var value: Int
        init(_ value: Int) { self.value = value }
    }
    
    private func makeBinding(_ box: Box) -> Binding<Int> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
    
    private func makeModel(_ box: Box, count: Int, isWrap: Bool) -> BCarouselViewModel<[Int], Int> {
        BCarouselViewModel(Array(0 ..< count), id: \.self, index: makeBinding(box), spacing: 0, headspace: 0, sidesScaling: 1.0, isWrap: isWrap, autoScroll: .inactive, canMove: true)
    }
    
    // MARK: - index 双向同步
    
    /// isWrap=true：init 把外部 index 映射为内部 activeIndex = index + 1（首尾补克隆页）
    func testWrapIndexMapping() {
        let box = Box(2)
        let model = makeModel(box, count: 3, isWrap: true)
        XCTAssertEqual(model.activeIndex, 3)
    }
    
    /// 外部改 index 后，syncExternalIndex 使内部跳页（视图未重建、仅 Binding 值变化的场景）
    func testSyncExternalIndexJump() {
        let box = Box(0)
        let model = makeModel(box, count: 3, isWrap: true)
        
        box.value = 2
        model.syncExternalIndex()
        XCTAssertEqual(model.activeIndex, 3)
        
        // 非包裹模式：外部与内部一一对应
        let plainBox = Box(0)
        let plainModel = makeModel(plainBox, count: 3, isWrap: false)
        plainBox.value = 2
        plainModel.syncExternalIndex()
        XCTAssertEqual(plainModel.activeIndex, 2)
    }
    
    /// 内部变化经 willSet 写回外部 index
    func testInternalChangeWritesBackIndex() {
        let box = Box(0)
        let model = makeModel(box, count: 3, isWrap: true)
        
        model.activeIndex = 2
        XCTAssertEqual(box.value, 1)
    }
    
    /// 外部值与上次一致时跳过同步：防回环，也避免 .constant(0) 场景下内部状态被误重置
    func testSyncSkipsUnchangedExternalIndex() {
        let model = makeModel(Box(0), count: 3, isWrap: true)
        
        // 模拟内部已翻页（.constant 写不进去，外部值不变）
        model.activeIndex = 2
        model.syncExternalIndex()
        XCTAssertEqual(model.activeIndex, 2, "外部 index 未变化时不应把内部状态重置回旧值")
    }
    
    // MARK: - 数据变化健壮性
    
    /// init 对越界 index 收敛到合法范围，不再 fatalError（数据源刷新后变短的场景）
    func testInitClampsOutOfRangeIndex() {
        let box = Box(9)
        let model = makeModel(box, count: 3, isWrap: true)
        XCTAssertEqual(model.activeIndex, 3, "index 9 越界，收敛到最后一个真实页（内部 3）")
    }
    
    /// 数据变短后 sync 越界收敛
    func testSyncClampsAfterDataShrink() {
        let box = Box(4)
        let model = makeModel(box, count: 5, isWrap: true)
        XCTAssertEqual(model.activeIndex, 5)
        
        // 模拟父视图用更短的数据重建后，外部 index 仍是旧值
        let shrunk = BCarouselViewModel(Array(0 ..< 3), id: \.self, index: makeBinding(box), spacing: 0, headspace: 0, sidesScaling: 1.0, isWrap: true, autoScroll: .inactive, canMove: true)
        XCTAssertEqual(shrunk.activeIndex, 3)
        XCTAssertNoThrow(shrunk.syncExternalIndex())
    }
    
    /// 空数据安全：不崩溃，activeIndex 收敛为 0
    func testEmptyData() {
        let box = Box(0)
        let model = makeModel(box, count: 0, isWrap: true)
        XCTAssertEqual(model.activeIndex, 0)
        
        model.activeIndex = 2
        model.syncExternalIndex()
        XCTAssertEqual(model.activeIndex, 0, "空数据时同步应把 activeIndex 收敛为 0")
    }
    
    // MARK: - 固定页宽
    
    /// fixedItemWidth 非 nil 时页宽用固定值，不受 viewSize（容器测量宽）影响；
    /// offset 同步按固定页宽对齐（页宽恒等于视口宽，第一页不会漏出第二页）
    func testFixedItemWidthOverridesViewSize() {
        let box = Box(0)
        let model = BCarouselViewModel(Array(0 ..< 3), id: \.self, index: makeBinding(box), spacing: 0, headspace: 0, sidesScaling: 1.0, isWrap: true, autoScroll: .inactive, canMove: true, fixedItemWidth: 380)
        
        model.viewSize = CGSize(width: 296, height: 200) // 容器测量宽偏小（safe 宽）的场景
        XCTAssertEqual(model.itemWidth, 380, "页宽应为固定值 380，而非测量值 296")
        XCTAssertEqual(model.offset, -380, "wrap 下 activeIndex=1，offset 按固定页宽对齐")
        
        model.activeIndex = 2
        XCTAssertEqual(model.offset, -760, "翻页后 offset 仍按固定页宽对齐")
    }
    
    /// fixedItemWidth 为 nil（默认）时保持原行为：页宽 = 测量宽 - defaultPadding×2
    func testNilFixedItemWidthKeepsMeasuredWidth() {
        let box = Box(0)
        let model = makeModel(box, count: 3, isWrap: true)
        
        model.viewSize = CGSize(width: 296, height: 200)
        XCTAssertEqual(model.itemWidth, 296)
    }
}
