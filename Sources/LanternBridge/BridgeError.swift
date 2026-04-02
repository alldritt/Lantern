import LanternVM

/// Errors that arise during bridge operations.
public enum BridgeError: Error, CustomStringConvertible {
    case typeNotRegistered(String)
    case methodNotRegistered(typeName: String, selector: String)
    case propertyNotRegistered(typeName: String, name: String)
    case functionNotRegistered(String)
    case argumentConversionFailed(parameter: String, expected: String, got: String)
    case returnConversionFailed(typeName: String)
    case readOnlyProperty(typeName: String, name: String)
    case duplicateRegistration(String)

    public var description: String {
        switch self {
        case .typeNotRegistered(let name):
            return "Type '\(name)' is not registered in the bridge registry"
        case .methodNotRegistered(let typeName, let selector):
            return "Method '\(selector)' is not registered on type '\(typeName)'"
        case .propertyNotRegistered(let typeName, let name):
            return "Property '\(name)' is not registered on type '\(typeName)'"
        case .functionNotRegistered(let name):
            return "Function '\(name)' is not registered in the bridge registry"
        case .argumentConversionFailed(let parameter, let expected, let got):
            return "Cannot convert argument '\(parameter)' — expected \(expected), got \(got)"
        case .returnConversionFailed(let typeName):
            return "Cannot convert return value of type '\(typeName)' to interpreter value"
        case .readOnlyProperty(let typeName, let name):
            return "Property '\(name)' on type '\(typeName)' is read-only"
        case .duplicateRegistration(let name):
            return "Duplicate registration: '\(name)'"
        }
    }
}
