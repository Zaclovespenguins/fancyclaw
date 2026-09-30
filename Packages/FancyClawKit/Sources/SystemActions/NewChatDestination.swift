import AppIntents

public enum NewChatDestination: String, AppEnum {
    case newChat
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.newChat: "New chat"]
}
