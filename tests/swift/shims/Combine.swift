// TEST ONLY shim - compiled into a fake "Combine" module so that files
// importing Combine can be type-checked on Windows.
public protocol ObservableObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(initialValue: Value) { self.wrappedValue = initialValue }
}
