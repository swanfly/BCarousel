/**
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import SwiftUI
import Combine

@available(iOS 13.0, OSX 10.15, *)
class BCarouselViewModel<Data, ID>: ObservableObject where Data : RandomAccessCollection, ID : Hashable {
    
    /// external index
    @Binding
    private var index: Int
    
    private let _data: Data
    private let _dataId: KeyPath<Data.Element, ID>
    private let _spacing: CGFloat
    private let _headspace: CGFloat
    private let _isWrap: Bool
    private let _sidesScaling: CGFloat
    private let _autoScroll: BCarouselAutoScroll
    private let _canMove: Bool
    /// 固定页宽：非 nil 时每个 item 固定该宽度（不依赖 GeometryReader 测量值）。
    /// 用于容器存在 UIScrollView 桥接等 safe area 注入场景——此时测量宽可能停在 safe 宽，
    /// 页宽小于视口会导致第一页右侧漏出第二页的一部分
    private let _fixedItemWidth: CGFloat?
    
    init(_ data: Data, id: KeyPath<Data.Element, ID>, index: Binding<Int>, spacing: CGFloat, headspace: CGFloat, sidesScaling: CGFloat, isWrap: Bool, autoScroll: BCarouselAutoScroll, canMove: Bool, fixedItemWidth: CGFloat? = nil) {
        
        // 数据源为空或父视图刷新后变短时 index 可能越界，收敛到合法范围
        //（原实现对越界 fatalError，数据源变化后会直接崩溃）
        let safeIndex = data.isEmpty ? 0 : max(0, min(index.wrappedValue, data.count - 1))
        
        self._data = data
        self._dataId = id
        self._spacing = spacing
        self._headspace = headspace
        self._isWrap = isWrap
        self._sidesScaling = sidesScaling
        self._autoScroll = autoScroll
        self._fixedItemWidth = fixedItemWidth
        self._canMove = canMove
        
        if data.count > 1 && isWrap {
            activeIndex = safeIndex + 1
        } else {
            activeIndex = safeIndex
        }
        
        // 记录初始外部 index，供 syncExternalIndex 判断外部是否真的变化过
        lastExternalIndex = index.wrappedValue
        
        self._index = index
    }
    
    
    /// The index of the currently active subview.
    @Published var activeIndex: Int = 0 {
        willSet {
            if isWrap {
                if newValue > _data.count || newValue == 0 {
                    return
                }
                index = newValue - 1
            } else {
                index = newValue
            }
        }
        didSet {
            changeOffset()
        }
    }
    
    /// 上次同步到内部的外部 index 值：外部值与它一致时说明外部没有变化
    ///（含 index 为 .constant 时写不进去的情形），跳过同步，避免把内部状态误重置回旧 index
    private var lastExternalIndex: Int?
    
    /// 外部 index → 内部 activeIndex 的同步（body 求值时调用）。
    /// activeIndex 的 willSet 只负责内部 → 外部；init 只在视图重建时读取一次 index，
    /// 视图未重建、仅 index Binding 值变化触发 body 重算时不会经过 init，由这里补上同步，
    /// 保证外部改 index 能跳页。同值时为 no-op（内部 willSet 写回的值与外部一致），不会形成回环。
    func syncExternalIndex() {
        let externalIndex = index
        if let last = lastExternalIndex, last == externalIndex {
            return
        }
        lastExternalIndex = externalIndex
        
        guard _data.count > 0 else {
            if activeIndex != 0 {
                activeIndex = 0
            }
            return
        }
        // 数据可能已变短，越界时收敛到合法范围
        let clampedIndex = max(0, min(externalIndex, _data.count - 1))
        let target = isWrap ? clampedIndex + 1 : clampedIndex
        if activeIndex != target {
            activeIndex = target
        }
    }
    
    /// 是否正在拖动（BCarousel 在 body 求值时根据 @GestureState 的 dragOffset 写入，
    /// 手势被取消时也会归零，无残留）。自动轮播在拖动中暂停。
    var isDragging = false
    
    /// size of GeometryProxy
    var viewSize: CGSize = .zero
    
    
    /// Counting of time
    /// work when `isTimerActive` is true
    /// Toggles the active subviewview and resets if the count is the same as
    /// the duration of the auto scroll. Otherwise, increment one
    private var timing: TimeInterval = 0
    
    /// Define listen to the timer
    /// Ignores listen while dragging, and listen again after the drag is over
    /// Ignores listen when App will resign active, and listen again when it become active
    private var isTimerActive = true
    func setTimerActive(_ active: Bool) {
        isTimerActive = active
    }
    
}


extension BCarouselViewModel where ID == Data.Element.ID, Data.Element : Identifiable {
    
    convenience init(_ data: Data, index: Binding<Int>, spacing: CGFloat, headspace: CGFloat, sidesScaling: CGFloat, isWrap: Bool, autoScroll: BCarouselAutoScroll, canMove: Bool, fixedItemWidth: CGFloat? = nil) {
        self.init(data, id: \.id, index: index, spacing: spacing, headspace: headspace, sidesScaling: sidesScaling, isWrap: isWrap, autoScroll: autoScroll, canMove: canMove, fixedItemWidth: fixedItemWidth)
    }
}


extension BCarouselViewModel {
    
    var data: Data {
        guard _data.count != 0 else {
            return _data
        }
        guard _data.count > 1 else {
            return _data
        }
        guard isWrap else {
            return _data
        }
        return [_data.last!] + _data + [_data.first!] as! Data
    }
    
    var dataId: KeyPath<Data.Element, ID> {
        return _dataId
    }
    
    var spacing: CGFloat {
        return _spacing
    }
    
    var offsetAnimation: Animation? {
        guard isWrap else {
            return .spring()
        }
        return isAnimatedOffset ? .spring() : .none
    }
    
    var itemWidth: CGFloat {
        // 固定页宽优先：绕过 GeometryReader 测量值（容器 safe area 注入时测量宽不可信）
        if let fixed = _fixedItemWidth {
            return max(0, fixed)
        }
        return max(0, viewSize.width - defaultPadding * 2)
    }
    
    var timer: TimePublisher? {
        guard autoScroll.isActive else {
            return nil
        }
        return Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }
    
    /// Defines the scaling based on whether the item is currently active or not.
    /// - Parameter item: The incoming item
    /// - Returns: scaling
    func itemScaling(_ item: Data.Element) -> CGFloat {
        guard activeIndex < data.count else {
            return 0
        }
        let activeItem = data[activeIndex as! Data.Index]
        return activeItem[keyPath: _dataId] == item[keyPath: _dataId] ? 1 : sidesScaling
    }
}

// MARK: - private variable
extension BCarouselViewModel {
    
    private var isWrap: Bool {
        return _data.count > 1 ? _isWrap : false
    }
    
    private var autoScroll: BCarouselAutoScroll {
        guard _data.count > 1 else { return .inactive }
        guard case let .active(t) = _autoScroll else { return _autoScroll }
        return t > 0 ? _autoScroll : .defaultActive
    }
    
    private var defaultPadding: CGFloat {
        return (_headspace + spacing)
    }
    
    private var itemActualWidth: CGFloat {
        itemWidth + spacing
    }
    
    private var sidesScaling: CGFloat {
        return max(min(_sidesScaling, 1), 0)
    }
    
    /// Is animated when view is in offset
    private var isAnimatedOffset: Bool {
        get { UserDefaults.isAnimatedOffset }
        set { UserDefaults.isAnimatedOffset = newValue }
    }
}

// MARK: - Offset Method
extension BCarouselViewModel {
    /// current offset value（不含拖动量：拖动量由视图层 @GestureState 的 dragOffset 叠加，
    /// 手势被取消时自动归零，不会残留错位）
    var offset: CGFloat {
        let activeOffset = CGFloat(activeIndex) * itemActualWidth
        return defaultPadding - activeOffset
    }
    
    /// change offset when acitveItem changes
    private func changeOffset() {
        isAnimatedOffset = true
        guard isWrap else {
            return
        }
        
        let minimumOffset = defaultPadding
        let maxinumOffset = defaultPadding - CGFloat(data.count - 1) * itemActualWidth
        
        if offset == minimumOffset {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.activeIndex = self.data.count - 2
                self.isAnimatedOffset = false
            }
        } else if offset == maxinumOffset {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.activeIndex = 1
                self.isAnimatedOffset = false
            }
        }
    }
}

// MARK: - Drag Gesture
extension BCarouselViewModel {
    /// 拖动中由视图层 .updating($dragOffset) 调用：clamp 单次拖动最多一页宽
    ///（避免一次拖动翻过多页）。dragOffset 的写入与归零都在视图层 @GestureState，
    /// 手势结束**或被取消**时自动归零，不会残留错位。
    func clampedDragOffset(_ translation: CGFloat) -> CGFloat {
        guard _canMove else { return 0 }
        isAnimatedOffset = true
        return max(-itemActualWidth, min(itemActualWidth, translation))
    }
    
    /// 拖动结束的翻页判定：拖动量超过阈值（默认 50pt）翻一页。
    /// dragOffset 归零由视图层 @GestureState 自动完成（含手势被抢占取消的情形）。
    func dragEnded(_ translation: CGFloat) {
        guard _canMove else { return }
        resetTiming()
        
        /// Defines the drag threshold
        /// At the end of the drag, if the drag value exceeds the drag threshold,
        /// the active view will be toggled
        /// default is one third of subview
        // let dragThreshold: CGFloat = itemWidth / 3
        let dragThreshold: CGFloat = 50
        
        var activeIndex = self.activeIndex
        if translation > dragThreshold {
            activeIndex -= 1
        }
        if translation < -dragThreshold {
            activeIndex += 1
        }
        self.activeIndex = max(0, min(activeIndex, data.count - 1))
    }
}

// MARK: - Receive Timer
extension BCarouselViewModel {
    
    /// timer change
    func receiveTimer(_ value: Timer.TimerPublisher.Output) {
        /// Ignores listen when `isTimerActive` is false.
        guard isTimerActive else {
            return
        }
        /// Ignores while dragging（isDragging 由视图层 @GestureState 推导，手势被取消时也会复位）
        guard !isDragging else {
            return
        }
        /// increments of one and compare to the scrolling duration
        /// return when timing less than duration
        activeTiming()
        timing += 1
        if timing < autoScroll.interval {
            return
        }
        
        if activeIndex == data.count - 1 {
            /// `isWrap` is false.
            /// Revert to the first view after scrolling to the last view
            activeIndex = 0
        } else {
            /// `isWrap` is true.
            /// Incremental, calculation of offset by `offsetChanged(_: proxy:)`
            activeIndex += 1
        }
        resetTiming()
    }
    
    
    /// reset counting of time
    private func resetTiming() {
        timing = 0
    }
    
    /// time increments of one
    private func activeTiming() {
        timing += 1
    }
}


private extension UserDefaults {

    private struct Keys {
        static let isAnimatedOffset = "isAnimatedOffset"
    }

    static var isAnimatedOffset: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Keys.isAnimatedOffset)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.isAnimatedOffset)
        }
    }
}
