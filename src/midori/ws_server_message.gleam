import midori/user_id.{type UserId}
import mist.{type WebsocketConnection}

// TODO: These should all be sync calls instead of async
pub type WebsocketServerMessage {
  Send(recipient: UserId, message: String)
  AddConnection(recipient: UserId, connection: WebsocketConnection)
  RemoveConnection(recipient: UserId)
}
