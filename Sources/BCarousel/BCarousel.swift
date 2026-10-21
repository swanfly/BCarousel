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


@available(iOS 13.0, OSX 10.15, *)
public struct BCarousel<Data, ID, Content> : View where Data : RandomAccessCollection, ID : Hashable, Content : View {
    
    @ObservedObject
    private var viewModel: BCarouselViewModel<Data, ID>
    private let content: (Data.Element) -> Content
    
    /// 拖动偏移量：@GestureState 在手势结束**或被取消**时自动归零。
    /// 修复手势被 ScrollView/系统手势抢占后 onEnded 不调用、dragOffset 残留，
    /// 导致 offset 不再是页宽整数倍、两页各露一部分且不自愈的问题
    @GestureState private var dragOffset: CGFloat = 0
    
    public var body: some View {
        // 外部 index → 内部同步：本视图未重建（init 未重新执行）、仅 index Binding 值变化
        // 触发 body 重算时，由 syncExternalIndex 补上同步，保证外部改 index 能跳页
        //（同值时为 no-op；内部变化先经 willSet 写回 index，不会被误重置）
        viewModel.syncExternalIndex()
        return GeometryReader { proxy -> AnyView in
            viewModel.viewSize = proxy.size
            return AnyView(generateContent(proxy: proxy))
        }.clipped()
    }
    
    private func generateContent(proxy: GeometryProxy) -> some View {
        // 拖动状态同步给 viewModel（body 求值时写入，非 @Published 不触发刷新）：
        // 自动轮播在拖动中暂停（原实现在 dragChanged/dragEnded 里开关 isTimerActive，
        // 手势被取消时 onEnded 不调用会导致轮播永久停摆，改为由 dragOffset 推导无残留）
        viewModel.isDragging = dragOffset != 0
        return HStack(spacing: viewModel.spacing) {
            ForEach(viewModel.data, id: viewModel.dataId) {
                content($0)
                    .frame(width: viewModel.itemWidth)
                    .scaleEffect(x: 1, y: viewModel.itemScaling($0), anchor: .center)
            }
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        // 拖动量叠加在 offset 外：dragOffset 变化不经过 .animation(value: offset)，跟手无弹簧感；
        // 手势取消归零时 offset 未变，无动画直接弹回对齐位置
        .offset(x: viewModel.offset + dragOffset)
        // 拖动量经 .updating 写入 @GestureState（手势结束或被取消时自动归零），
        // 翻页判定在 onEnded（手势被抢占取消时 onEnded 不调用，但 dragOffset 已由 @GestureState 复位）
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = viewModel.clampedDragOffset(value.translation.width)
                }
                .onEnded { value in
                    viewModel.dragEnded(value.translation.width)
                }
        )
        .animation(viewModel.offsetAnimation, value: viewModel.offset)
        .onReceive(timer: viewModel.timer, perform: viewModel.receiveTimer)
        .onReceiveAppLifeCycle(perform: viewModel.setTimerActive)
    }
}


// MARK: - Initializers

@available(iOS 13.0, OSX 10.15, *)
extension BCarousel {
    
    /// Creates an instance that uniquely identifies and creates views across
    /// updates based on the identity of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The data that the ``BCarousel`` instance uses to create views
    ///     dynamically.
    ///   - id: The key path to the provided data's identifier.
    ///   - index: The index of currently active.
    ///   - spacing: The distance between adjacent subviews, default is 10.
    ///   - headspace: The width of the exposed side subviews, default is 10
    ///   - sidesScaling: The scale of the subviews on both sides, limits 0...1,
    ///     default is 0.8.
    ///   - isWrap: Define views to scroll through in a loop, default is false.
    ///   - autoScroll: A enum that define view to scroll automatically. See
    ///     ``BCarouselAutoScroll``. default is `inactive`.
    ///   - fixedItemWidth: 固定每个 item 的宽度（如全屏物理宽），非 nil 时不依赖容器测量宽，
    ///     用于容器存在 safe area 注入导致测量宽偏小的场景，default is `nil`.
    ///   - content: The view builder that creates views dynamically.
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, index: Binding<Int> = .constant(0), spacing: CGFloat = 10, headspace: CGFloat = 10, sidesScaling: CGFloat = 0.8, isWrap: Bool = false, autoScroll: BCarouselAutoScroll = .inactive, canMove: Bool = true, fixedItemWidth: CGFloat? = nil, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        
        self.viewModel = BCarouselViewModel(data, id: id, index: index, spacing: spacing, headspace: headspace, sidesScaling: sidesScaling, isWrap: isWrap, autoScroll: autoScroll, canMove: canMove, fixedItemWidth: fixedItemWidth)
        self.content = content
    }
    
}

@available(iOS 13.0, OSX 10.15, *)
extension BCarousel where ID == Data.Element.ID, Data.Element : Identifiable {
    
    /// Creates an instance that uniquely identifies and creates views across
    /// updates based on the identity of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The identified data that the ``BCarousel`` instance uses to
    ///     create views dynamically.
    ///   - index: The index of currently active.
    ///   - spacing: The distance between adjacent subviews, default is 10.
    ///   - headspace: The width of the exposed side subviews, default is 10
    ///   - sidesScaling: The scale of the subviews on both sides, limits 0...1,
    ///      default is 0.8.
    ///   - isWrap: Define views to scroll through in a loop, default is false.
    ///   - autoScroll: A enum that define view to scroll automatically. See
    ///     ``BCarouselAutoScroll``. default is `inactive`.
    ///   - fixedItemWidth: 固定每个 item 的宽度（如全屏物理宽），非 nil 时不依赖容器测量宽，
    ///     用于容器存在 safe area 注入导致测量宽偏小的场景，default is `nil`.
    ///   - content: The view builder that creates views dynamically.
    public init(_ data: Data, index: Binding<Int> = .constant(0), spacing: CGFloat = 10, headspace: CGFloat = 10, sidesScaling: CGFloat = 0.8, isWrap: Bool = false, autoScroll: BCarouselAutoScroll = .inactive, canMove: Bool = true, fixedItemWidth: CGFloat? = nil, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        
        self.viewModel = BCarouselViewModel(data, index: index, spacing: spacing, headspace: headspace, sidesScaling: sidesScaling, isWrap: isWrap, autoScroll: autoScroll, canMove: canMove, fixedItemWidth: fixedItemWidth)
        self.content = content
    }
    
}


@available(iOS 14.0, OSX 11.0, *)
struct BCarousel_LibraryContent: LibraryContentProvider {
    let Datas = Array(repeating: _Item(color: .red), count: 3)
    @LibraryContentBuilder
    var views: [LibraryItem] {
        LibraryItem(BCarousel(Datas) { _ in }, title: "BCarousel", category: .control)
        LibraryItem(BCarousel(Datas, index: .constant(0), spacing: 10, headspace: 10, sidesScaling: 0.8, isWrap: false, autoScroll: .inactive) { _ in }, title: "BCarousel full parameters", category: .control)
    }

    struct _Item: Identifiable {
        let id = UUID()
        let color: Color
    }
}
