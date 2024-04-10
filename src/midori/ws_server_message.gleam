import midori/game_id.{type GameId}
import mist.{type WebsocketConnection}

// TODO: These should all be sync calls instead of async
pub type WebsocketServerMessage {
  Send(recipient: GameId, message: String)
  AddConnection(recipient: GameId, connection: WebsocketConnection)
  RemoveConnection(recipient: GameId)
}
