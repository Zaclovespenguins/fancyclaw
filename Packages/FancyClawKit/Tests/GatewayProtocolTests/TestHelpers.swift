import Foundation
import GatewayProtocol

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try GatewayCoding.decoder().decode(T.self, from: Data(json.utf8))
}
