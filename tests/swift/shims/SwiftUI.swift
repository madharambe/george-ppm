// TEST ONLY shim - compiled into a fake "SwiftUI" module so ContentView.swift
// and GeorgePPMApp.swift can be type-checked on Windows.
//
// It mirrors ONLY the API surface this app uses. It is not SwiftUI and makes no
// claim to be: its job is to catch typos, wrong argument labels and type errors
// in our own view code - the class of bug that otherwise only a macOS build finds.
//
// IMPORTANT: a pass here means "our Swift is well-formed against a plausible
// SwiftUI signature", NOT "this renders correctly on iOS".
import Foundation
import Combine      // StateObject's ObjectType must conform to ObservableObject

// ------------------------------------------------------------------- core
public protocol View {}

public struct EmptyView: View {
    public init() {}
}

public struct TupleView: View {
    public init(_ views: [any View]) {}
}

@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock(_ components: any View...) -> TupleView {
        TupleView(components)
    }
}

/// Concrete wrapper returned by modifiers, so no opaque return types are needed.
public struct _Modified<Content: View>: View {
    public init(_ content: Content) {}
}

// ---------------------------------------------------------------- geometry
public typealias CGFloat = Double

public enum Edge {
    public struct Set {
        public static let all = Set()
        public static let horizontal = Set()
        public static let vertical = Set()
        public static let top = Set()
        public static let bottom = Set()
        public static let leading = Set()
        public static let trailing = Set()
    }
}

public enum HorizontalAlignment { case leading, center, trailing }
public enum VerticalAlignment { case top, center, bottom, firstTextBaseline, lastTextBaseline }
public struct Alignment {
    public static let leading = Alignment()
    public static let center = Alignment()
    public static let trailing = Alignment()
    public init() {}
}

public enum ColorScheme { case light, dark }

// ------------------------------------------------------------------ colour
public struct Color: View {
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    public init(_ name: String) {}
    public func opacity(_ value: Double) -> Color { self }
}

// ------------------------------------------------------------------- text
public struct Font {
    public enum Weight { case regular, medium, semibold, bold }
    public enum Design { case rounded, monospaced, serif }
    public static func system(size: CGFloat, weight: Weight = .regular,
                              design: Design? = nil) -> Font { Font() }
    public init() {}
}

public struct Text: View {
    public init(_ content: String) {}
    public init(verbatim content: String) {}
}

// ----------------------------------------------------------------- shapes
public protocol Shape: View {}
public protocol ShapeStyle {}

public struct Capsule: Shape {
    public init() {}
}

public struct RoundedRectangle: Shape {
    public struct Style {
        public static let continuous = Style()
        public init() {}
    }
    public init(cornerRadius: CGFloat, style: Style = .continuous) {}
}

public struct Spacer: View {
    public init(minLength: CGFloat? = nil) {}
}

// -------------------------------------------------------------- containers
public struct VStack<Content: View>: View {
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct HStack<Content: View>: View {
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct ZStack<Content: View>: View {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
}

public struct ScrollView<Content: View>: View {
    public init(_ axes: Int = 0, @ViewBuilder content: () -> Content) {}
}

public struct Button<Label: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
}

public struct SwitchToggleStyle {
    public init(tint: Color? = nil) {}
}

public struct Toggle<Label: View>: View {
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {}
}

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

// --------------------------------------------------------- property wrappers
public struct Binding<Value> {
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {}
    public var wrappedValue: Value {
        get { fatalError() }
        nonmutating set {}
    }
}

@propertyWrapper
public struct State<Value> {
    // A reference box: the projected Binding must mutate the stored value from a
    // non-mutating context, which a plain stored property cannot do.
    private final class Box {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let box: Box

    public init(wrappedValue: Value) { self.box = Box(wrappedValue) }

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { self.box.value }, set: { self.box.value = $0 })
    }
}

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public var projectedValue: ObjectType { wrappedValue }
}

// ---------------------------------------------------------------- modifiers
extension View {
    public func font(_ font: Font) -> _Modified<Self> { _Modified(self) }
    public func foregroundColor(_ color: Color?) -> _Modified<Self> { _Modified(self) }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> _Modified<Self> { _Modified(self) }
    public func padding(_ length: CGFloat) -> _Modified<Self> { _Modified(self) }
    public func background(_ color: Color) -> _Modified<Self> { _Modified(self) }
    public func clipShape<S: Shape>(_ shape: S) -> _Modified<Self> { _Modified(self) }
    public func overlay<V: View>(_ view: V) -> _Modified<Self> { _Modified(self) }
    public func frame(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> _Modified<Self> { _Modified(self) }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil,
                      alignment: Alignment = .center) -> _Modified<Self> { _Modified(self) }
    public func tracking(_ value: CGFloat) -> _Modified<Self> { _Modified(self) }
    public func lineLimit(_ number: Int?) -> _Modified<Self> { _Modified(self) }
    public func minimumScaleFactor(_ factor: CGFloat) -> _Modified<Self> { _Modified(self) }
    public func disabled(_ disabled: Bool) -> _Modified<Self> { _Modified(self) }
    public func toggleStyle<S>(_ style: S) -> _Modified<Self> { _Modified(self) }
    public func onChange<V: Equatable>(of value: V,
                                       perform action: @escaping (V) -> Void) -> _Modified<Self> {
        _Modified(self)
    }
    public func preferredColorScheme(_ scheme: ColorScheme?) -> _Modified<Self> { _Modified(self) }
    public func ignoresSafeArea(_ edges: Edge.Set = .all) -> _Modified<Self> { _Modified(self) }
    public func opacity(_ value: Double) -> _Modified<Self> { _Modified(self) }
}

extension Shape {
    public func stroke(_ color: Color, lineWidth: CGFloat = 1) -> _Modified<Self> { _Modified(self) }
}

extension Color: ShapeStyle {}

// -------------------------------------------------------------- app / scene
public protocol Scene {}

public struct WindowGroup<Content: View>: Scene {
    public init(@ViewBuilder content: () -> Content) {}
}

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
}

@resultBuilder
public struct SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
}

extension App {
    /// Real SwiftUI.App provides this; @main requires it.
    public static func main() {}
}
